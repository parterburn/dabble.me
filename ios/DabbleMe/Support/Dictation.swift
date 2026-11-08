import AVFoundation
import Speech

/// PRO voice dictation in the editor. Speech is recognized on the device only
/// (`requiresOnDeviceRecognition`), so neither audio nor text leaves the phone for it.
@MainActor
final class Dictation {
    /// On-device recognition for the user's language (needs a recent iPhone or iPad).
    static var isSupported: Bool {
        SFSpeechRecognizer()?.supportsOnDeviceRecognition == true
    }

    private(set) var isListening = false
    /// Called with the whole transcript so far, each time it changes.
    var onTranscript: (String) -> Void = { _ in }
    var onStateChange: (Bool) -> Void = { _ in }

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    enum Failure: LocalizedError {
        case speechDenied, microphoneDenied, unavailable

        var errorDescription: String? {
            switch self {
            case .speechDenied: "Allow Speech Recognition for Dabble Me in Settings to dictate."
            case .microphoneDenied: "Allow the microphone for Dabble Me in Settings to dictate."
            case .unavailable: "On-device dictation isn't available for your language on this device."
            }
        }
    }

    func start() async throws {
        guard !isListening else { return }
        let speech = await Self.requestSpeechAuthorization()
        guard speech == .authorized else { throw Failure.speechDenied }
        guard await AVAudioApplication.requestRecordPermission() else { throw Failure.microphoneDenied }
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            throw Failure.unavailable
        }

        #if DEBUG
        // UI tests: the simulator often can't reach the Mac's microphone (the audio engine then
        // aborts), so -DabbleDictationSkipAudio YES stops after the permission checks.
        if UserDefaults.standard.bool(forKey: "DabbleDictationSkipAudio") {
            isListening = true
            onStateChange(true)
            return
        }
        #endif

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        Self.installTap(on: engine.inputNode, feeding: request)
        engine.prepare()
        do {
            try engine.start()
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            throw error
        }

        self.request = request
        task = Self.recognize(with: recognizer, request: request) { [weak self] text, finished in
            Task { @MainActor in
                guard let self else { return }
                if let text { self.onTranscript(text) }
                if finished { self.finish() }
            }
        }
        isListening = true
        onStateChange(true)
    }

    /// Stops listening; the last words still come through `onTranscript`.
    func stop() {
        guard isListening else { return }
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "DabbleDictationSkipAudio") {
            isListening = false
            onStateChange(false)
            return
        }
        #endif
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        isListening = false
        onStateChange(false)
    }

    private func finish() {
        stop()
        task = nil
        request = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // Permission, audio and recognition callbacks arrive on background threads, so they're set up
    // outside the main actor (a closure written on the main actor would trap when called there).
    nonisolated private static func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
    }

    nonisolated private static func installTap(on input: AVAudioInputNode, feeding request: SFSpeechAudioBufferRecognitionRequest) {
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
            request.append(buffer)
        }
    }

    nonisolated private static func recognize(with recognizer: SFSpeechRecognizer, request: SFSpeechAudioBufferRecognitionRequest,
                                              handler: @escaping @Sendable (String?, Bool) -> Void) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            handler(result?.bestTranscription.formattedString, result?.isFinal == true || error != nil)
        }
    }
}
