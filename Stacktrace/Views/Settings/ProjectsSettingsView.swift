import SwiftUI

/// Manage projects (name + description). Entries can be attached to a project
/// and a project-specific PDF exported from Generate Report.
struct ProjectsSettingsView: View {
    @EnvironmentObject private var store: DataStore
    @State private var editing: Project?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Group entries under a project, then export a report for just that project.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button {
                    editing = Project(name: "")
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
            .padding(16)

            Divider()

            if store.projects.isEmpty {
                ContentUnavailableView("No projects yet", systemImage: "folder",
                    description: Text("Add a project to tag entries and run per-project reports."))
                    .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(store.projects) { project in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(project.name).font(.headline)
                            if !project.details.isEmpty {
                                Text(project.details).font(.caption).foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { editing = project }
                    }
                }
                .listStyle(.inset)
            }
        }
        .sheet(item: $editing) { project in
            ProjectEditor(project: project)
        }
    }
}

private struct ProjectEditor: View {
    @State var project: Project
    @EnvironmentObject private var store: DataStore
    @Environment(\.dismiss) private var dismiss

    private var exists: Bool { store.projects.contains { $0.id == project.id } }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Name", text: $project.name)
                    TextField("Description", text: $project.details, axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                if exists {
                    Button("Delete", role: .destructive) {
                        store.deleteProject(project); dismiss()
                    }
                    .foregroundStyle(.red)
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save") {
                    store.upsertProject(project); dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(project.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(16)
        }
        .frame(width: 440, height: 360)
    }
}
