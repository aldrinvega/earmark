import ABSClient
import Foundation
import Observation

/// Sign-in state: the server address, the account, and the client once signed in.
@Observable @MainActor
public final class SignInModel {
    public var serverAddress: String
    public var username = ""
    public var password = ""
    public private(set) var isWorking = false
    public private(set) var errorMessage: String?
    public private(set) var client: ABSClient?
    /// `true` once the launch-time check for stored tokens has finished, so the sign-in screen does not flash.
    public private(set) var hasRestored = false

    private let transport: HTTPTransport
    private let tokenStore: TokenStore
    private let saveAddress: @MainActor (String) -> Void

    public init(
        savedAddress: String?,
        transport: HTTPTransport,
        tokenStore: TokenStore,
        saveAddress: @escaping @MainActor (String) -> Void
    ) {
        self.serverAddress = savedAddress ?? ""
        self.transport = transport
        self.tokenStore = tokenStore
        self.saveAddress = saveAddress
    }

    public var canSignIn: Bool {
        !isWorking && Self.normalizedURL(serverAddress) != nil && !username.isEmpty && !password.isEmpty
    }

    /// "mac.tailnet.ts.net:8443" becomes https://mac.tailnet.ts.net:8443; anything without a host is rejected.
    public static func normalizedURL(_ text: String) -> URL? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if !trimmed.contains("://") { trimmed = "https://" + trimmed }
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http", let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    /// At launch: signed in again with the stored tokens, if there are any.
    public func restore() async {
        defer { hasRestored = true }
        guard client == nil, let url = Self.normalizedURL(serverAddress), await tokenStore.load() != nil else { return }
        client = ABSClient(baseURL: url, transport: transport, tokenStore: tokenStore)
    }

    public func signIn() async {
        guard let url = Self.normalizedURL(serverAddress) else {
            errorMessage = "Enter the server address, like https://your-mac.your-tailnet.ts.net:8443."
            return
        }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        let candidate = ABSClient(baseURL: url, transport: transport, tokenStore: tokenStore)
        do {
            try await candidate.login(username: username, password: password)
            saveAddress(url.absoluteString)
            password = ""
            client = candidate
        } catch {
            errorMessage = ABSErrorText.message(for: error, signingIn: true)
        }
    }

    public func signOut() async {
        await client?.signOut()
        client = nil
    }

    /// The server refused the tokens and they could not be renewed.
    public func sessionExpired() async {
        await signOut()
        errorMessage = ABSErrorText.message(for: ABSError.unauthorized)
    }
}
