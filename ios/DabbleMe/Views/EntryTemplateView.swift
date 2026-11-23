import SwiftUI

/// Settings → Entry Template: headings or questions an entry can start from, written and
/// formatted as an entry is. Kept as it's typed; emptied, there's no template.
struct EntryTemplateView: View {
    @Environment(AppModel.self) private var model
    @State private var editor = RichTextEditorModel(typed: EntryTemplate.runs)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // (The button's own icon, in the sentence.)
            Text("A starting point for your entries: headings or questions you answer each time. A new entry shows it, faintly, on its empty page: swipe right or tap Swipe to start from it, or just start writing. Touch and hold a Write button on Today to open a new entry with it already in.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 12)
            Divider()
            // B, I and U, always: as in an entry's bar, and the only buttons here.
            RichTextEditor(model: editor, trailing: AnyView(formatButtons.foregroundStyle(.tint)),
                           barKey: "\(editor.isBold)|\(editor.isItalic)|\(editor.isUnderlined)")
                .overlay(alignment: .topLeading) {
                    if editor.isEmpty {
                        Text("What went well today?")
                            .font(Font(RichText.Style.journal.baseFont.with(bold: true, italic: false)))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 16)
                            .padding(.leading, 17)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
        }
        .background(Color(.systemBackground))
        .slabBackButton()
        .navigationTitle("Entry Template")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { editor.allowsLinks = false }
        .onChange(of: editor.revision) { save() }
        .onDisappear {
            save()
            // Sent to the account once, on the way out, not on every letter typed.
            AccountSettings.sync(with: model)
        }
    }

    /// Bold, italic and underline, the same letters as an entry's bar: for the selected words or,
    /// with none, for what's typed next. Each is lit while it's on.
    private var formatButtons: some View {
        HStack(spacing: 6) {
            FormatButton(name: "Bold", letter: .bold, isOn: editor.isBold) { editor.toggleBold() }
            FormatButton(name: "Italic", letter: .italic, isOn: editor.isItalic) { editor.toggleItalic() }
            FormatButton(name: "Underline", letter: .underline, isOn: editor.isUnderlined) { editor.toggleUnderline() }
        }
    }

    private func save() {
        guard editor.isDirty else { return }
        EntryTemplate.runs = editor.isEmpty ? [] : editor.typedRuns
        // On the account too, so signing out or a new phone doesn't lose it.
        AccountSettings.markPending(.entryTemplate)
    }
}
