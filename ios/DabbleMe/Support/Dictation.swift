import AVFoundation
import os
import Speech
import SwiftUI

/// Speaking an entry instead of typing it, the way Hex (github.com/anomalyco/hex) does it on the
/// iPhone: what's said is recorded, then, once it's stopped, transcribed in one pass over the
/// whole recording by iOS 26's on-device `SpeechTranscriber`, then tidied by `CleanupTagger`
/// (ums, repeats, and spoken corrections go), and put in the entry at the cursor.
///
/// Nothing shows while it's being said. That's the point: the keyboard's dictation and build 83's
/// microphone both wrote words as they came, a stretch at a time, and read no better for it. One
/// pass hears each word with everything around it, and the cleanup needs the whole of it too.
///
/// The writer's hashtags go to the transcriber as words to expect (names: "Leo", "Kenji"), and
/// the cleanup never drops one outside a correction. What's said never leaves the phone: the
/// recording is a temporary file, deleted once it's been transcribed or dropped. The first use
/// downloads the language's model, which iOS keeps (it isn't part of the app).
///
/// Quick to start and to finish, as Hex is: the model is loaded when the composer opens
/// (`prewarm`), not after Done, so a tap records at once and the words come back right after it.
/// How long each step took goes to the log (Console, "Dictation").
@MainActor
@Observable
final class Dictation {
    enum State: Equatable {
        case idle
        /// Asking for the microphone, or fetching the model.
        case preparing
        /// Recording.
        case listening
        /// Stopped: the recording is being transcribed and tidied.
        case writing
    }

    enum Problem: Error, Equatable {
        case microphoneDenied
        case language
        case download
        case nothingHeard
        case unavailable

        var message: String {
            switch self {
            case .microphoneDenied: "Allow the microphone for Dabble Me to speak your entry."
            case .language: "Speaking an entry isn't available in your language yet."
            case .download: "Couldn't download what's needed to listen. Check your connection and try again."
            case .nothingHeard: "Didn't hear anything. Try again."
            case .unavailable: "Couldn't start listening. Try again."
            }
        }
    }

    /// Longest recording, in seconds: a long entry, said in one go.
    static let maxDuration: TimeInterval = 15 * 60
    /// With no voice this long from the start, it stops and says it heard nothing, rather than
    /// seem to record when the microphone isn't getting anything.
    static let silenceLimit: TimeInterval = 10
    /// A level (`Recorder.level`, 0...1 over -50...0 dB) above this is a voice: about -40 dB,
    /// low so a soft voice counts. A quiet room sits under it.
    nonisolated static let voiceLevel = 0.2
    /// How long the cleanup may take before the words go in as heard.
    static let cleanupBudget: TimeInterval = 1.5
    /// Hex's limit on words for the transcriber to expect.
    nonisolated static let maxHints = 100

    private(set) var state: State = .idle
    private(set) var problem: Problem?
    /// The model's download, 0...1, while it's coming down.
    private(set) var downloadProgress: Double?
    /// When the recording started, for the row's clock.
    private(set) var listeningSince: Date?
    /// How loud it's been, 0...1, newest last: the waveform while recording.
    private(set) var levels: [Double] = []
    /// How many of `levels` are kept (the waveform's width in bars).
    static let levelCount = 48

    @ObservationIgnored private var run: Task<Void, Never>?
    /// The transcriber with its model loaded, for the next recording (`prewarm`): a
    /// `WarmSpeech` on iOS 26. Each one hears one recording.
    @ObservationIgnored private var warm: AnyObject?
    @ObservationIgnored private var warming: Task<Void, Never>?
    /// The composer has closed (`cancel`): nothing more is loaded for it.
    @ObservationIgnored private var isClosed = false
    /// Where this dictation's time went, for the log.
    @ObservationIgnored private var timings: [String] = []
    @ObservationIgnored private var tappedAt = ContinuousClock.now
    @ObservationIgnored private var stoppedAt = ContinuousClock.now
    static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "me.dabble.ios", category: "Dictation")
    /// Ends the recording; what was said is still transcribed and handed over.
    @ObservationIgnored private var endInput: (() -> Void)?
    /// Drops everything now.
    @ObservationIgnored private var abandon: (() -> Void)?

    var isActive: Bool { state != .idle }

    /// The phone can do it: iOS 26, on a device the transcriber runs on.
    static var isSupported: Bool {
        if isDebugFake { return true }
        if #available(iOS 26.0, *) { return SpeechTranscriber.isAvailable }
        return false
    }

    /// UI tests and screenshots: `-DabbleDebugDictation YES` hears a made-up sentence (with an
    /// "um" and a correction for the cleanup), since the simulator has no transcriber.
    private static var isDebugFake: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "DabbleDebugDictation")
        #else
        false
        #endif
    }

    /// Starts recording. Once it's stopped, the whole of what was said goes to `insert` at once.
    /// `hints` gives the writer's hashtags, asked for once the recording's done (they may still
    /// have been loading when it started). `canListen` is asked once the model is ready, in case
    /// the editor has lost the keyboard while it came down.
    /// `style`: Polished runs the cleanup, Verbatim leaves it as heard.
    func start(style: DictationStyle, hints: @escaping @MainActor () -> [String], canListen: @escaping @MainActor () -> Bool,
               insert: @escaping @MainActor (String) -> Void) {
        guard state == .idle else { return }
        problem = nil
        levels = []
        timings = []
        tappedAt = .now
        isClosed = false
        state = .preparing
        // Loaded while it's said, so it's ready when the transcript is. English only.
        let cleansUp = DictationSettings.cleansUp(DictationSettings.language ?? .current)
        if style == .polished, cleansUp {
            CleanupTagger.shared.prepare()
            AppleIntelligenceCleanup.prepare()
        }
        run = Task {
            do {
                let heard: String
                if Self.isDebugFake {
                    heard = try await pretend()
                } else if #available(iOS 26.0, *) {
                    heard = try await listen(hints: hints, canListen: canListen)
                } else {
                    throw Problem.unavailable
                }
                // The writer's own spellings ("dabble me" → "Dabble Me"), in either style.
                var lap = ContinuousClock.now
                let expected = Self.hints(from: hints())
                let spellings = Self.spellings(from: expected, vocabulary: DictationSettings.words)
                var cleaned = Self.ownSpellings(spellings, in: heard)
                lap = time("spellings", since: lap)
                if style == .polished, cleansUp {
                    cleaned = await CleanupTagger.shared.clean(cleaned, within: Self.cleanupBudget, protectedTerms: expected)
                    lap = time("cleanup", since: lap)
                    // Settings → Dictation → Fix Misheard Words (Apple Intelligence), when it's on.
                    if AppleIntelligenceCleanup.isEnabled {
                        cleaned = await AppleIntelligenceCleanup.clean(cleaned)
                        lap = time("apple intelligence", since: lap)
                    }
                    // "comma", "exclamation point", "hashtag leo": the marks, then the writer's own
                    // tags and spellings again (a capital after a new "." can undo "iPhone").
                    cleaned = SpokenPunctuation.format(cleaned, language: "en")
                    cleaned = Self.knownHashtags(in: cleaned, tags: expected)
                    cleaned = Self.ownSpellings(spellings, in: cleaned)
                    time("punctuation", since: lap)
                }
                try Task.checkCancellation()
                insert(cleaned)
                time("done to words", since: stoppedAt)
                let finished = timings.joined(separator: ", ")
                Self.log.notice("Dictation finished: \(finished, privacy: .public)")
            } catch is CancellationError {
            } catch let problem as Problem {
                self.problem = problem
            } catch {
                problem = .unavailable
            }
            endInput = nil
            abandon = nil
            downloadProgress = nil
            listeningSince = nil
            levels = []
            state = .idle
            UIApplication.shared.isIdleTimerDisabled = false
            // The next one's model, loaded now rather than after its Done.
            prewarm()
        }
    }

    /// Loads the transcriber's model, so the next tap records at once and its words come back
    /// right after Done (the composer opening, and after each dictation). Only once the model's
    /// on the phone: the first download waits for a tap, where its progress shows.
    ///
    /// Off the main thread but for two small objects: the checks and the loading are calls to
    /// iOS's speech service that are awaited, not waited on. No audio session, no microphone (so
    /// no orange dot), and nothing when dictation is off or the phone can't do it.
    func prewarm() {
        guard !Self.isDebugFake, !isClosed, warm == nil, warming == nil, state == .idle,
              Self.isSupported, DictationSettings.isEnabled else { return }
        guard #available(iOS 26.0, *) else { return }
        let requested = DictationSettings.language ?? .current
        warming = Task { [weak self] in
            let began = ContinuousClock.now
            let speech = await WarmSpeech.make(for: requested)
            guard let self else { return }
            self.warming = nil
            guard let speech, !self.isClosed else { return }
            // Kept while its model still loads: a tap now records at once, and waits for the
            // model only after Done.
            self.warm = speech
            Task {
                await speech.loading.value
                let loaded = Self.milliseconds(since: began)
                Self.log.notice("Dictation model loaded in \(loaded, privacy: .public) ms after the composer asked")
            }
        }
    }

    /// Notes how long `stage` took since `since`, for the log, and returns now for the next.
    @discardableResult
    private func time(_ stage: String, since: ContinuousClock.Instant) -> ContinuousClock.Instant {
        timings.append("\(stage) \(Self.milliseconds(since: since)) ms")
        return .now
    }

    private static func milliseconds(since: ContinuousClock.Instant) -> Int {
        Int(((ContinuousClock.now - since) / .milliseconds(1)).rounded())
    }

    /// Stops recording; what was said is transcribed and put in the entry.
    func stop() {
        switch state {
        case .idle, .writing: break
        case .preparing: drop()
        case .listening:
            stoppedAt = .now
            state = .writing
            endInput?()
        }
    }

    /// `stop()`, waiting until the words are in (before saving).
    func finish() async {
        stop()
        await run?.value
    }

    /// Stops and drops what was said (the composer closing).
    func cancel() {
        drop()
        isClosed = true
        warming?.cancel()
        warm = nil
    }

    /// The X: drops what was said, and gets ready for the next one.
    func discard() { drop() }

    private func drop() {
        abandon?()
        run?.cancel()
    }

    func clearProblem() { problem = nil }

    /// The hashtags as words to expect: without the "#", each once, at most `maxHints`.
    nonisolated static func hints(from tags: [String]) -> [String] {
        var seen: Set<String> = []
        var hints: [String] = []
        for tag in tags {
            let word = tag.trimmingCharacters(in: CharacterSet(charactersIn: "#").union(.whitespacesAndNewlines))
            guard !word.isEmpty, seen.insert(word.lowercased()).inserted else { continue }
            hints.append(word)
            if hints.count == maxHints { break }
        }
        return hints
    }

    /// The words to expect, in the order they're kept under `maxHints`: the writer's Custom
    /// Vocabulary first, so no number of hashtags can push one out, then the recent hashtags,
    /// then the rest (most used first).
    nonisolated static func expected(words: [String], recentTags: [String], allTags: [String]) -> [String] {
        hints(from: words + recentTags + allTags)
    }

    /// The hashtags that make it into `expected`, without the writer's own words: what
    /// Settings → Dictation lists under Custom Vocabulary.
    nonisolated static func hashtagTerms(words: [String], recentTags: [String], allTags: [String]) -> [String] {
        let own = Set(hints(from: words).map { $0.lowercased() })
        return expected(words: words, recentTags: recentTags, allTags: allTags).filter { !own.contains($0.lowercased()) }
    }

    /// What dictation holds to the writer's spelling (`VocabularySpelling`): every Custom
    /// Vocabulary word, and the hashtags that read as names ("Leo", "NYC"): one word with a
    /// capital that the dictionary doesn't know in lowercase. Not "#Work", which would capitalize
    /// every "work", and not a joined-up "#LeoBirthday", which would swallow "Leo's birthday".
    static func spellings(from expected: [String], vocabulary: [String]) -> [String] {
        let own = Set(vocabulary.map { $0.lowercased() })
        return expected.filter { own.contains($0.lowercased()) || isNameLike($0) }
    }

    private static func isNameLike(_ tag: String) -> Bool {
        guard tag.contains(where: \.isUppercase), tag.allSatisfy(\.isLetter),
              !VocabularySpelling.looksCompound(tag), let language = checkerLanguage else { return false }
        return !knowsInLowercase(tag, language: language)
    }

    /// A hashtag said aloud (`SpokenPunctuation`: "hashtag leo birthday" → "#leo birthday") takes
    /// the spelling of one the writer already uses, across up to four words, the longest first:
    /// "#LeoBirthday". One they don't use stays as said.
    nonisolated static func knownHashtags(in text: String, tags: [String]) -> String {
        let key = { (word: String) in word.lowercased().filter { $0.isLetter || $0.isNumber } }
        var known: [String: String] = [:]
        for tag in tags {
            let tagKey = key(tag)
            // Only a real tag: a Custom Vocabulary term with a space ("Dabble Me") isn't one.
            guard tag.allSatisfy({ $0.isLetter || $0.isNumber }) else { continue }
            if !tagKey.isEmpty, known[tagKey] == nil { known[tagKey] = tag }
        }
        guard !known.isEmpty, text.contains("#") else { return text }
        let words = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        var out: [String] = []
        var index = 0
        while index < words.count {
            let word = words[index]
            guard word.hasPrefix("#"), word.count > 1 else {
                out.append(word)
                index += 1
                continue
            }
            var matched = false
            for count in stride(from: min(4, words.count - index), through: 1, by: -1) {
                var cores = Array(words[index..<(index + count)])
                cores[0].removeFirst()
                // Only the last word may carry punctuation after it ("#leo birthday.").
                let last = cores[count - 1]
                let core = String(last.prefix { $0.isLetter || $0.isNumber })
                let trailing = String(last.dropFirst(core.count))
                cores[count - 1] = core
                guard !trailing.contains(where: { $0.isLetter || $0.isNumber }),
                      cores.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isLetter || $0.isNumber } }),
                      let tag = known[key(cores.joined())] else { continue }
                out.append("#" + tag + trailing)
                index += count
                matched = true
                break
            }
            if !matched {
                out.append(word)
                index += 1
            }
        }
        return out.joined(separator: " ")
    }

    // MARK: Recording, then transcribing

    @available(iOS 26.0, *)
    private func listen(hints: @MainActor () -> [String], canListen: @MainActor () -> Bool) async throws -> String {
        guard await AVAudioApplication.requestRecordPermission() else { throw Problem.microphoneDenied }
        var lap = time("permission", since: tappedAt)
        let speech = try await readySpeech()
        lap = time(speech.wasWarm ? "model (ready)" : "model", since: lap)
        try Task.checkCancellation()
        guard canListen() else { throw CancellationError() }

        // A recording left by a run the app didn't live to finish goes first: it's journal audio.
        let temporary = FileManager.default.temporaryDirectory
        for old in (try? FileManager.default.contentsOfDirectory(at: temporary, includingPropertiesForKeys: nil)) ?? []
        where old.lastPathComponent.hasPrefix("dictation-") && old.pathExtension == "wav" {
            try? FileManager.default.removeItem(at: old)
        }
        let url = temporary.appendingPathComponent("dictation-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let recorder = try Recorder(url: url, maxDuration: Self.maxDuration)
        defer { recorder.stop() }

        // Until Done (or the mic again, Save, the keyboard going, the app leaving), a phone
        // call, or the longest recording.
        let stopped = AsyncStream<Ending>.makeStream()
        endInput = { stopped.continuation.yield(.keep); stopped.continuation.finish() }
        abandon = { stopped.continuation.yield(.drop); stopped.continuation.finish() }
        let interruptions = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: AVAudioSession.interruptionNotification).map({ _ in () }) {
                self?.stop()
            }
        }
        defer { interruptions.cancel() }
        let started = Date.now
        let silence = stopped.continuation
        let metering = Task { [weak self] in
            var heardVoice = false
            while !Task.isCancelled {
                guard let self else { return }
                let level = recorder.level
                self.record(level: level)
                if level > Self.voiceLevel { heardVoice = true }
                if !recorder.isRecording, self.state == .listening { self.stop() }
                // Nothing like a voice yet: stop and say so.
                if !heardVoice, self.state == .listening, Date.now.timeIntervalSince(started) >= Self.silenceLimit {
                    silence.yield(.silent)
                    silence.finish()
                    return
                }
                try? await Task.sleep(for: .milliseconds(80))
            }
        }
        defer { metering.cancel() }

        state = .listening
        listeningSince = .now
        UIApplication.shared.isIdleTimerDisabled = true
        time("microphone", since: lap)
        time("tap to recording", since: tappedAt)
        let startedIn = timings.joined(separator: ", ")
        Self.log.notice("Dictation started: \(startedIn, privacy: .public)")
        var ending = Ending.drop
        for await end in stopped.stream { ending = end; break }
        recorder.stop()
        guard !Task.isCancelled else { throw CancellationError() }
        switch ending {
        case .keep: break
        case .drop: throw CancellationError()
        case .silent: throw Problem.nothingHeard
        }

        timings.append(String(format: "recorded %.1f s", Date.now.timeIntervalSince(started)))
        lap = stoppedAt
        // Loaded while it was said, when it wasn't ready at the tap.
        await speech.loading.value
        let analyzer = speech.analyzer
        // Each analyzer hears one recording and is let go, so the hints can't carry over.
        let expected = Self.hints(from: hints())
        if !expected.isEmpty {
            let context = AnalysisContext()
            context.contextualStrings[.general] = expected
            try? await analyzer.setContext(context)
        }
        let file = try AVAudioFile(forReading: url)
        try await analyzer.start(inputAudioFile: file, finishAfterFile: true)
        var transcript = AttributedString()
        for try await result in speech.transcriber.results where result.isFinal {
            transcript += result.text
        }
        time("transcribe", since: lap)
        let text = String(transcript.characters).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw Problem.nothingHeard }
        return text
    }

    /// The transcriber for this recording: the one `prewarm` loaded, else a new one (its model
    /// downloaded first if it isn't on the phone), loading while the recording runs.
    @available(iOS 26.0, *)
    private func readySpeech() async throws -> WarmSpeech {
        // Settings → Dictation's language, else the phone's.
        let requested = DictationSettings.language ?? .current
        // One being set up now (a quick check that the model's there) is further along.
        if let warming { await warming.value }
        defer { warm = nil }
        if let speech = warm as? WarmSpeech, speech.requested == requested.identifier { return speech }
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: requested) else { throw Problem.language }
        // `.transcription`: finished text only, no words-so-far, over the whole recording.
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        try await install(transcriber)
        return WarmSpeech(requested: requested.identifier, transcriber: transcriber, wasWarm: false)
    }

    /// How a recording ended: Done (transcribe it), dropped, or nothing heard in time.
    private enum Ending: Sendable { case keep, drop, silent }

    /// The language's model, fetched the first time (and after iOS has cleared it away).
    @available(iOS 26.0, *)
    private func install(_ transcriber: SpeechTranscriber) async throws {
        do {
            guard let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else { return }
            let progress = request.progress
            downloadProgress = 0
            let watching = Task { [weak self] in
                while !Task.isCancelled {
                    self?.downloadProgress = progress.fractionCompleted
                    try? await Task.sleep(for: .milliseconds(250))
                }
            }
            defer {
                watching.cancel()
                downloadProgress = nil
            }
            try await request.downloadAndInstall()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw Problem.download
        }
    }

    private func record(level: Double) {
        levels.append(level)
        if levels.count > Self.levelCount { levels.removeFirst(levels.count - Self.levelCount) }
    }

    /// The made-up recording: listens until it's stopped, then "hears" a sentence.
    private func pretend() async throws -> String {
        let stopped = AsyncStream<Bool>.makeStream()
        endInput = { stopped.continuation.yield(true); stopped.continuation.finish() }
        abandon = { stopped.continuation.yield(false); stopped.continuation.finish() }
        try await Task.sleep(for: .milliseconds(400))
        state = .listening
        listeningSince = .now
        // A voice-like wobble for the waveform.
        let wobble = Task { [weak self] in
            var tick = 0.0
            while !Task.isCancelled {
                tick += 1
                self?.record(level: 0.35 + 0.3 * sin(tick / 3) * cos(tick / 7) + 0.2 * sin(tick * 1.7))
                try? await Task.sleep(for: .milliseconds(80))
            }
        }
        defer { wobble.cancel() }
        var keeps = false
        for await keep in stopped.stream { keeps = keep; break }
        guard keeps else { throw CancellationError() }
        try await Task.sleep(for: .milliseconds(600))
        return "We walked along the river after, um, after dinner. Leo found a heron at 6, actually 7."
    }

    // MARK: Into the entry

    /// What goes into the entry for what was heard: trimmed, with a space before it unless it
    /// starts the entry or a line, or follows a space; and, in the middle of a sentence, its first
    /// word in lowercase when that's a dictionary word (not "I", a name, or an acronym).
    static func insertion(of heard: String, before: String) -> String {
        var words = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return "" }
        let previous = before.last
        if continuesSentence(before), let first = words.split(separator: " ").first.map(String.init),
           lowersMidSentence(first) {
            words = first.lowercased() + words.dropFirst(first.count)
        }
        guard let previous, !previous.isWhitespace else { return words }
        return " " + words
    }

    /// The text before the cursor stops mid-sentence: there is some, and it doesn't end with a
    /// sentence's end or a line break.
    nonisolated static func continuesSentence(_ before: String) -> Bool {
        let trimmed = before.trimmingCharacters(in: .whitespaces)
        guard let last = trimmed.last, !last.isNewline else { return false }
        return !".!?…:".contains(last)
    }

    /// The writer's spellings, by letters ("dabble me" → "Dabble Me"), then by sound for their
    /// one-word names ("Caitlin" → "Katelyn" when they tag #Katelyn).
    private static func ownSpellings(_ spellings: [String], in text: String) -> String {
        let spelled = VocabularySpelling.apply(spellings, to: text)
        // Only a capitalized one: a lowercase Custom Vocabulary word is no name to swap in.
        let names = spellings.filter { $0.first?.isUppercase == true && $0.allSatisfy(\.isLetter) }
        return SoundAlikeNames.apply(names, to: spelled, isOrdinaryWord: { isOrdinaryWord($0) })
    }

    /// The dictionary knows `word` in lowercase ("Cattle"). With no dictionary, every word is
    /// taken as ordinary, so nothing is changed by sound.
    private static func isOrdinaryWord(_ word: String) -> Bool {
        guard let language = checkerLanguage else { return true }
        return knowsInLowercase(word, language: language)
    }

    /// A capitalized first word that reads the same in lowercase: not "I" or its contractions,
    /// not an acronym or a word with capitals inside ("NASA", "iPhone"), and one the dictionary
    /// knows in lowercase (so "Leo" and "Denver" keep theirs).
    private static func lowersMidSentence(_ word: String) -> Bool {
        let letters = word.trimmingCharacters(in: .punctuationCharacters)
        guard let first = letters.first, first.isUppercase else { return false }
        if letters == "I" || letters.hasPrefix("I'") || letters.hasPrefix("I’") { return false }
        guard !letters.dropFirst().contains(where: \.isUppercase) else { return false }
        // No dictionary for the language: left as said.
        guard let language = checkerLanguage else { return false }
        return knowsInLowercase(letters, language: language)
    }

    /// The dictionary spells `word` in lowercase too ("work", not "leo").
    private static func knowsInLowercase(_ word: String, language: String) -> Bool {
        let lower = word.lowercased()
        let range = NSRange(location: 0, length: (lower as NSString).length)
        return checker.rangeOfMisspelledWord(in: lower, range: range, startingAt: 0, wrap: false, language: language).location == NSNotFound
    }

    /// One for every lookup: a dictation asks about each of its hundred hints and more.
    private static let checker = UITextChecker()

    /// The phone's language as `UITextChecker` names it ("en_US"), or one of its kind ("en_GB"),
    /// looked up once.
    private static let checkerLanguage: String? = {
        let available = UITextChecker.availableLanguages
        let identifier = Locale.current.identifier
        if available.contains(identifier) { return identifier }
        guard let code = Locale.current.language.languageCode?.identifier else { return nil }
        return available.first { $0 == code || $0.hasPrefix(code + "_") || $0.hasPrefix(code + "-") }
    }()
}

/// A transcriber and the analyzer that will hear one recording, its model loading from the start
/// (`prepareToAnalyze`), as Hex keeps one ready: loaded after Done, the model was most of the
/// wait for the words. `.lingering` keeps the model in memory a while after, for the next one.
@available(iOS 26.0, *)
@MainActor
private final class WarmSpeech {
    /// The language it was asked for (`Locale.identifier`), to tell whether Settings changed.
    let requested: String
    let transcriber: SpeechTranscriber
    let analyzer: SpeechAnalyzer
    /// The model loading; done once it's ready to hear.
    let loading: Task<Void, Never>
    /// Ready at the tap (`Dictation.prewarm`), for the log.
    let wasWarm: Bool

    init(requested: String, transcriber: SpeechTranscriber, wasWarm: Bool) {
        self.requested = requested
        self.transcriber = transcriber
        self.wasWarm = wasWarm
        let analyzer = SpeechAnalyzer(modules: [transcriber],
                                      options: SpeechAnalyzer.Options(priority: .userInitiated, modelRetention: .lingering))
        self.analyzer = analyzer
        // A failure here shows when it's used.
        loading = Task { try? await analyzer.prepareToAnalyze(in: nil) }
    }

    /// One for `requested`, its model loading, or nil when the language isn't there or its model
    /// isn't on the phone yet (the tap downloads it).
    static func make(for requested: Locale) async -> WarmSpeech? {
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: requested) else { return nil }
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        guard await AssetInventory.status(forModules: [transcriber]) == .installed, !Task.isCancelled else { return nil }
        // The only part on the main thread: making the analyzer. Logged, to keep it honest.
        let began = ContinuousClock.now
        let speech = WarmSpeech(requested: requested.identifier, transcriber: transcriber, wasWarm: true)
        let onMain = (ContinuousClock.now - began) / .milliseconds(1)
        Dictation.log.notice("Dictation prewarm: \(onMain, format: .fixed(precision: 1), privacy: .public) ms on the main thread")
        return speech
    }
}

/// The microphone, recorded to a 16 kHz mono WAV, as Hex records it. On the main actor.
@MainActor
private final class Recorder {
    /// Stopped recorders, kept a few seconds (`stop`).
    private static var retired: [AVAudioRecorder] = []
    private let recorder: AVAudioRecorder
    private var isStopped = false
    /// The session's category before recording, put back after (`.record` silences playback).
    private let previous: (category: AVAudioSession.Category, mode: AVAudioSession.Mode, options: AVAudioSession.CategoryOptions)

    init(url: URL, maxDuration: TimeInterval) throws {
        let session = AVAudioSession.sharedInstance()
        previous = (session.category, session.mode, session.categoryOptions)
        do {
            // `.measurement`: the microphone as it is, without the voice-call processing.
            try session.setCategory(.record, mode: .measurement)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            recorder = try AVAudioRecorder(url: url, settings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsFloatKey: false,
            ])
        } catch {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            try? session.setCategory(previous.category, mode: previous.mode, options: previous.options)
            throw Dictation.Problem.unavailable
        }
        recorder.isMeteringEnabled = true
        recorder.prepareToRecord()
        guard recorder.record(forDuration: maxDuration) else {
            stop()
            throw Dictation.Problem.unavailable
        }
    }

    var isRecording: Bool { recorder.isRecording }

    /// 0...1 from the average power (-50 dB and below is silence).
    var level: Double {
        guard recorder.isRecording else { return 0 }
        recorder.updateMeters()
        let power = Double(recorder.averagePower(forChannel: 0))
        return min(1, max(0, (power + 50) / 50))
    }

    func stop() {
        guard !isStopped else { return }
        isStopped = true
        recorder.stop()
        // Hex: a recorder freed while its audio queue winds down crashed on the queue's thread,
        // so it's held a few seconds after stopping.
        Self.retired.append(recorder)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            if !Self.retired.isEmpty { Self.retired.removeFirst() }
        }
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        try? session.setCategory(previous.category, mode: previous.mode, options: previous.options)
    }
}
