import Speech
import SwiftUI

/// Settings → Dictation: the composer's microphone on or off, how what's said is written down
/// (Polished or Verbatim), and Custom Vocabulary: names and terms spelled the writer's way, beside their hashtags.
struct DictationSettingsView: View {
    @AppStorage(DictationSettings.enabledKey) private var isEnabled = true
    @AppStorage(DictationSettings.styleKey) private var style = DictationStyle.polished
    @AppStorage(DictationSettings.wordsKey) private var storedWords = ""
    @AppStorage(DictationSettings.languageKey) private var language = ""
    @AppStorage(AppleIntelligenceCleanup.enabledKey) private var fixesMisheardWords = false
    /// The languages the phone's transcriber has, by name.
    @State private var languages: [(id: String, name: String)] = []
    @State private var newWord = ""
    @FocusState private var addingWord: Bool

    private var words: [String] { DictationSettings.words(from: storedWords) }
    private var cleansUp: Bool { DictationSettings.cleansUp(language.isEmpty ? .current : Locale(identifier: language)) }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $isEnabled) {
                    Label("Speak Your Entries", icon: "slab-microphone")
                }
                .disabled(!Dictation.isSupported)
            } footer: {
                if Dictation.isSupported {
                    Text("Tap the microphone while writing. It all stays on your phone.")
                } else {
                    Text("Needs iOS 26.")
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
                    Text("Automatic uses your iPhone's language.")
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
                    if cleansUp {
                        Text(style.explanation)
                    } else {
                        Text("Polished only works in English.")
                    }
                }

                // Apple Intelligence's pass, after Polished: only where it's on, and in English.
                if style == .polished, cleansUp, AppleIntelligenceCleanup.isAvailable {
                    Section {
                        Toggle(isOn: $fixesMisheardWords) {
                            Label("Fix Misheard Words", icon: "slab-sparkles")
                        }
                    } footer: {
                        Text("Experimental. Uses Apple Intelligence to fix words it got wrong.")
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
                    Text("Spell names and terms your way. Your hashtags are included.")
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
