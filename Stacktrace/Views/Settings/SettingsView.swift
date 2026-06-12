import SwiftUI

/// App preferences. Future-proof: each pane is a `SettingsPane` case with its
/// own view — add a case and a view to grow the window, nothing else changes.
struct SettingsView: View {
    var body: some View {
        TabView {
            ForEach(SettingsPane.allCases) { pane in
                pane.content
                    .tabItem { Label(pane.title, systemImage: pane.systemImage) }
                    .tag(pane)
            }
        }
        .frame(width: 500, height: 440)
    }
}

enum SettingsPane: String, CaseIterable, Identifiable {
    case days
    case reminders
    case tags
    case ai
    case storage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .days: return "Days"
        case .reminders: return "Reminders"
        case .tags: return "Tags"
        case .ai: return "AI"
        case .storage: return "Storage"
        }
    }

    var systemImage: String {
        switch self {
        case .days: return "calendar"
        case .reminders: return "bell"
        case .tags: return "tag"
        case .ai: return "sparkles"
        case .storage: return "externaldrive"
        }
    }

    @ViewBuilder
    var content: some View {
        switch self {
        case .days: DaysSettingsView()
        case .reminders: RemindersSettingsView()
        case .tags: TagsSettingsView()
        case .ai: AISettingsView()
        case .storage: StorageSettingsView()
        }
    }
}
