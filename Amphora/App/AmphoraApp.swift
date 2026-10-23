import SwiftUI

@main
struct AmphoraApp: App {
    @State private var appStore = AppStore()

    init() {
        // Crash handlers must be in place before anything can go wrong.
        CrashReporter.shared.install()
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        AppLog.info("Amphora launched, app \(version) build \(build)")
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appStore)
        }
    }
}
