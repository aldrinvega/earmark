import Foundation

/// Audiobookshelf API client. Tokens come from a `TokenStore`; an expired access token is renewed once, then the
/// request is retried. Endpoint shapes are recorded in docs/abs-api.md.
public actor ABSClient {
    private let baseURL: URL
    private let transport: HTTPTransport
    private let tokenStore: TokenStore
    private let decoder = JSONDecoder()

    public init(baseURL: URL, transport: HTTPTransport, tokenStore: TokenStore) {
        self.baseURL = baseURL
        self.transport = transport
        self.tokenStore = tokenStore
    }

    // MARK: Sign in

    public func status() async throws -> ABSServerStatus {
        try decode(ABSServerStatus.self, from: try await send(HTTPRequest(url: url("status"))))
    }

    /// Signs in and stores the tokens.
    public func login(username: String, password: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["username": username, "password": password])
        let request = HTTPRequest(url: url("login"), method: "POST",
                                  headers: ["Content-Type": "application/json", "x-return-tokens": "true"], body: body)
        try await storeTokens(from: try await send(request))
    }

    public func signOut() async {
        await tokenStore.clear()
    }

    // MARK: Library

    public func libraries() async throws -> [ABSLibrary] {
        struct Reply: Decodable { let libraries: [ABSLibrary] }
        return try decode(Reply.self, from: try await authorized(path: "api/libraries")).libraries
    }

    public func books(inLibrary id: String, limit: Int = 50, page: Int = 0) async throws -> ABSBookPage {
        struct Reply: Decodable { let results: [ABSBookSummary]; let total: Int }
        let query = [URLQueryItem(name: "limit", value: String(limit)), URLQueryItem(name: "page", value: String(page))]
        let reply = try decode(Reply.self, from: try await authorized(path: "api/libraries/\(id)/items", query: query))
        return ABSBookPage(books: reply.results, total: reply.total)
    }

    public func book(id: String) async throws -> ABSBookDetail {
        let query = [URLQueryItem(name: "expanded", value: "1")]
        return try decode(ABSBookDetail.self, from: try await authorized(path: "api/items/\(id)", query: query))
    }

    public func coverData(bookID: String) async throws -> Data {
        try await authorized(path: "api/items/\(bookID)/cover").data
    }

    // MARK: Playback and progress

    public func startPlayback(bookID: String, deviceID: String) async throws -> ABSPlaySession {
        let body: [String: Any] = [
            "deviceInfo": ["clientName": "Earmark", "deviceId": deviceID],
            "forceDirectPlay": true,
            "forceTranscode": false,
            "supportedMimeTypes": ["audio/mpeg", "audio/mp4", "audio/flac"],
        ]
        let reply = try await authorized(path: "api/items/\(bookID)/play", method: "POST", json: body)
        return try decode(ABSPlaySession.self, from: reply)
    }

    public func sync(sessionID: String, currentTime: Double, timeListened: Double, duration: Double) async throws {
        let body: [String: Any] = ["currentTime": currentTime, "timeListened": timeListened, "duration": duration]
        _ = try await authorized(path: "api/session/\(sessionID)/sync", method: "POST", json: body)
    }

    public func close(sessionID: String, currentTime: Double, timeListened: Double) async throws {
        let body: [String: Any] = ["currentTime": currentTime, "timeListened": timeListened]
        _ = try await authorized(path: "api/session/\(sessionID)/close", method: "POST", json: body)
    }

    /// The server's saved progress, or `nil` when the Book was never started.
    public func progress(bookID: String) async throws -> ABSProgress? {
        do {
            return try decode(ABSProgress.self, from: try await authorized(path: "api/me/progress/\(bookID)"))
        } catch ABSError.notFound {
            return nil
        }
    }

    /// A streaming request for one track, with the access token attached (AVPlayer needs the header).
    public func audioRequest(for track: ABSTrack) async throws -> HTTPRequest {
        guard let path = track.contentUrl, let tokens = await tokenStore.load() else { throw ABSError.unauthorized }
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return HTTPRequest(url: url(trimmed), headers: ["Authorization": "Bearer \(tokens.access)"])
    }

    // MARK: Plumbing

    private func url(_ path: String, query: [URLQueryItem] = []) -> URL {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        return components.url!
    }

    private func authorized(path: String, query: [URLQueryItem] = [], method: String = "GET",
                            json: [String: Any]? = nil) async throws -> HTTPResponse {
        let body = try json.map { try JSONSerialization.data(withJSONObject: $0) }
        func make(_ token: String) -> HTTPRequest {
            var headers = ["Authorization": "Bearer \(token)"]
            if body != nil { headers["Content-Type"] = "application/json" }
            return HTTPRequest(url: url(path, query: query), method: method, headers: headers, body: body)
        }
        guard let tokens = await tokenStore.load() else { throw ABSError.unauthorized }
        do {
            return try await send(make(tokens.access))
        } catch ABSError.unauthorized {
            let renewed = try await refresh(using: tokens)
            return try await send(make(renewed.access))
        }
    }

    private func refresh(using tokens: ABSTokens) async throws -> ABSTokens {
        let request = HTTPRequest(url: url("auth/refresh"), method: "POST", headers: ["x-refresh-token": tokens.refresh])
        do {
            return try await storeTokens(from: try await send(request))
        } catch ABSError.unauthorized {
            await tokenStore.clear()
            throw ABSError.unauthorized
        }
    }

    @discardableResult
    private func storeTokens(from response: HTTPResponse) async throws -> ABSTokens {
        struct Reply: Decodable {
            struct User: Decodable { let accessToken: String; let refreshToken: String }
            let user: User
        }
        let reply = try decode(Reply.self, from: response)
        let tokens = ABSTokens(access: reply.user.accessToken, refresh: reply.user.refreshToken)
        await tokenStore.save(tokens)
        return tokens
    }

    /// Sends one request and maps transport failures and HTTP statuses to `ABSError`.
    private func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let response: HTTPResponse
        do {
            response = try await transport.send(request)
        } catch {
            throw ABSError.unreachable
        }
        switch response.status {
        case 200..<300: return response
        case 401, 403: throw ABSError.unauthorized
        case 404: throw ABSError.notFound
        default: throw ABSError.server(status: response.status)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from response: HTTPResponse) throws -> T {
        do {
            return try decoder.decode(T.self, from: response.data)
        } catch {
            throw ABSError.decoding(String(describing: error))
        }
    }
}
