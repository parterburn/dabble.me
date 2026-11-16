import AVFoundation
import Speech
import SwiftUI

/// Speaking an entry instead of typing it, with iOS 26's on-device transcriber (SpeechTranscriber),
/// which hears a good deal better than the keyboard's dictation. What's said never leaves the
/// phone. The first use downloads the language's model, which iOS keeps (it isn't part of the app).
@MainActor
@Observable
final class Dictation {
    enum State: Equatable {
        case idle
        /// Asking for the microphone, or fetching the model.
        case preparing
        case listening
        /// Stopped: the last words are being settled.
        case finishing
    }

    enum Problem: Error, Equatable {
        case microphoneDenied
        case language
        case download
        case unavailable

        var message: String {
            switch self {
            case .microphoneDenied: "Allow the microphone for Dabble Me to speak your entry."
            case .language: "Speaking an entry isn't available in your language yet."
            case .download: "Couldn't download what's needed to listen. Check your connection and try again."
            case .unavailable: "Couldn't start listening. Try again."
            }
        }
    }

    private(set) var state: State = .idle
    /// The words being heard that aren't settled yet (they change as more is said).
    private(set) var hearing = ""
    private(set) var problem: Problem?
    /// The model's download, 0...1, while it's coming down.
    private(set) var downloadProgress: Double?

    @ObservationIgnored private var run: Task<Void, Never>?
    /// Ends the microphone's part; what's been said is still settled and handed over.
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

    /// UI tests and screenshots: `-DabbleDebugDictation YES` hears a made-up sentence, since the
    /// simulator has no transcriber.
    private static var isDebugFake: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "DabbleDebugDictation")
        #else
        false
        #endif
    }

    /// Starts listening. Each stretch that's settled (about a sentence) goes to `insert`.
    func start(insert: @escaping @MainActor (String) -> Void) {
        guard state == .idle else { return }
        problem = nil
        hearing = ""
        state = .preparing
        run = Task {
            do {
                if Self.isDebugFake {
                    try await pretend(insert)
                } else if #available(iOS 26.0, *) {
                    try await listen(insert)
                }
            } catch is CancellationError {
            } catch let problem as Problem {
                self.problem = problem
            } catch {
                problem = .unavailable
            }
            endInput = nil
            abandon = nil
            hearing = ""
            downloadProgress = nil
            state = .idle
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    /// Stops listening; the words still being heard are settled and put in the entry.
    func stop() {
        switch state {
        case .idle, .finishing: break
        case .preparing: cancel()
        case .listening:
            state = .finishing
            endInput?()
        }
    }

    /// `stop()`, waiting until the last words are in (before saving).
    func finish() async {
        stop()
        await run?.value
    }

    /// Stops and drops what wasn't settled (the composer closing).
    func cancel() {
        abandon?()
        run?.cancel()
    }

    func clearProblem() { problem = nil }

    @available(iOS 26.0, *)
    private func listen(_ insert: @escaping @MainActor (String) -> Void) async throws {
        guard await AVAudioApplication.requestRecordPermission() else { throw Problem.microphoneDenied }
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: .current) else { throw Problem.language }
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults], attributeOptions: [])
        try await install(transcriber)
        try Task.checkCancellation()

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else { throw Problem.unavailable }
        let (input, feed) = AsyncStream<AnalyzerInput>.makeStream()
        let microphone = try MicrophoneCapture(format: format, feed: feed)
        endInput = {
            microphone.stop()
            Task { try? await analyzer.finalizeAndFinishThroughEndOfInput() }
        }
        abandon = {
            microphone.stop()
            Task { await analyzer.cancelAndFinishNow() }
        }
        // A phone call or another app taking the microphone ends it, keeping what was said.
        let interruptions = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: AVAudioSession.interruptionNotification).map({ _ in () }) {
                self?.stop()
            }
        }
        defer {
            interruptions.cancel()
            microphone.stop()
        }
        try await analyzer.start(inputSequence: input)
        try Task.checkCancellation()
        state = .listening
        UIApplication.shared.isIdleTimerDisabled = true
        for try await result in transcriber.results {
            let text = String(result.text.characters)
            if result.isFinal {
                hearing = ""
                insert(text)
            } else {
                hearing = text
            }
        }
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

    /// The made-up sentence, a word at a time, until it's stopped.
    private func pretend(_ insert: @escaping @MainActor (String) -> Void) async throws {
        var stopped = false
        endInput = { stopped = true }
        try await Task.sleep(for: .milliseconds(400))
        state = .listening
        for sentence in ["We walked along the river after dinner.", " Leo found a heron standing in the shallows."] {
            for word in sentence.split(separator: " ", omittingEmptySubsequences: false) {
                if stopped { break }
                hearing += (hearing.isEmpty ? "" : " ") + word
                try await Task.sleep(for: .milliseconds(180))
            }
            if !hearing.isEmpty { insert(hearing) }
            hearing = ""
            if stopped { return }
        }
        while !stopped { try await Task.sleep(for: .milliseconds(100)) }
    }

    /// What goes into the entry for a settled stretch: trimmed, with a space before it unless
    /// it starts the entry or a line, or follows a space.
    nonisolated static func insertion(of heard: String, after previous: Character?) -> String {
        let words = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return "" }
        guard let previous, !previous.isWhitespace else { return words }
        return " " + words
    }
}

/// The microphone, handed to the transcriber in the audio format it asks for. Not on the main
/// actor: the tap is called on the audio thread.
@available(iOS 26.0, *)
private final class MicrophoneCapture: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let format: AVAudioFormat
    private let converter: AVAudioConverter
    private let feed: AsyncStream<AnalyzerInput>.Continuation
    private let lock = NSLock()
    private var isStopped = false

    init(format: AVAudioFormat, feed: AsyncStream<AnalyzerInput>.Continuation) throws {
        self.format = format
        self.feed = feed
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .default)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        let input = engine.inputNode
        let heard = input.outputFormat(forBus: 0)
        guard heard.sampleRate > 0, let converter = AVAudioConverter(from: heard, to: format) else { throw Dictation.Problem.unavailable }
        converter.primeMethod = .none
        self.converter = converter
        input.installTap(onBus: 0, bufferSize: 4096, format: heard) { [weak self] buffer, _ in
            guard let self, let converted = self.convert(buffer) else { return }
            self.feed.yield(AnalyzerInput(buffer: converted))
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            stop()
            throw Dictation.Problem.unavailable
        }
    }

    func stop() {
        lock.lock()
        let wasStopped = isStopped
        isStopped = true
        lock.unlock()
        guard !wasStopped else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        feed.finish()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if buffer.format == format { return buffer }
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 16
        guard let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        nonisolated(unsafe) var handedOver = false
        var error: NSError?
        let status = converter.convert(to: converted, error: &error) { _, inputStatus in
            if handedOver {
                inputStatus.pointee = .noDataNow
                return nil
            }
            handedOver = true
            inputStatus.pointee = .haveData
            return buffer
        }
        return status == .error ? nil : converted
    }
}
