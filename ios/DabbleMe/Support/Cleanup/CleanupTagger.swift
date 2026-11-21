// Ported from Hex (github.com/anomalyco/hex, ios/HEXShared/CleanupTagger.swift), MIT License,
// Copyright (c) 2026 Christopher Langton. See DabbleMe/Resources/CleanupTagger/Hex-LICENSE.txt.
// Dabble Me keeps the model and its runs as Hex has them, without Hex's settings, styles,
// keyboard extension, or other languages' word rules.

import CoreML
import Foundation
import UIKit

/// Tidies a spoken entry (`Dictation`): a small BERT token classifier (4 layers, 512 wide, int8
/// Core ML weights, fine-tuned by Hex from Google's Apache-2.0 `bert_uncased_L-4_H-512_A-8`)
/// gives each spoken word P(DELETE), `CleanupGuard` lets only known disfluencies go (ums,
/// repeats, false starts, and the words a spoken correction replaces: "at 3, actually 4"), and
/// `CleanupReconstruction` mends the commas and capitals next to what went. It only removes
/// words; it never adds, reorders, or changes one. English only, and on the phone only.
///
/// The model and its WordPiece vocabulary ship in the app (`Resources/CleanupTagger`). It loads
/// when listening starts (`prepare`), so the load overlaps the speaking, stays loaded while the
/// app runs, and is let go on a memory warning.
nonisolated final class CleanupTagger: @unchecked Sendable {
    static let shared = CleanupTagger()

    /// P(DELETE) a word must exceed to be marked; `CleanupGuard` then decides which marked words go.
    static let deleteThreshold = CleanupGuard.deleteThreshold
    /// Longest Core ML input, [CLS] and [SEP] included; longer transcripts are tagged in
    /// chunks of whole words.
    static let maxTokens = 128
    /// The model's enumerated sequence lengths; each chunk is padded to the next one.
    static let sequenceLengths = [16, 32, 64, 128]

    static let modelName = "HexCleanupTagger"
    static let vocabularyName = "HexCleanupTaggerVocab"

    enum TaggerError: Error {
        case missingResource(String)
        case badOutput
    }

    private struct Loaded {
        let model: MLModel
        let tokenizer: CleanupTokenizer
    }

    /// Owns `loaded`: every load, prediction, and release runs here, one at a time.
    private let queue = DispatchQueue(label: "me.dabble.ios.cleanup-tagger", qos: .userInitiated)
    private let computeUnits: MLComputeUnits
    private var loaded: Loaded?
    private var memoryWarningObserver: NSObjectProtocol?

    /// Not the GPU: in Hex's simulator runs its Metal pipeline took 0.8 s to load and added 30 MB.
    init(computeUnits: MLComputeUnits = .cpuAndNeuralEngine) {
        self.computeUnits = computeUnits
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.unload()
        }
    }

    deinit {
        if let memoryWarningObserver {
            NotificationCenter.default.removeObserver(memoryWarningObserver)
        }
    }

    /// Whether the model is in memory now.
    var isLoaded: Bool {
        queue.sync { loaded != nil }
    }

    /// Loads the model in the background if it isn't loaded yet.
    func prepare() {
        queue.async {
            _ = try? self.loadedOnQueue()
        }
    }

    /// Frees the model; the next cleanup loads it again.
    func unload() {
        queue.async {
            self.loaded = nil
        }
    }

    /// The cleaned transcript, or `text` itself when nothing is removed. Blocks the caller
    /// until the model has loaded and run; never call it on the main thread.
    /// `protectedTerms` (the writer's hashtags) go only in a self-correction.
    func clean(_ text: String, protectedTerms: [String] = []) throws -> String {
        try queue.sync { try cleanOnQueue(text, protectedTerms: protectedTerms) }
    }

    /// P(DELETE) for each whitespace-separated word, in order, as the model scores it.
    func deleteProbabilities(for words: [String]) throws -> [Double] {
        try queue.sync { try probabilitiesOnQueue(words) }
    }

    /// The cleaned transcript within `budget`, else `text` unchanged: any failure, a late
    /// answer, or a cleanup that removes every word keeps the transcript as heard. A late
    /// run still finishes in the background, so the model is ready for the next time.
    func clean(_ text: String, within budget: TimeInterval, protectedTerms: [String] = []) async -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return text }
        let gate = CleanupTaggerOnceGate()
        return await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
            queue.async {
                let cleaned = (try? self.cleanOnQueue(text, protectedTerms: protectedTerms)) ?? text
                let result = cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? text : cleaned
                if gate.claim() {
                    continuation.resume(returning: result)
                }
            }
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + budget) {
                if gate.claim() {
                    continuation.resume(returning: text)
                }
            }
        }
    }

    // MARK: On the queue

    private func cleanOnQueue(_ text: String, protectedTerms: [String]) throws -> String {
        let words = Self.words(in: text)
        guard !words.isEmpty else { return text }
        let deletes = try CleanupGuard.deletes(
            words,
            probabilities: probabilitiesOnQueue(words),
            protectedTerms: CleanupGuard.protectedTerms(protectedTerms)
        )
        guard deletes.contains(true) else { return text }
        return CleanupReconstruction.reconstruct(words, deletes: deletes)
    }

    private func probabilitiesOnQueue(_ words: [String]) throws -> [Double] {
        let state = try loadedOnQueue()
        var probabilities: [Double] = []
        probabilities.reserveCapacity(words.count)
        for chunk in Self.chunks(words.map { state.tokenizer.encode(CleanupGuard.modelWord($0)) }) {
            probabilities += try predict(chunk, model: state.model)
        }
        return probabilities
    }

    private func loadedOnQueue() throws -> Loaded {
        if let loaded { return loaded }
        guard let modelURL = Bundle.main.url(forResource: Self.modelName, withExtension: "mlmodelc") else {
            throw TaggerError.missingResource(Self.modelName)
        }
        guard let vocabularyURL = Bundle.main.url(forResource: Self.vocabularyName, withExtension: "txt") else {
            throw TaggerError.missingResource(Self.vocabularyName)
        }
        let tokenizer = try CleanupTokenizer(vocabulary: String(contentsOf: vocabularyURL, encoding: .utf8))
        let configuration = MLModelConfiguration()
        configuration.computeUnits = computeUnits
        let model = try MLModel(contentsOf: modelURL, configuration: configuration)
        let state = Loaded(model: model, tokenizer: tokenizer)
        loaded = state
        return state
    }

    /// One model run: [CLS] ids [SEP], zero-padded to an enumerated length, with the real
    /// length masking the padding. Returns P(DELETE) at each word's first subword.
    private func predict(_ chunk: Chunk, model: MLModel) throws -> [Double] {
        let count = chunk.ids.count
        guard let length = Self.sequenceLengths.first(where: { $0 >= count }) else {
            throw TaggerError.badOutput
        }
        let inputIDs = try MLMultiArray(shape: [1, NSNumber(value: length)], dataType: .int32)
        inputIDs.withUnsafeMutableBufferPointer(ofType: Int32.self) { buffer, strides in
            let step = strides[1]
            for position in 0..<length {
                buffer[position * step] = position < count ? chunk.ids[position] : CleanupTokenizer.padID
            }
        }
        let realLength = try MLMultiArray(shape: [1], dataType: .int32)
        realLength[0] = NSNumber(value: count)
        let input = try MLDictionaryFeatureProvider(dictionary: [
            "input_ids": MLFeatureValue(multiArray: inputIDs),
            "length": MLFeatureValue(multiArray: realLength),
        ])
        let output = try model.prediction(from: input)
        guard let logits = output.featureValue(for: "delete_logit")?.multiArrayValue,
              logits.count >= count else {
            throw TaggerError.badOutput
        }
        return chunk.firstTokens.map { position in
            guard let position else { return 0 } // a word with no tokens is kept
            let logit = logits[[0, NSNumber(value: position)]].doubleValue
            return 1 / (1 + exp(-logit))
        }
    }

    // MARK: Words and chunks

    struct Chunk: Equatable {
        /// [CLS], the words' WordPiece ids, [SEP].
        var ids: [Int32]
        /// Where each word's first subword sits in `ids`; nil for a word with no tokens.
        var firstTokens: [Int?]
    }

    /// The transcript's whitespace-separated words.
    static func words(in text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Whole words per chunk, each chunk within `maxTokens` with [CLS] and [SEP]. A single
    /// word longer than that keeps only its first tokens; only its first subword is scored.
    static func chunks(_ words: [[Int32]]) -> [Chunk] {
        var chunks: [Chunk] = []
        var current = Chunk(ids: [CleanupTokenizer.clsID], firstTokens: [])
        for var tokens in words {
            if !current.firstTokens.isEmpty, current.ids.count + 1 + tokens.count > maxTokens {
                current.ids.append(CleanupTokenizer.sepID)
                chunks.append(current)
                current = Chunk(ids: [CleanupTokenizer.clsID], firstTokens: [])
            }
            if tokens.count > maxTokens - 2 {
                tokens = Array(tokens.prefix(maxTokens - 2))
            }
            current.firstTokens.append(tokens.isEmpty ? nil : current.ids.count)
            current.ids += tokens
        }
        if !current.firstTokens.isEmpty {
            current.ids.append(CleanupTokenizer.sepID)
            chunks.append(current)
        }
        return chunks
    }
}

/// Resumes a cleanup race exactly once, whichever of the tagger or the budget finishes first.
private final class CleanupTaggerOnceGate: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !claimed else { return false }
        claimed = true
        return true
    }
}
