//
//  CrashReporter.swift
//  Amphora
//
//  Best-effort crash capture. Swift traps (fatal errors, array out of
//  range, force-unwrap of nil) and Objective-C exceptions kill the
//  process; on a device without a debugger the only trace was the
//  system crash log, which is awkward to reach from LiveContainer. A
//  handler runs at the moment of the crash and writes what it can to
//  `Application Support/Amphora/last-crash.txt`:
//
//  - **Signal handlers** (SIGABRT/SIGILL/SIGSEGV/SIGBUS/SIGFPE/SIGTRAP)
//    do async-signal-safe work only: they write a one-line header plus
//    the log tail that `AppLog` mirrors into raw memory, then restore
//    the default handler and re-raise so the system still records its
//    own crash report.
//  - **The uncaught-exception handler** records the NSException name,
//    reason and stack with regular Foundation I/O and marks the report
//    as written, so the SIGABRT that follows does not overwrite it.
//
//  The next launch reads the file back before it is reset, and the
//  Diagnostics screen shows it — that is how a crash gets pasted into a
//  bug report.
//

import Darwin
import Foundation

/// Raw tail of the log, in signal-handler-writable memory.
private let crashTailCapacity = 1 << 14 // 16 KiB

nonisolated(unsafe) private let crashTail: UnsafeMutablePointer<CChar> = {
    let pointer = UnsafeMutablePointer<CChar>.allocate(capacity: crashTailCapacity)
    pointer.initialize(repeating: 0, count: crashTailCapacity)
    return pointer
}()

/// These are touched from a signal handler, so they must be plain
/// globals the concurrency checker does not try to isolate.
nonisolated(unsafe) private var crashFileDescriptor: Int32 = -1
nonisolated(unsafe) private var exceptionReportWritten: Int32 = 0

final class CrashReporter: @unchecked Sendable {
    static let shared = CrashReporter()

    /// The previous session's crash report, captured before the file is
    /// reset for this session. Shown by the Diagnostics screen.
    private(set) var previousCrashReport: String?

    private let lock = NSLock()
    private var installed = false

    private static let crashFileURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base
            .appendingPathComponent("Amphora", isDirectory: true)
            .appendingPathComponent("last-crash.txt", isDirectory: false)
    }()

    /// Installs the handlers once. Call from `App.init()`.
    func install() {
        lock.lock()
        defer { lock.unlock() }
        guard !installed else { return }
        installed = true

        // Read the previous crash before the file is reset for this run.
        previousCrashReport = try? String(contentsOf: Self.crashFileURL, encoding: .utf8)

        let path = Self.crashFileURL.path
        let descriptor = path.withCString { cPath in
            open(cPath, O_RDWR | O_CREAT | O_TRUNC, 0o644)
        }
        if descriptor >= 0 {
            crashFileDescriptor = descriptor
        }

        installHandlers()
    }

    /// Drops the stored report (the user dismissed it in Diagnostics).
    func clearLastCrashReport() {
        lock.lock()
        previousCrashReport = nil
        lock.unlock()
        if crashFileDescriptor >= 0 {
            _ = ftruncate(crashFileDescriptor, 0)
        }
    }

    /// Mirrors the most recent log lines into raw memory. Called by the
    /// log buffer; must stay synchronous and cheap.
    static func setCrashTail(_ text: String) {
        text.withCString { source in
            _ = strlcpy(crashTail, source, crashTailCapacity)
        }
    }

    private func installHandlers() {
        NSSetUncaughtExceptionHandler { exception in
            CrashReporter.writeExceptionReport(exception)
        }
        for number in [SIGABRT, SIGILL, SIGSEGV, SIGBUS, SIGFPE, SIGTRAP] {
            signal(number) { received in
                CrashReporter.handleSignal(received)
            }
        }
    }

    /// The NSException path — regular code, Foundation I/O allowed.
    private static func writeExceptionReport(_ exception: NSException) {
        var text = "Amphora crashed: uncaught exception\n"
        text += "name: \(exception.name.rawValue)\n"
        if let reason = exception.reason {
            text += "reason: \(reason)\n"
        }
        text += exception.callStackSymbols.joined(separator: "\n")
        text += "\n"
        try? text.write(to: crashFileURL, atomically: true, encoding: .utf8)
        exceptionReportWritten = 1
    }

    /// The signal path — async-signal-safe calls only, then re-raise.
    private static func handleSignal(_ number: Int32) {
        if exceptionReportWritten == 0, crashFileDescriptor >= 0 {
            // Swift cannot call C variadics (`snprintf` is unavailable),
            // so the header is formatted in Swift. The small allocation
            // is a best-effort trade-off the rest of this path already
            // makes.
            let header = "Amphora crashed: signal \(number)\n"
            header.withCString { cHeader in
                _ = lseek(crashFileDescriptor, 0, SEEK_SET)
                let headerLength = strlen(cHeader)
                _ = write(crashFileDescriptor, cHeader, headerLength)
                let tailLength = strlen(crashTail)
                if tailLength > 0 {
                    _ = write(crashFileDescriptor, crashTail, tailLength)
                }
                _ = ftruncate(crashFileDescriptor, off_t(headerLength + tailLength))
            }
        }
        signal(number, SIG_DFL)
        raise(number)
    }
}
