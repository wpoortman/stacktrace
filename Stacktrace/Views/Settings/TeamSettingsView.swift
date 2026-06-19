import SwiftUI
import AppKit

/// Team sync (Pro). The employee never sees rates or billing — that lives only
/// in the agency's web admin. This pane is just consent + a manual sync.
struct TeamSettingsView: View {
    @EnvironmentObject private var pro: ProManager
    @EnvironmentObject private var team: TeamManager
    @EnvironmentObject private var store: DataStore

    var body: some View {
        if !pro.isPro {
            ProLockedView(feature: "Team")
        } else {
            Form {
                Section {
                    Toggle("Share my daily summary with my team", isOn: $team.syncEnabled)
                    if team.syncEnabled {
                        LabeledContent("Server", value: team.connectionDescription)
                        HStack {
                            Button("Sync today") { Task { await team.syncDay(store) } }
                            if team.isBusy { ProgressView().controlSize(.small) }
                        }
                        if let err = team.lastError {
                            Text(err).font(.caption).foregroundStyle(.red)
                        }
                    }
                } header: {
                    Text("Team sync")
                } footer: {
                    Text("Shares only coarse daily numbers — entries count, wins/setbacks, an average wellbeing score, and your day score. Never your notes. Off by default.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section {
                    Button("Open Team Admin (web)") { NSWorkspace.shared.open(AppConfig.adminURL) }
                } footer: {
                    Text("Agency owners manage members and the team in the browser admin.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
    }
}
