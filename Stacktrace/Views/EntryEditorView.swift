import SwiftUI

/// Sheet for creating / editing one entry. Works on a local copy; commits to
/// the store on Done. A blank new entry is discarded.
struct EntryEditorView: View {
    @State var entry: ReportEntry
    let isNew: Bool

    @EnvironmentObject private var store: DataStore
    @Environment(\.dismiss) private var dismiss

    @State private var newTagText: String = ""

    @State private var isEnhancing = false
    @State private var enhanceError: String?
    @State private var undoSnapshot: EntryText?

    private var currentText: EntryText {
        EntryText(title: entry.title, detail: entry.detail,
                  wentWell: entry.wentWell, wentBad: entry.wentBad)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    field("Title") {
                        TextField("What did you work on?", text: $entry.title)
                            .textFieldStyle(.roundedBorder)
                    }
                    field("How did it go?") {
                        MoodPicker(mood: $entry.mood)
                    }
                    field("Description") {
                        editor($entry.detail, height: 110,
                               placeholder: "What did you do?")
                    }
                    field("What went well") {
                        editor($entry.wentWell, height: 80,
                               placeholder: "Wins, progress, things that worked.")
                    }
                    field("What went bad / to improve") {
                        editor($entry.wentBad, height: 80,
                               placeholder: "Blockers, mistakes, things to do better.")
                    }
                    field("Tags") {
                        tagEditor
                    }
                }
                .padding(20)
            }

            if let enhanceError {
                Text(enhanceError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 6)
                    .background(Color.red.opacity(0.08))
            }

            footer
        }
        .frame(width: 540, height: 712)
    }

    private var header: some View {
        HStack {
            Text(DateFormat.dayHeader.string(from: entry.date))
                .font(.headline)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.bar)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button("Cancel", role: .cancel) { dismiss() }
            if !isNew {
                Button("Delete", role: .destructive) {
                    store.delete(entry)
                    dismiss()
                }
                .foregroundStyle(.red)
            }
            Spacer()

            if undoSnapshot != nil {
                Button("Undo") {
                    if let s = undoSnapshot { apply(s) }
                    undoSnapshot = nil
                }
            }

            Button(action: enhance) {
                if isEnhancing {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Enhance with AI", systemImage: "sparkles")
                }
            }
            .disabled(isEnhancing || currentText.isAllEmpty)

            Button("Done") {
                addTypedTag()
                if !entry.isEmpty || !isNew {
                    store.upsert(entry)
                }
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.bar)
    }

    private var tagEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !entry.tags.isEmpty {
                FlowLayout {
                    ForEach(entry.tags, id: \.self) { tag in
                        TagChip(name: tag, filled: true, trailingSystemImage: "xmark") {
                            entry.tags.removeAll { $0 == tag }
                        }
                    }
                }
            }

            let available = store.tags.filter { !entry.tags.contains($0) }
            if !available.isEmpty {
                Text("Click to add")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                FlowLayout {
                    ForEach(available, id: \.self) { tag in
                        TagChip(name: tag) { entry.tags.append(tag) }
                    }
                }
            }

            HStack {
                TextField("New tag…", text: $newTagText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addTypedTag() }
                Button("Add", action: addTypedTag)
                    .disabled(newTagText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func field<Content: View>(
        _ label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func editor(_ text: Binding<String>, height: CGFloat,
                        placeholder: String) -> some View {
        ZStack(alignment: .topLeading) {
            if text.wrappedValue.isEmpty {
                Text(placeholder)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)
                    .padding(.leading, 7)
            }
            SpellCheckTextEditor(text: text)
                .padding(4)
        }
        .frame(height: height)
        .background(Color(nsColor: .textBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor))
        )
    }

    private func addTypedTag() {
        guard let name = store.addTag(newTagText) else { return }
        if !entry.tags.contains(name) {
            entry.tags.append(name)
        }
        newTagText = ""
    }

    private func enhance() {
        enhanceError = nil
        let snapshot = currentText
        isEnhancing = true
        Task {
            do {
                let result = try await EnhancementService.enhance(snapshot)
                undoSnapshot = snapshot
                apply(result)
            } catch {
                enhanceError = error.localizedDescription
            }
            isEnhancing = false
        }
    }

    private func apply(_ text: EntryText) {
        entry.title = text.title
        entry.detail = text.detail
        entry.wentWell = text.wentWell
        entry.wentBad = text.wentBad
    }
}
