import SwiftUI
import AppKit

/// Activate a Pro license with a key (Individual or Team seat).
struct ProSettingsView: View {
    @EnvironmentObject private var pro: ProManager
    @State private var key = ""

    private static let buyURL = URL(string: "https://stacktrace.app/pricing")!

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; return f
    }()

    var body: some View {
        Form {
            if pro.isPro, let e = pro.entitlement {
                Section {
                    Label("Pro is active", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    LabeledContent("Plan", value: e.plan.title)
                    LabeledContent("Seats", value: e.plan == .custom ? "Custom" : "\(e.seats)")
                    LabeledContent("Renews", value: Self.dateFormatter.string(from: e.expires))
                    LabeledContent("License", value: maskedKey(e.key))
                    Button("Deactivate this device", role: .destructive) {
                        Task { await pro.deactivate() }
                    }
                } header: {
                    Text("License")
                } footer: {
                    Text("Deactivating frees this seat so it can be used on another Mac.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Section {
                    TextField("Enter license key", text: $key)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Button("Activate") {
                            Task { await pro.activate(key) }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty || pro.isWorking)
                        if pro.isWorking { ProgressView().controlSize(.small) }
                        Spacer()
                        Button("Buy a license") { NSWorkspace.shared.open(Self.buyURL) }
                    }
                    if let err = pro.lastError {
                        Text(err).font(.caption).foregroundStyle(.red)
                    }
                } header: {
                    Text("Unlock Pro")
                } footer: {
                    Text("Individual is one seat. Team covers up to 50 seats from a single key — the agency owner shares it with the team. Larger? Choose Custom on the pricing page to reach out.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func maskedKey(_ k: String) -> String {
        guard k.count > 4 else { return "••••" }
        return "••••" + k.suffix(4)
    }
}

/// Placeholder shown where a Pro-only feature would be, with a way to unlock.
struct ProLockedView: View {
    let feature: String
    @AppStorage("settingsPane") private var paneRaw = "general"

    var body: some View {
        ContentUnavailableView {
            Label("\(feature) is a Pro feature", systemImage: "star.circle.fill")
        } description: {
            Text("Unlock Pro to use \(feature).")
        } actions: {
            SettingsLink {
                Text("Unlock Pro")
            }
            .buttonStyle(.borderedProminent)
            .simultaneousGesture(TapGesture().onEnded { paneRaw = "license" })
        }
    }
}
