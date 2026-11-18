import ReadAlongCore

/// A speech engine and the name the Diagnostics screen shows for it.
public struct NamedTranscriber: Sendable {
    public let name: String
    public let transcriber: any Transcribing

    public init(name: String, transcriber: any Transcribing) {
        self.name = name
        self.transcriber = transcriber
    }
}
