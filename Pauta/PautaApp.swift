import SwiftUI
import SwiftData

@main
struct PautaApp: App {
    var body: some Scene {
        #if os(macOS)
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: Recording.self)
        .defaultSize(width: 1050, height: 700)

        Settings {
            SettingsView()
                .frame(minWidth: 480, minHeight: 420)
        }
        #else
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: Recording.self)
        #endif
    }
}
