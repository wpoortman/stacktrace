import SwiftUI

/// Tags preference pane: add / rename / delete catalog tags. Renames and
/// deletes propagate to every entry through the store.
struct TagsSettingsView: View {
    @EnvironmentObject private var store: DataStore
    @State private var newTag: String = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("New tag…", text: $newTag)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                Button("Add", action: add)
                    .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(16)

            Divider()

            if store.tags.isEmpty {
                ContentUnavailableView("No tags yet", systemImage: "tag",
                                       description: Text("Add a tag above to reuse it on entries."))
                    .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(store.tags, id: \.self) { tag in
                        TagSettingsRow(tag: tag)
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private func add() {
        store.addTag(newTag)
        newTag = ""
    }
}

private struct TagSettingsRow: View {
    let tag: String
    @EnvironmentObject private var store: DataStore
    @State private var draft: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack {
            TextField("Tag name", text: $draft)
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit(commit)
                .onChange(of: focused) { _, isFocused in
                    if !isFocused { commit() }
                }
            Spacer()
            Button(role: .destructive) {
                store.deleteTag(tag)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.red)
        }
        .onAppear { draft = tag }
    }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            draft = tag
            return
        }
        if trimmed != tag {
            store.renameTag(tag, to: trimmed)
            draft = trimmed
        }
    }
}
