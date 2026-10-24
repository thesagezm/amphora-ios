import SwiftUI
import UIKit

/// In-app diagnostics: the recent app log and the previous session's
/// crash report, with one-tap Copy/Share so a crash can be pasted into a
/// bug report. The app ships without a debugger (LiveContainer), so this
/// screen is the only window into what happened on the device.
/// Presented from Settings → Diagnostics & Logs.
struct DiagnosticsView: View {
    @State private var logText = ""
    @State private var crashText: String?
    @State private var didCopy = false

    var body: some View {
        Group {
            if logText.isEmpty && crashText == nil {
                ContentUnavailableView(
                    "Nothing recorded yet",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Reproduce the problem, then reopen this screen.")
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if let crashText {
                            section("Last crash") {
                                Text(crashText)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.red.opacity(0.9))
                                    .textSelection(.enabled)
                            }
                        }
                        section("Device") {
                            Text(deviceSummary)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        section("Log (most recent \(logLines.count) lines)") {
                            Text(logText)
                                .font(.system(.caption2, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    copyAll()
                } label: {
                    Label("Copy", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                }
                .disabled(reportText.isEmpty)
                .accessibilityLabel("Copy diagnostics to the clipboard")
            }
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: reportText) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .disabled(reportText.isEmpty)
            }
        }
        .task { refresh() }
    }

    // MARK: - Data

    private var logLines: [String] {
        logText.isEmpty ? [] : logText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    private var reportText: String {
        var text = deviceSummary + "\n\n"
        if let crashText {
            text += "--- last crash ---\n\(crashText)\n\n"
        }
        text += "--- log ---\n\(logText)"
        return text
    }

    private func refresh() {
        AppLog.flushNow()
        logText = AppLog.text()
        crashText = CrashReporter.shared.previousCrashReport
    }

    private func copyAll() {
        UIPasteboard.general.string = reportText
        didCopy = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            didCopy = false
        }
    }

    // MARK: - Pieces

    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var deviceSummary: String {
        var system = utsname()
        uname(&system)
        let model = withUnsafeBytes(of: &system.machine) { raw in
            String(decoding: Data(raw).prefix(while: { $0 != 0 }), as: UTF8.self)
        }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return """
        device: \(model.isEmpty ? "?" : model)
        os: iOS \(ProcessInfo.processInfo.operatingSystemVersionString)
        app: \(version) (\(build))
        """
    }
}
