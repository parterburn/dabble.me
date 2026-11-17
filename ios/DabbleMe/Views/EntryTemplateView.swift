import SwiftUI

/// Settings → Entry Template: headings or questions an entry can start from, written and
/// formatted as an entry is. Kept as it's typed; emptied, there's no template.
struct EntryTemplateView: View {
    @State private var editor = RichTextEditorModel(typed: EntryTemplate.runs)
    @AppStorage(EntryTemplate.autoKey) private var addsToNewEntries = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // (The button's own icon, in the sentence.)
            Text("A starting point for your entries: headings or questions you answer each time. Add it from the \(inlineIcon("slab-lightbulb", named: "Prompt")) button while writing, or touch and hold that button to add it straight away.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)
                .padding(.top, 10)
            Toggle("Start New Entries with It", isOn: $addsToNewEntries)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            Divider()
            // (Format shows while words are selected, as in the composer.)
            RichTextEditor(model: editor, trailing: editor.hasSelection ? AnyView(formatButton.foregroundStyle(.tint)) : nil,
                           barKey: "\(editor.hasSelection)")
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
    }

    /// Bold, italic and underline for the selected words, as in an entry.
    private var formatButton: some View {
        Menu {
            Button { editor.toggleBold() } label: { Label("Bold", icon: "bold") }
            Button { editor.toggleItalic() } label: { Label("Italic", icon: "italic") }
            Button { editor.toggleUnderline() } label: { Label("Underline", icon: "underline") }
        } label: {
            appIcon("slab-format")
                .frame(width: 40, height: 36)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Format")
    }

    private func save() {
        guard editor.isDirty else { return }
        EntryTemplate.runs = editor.isEmpty ? [] : editor.typedRuns
    }
}
