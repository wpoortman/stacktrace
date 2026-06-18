import SwiftUI
import AppKit

/// Team sync + your rate (Pro). Read-only here; the agency admin manages
/// members and rates in the web admin.
struct TeamSettingsView: View {
    @EnvironmentObject private var pro: ProManager
    @EnvironmentObject private var team: TeamManager
    @EnvironmentObject private var store: DataStore

    private static let adminURL = URL(string: "https://stacktrace.app/admin")!

    var body: some View {
        if !pro.isPro {
            ProLockedView(feature: "Team")
        } else {
            Form {
                Section {
                    Toggle("Sync my daily summary to my team", isOn: $team.syncEnabled)
                    if team.syncEnabled {
                        TextField("Team server URL (blank = demo)", text: $team.baseURLString)
                            .textFieldStyle(.roundedBorder)
                    }
                } header: {
                    Text("Team sync")
                } footer: {
                    Text("Shares only coarse daily numbers — entries count, wins/setbacks, an average wellbeing score, and your day score. Never your notes. Off by default.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                if team.syncEnabled {
                    Section("Your rate") {
                        if let p = team.profile {
                            LabeledContent("Name", value: p.name)
                            LabeledContent("Role", value: p.role)
                            LabeledContent("Base rate", value: rate(p.baseRateCents, p.currency))
                            LabeledContent("Effective rate", value: rate(p.effectiveRateCents, p.currency))
                        } else {
                            Text("Not loaded yet.").foregroundStyle(.secondary)
                        }
                        HStack {
                            Button("Refresh") { Task { await team.refresh() } }
                            Button("Sync today") { Task { await team.syncDay(store) } }
                            if team.isBusy { ProgressView().controlSize(.small) }
                        }
                        if let err = team.lastError {
                            Text(err).font(.caption).foregroundStyle(.red)
                        }
                    }
                }

                Section {
                    Button("Open Team Admin (web)") { NSWorkspace.shared.open(Self.adminURL) }
                } footer: {
                    Text("Agency owners manage members, roles, and rates in the browser admin.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .task { await team.refresh() }
        }
    }

    private func rate(_ cents: Int, _ currency: String) -> String {
        let f = NumberFormatter(); f.numberStyle = .currency; f.currencyCode = currency
        return f.string(from: NSNumber(value: Double(cents) / 100)) ?? "\(cents)"
    }
}
