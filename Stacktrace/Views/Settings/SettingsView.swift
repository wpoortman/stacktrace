import SwiftUI

/// App preferences in a grouped sidebar (no tab overflow). Add a case to
/// `SettingsPane` and place it in a group below.
struct SettingsView: View {
    @State private var selection: SettingsPane = .general

    private struct Group: Identifiable {
        let title: String
        let panes: [SettingsPane]
        var id: String { title }
    }
    private let groups = [
        Group(title: "App", panes: [.general, .storage, .license]),
        Group(title: "Logging", panes: [.days, .tags]),
        Group(title: "Schedule", panes: [.routines, .calendar, .reminders, .holiday]),
        Group(title: "Assist", panes: [.ai]),
    ]

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(groups) { group in
                    Section(group.title) {
                        ForEach(group.panes) { pane in
                            Label(pane.title, systemImage: pane.systemImage)
                                .tag(pane)
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(190)
        } detail: {
            selection.content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 740, height: 500)
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
    case holiday

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
        case .holiday: return "Holiday"
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
        case .holiday: return "beach.umbrella"
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
        case .holiday: HolidaySettingsView()
        }
    }
}
