import SwiftUI

/// Settings → Entry Template: headings or questions an entry can start from, written and
/// formatted as an entry is. Kept as it's typed; emptied, there's no template.
struct EntryTemplateView: View {
    @Environment(AppModel.self) private var model
    @State private var editor = RichTextEditorModel(typed: EntryTemplate.runs)
    @AppStorage(EntryTemplate.autoKey) private var addsToNewEntries = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // (The button's own icon, in the sentence.)
            Text("A starting point for your entries: headings or questions you answer each time. Add it from the \(inlineIcon("slab-lightbulb", named: "Prompt")) button while writing, or touch and hold that button to add it straight away. Touch and hold a Write button on Today to start an entry with it.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)
                .padding(.top, 10)
            Toggle("Start New Entries with It", isOn: $addsToNewEntries)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            Divider()
            // (Format is always there: it's the bar's only button here.)
            RichTextEditor(model: editor, trailing: AnyView(formatButton.foregroundStyle(.tint)), barKey: "\(editor.isFormatted)")
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
        .onDisappear { save() }
        .onChange(of: addsToNewEntries) { AccountSettings.changed(.entryTemplateAuto, model: model) }
    }

    /// Bold, italic and underline, as in an entry: for the selected words or, with none, for
    /// what's typed next.
    private var formatButton: some View {
        Menu {
            Button { editor.toggleBold() } label: { Label("Bold", icon: "bold") }
            Button { editor.toggleItalic() } label: { Label("Italic", icon: "italic") }
            Button { editor.toggleUnderline() } label: { Label("Underline", icon: "underline") }
        } label: {
            // (Filled in while the words it's for are bold, italic or underlined.)
            appIcon(editor.isFormatted ? "slab-format-full" : "slab-format")
                .frame(width: 40, height: 36)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Format")
    }

    private func save() {
        guard editor.isDirty else { return }
        EntryTemplate.runs = editor.isEmpty ? [] : editor.typedRuns
        // On the account too, so signing out or a new phone doesn't lose it.
        AccountSettings.changed(.entryTemplate, model: model)
    }
}
