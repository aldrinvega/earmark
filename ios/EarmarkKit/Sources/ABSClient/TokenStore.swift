import Foundation

public struct ABSTokens: Sendable, Equatable {
    public var access: String
    public var refresh: String

    public init(access: String, refresh: String) {
        self.access = access
        self.refresh = refresh
    }
}

/// Where the tokens live. The app implements this with the Keychain; tokens are never logged or written to files.
public protocol TokenStore: Sendable {
    func load() async -> ABSTokens?
    func save(_ tokens: ABSTokens) async
    func clear() async
}

public actor InMemoryTokenStore: TokenStore {
    private var tokens: ABSTokens?

    public init(_ tokens: ABSTokens? = nil) {
        self.tokens = tokens
    }

    public func load() -> ABSTokens? { tokens }
    public func save(_ tokens: ABSTokens) { self.tokens = tokens }
    public func clear() { tokens = nil }
}
