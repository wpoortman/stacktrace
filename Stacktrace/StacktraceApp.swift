import SwiftUI

@main
struct StacktraceApp: App {
    @StateObject private var store = DataStore()

    var body: some Scene {
        Window("Stacktrace", id: "main") {
            ContentView()
                .frame(minWidth: 820, minHeight: 560)
                .environmentObject(store)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        MenuBarExtra("Stacktrace", systemImage: "square.stack.fill") {
            MenuBarView()
                .environmentObject(store)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(store)
        }
    }
}
