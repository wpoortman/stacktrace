import SwiftUI

@main
struct StacktraceApp: App {
    @StateObject private var store = DataStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 820, minHeight: 560)
                .environmentObject(store)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            SettingsView()
                .environmentObject(store)
        }
    }
}
