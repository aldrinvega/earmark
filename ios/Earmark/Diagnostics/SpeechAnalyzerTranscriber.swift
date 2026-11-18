import AVFoundation
import CoreMedia
import Foundation
import ReadAlongCore
import Speech

/// The iOS 26 engine: `SpeechAnalyzer` + `SpeechTranscriber`, which transcribes long-form audio entirely on device.
///
/// The analyzer has no server path at all. The language model is an asset, so the first run in a locale installs it
/// through `AssetInventory`; `isAvailable` is false on devices (and simulators) without the model, and the chooser
/// then uses `LegacySpeechTranscriber`.
///
/// The file is analysed with `SpeechAnalyzer.analyzeSequence(from:)` and words come from each final result's
/// `.audioTimeRange` attribute, so every `TranscriptWord` carries real audio time.
struct SpeechAnalyzerTranscriber: Transcribing {
    /// English (US) for the first Earmark build; the EPUB's language will pick this later.
    let locale: Locale

    init(locale: Locale = Locale(identifier: "en-US")) {
        self.locale = locale
    }

    /// Whether this device can run the iOS 26 analyzer right now.
    ///
    /// False before iOS 26 and on devices without Apple's on-device speech model; the app then falls back to
    /// `SFSpeechRecognizer` (still on device).
    static var isAvailable: Bool {
        guard #available(iOS 26.0, *) else { return false }
        return SpeechTranscriber.isAvailable
    }

    func transcribe(audioFile: URL) async throws -> [TranscriptWord] {
        guard #available(iOS 26.0, *) else {
            throw TranscriptionError.unavailableOnDevice
        }
        return try await transcribeWithAnalyzer(audioFile: audioFile)
    }

    @available(iOS 26.0, *)
    private func transcribeWithAnalyzer(audioFile: URL) async throws -> [TranscriptWord] {
        // SpeechTranscriber has no network path; if its model is not available there is nothing to fall back to here.
        guard SpeechTranscriber.isAvailable else {
            throw TranscriptionError.failed("SpeechTranscriber is not available on this iPhone (isAvailable is false).")
        }

        try await SpeechRecognitionAuthorization.ensureAuthorized()
        if Task.isCancelled { throw TranscriptionError.cancelled }

        guard let supportedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw TranscriptionError.failed("SpeechTranscriber has no model for \(locale.identifier) on this iPhone.")
        }

        let transcriber = SpeechTranscriber(
            locale: supportedLocale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: [.audioTimeRange]
        )
        try await Self.installAssetsIfNeeded(for: transcriber)
        if Task.isCancelled { throw TranscriptionError.cancelled }

        let audio: AVAudioFile
        do {
            audio = try AVAudioFile(forReading: audioFile)
        } catch {
            throw TranscriptionError.failed(error.localizedDescription)
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        do {
            let words = try await withTaskCancellationHandler {
                // Start reading results before feeding audio, or the first result can be missed.
                async let collected = Self.collectWords(from: transcriber)
                _ = try await analyzer.analyzeSequence(from: audio)
                try await analyzer.finalizeAndFinishThroughEndOfInput()
                return try await collected
            } onCancel: {
                Task { await analyzer.cancelAndFinishNow() }
            }

            if Task.isCancelled { throw TranscriptionError.cancelled }
            return words
        } catch {
            if Task.isCancelled || error is CancellationError {
                throw TranscriptionError.cancelled
            }
            if let transcriptionError = error as? TranscriptionError {
                throw transcriptionError
            }
            throw TranscriptionError.failed(error.localizedDescription)
        }
    }

    /// Downloads the on-device model for this transcriber if it is not installed yet.
    @available(iOS 26.0, *)
    private static func installAssetsIfNeeded(for transcriber: SpeechTranscriber) async throws {
        let status = await AssetInventory.status(forModules: [transcriber])
        switch status {
        case .installed:
            return
        case .unsupported:
            throw TranscriptionError.failed(
                "Apple's speech model is not supported on this iPhone (AssetInventory status: unsupported).")
        default:
            // .supported or .downloading: ask for the download (the request may be nil when another process owns it).
            guard let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else {
                throw TranscriptionError.failed(
                    "The speech model is not installed and iOS returned no download request (status: \(status)).")
            }
            do {
                try await request.downloadAndInstall()
            } catch {
                throw TranscriptionError.failed("Downloading the speech model failed: \(error.localizedDescription)")
            }
        }
    }

    /// Collects the final results of one analyzer run into words.
    @available(iOS 26.0, *)
    private static func collectWords(from transcriber: SpeechTranscriber) async throws -> [TranscriptWord] {
        var words: [TranscriptWord] = []
        for try await result in transcriber.results {
            // Only finals are requested, but ignore anything that is still volatile anyway.
            guard result.isFinal else { continue }
            appendWords(in: result.text, to: &words)
        }
        return words
    }

    /// Splits each timed run of the result's `AttributedString` into words, keeping the run's audio time range.
    ///
    /// Runs usually hold one word (plus its punctuation or trailing space); if a run holds several words they share
    /// the run's range, which the aligner tolerates.
    @available(iOS 26.0, *)
    private static func appendWords(in text: AttributedString, to words: inout [TranscriptWord]) {
        for run in text.runs {
            guard let timeRange = run[AttributeScopes.SpeechAttributes.TimeRangeAttribute.self] else { continue }
            let start = timeRange.start.seconds
            let end = timeRange.end.seconds
            guard start.isFinite, end.isFinite, end > start else { continue }

            let chunk = String(text[run.range].characters)
            for token in chunk.split(whereSeparator: { $0.isWhitespace }) {
                words.append(TranscriptWord(text: String(token), start: start, end: end))
            }
        }
    }
}
