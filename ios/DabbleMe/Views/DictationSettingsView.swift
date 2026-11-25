import Speech
import SwiftUI

/// Settings → Dictation: the composer's microphone on or off, how what's said is written down
/// (Polished or Verbatim), and Custom Vocabulary: names and terms spelled the writer's way, then
/// the hashtags that go with them (listed, not editable here).
struct DictationSettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(DictationSettings.enabledKey) private var isEnabled = true
    @AppStorage(DictationSettings.liveKey) private var typesAsSpoken = true
    @AppStorage(DictationSettings.styleKey) private var style = DictationStyle.polished
    @AppStorage(DictationSettings.wordsKey) private var storedWords = ""
    @AppStorage(DictationSettings.languageKey) private var language = ""
    @AppStorage(AppleIntelligenceCleanup.enabledKey) private var fixesMisheardWords = false
    /// The languages the phone's transcriber has, by name.
    @State private var languages: [(id: String, name: String)] = []
    @State private var newWord = ""
    @FocusState private var addingWord: Bool
    /// The writer's hashtags, as the composer fetches them, for the list under Custom Vocabulary.
    @State private var recentTags: [String] = []
    @State private var allTags: [String] = []

    private var words: [String] { DictationSettings.words(from: storedWords) }
    /// The hashtags dictation expects beside `words`, as it orders and caps them.
    private var hashtagTerms: [String] {
        Dictation.hashtagTerms(words: words, recentTags: recentTags, allTags: allTags)
    }
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
                    Text("Not available on this iPhone.")
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
                    Toggle(isOn: $typesAsSpoken) {
                        Label("Type as I Speak", icon: "slab-edit")
                    }
                } footer: {
                    if typesAsSpoken {
                        Text("Words appear as you talk and can change until you stop.")
                    } else {
                        Text("Words appear once you tap Done.")
                    }
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
                    // The field first, so a word added below it never moves it, and Return
                    // adds the word and leaves the keyboard up for the next one. (A one-line
                    // field's Return ends editing; this one takes the line break itself.)
                    HStack {
                        TextField("Add a word or phrase", text: $newWord, axis: .vertical)
                            .lineLimit(1)
                            .focused($addingWord)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            // (Should Return ever submit instead, it still adds the word.)
                            .onSubmit(add)
                            .onChange(of: newWord) { _, typed in
                                if typed.contains(where: \.isNewline) { add() }
                            }
                        if !newWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Button("Add", action: add)
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                    // The newest first, just under the field.
                    ForEach(words.reversed(), id: \.self) { word in
                        Text(word)
                    }
                    .onDelete { offsets in
                        let shown = Array(words.reversed())
                        for word in offsets.map({ shown[$0] }) {
                            storedWords = DictationSettings.removing(word, from: storedWords)
                        }
                    }
                } header: {
                    Text("Custom Vocabulary")
                } footer: {
                    Text("Spell names and terms your way.")
                }

                if !hashtagTerms.isEmpty {
                    Section {
                        ForEach(hashtagTerms, id: \.self) { tag in
                            Text("#" + tag)
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("From Your Hashtags")
                    } footer: {
                        Text("Added automatically. Your words above come first.")
                    }
                }
            }
        }
        .slabBackButton()
        .navigationTitle("Dictation")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: style)
        .task { await loadLanguages() }
        .task { await loadHashtags() }
    }

    private func loadHashtags() async {
        // Offline, the list just isn't shown; dictation fetches them again when it starts.
        recentTags = (try? await model.recentHashtags()) ?? []
        allTags = ((try? await model.allHashtags()) ?? []).map(\.tag)
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
        let word = newWord.replacingOccurrences(of: "\n", with: " ")
        let added = DictationSettings.adding(word, to: storedWords)
        // Kept in the field when it isn't added (the list is full), with the line break gone.
        guard added != storedWords || word.trimmingCharacters(in: .whitespaces).isEmpty else {
            newWord = word.trimmingCharacters(in: .whitespaces)
            return
        }
        storedWords = added
        newWord = ""
        addingWord = true
    }
}
