import AVFoundation
import AppFeatures
import Foundation
import ReadAlongCore

/// The test chapter bundled with the app (the package's public-domain `Fixtures` folder, copied by project.yml).
enum DiagnosticsBundle {
    static let clipName = "pp-ch3-clip.m4a"
    static let chapterName = "pp-ch3.xhtml"
    static let expectedName = "pp-ch3-expected-starts.json"

    static var folder: URL? { Bundle.main.url(forResource: "Fixtures", withExtension: nil) }
    static var clipURL: URL? { folder?.appending(path: clipName) }

    /// Builds the model with every engine this iPhone can run, in the preferred order.
    @MainActor
    static func makeModel() -> AlignTestModel {
        let folder = folder
        let clip = folder?.appending(path: clipName) ?? URL(fileURLWithPath: "/missing/\(clipName)")
        let chapter = folder.flatMap { try? Data(contentsOf: $0.appending(path: chapterName)) } ?? Data()
        let expected = folder.flatMap { try? Data(contentsOf: $0.appending(path: expectedName)) } ?? Data()
        return AlignTestModel(
            engines: availableEngines(),
            audioFile: clip,
            audioDuration: duration(of: clip),
            chapter: chapter,
            expectedStarts: expected
        )
    }

    static func availableEngines() -> [NamedTranscriber] {
        var engines: [NamedTranscriber] = []
        if SpeechAnalyzerTranscriber.isAvailable {
            engines.append(NamedTranscriber(name: TranscriptionEngine.speechAnalyzer.displayName,
                                            transcriber: SpeechAnalyzerTranscriber()))
        }
        if LegacySpeechTranscriber.isAvailable() {
            engines.append(NamedTranscriber(name: TranscriptionEngine.legacySpeechRecognizer.displayName,
                                            transcriber: LegacySpeechTranscriber()))
        }
        return engines
    }

    static func duration(of url: URL) -> TimeInterval {
        guard let file = try? AVAudioFile(forReading: url) else { return 180 }
        return Double(file.length) / file.processingFormat.sampleRate
    }
}
