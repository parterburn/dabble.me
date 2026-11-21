import AVFoundation
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
            case .nothingHeard: "Didn't hear anything. Try again, a little closer to the phone."
            case .unavailable: "Couldn't start listening. Try again."
            }
        }
    }

    /// Longest recording, in seconds: a long entry, said in one go.
    static let maxDuration: TimeInterval = 15 * 60
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
        state = .preparing
        // Loaded while it's said, so it's ready when the transcript is. English only.
        let cleansUp = DictationSettings.cleansUp(DictationSettings.language ?? .current)
        if style == .polished, cleansUp { CleanupTagger.shared.prepare() }
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
                var cleaned = heard
                if style == .polished, cleansUp {
                    cleaned = await CleanupTagger.shared.clean(heard, within: Self.cleanupBudget, protectedTerms: Self.hints(from: hints()))
                    // Settings → Dictation → Fix Misheard Words (Apple Intelligence), when it's on.
                    cleaned = await AppleIntelligenceCleanup.clean(cleaned)
                }
                try Task.checkCancellation()
                insert(cleaned)
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
        }
    }

    /// Stops recording; what was said is transcribed and put in the entry.
    func stop() {
        switch state {
        case .idle, .writing: break
        case .preparing: cancel()
        case .listening:
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

    // MARK: Recording, then transcribing

    @available(iOS 26.0, *)
    private func listen(hints: @MainActor () -> [String], canListen: @MainActor () -> Bool) async throws -> String {
        guard await AVAudioApplication.requestRecordPermission() else { throw Problem.microphoneDenied }
        // Settings → Dictation's language, else the phone's.
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: DictationSettings.language ?? .current) else { throw Problem.language }
        // `.transcription`: finished text only, no words-so-far, over the whole recording.
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        try await install(transcriber)
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
        let stopped = AsyncStream<Bool>.makeStream()
        endInput = { stopped.continuation.yield(true); stopped.continuation.finish() }
        abandon = { stopped.continuation.yield(false); stopped.continuation.finish() }
        let interruptions = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: AVAudioSession.interruptionNotification).map({ _ in () }) {
                self?.stop()
            }
        }
        defer { interruptions.cancel() }
        let metering = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.record(level: recorder.level)
                if !recorder.isRecording, self.state == .listening { self.stop() }
                try? await Task.sleep(for: .milliseconds(80))
            }
        }
        defer { metering.cancel() }

        state = .listening
        listeningSince = .now
        UIApplication.shared.isIdleTimerDisabled = true
        var keeps = false
        for await keep in stopped.stream { keeps = keep; break }
        recorder.stop()
        guard keeps, !Task.isCancelled else { throw CancellationError() }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
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
        for try await result in transcriber.results where result.isFinal {
            transcript += result.text
        }
        let text = String(transcript.characters).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw Problem.nothingHeard }
        return text
    }

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
        let lower = letters.lowercased()
        let range = NSRange(location: 0, length: (lower as NSString).length)
        return UITextChecker().rangeOfMisspelledWord(in: lower, range: range, startingAt: 0, wrap: false, language: language).location == NSNotFound
    }

    /// The phone's language as `UITextChecker` names it ("en_US"), or one of its kind ("en_GB").
    private static var checkerLanguage: String? {
        let available = UITextChecker.availableLanguages
        let identifier = Locale.current.identifier
        if available.contains(identifier) { return identifier }
        guard let code = Locale.current.language.languageCode?.identifier else { return nil }
        return available.first { $0 == code || $0.hasPrefix(code + "_") || $0.hasPrefix(code + "-") }
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
