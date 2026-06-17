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
    case general
    case days
    case routines
    case calendar
    case reminders
    case tags
    case ai
    case storage
    case license

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .days: return "Days"
        case .routines: return "Routines"
        case .calendar: return "Calendar"
        case .reminders: return "Reminders"
        case .tags: return "Tags"
        case .ai: return "AI"
        case .storage: return "Storage"
        case .license: return "Pro"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .days: return "calendar"
        case .routines: return "figure.walk"
        case .calendar: return "calendar.badge.clock"
        case .reminders: return "bell"
        case .tags: return "tag"
        case .ai: return "sparkles"
        case .storage: return "externaldrive"
        case .license: return "star.circle"
        }
    }

    @ViewBuilder
    var content: some View {
        switch self {
        case .general: GeneralSettingsView()
        case .days: DaysSettingsView()
        case .routines: RoutinesSettingsView()
        case .calendar: CalendarSettingsView()
        case .reminders: RemindersSettingsView()
        case .tags: TagsSettingsView()
        case .ai: AISettingsView()
        case .storage: StorageSettingsView()
        case .license: ProSettingsView()
        }
    }
}
