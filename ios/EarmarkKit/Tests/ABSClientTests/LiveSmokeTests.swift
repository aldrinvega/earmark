import Foundation
import Testing
@testable import ABSClient

/// Manual contract check against the real server. Skipped unless EARMARK_ABS_URL, EARMARK_ABS_USER and
/// EARMARK_ABS_PASSWORD are set (never committed). It reads only, and closes the play session straight away.
private let env = ProcessInfo.processInfo.environment

@Suite(.enabled(if: env["EARMARK_ABS_URL"] != nil)) struct LiveSmokeTests {
    @Test func theRealServerDecodesEndToEnd() async throws {
        let url = try #require(env["EARMARK_ABS_URL"].flatMap(URL.init(string:)))
        let abs = ABSClient(baseURL: url, transport: URLSessionTransport(), tokenStore: InMemoryTokenStore())
        #expect(try await abs.status().isInit)
        try await abs.login(username: env["EARMARK_ABS_USER"] ?? "", password: env["EARMARK_ABS_PASSWORD"] ?? "")
        let library = try #require(try await abs.libraries().first)
        let page = try await abs.books(inLibrary: library.id, limit: 5)
        let summary = try #require(page.books.first)
        let book = try await abs.book(id: summary.id)
        #expect(book.chapters.count == summary.numChapters)
        #expect(try await abs.coverData(bookID: book.id).count > 1000)
        let session = try await abs.startPlayback(bookID: book.id, deviceID: "earmark-live-smoke")
        let track = try #require(session.audioTracks.first)
        let request = try await abs.audioRequest(for: track)
        #expect(request.headers["Authorization"] != nil)
        try await abs.sync(sessionID: session.id, currentTime: session.currentTime, timeListened: 0, duration: session.duration)
        try await abs.close(sessionID: session.id, currentTime: session.currentTime, timeListened: 0)
        _ = try await abs.progress(bookID: book.id)
        print("live smoke: \(page.total) books, '\(book.chapters.count)' chapters, \(session.audioTracks.count) track(s)")
    }
}
