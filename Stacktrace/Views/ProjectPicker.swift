import SwiftUI

/// Picker to (optionally) attach an entry to a project. Hidden if there are no
/// projects yet.
struct ProjectPicker: View {
    @Binding var projectID: UUID?
    @EnvironmentObject private var store: DataStore

    var body: some View {
        if !store.projects.isEmpty {
            Picker("Project", selection: $projectID) {
                Text("None").tag(UUID?.none)
                ForEach(store.projects) { project in
                    Text(project.name).tag(UUID?.some(project.id))
                }
            }
        }
    }
}
