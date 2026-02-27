import SwiftUI

@main
struct ModelWarClientApp: App {
    @State private var appSession = AppSession()

    var body: some Scene {
        WindowGroup {
            ContentView(appSession: appSession)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1400, height: 900)
    }
}
