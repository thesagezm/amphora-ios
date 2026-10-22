import SwiftUI

@main
struct AmphoraApp: App {
    @State private var appStore = AppStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appStore)
        }
    }
}
