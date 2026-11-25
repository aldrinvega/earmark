import ABSClient
import Foundation
import Testing
@testable import AppFeatures

/// Replays canned responses (same idea as the ABSClient tests).
private actor ReplayTransport: HTTPTransport {
    enum Step: Sendable {
        case reply(Int, String)
        case fail
    }

    private var steps: [Step]
    private(set) var paths: [String] = []

    init(_ steps: [Step]) {
        self.steps = steps
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        paths.append(request.url.path)
        guard !steps.isEmpty else { throw URLError(.cannotConnectToHost) }
        switch steps.removeFirst() {
        case .reply(let status, let body): return HTTPResponse(status: status, data: Data(body.utf8))
        case .fail: throw URLError(.notConnectedToInternet)
        }
    }
}

private let tokens = #"{"user":{"accessToken":"A2","refreshToken":"R2"}}"#
private let libraries = #"{"libraries":[{"id":"l1","name":"Audiobooks","mediaType":"book"}]}"#
private func page(_ ids: [String], total: Int) -> String {
    let results = ids.map { #"{"id":"\#($0)","media":{"metadata":{"title":"Book \#($0)"},"duration":60,"numChapters":1}}"# }
    return #"{"results":[\#(results.joined(separator: ","))],"total":\#(total),"limit":100,"page":0}"#
}

@MainActor @Suite struct SignInModelTests {
    private func model(_ steps: [ReplayTransport.Step], tokens stored: ABSTokens? = nil, address: String? = "abs.test")
        -> (SignInModel, ReplayTransport, SavedAddress) {
        let transport = ReplayTransport(steps)
        let saved = SavedAddress()
        let model = SignInModel(savedAddress: address, transport: transport, tokenStore: InMemoryTokenStore(stored),
                                saveAddress: { saved.value = $0 })
        return (model, transport, saved)
    }

    @Test(arguments: [
        ("abs.test", "https://abs.test"),
        ("  https://abs.test:8443/  ", "https://abs.test:8443"),
        ("http://100.1.2.3:13378", "http://100.1.2.3:13378"),
    ])
    func addressesAreNormalised(input: String, expected: String) {
        #expect(SignInModel.normalizedURL(input)?.absoluteString == expected)
    }

    @Test(arguments: ["", "   ", "ftp://abs.test", "https://", "://"])
    func badAddressesAreRejected(input: String) {
        #expect(SignInModel.normalizedURL(input) == nil)
    }

    @Test func signingInNeedsAllThreeFields() {
        let (model, _, _) = model([])
        #expect(!model.canSignIn)
        model.username = "reader"
        model.password = "pw"
        #expect(model.canSignIn)
        model.serverAddress = ""
        #expect(!model.canSignIn)
    }

    @Test func signingInKeepsTheClientAndAddressAndForgetsThePassword() async {
        let (model, _, saved) = model([.reply(200, tokens)], address: "abs.test:8443")
        model.username = "reader"
        model.password = "pw"
        await model.signIn()
        #expect(model.client != nil && model.errorMessage == nil)
        #expect(model.password.isEmpty)
        #expect(saved.value == "https://abs.test:8443")
    }

    @Test func aWrongPasswordShowsAMessageAndStaysSignedOut() async {
        let (model, _, saved) = model([.reply(401, "")])
        model.username = "reader"
        model.password = "bad"
        await model.signIn()
        #expect(model.client == nil)
        #expect(model.errorMessage == "Sign-in failed. Check the username and password.")
        #expect(saved.value == nil)
    }

    @Test func anUnreachableServerSaysSo() async {
        let (model, _, _) = model([.fail])
        model.username = "reader"
        model.password = "pw"
        await model.signIn()
        #expect(model.errorMessage?.hasPrefix("Can't reach the server") == true)
    }

    @Test func storedTokensSignInAgainWithoutAPassword() async {
        let (model, transport, _) = model([], tokens: ABSTokens(access: "A", refresh: "R"))
        await model.restore()
        #expect(model.client != nil)
        #expect(await transport.paths.isEmpty)
    }

    @Test func withoutStoredTokensRestoreStaysSignedOut() async {
        let (model, _, _) = model([])
        await model.restore()
        #expect(model.client == nil)
    }

    @Test func aDeadSessionSignsOutWithAMessage() async {
        let (model, _, _) = model([], tokens: ABSTokens(access: "A", refresh: "R"))
        await model.restore()
        await model.sessionExpired()
        #expect(model.client == nil && model.errorMessage == "Your session expired. Sign in again.")
    }
}

/// Mutable box for the saved-address closure (a `@MainActor` closure can write to it).
@MainActor final class SavedAddress {
    var value: String?
}

@MainActor @Suite struct LibraryModelTests {
    private func model(_ steps: [ReplayTransport.Step], onExpired: @escaping @MainActor () async -> Void = {}) -> LibraryModel {
        let client = ABSClient(baseURL: URL(string: "https://abs.test")!, transport: ReplayTransport(steps),
                               tokenStore: InMemoryTokenStore(ABSTokens(access: "A", refresh: "R")))
        return LibraryModel(client: client, onSessionExpired: onExpired)
    }

    @Test func loadsEveryPageSortedByTitle() async {
        let model = model([.reply(200, libraries), .reply(200, page(["b", "a"], total: 3)), .reply(200, page(["c"], total: 3))])
        await model.load()
        #expect(model.state == .loaded)
        #expect(model.books.map(\.id) == ["a", "b", "c"])
    }

    private func me(_ entries: [(id: String, progress: Double, time: Double, finished: Bool, updated: Int64)]) -> String {
        let items = entries.map {
            #"{"libraryItemId":"\#($0.id)","duration":100,"progress":\#($0.progress),"currentTime":\#($0.time),"isFinished":\#($0.finished),"lastUpdate":\#($0.updated)}"#
        }
        return #"{"id":"u","mediaProgress":[\#(items.joined(separator: ","))]}"#
    }

    @Test func statusesAndTheContinueBookComeFromServerProgress() async {
        let progress = me([("a", 0.34, 34, false, 1_000), ("b", 1, 100, true, 5_000), ("c", 0.5, 50, false, 3_000)])
        let model = model([.reply(200, libraries), .reply(200, page(["a", "b", "c", "d"], total: 4)), .reply(200, progress)])
        await model.load()
        let byID = Dictionary(uniqueKeysWithValues: model.books.map { ($0.id, $0) })
        #expect(model.status(for: byID["a"]!) == "34% · 1 min left")
        #expect(model.status(for: byID["b"]!) == "Finished")
        #expect(model.status(for: byID["d"]!) == "New")
        #expect(model.continueBook?.id == "c")
        #expect(model.fractionDone(for: byID["a"]!) == 0.34)
        #expect(model.fractionDone(for: byID["d"]!) == 0)
    }

    @Test func theShelfStillLoadsWhenProgressCannotBeRead() async {
        let model = model([.reply(200, libraries), .reply(200, page(["a"], total: 1)), .reply(500, "")])
        await model.load()
        #expect(model.state == .loaded && model.continueBook == nil)
        #expect(model.status(for: model.books[0]) == "New")
    }

    @Test func searchMatchesTitleAndAuthorIgnoringCase() async {
        let model = model([.reply(200, libraries), .reply(200, page(["apple", "pear"], total: 2))])
        await model.load()
        #expect(model.search("PEAR").map(\.id) == ["pear"])
        #expect(model.search("  ").count == 2)
        #expect(model.search("zzz").isEmpty)
    }

    @Test func aServerWithoutABookLibraryIsAMessage() async {
        let model = model([.reply(200, #"{"libraries":[{"id":"p","name":"Pods","mediaType":"podcast"}]}"#)])
        await model.load()
        #expect(model.state == .failed("The server has no audiobook library."))
    }

    @Test func anUnreachableServerIsAMessage() async {
        let model = model([.fail])
        await model.load()
        if case .failed(let message) = model.state {
            #expect(message.hasPrefix("Can't reach the server"))
        } else {
            Issue.record("expected a failure")
        }
    }

    @Test func anExpiredSessionSignsOut() async {
        var expired = false
        let model = model([.reply(401, ""), .reply(401, "")], onExpired: { expired = true })
        await model.load()
        #expect(expired)
    }
}

@MainActor @Suite struct CoverPickerModelTests {
    private func picker(_ steps: [ReplayTransport.Step], title: String = "Atomic Habits: An Easy & Proven Way") -> (CoverPickerModel, ReplayTransport) {
        let transport = ReplayTransport(steps)
        let client = ABSClient(baseURL: URL(string: "https://abs.test")!, transport: transport,
                               tokenStore: InMemoryTokenStore(ABSTokens(access: "A", refresh: "R")))
        let book = ABSBookSummary.testBook(id: "b1", title: title, author: "James Clear")
        return (CoverPickerModel(book: book, client: client), transport)
    }

    @Test func searchTitleDropsTheSubtitle() {
        #expect(CoverPickerModel.searchTitle(for: "Atomic Habits: An Easy & Proven Way") == "Atomic Habits")
        #expect(CoverPickerModel.searchTitle(for: "Deep Work") == "Deep Work")
        #expect(CoverPickerModel.searchTitle(for: ": Odd") == "Odd")
    }

    @Test func searchingListsCandidatesAndCapsThem() async {
        let links = (1...40).map { "\"https://img.test/\($0).jpg\"" }.joined(separator: ",")
        let (model, _) = picker([.reply(200, #"{"results":[\#(links)]}"#)])
        await model.search()
        #expect(model.state == .results && model.candidates.count == 24)
    }

    @Test func noResultsIsAnEmptyState() async {
        let (model, _) = picker([.reply(200, #"{"results":[]}"#)])
        await model.search()
        #expect(model.state == .empty && model.candidates.isEmpty)
    }

    @Test func aSearchFailureIsAMessage() async {
        let (model, _) = picker([.fail])
        await model.search()
        if case .failed(let message) = model.state {
            #expect(message.hasPrefix("Can't reach the server"))
        } else {
            Issue.record("expected a failure")
        }
    }

    @Test func choosingSavesTheCover() async {
        let (model, transport) = picker([.reply(200, "{}")])
        let saved = await model.choose(URL(string: "https://img.test/1.jpg")!)
        #expect(saved && model.state == .results)
        #expect(await transport.paths == ["/api/items/b1/cover"])
    }

    @Test func aRefusedSaveExplainsWhy() async {
        let (model, _) = picker([.reply(403, "")])
        let saved = await model.choose(URL(string: "https://img.test/1.jpg")!)
        #expect(!saved)
        if case .failed(let message) = model.state {
            #expect(message.contains("admin or editor"))
        } else {
            Issue.record("expected a failure")
        }
    }
}

extension ABSBookSummary {
    /// A Book for tests, decoded from the same JSON shape the server sends.
    static func testBook(id: String, title: String, author: String?) -> ABSBookSummary {
        let authorField = author.map { #","authorName":"\#($0)""# } ?? ""
        let json = #"{"id":"\#(id)","media":{"metadata":{"title":"\#(title)"\#(authorField)},"duration":60,"numChapters":1}}"#
        return try! JSONDecoder().decode(ABSBookSummary.self, from: Data(json.utf8))
    }
}

@Suite struct TimeFormatTests {
    @Test func clockShowsMinutesOrHours() {
        #expect(TimeFormat.clock(75) == "1:15")
        #expect(TimeFormat.clock(3725) == "1:02:05")
        #expect(TimeFormat.clock(0) == "0:00")
        #expect(TimeFormat.clock(-4) == "0:00")
        #expect(TimeFormat.clock(.nan) == "0:00")
    }

    @Test func leftIsShortForTheShelf() {
        #expect(TimeFormat.left(19620) == "5 h left")
        #expect(TimeFormat.left(2460) == "41 min left")
        #expect(TimeFormat.left(40) == "1 min left")
        #expect(TimeFormat.left(0) == "0 min left")
        #expect(TimeFormat.left(.nan) == "0 min left")
    }

    @Test func lengthRoundsToMinutes() {
        #expect(TimeFormat.length(25199) == "7 h 0 min")
        #expect(TimeFormat.length(1800) == "30 min")
        #expect(TimeFormat.length(89) == "1 min")
    }
}

@Suite struct ABSErrorTextTests {
    @Test func everyErrorHasAHumanMessage() {
        let errors: [ABSError] = [.unreachable, .unauthorized, .forbidden, .notFound, .decoding("x"), .server(status: 500)]
        for error in errors { #expect(!ABSErrorText.message(for: error).isEmpty) }
        #expect(ABSErrorText.message(for: ABSError.server(status: 502)).contains("502"))
        #expect(ABSErrorText.message(for: URLError(.badURL)) == "Something went wrong. Try again.")
    }
}
