import Speech
import SwiftUI

/// Settings → Dictation: the composer's microphone on or off, how what's said is written down
/// (Polished or Verbatim), and Custom Vocabulary: names and terms spelled the writer's way, beside their hashtags.
struct DictationSettingsView: View {
    @AppStorage(DictationSettings.enabledKey) private var isEnabled = true
    @AppStorage(DictationSettings.styleKey) private var style = DictationStyle.polished
    @AppStorage(DictationSettings.wordsKey) private var storedWords = ""
    @AppStorage(DictationSettings.languageKey) private var language = ""
    /// The languages the phone's transcriber has, by name.
    @State private var languages: [(id: String, name: String)] = []
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
                    Picker("Language", selection: $language) {
                        Text("Automatic (\(Self.name(of: .current)))").tag("")
                        ForEach(languages, id: \.id) { language in
                            Text(language.name).tag(language.id)
                        }
                    }
                } footer: {
                    Text("Automatic follows your iPhone's language. A new language downloads once, the first time you speak in it.")
                }

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
                    if DictationSettings.cleansUp(language.isEmpty ? .current : Locale(identifier: language)) {
                        Text(style.explanation)
                    } else {
                        Text("Polished tidies English only. In this language, what you say is written as heard either way.")
                    }
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
                        TextField("Add a word or phrase", text: $newWord)
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
                    Text("Custom Vocabulary")
                } footer: {
                    Text("Spell names and terms your way, like a friend's name or a place. Your hashtags are already included. Up to \(Dictation.maxHints) terms.")
                }
            }
        }
        .slabBackButton()
        .navigationTitle("Dictation")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: style)
        .task { await loadLanguages() }
    }

    private func loadLanguages() async {
        guard #available(iOS 26.0, *) else { return }
        let locales = await SpeechTranscriber.supportedLocales
        languages = locales
            .map { (id: $0.identifier(.bcp47), name: Self.name(of: $0)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// "English (United States)", in the phone's own language.
    private static func name(of locale: Locale) -> String {
        Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
    }

    private func add() {
        storedWords = DictationSettings.adding(newWord, to: storedWords)
        newWord = ""
        addingWord = true
    }
}
