import SwiftUI

@main
struct StacktraceApp: App {
    @StateObject private var store = DataStore()
    @StateObject private var pro = ProManager.shared

    var body: some Scene {
        Window("Stacktrace", id: "main") {
            ContentView()
                .frame(minWidth: 820, minHeight: 560)
                .environmentObject(store)
                .environmentObject(pro)
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
                .environmentObject(pro)
        }
    }
}
