import SwiftUI

/// Settings → Dictation: the composer's microphone on or off, how what's said is written down
/// (Polished or Verbatim), and the writer's own words for it to expect, beside their hashtags.
struct DictationSettingsView: View {
    @AppStorage(DictationSettings.enabledKey) private var isEnabled = true
    @AppStorage(DictationSettings.styleKey) private var style = DictationStyle.polished
    @AppStorage(DictationSettings.wordsKey) private var storedWords = ""
    @State private var newWord = ""
    @FocusState private var addingWord: Bool

    private var words: [String] { DictationSettings.words(from: storedWords) }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $isEnabled) {
                    Label("Speak Your Entries", icon: "slab-microphone")
                }
                .disabled(!Dictation.isSupported)
            } footer: {
                if Dictation.isSupported {
                    Text("A microphone at the far right of the bar over the keyboard. Talk, tap Done, and what you said is written in where the cursor is. It's all done on your phone: nothing you say is sent anywhere.")
                } else {
                    Text("Speaking an entry needs iOS 26 on an iPhone that can turn speech into words by itself.")
                }
            }

            if isEnabled, Dictation.isSupported {
                Section {
                    Picker("Style", selection: $style) {
                        ForEach(DictationStyle.allCases) { style in
                            Text(style.label).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Style")
                } header: {
                    Text("Style")
                } footer: {
                    Text(style.explanation)
                }

                Section {
                    ForEach(words, id: \.self) { word in
                        Text(word)
                    }
                    .onDelete { offsets in
                        for word in offsets.map({ words[$0] }) {
                            storedWords = DictationSettings.removing(word, from: storedWords)
                        }
                    }
                    HStack {
                        TextField("Add a name or word", text: $newWord)
                            .focused($addingWord)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .onSubmit(add)
                        if !newWord.trimmingCharacters(in: .whitespaces).isEmpty {
                            Button("Add", action: add)
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                } header: {
                    Text("Words to Expect")
                } footer: {
                    Text("Names and words it should listen for and spell your way, like a friend's name or a place. Your hashtags are already included. Up to \(Dictation.maxHints).")
                }
            }
        }
        .slabBackButton()
        .navigationTitle("Dictation")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: style)
    }

    private func add() {
        storedWords = DictationSettings.adding(newWord, to: storedWords)
        newWord = ""
        addingWord = true
    }
}
