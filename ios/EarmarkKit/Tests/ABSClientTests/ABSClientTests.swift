import Foundation
import Testing
@testable import ABSClient

/// Replays canned responses and records what the client sent.
actor FakeTransport: HTTPTransport {
    enum Step: Sendable {
        case reply(Int, String)
        case fail
    }

    private var steps: [Step]
    private(set) var requests: [HTTPRequest] = []

    init(_ steps: [Step]) {
        self.steps = steps
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        requests.append(request)
        guard !steps.isEmpty else { throw URLError(.cannotConnectToHost) }
        switch steps.removeFirst() {
        case .reply(let status, let body): return HTTPResponse(status: status, data: Data(body.utf8))
        case .fail: throw URLError(.notConnectedToInternet)
        }
    }
}

enum Fixture {
    static let tokens = #"{"user":{"id":"u1","accessToken":"ACCESS-2","refreshToken":"REFRESH-2"}}"#
    static let status = #"{"app":"audiobookshelf","serverVersion":"2.37.2","isInit":true,"authMethods":["local"]}"#
    static let libraries = #"{"libraries":[{"id":"lib1","name":"Audiobooks","mediaType":"book"}]}"#
    static let items = #"""
    {"results":[{"id":"b1","media":{"metadata":{"title":"A Book","authorName":"An Author"},"duration":25199.122,"numChapters":9}},
                {"id":"b2","media":{"metadata":{"title":"No Author"}}}],
     "total":32,"limit":2,"page":0}
    """#
    static let detail = #"""
    {"id":"b1","media":{"metadata":{"title":"A Book","authorName":"An Author"},"duration":100.5,
      "chapters":[{"id":0,"start":0,"end":60.25,"title":"Chapter 1"},{"id":1,"start":60.25,"end":100.5,"title":"Chapter 2"}],
      "tracks":[{"index":1,"startOffset":0,"duration":100.5,"contentUrl":"/api/items/b1/file/9","mimeType":"audio/mp4"}]}}
    """#
    static let session = #"""
    {"id":"s1","libraryItemId":"b1","duration":100.5,"currentTime":42.5,"playMethod":0,
     "chapters":[{"id":0,"start":0,"end":100.5,"title":"Chapter 1"}],
     "audioTracks":[{"index":1,"startOffset":0,"duration":100.5,"contentUrl":"/api/items/b1/file/9","mimeType":"audio/mp4"}]}
    """#
    static let progress = #"{"id":"p1","libraryItemId":"b1","duration":100.5,"progress":0.4228,"currentTime":42.5,"isFinished":false,"lastUpdate":1795561937019}"#
}

private let base = URL(string: "https://abs.example.test:8443")!

private func client(_ steps: [FakeTransport.Step], tokens: ABSTokens? = ABSTokens(access: "ACCESS-1", refresh: "REFRESH-1"))
    -> (ABSClient, FakeTransport, InMemoryTokenStore) {
    let transport = FakeTransport(steps)
    let store = InMemoryTokenStore(tokens)
    return (ABSClient(baseURL: base, transport: transport, tokenStore: store), transport, store)
}

@Suite struct ABSClientTests {
    @Test func statusDecodesTheServerVersion() async throws {
        let (abs, _, _) = client([.reply(200, Fixture.status)], tokens: nil)
        let status = try await abs.status()
        #expect(status.serverVersion == "2.37.2" && status.isInit)
    }

    @Test func loginAsksForTokensAndStoresThem() async throws {
        let (abs, transport, store) = client([.reply(200, Fixture.tokens)], tokens: nil)
        try await abs.login(username: "reader", password: "pw")
        let request = try #require(await transport.requests.first)
        #expect(request.method == "POST" && request.url.path == "/login")
        #expect(request.headers["x-return-tokens"] == "true")
        #expect(await store.load() == ABSTokens(access: "ACCESS-2", refresh: "REFRESH-2"))
    }

    @Test func wrongPasswordIsUnauthorizedAndStoresNothing() async {
        let (abs, _, store) = client([.reply(401, "Unauthorized")], tokens: nil)
        await #expect(throws: ABSError.unauthorized) { try await abs.login(username: "reader", password: "bad") }
        #expect(await store.load() == nil)
    }

    @Test func requestsCarryTheBearerToken() async throws {
        let (abs, transport, _) = client([.reply(200, Fixture.libraries)])
        let libraries = try await abs.libraries()
        #expect(libraries.map(\.id) == ["lib1"])
        #expect(await transport.requests.first?.headers["Authorization"] == "Bearer ACCESS-1")
    }

    @Test func withoutTokensNothingIsSent() async {
        let (abs, transport, _) = client([], tokens: nil)
        await #expect(throws: ABSError.unauthorized) { try await abs.libraries() }
        #expect(await transport.requests.isEmpty)
    }

    @Test func anExpiredTokenIsRefreshedOnceAndTheRequestRetried() async throws {
        let (abs, transport, store) = client([.reply(401, ""), .reply(200, Fixture.tokens), .reply(200, Fixture.libraries)])
        let libraries = try await abs.libraries()
        #expect(libraries.count == 1)
        let requests = await transport.requests
        #expect(requests.map(\.url.path) == ["/api/libraries", "/auth/refresh", "/api/libraries"])
        #expect(requests[1].headers["x-refresh-token"] == "REFRESH-1")
        #expect(requests[2].headers["Authorization"] == "Bearer ACCESS-2")
        #expect(await store.load()?.access == "ACCESS-2")
    }

    @Test func aDeadRefreshTokenSignsOut() async {
        let (abs, _, store) = client([.reply(401, ""), .reply(401, "")])
        await #expect(throws: ABSError.unauthorized) { try await abs.libraries() }
        #expect(await store.load() == nil)
    }

    @Test func aRetryThatIsStillRefusedDoesNotLoop() async {
        let (abs, transport, _) = client([.reply(401, ""), .reply(200, Fixture.tokens), .reply(401, "")])
        await #expect(throws: ABSError.unauthorized) { try await abs.libraries() }
        #expect(await transport.requests.count == 3)
    }

    @Test func aMissingServerIsUnreachable() async {
        let (abs, _, _) = client([.fail])
        await #expect(throws: ABSError.unreachable) { try await abs.libraries() }
    }

    @Test func serverErrorsKeepTheirStatus() async {
        let (abs, _, _) = client([.reply(500, "")])
        await #expect(throws: ABSError.server(status: 500)) { try await abs.libraries() }
    }

    @Test func garbageIsADecodingError() async {
        let (abs, _, _) = client([.reply(200, "<html>")])
        do {
            _ = try await abs.libraries()
            Issue.record("expected a decoding error")
        } catch let error as ABSError {
            if case .decoding = error { return }
            Issue.record("wrong error \(error)")
        } catch {
            Issue.record("wrong error \(error)")
        }
    }

    @Test func aBookListingDecodesWithAndWithoutAnAuthor() async throws {
        let (abs, transport, _) = client([.reply(200, Fixture.items)])
        let page = try await abs.books(inLibrary: "lib1", limit: 2, page: 0)
        #expect(page.total == 32 && page.books.count == 2)
        #expect(page.books[0].title == "A Book" && page.books[0].authorName == "An Author")
        #expect(page.books[0].numChapters == 9 && page.books[0].duration == 25199.122)
        #expect(page.books[1].authorName == nil && page.books[1].duration == 0)
        let url = try #require(await transport.requests.first?.url)
        #expect(url.path == "/api/libraries/lib1/items" && url.query == "limit=2&page=0")
    }

    @Test func aBookDetailHasChaptersAndTracks() async throws {
        let (abs, transport, _) = client([.reply(200, Fixture.detail)])
        let book = try await abs.book(id: "b1")
        #expect(book.chapters.map(\.title) == ["Chapter 1", "Chapter 2"])
        #expect(book.chapters[1].start == 60.25 && book.tracks.count == 1)
        #expect(await transport.requests.first?.url.query == "expanded=1")
    }

    @Test func startingPlaybackReturnsTheResumePosition() async throws {
        let (abs, transport, _) = client([.reply(200, Fixture.session)])
        let session = try await abs.startPlayback(bookID: "b1", deviceID: "dev1")
        #expect(session.id == "s1" && session.currentTime == 42.5 && session.audioTracks.count == 1)
        let request = try #require(await transport.requests.first)
        #expect(request.method == "POST" && request.url.path == "/api/items/b1/play")
        let data = try #require(request.body)
        let body = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(body["forceDirectPlay"] as? Bool == true)
    }

    @Test func syncAndCloseSendTheListeningPosition() async throws {
        let (abs, transport, _) = client([.reply(200, "\"OK\""), .reply(200, "")])
        try await abs.sync(sessionID: "s1", currentTime: 50, timeListened: 8, duration: 100.5)
        try await abs.close(sessionID: "s1", currentTime: 55, timeListened: 5)
        let requests = await transport.requests
        #expect(requests.map(\.url.path) == ["/api/session/s1/sync", "/api/session/s1/close"])
        let syncData = try #require(requests[0].body)
        let sync = try #require(try JSONSerialization.jsonObject(with: syncData) as? [String: Double])
        #expect(sync == ["currentTime": 50, "timeListened": 8, "duration": 100.5])
    }

    @Test func progressDecodesAndMissingProgressIsNil() async throws {
        let (abs, _, _) = client([.reply(200, Fixture.progress), .reply(404, "")])
        let progress = try #require(try await abs.progress(bookID: "b1"))
        #expect(progress.currentTime == 42.5 && !progress.isFinished && progress.lastUpdate == 1_795_561_937_019)
        #expect(try await abs.progress(bookID: "b2") == nil)
    }

    @Test func allProgressListsEveryStartedBook() async throws {
        let body = #"{"id":"u","mediaProgress":[{"libraryItemId":"b1","duration":100,"progress":0.4,"currentTime":40,"isFinished":false,"lastUpdate":7},{"libraryItemId":"b2","duration":50,"progress":1,"currentTime":50,"isFinished":true,"lastUpdate":9}]}"#
        let (abs, transport, _) = client([.reply(200, body), .reply(200, #"{"id":"u"}"#)])
        let all = try await abs.allProgress()
        #expect(all.map(\.libraryItemId) == ["b1", "b2"] && all[1].isFinished && all[0].lastUpdate == 7)
        #expect(await transport.requests.first?.url.path == "/api/me")
        #expect(try await abs.allProgress().isEmpty)
    }

    @Test func coverSearchEncodesTheQueryAndKeepsOnlyHttpsLinks() async throws {
        let body = #"{"results":["https://img.example.test/a.jpg","http://insecure.example.test/b.jpg","not a url","https://img.example.test/c.jpg"]}"#
        let (abs, transport, _) = client([.reply(200, body)])
        let found = try await abs.searchCovers(title: "Pride & Prejudice", author: "Jane Austen", provider: "audible")
        #expect(found.map(\.absoluteString) == ["https://img.example.test/a.jpg", "https://img.example.test/c.jpg"])
        let request = try #require(await transport.requests.first)
        #expect(request.url.path == "/api/search/covers")
        // "&" inside the title must not split it into two parameters.
        #expect(request.url.absoluteString.hasSuffix("title=Pride%20%26%20Prejudice&provider=audible&author=Jane%20Austen"))
    }

    @Test func coverSearchWithoutResultsIsEmpty() async throws {
        let (abs, _, _) = client([.reply(200, #"{"results":[]}"#), .reply(200, "{}")])
        #expect(try await abs.searchCovers(title: "X", author: nil, provider: "itunes").isEmpty)
        #expect(try await abs.searchCovers(title: "X", author: "", provider: "itunes").isEmpty)
    }

    @Test func settingACoverPostsTheImageLink() async throws {
        let (abs, transport, _) = client([.reply(200, #"{"success":true}"#)])
        try await abs.setCover(bookID: "b1", from: URL(string: "https://img.example.test/a.jpg")!)
        let request = try #require(await transport.requests.first)
        #expect(request.method == "POST" && request.url.path == "/api/items/b1/cover")
        let data = try #require(request.body)
        let body = try #require(try JSONSerialization.jsonObject(with: data) as? [String: String])
        #expect(body == ["url": "https://img.example.test/a.jpg"])
    }

    @Test func anAccountThatMayNotEditIsForbiddenNotSignedOut() async {
        let (abs, transport, store) = client([.reply(403, "")])
        await #expect(throws: ABSError.forbidden) {
            try await abs.setCover(bookID: "b1", from: URL(string: "https://img.example.test/a.jpg")!)
        }
        #expect(await transport.requests.count == 1)
        #expect(await store.load() != nil)
    }

    @Test func theAudioRequestCarriesTheTokenAndTheTrackPath() async throws {
        let (abs, _, _) = client([])
        let track = try JSONDecoder().decode(ABSTrack.self, from: Data(
            #"{"startOffset":0,"duration":10,"contentUrl":"/api/items/b1/file/9","mimeType":"audio/mp4"}"#.utf8))
        let request = try await abs.audioRequest(for: track)
        #expect(request.url.absoluteString == "https://abs.example.test:8443/api/items/b1/file/9")
        #expect(request.headers["Authorization"] == "Bearer ACCESS-1")
    }

    @Test func signingOutForgetsTheTokens() async {
        let (abs, _, store) = client([])
        await abs.signOut()
        #expect(await store.load() == nil)
    }
}
