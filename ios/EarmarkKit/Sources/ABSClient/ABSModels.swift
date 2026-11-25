import Foundation

public struct ABSServerStatus: Sendable, Equatable, Decodable {
    public let serverVersion: String
    public let isInit: Bool
}

public struct ABSLibrary: Sendable, Equatable, Decodable {
    public let id: String
    public let name: String
    public let mediaType: String
}

public struct ABSChapter: Sendable, Equatable, Decodable {
    public let id: Int
    public let start: Double
    public let end: Double
    public let title: String
}

public struct ABSTrack: Sendable, Equatable, Decodable {
    public let startOffset: Double
    public let duration: Double
    public let contentUrl: String?
    public let mimeType: String?
}

/// One Book in a library listing.
public struct ABSBookSummary: Sendable, Equatable, Decodable, Identifiable {
    public let id: String
    public let title: String
    public let authorName: String?
    public let duration: Double
    public let numChapters: Int

    private enum CodingKeys: String, CodingKey { case id, media }
    private struct Media: Decodable {
        let metadata: Metadata
        let duration: Double?
        let numChapters: Int?
    }
    private struct Metadata: Decodable {
        let title: String
        let authorName: String?
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        let media = try container.decode(Media.self, forKey: .media)
        title = media.metadata.title
        authorName = media.metadata.authorName
        duration = media.duration ?? 0
        numChapters = media.numChapters ?? 0
    }
}

public struct ABSBookPage: Sendable, Equatable {
    public let books: [ABSBookSummary]
    public let total: Int
}

/// One Book with its chapters and tracks (`GET /api/items/{id}?expanded=1`).
public struct ABSBookDetail: Sendable, Equatable, Decodable {
    public let id: String
    public let title: String
    public let authorName: String?
    public let duration: Double
    public let chapters: [ABSChapter]
    public let tracks: [ABSTrack]

    private enum CodingKeys: String, CodingKey { case id, media }
    private struct Media: Decodable {
        let metadata: Metadata
        let duration: Double?
        let chapters: [ABSChapter]?
        let tracks: [ABSTrack]?
    }
    private struct Metadata: Decodable {
        let title: String
        let authorName: String?
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        let media = try container.decode(Media.self, forKey: .media)
        title = media.metadata.title
        authorName = media.metadata.authorName
        duration = media.duration ?? 0
        chapters = media.chapters ?? []
        tracks = media.tracks ?? []
    }
}

/// A play session: where to resume and which files to stream.
public struct ABSPlaySession: Sendable, Equatable, Decodable {
    public let id: String
    public let libraryItemId: String
    public let duration: Double
    public let currentTime: Double
    public let chapters: [ABSChapter]
    public let audioTracks: [ABSTrack]
}

public struct ABSProgress: Sendable, Equatable, Decodable {
    public let currentTime: Double
    public let duration: Double
    public let progress: Double
    public let isFinished: Bool
    /// Milliseconds since 1970, set by the server; the newest wins when two devices disagree.
    public let lastUpdate: Int64
}

/// One Book's saved progress from `GET /api/me` (`mediaProgress`), for the shelf and the Continue card.
public struct ABSBookProgress: Sendable, Equatable, Decodable {
    public let libraryItemId: String
    public let currentTime: Double
    public let duration: Double
    public let progress: Double
    public let isFinished: Bool
    /// Milliseconds since 1970, stamped by the server.
    public let lastUpdate: Int64
}
