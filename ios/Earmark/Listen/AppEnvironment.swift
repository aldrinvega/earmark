import ABSClient
import AppFeatures
import Foundation
import Observation

/// Holds what the Listen screens share: the sign-in model (and through it the Audiobookshelf client).
@Observable @MainActor
final class AppEnvironment {
    let signIn: SignInModel

    init() {
        let defaults = UserDefaults.standard
        signIn = SignInModel(
            savedAddress: defaults.string(forKey: "serverAddress"),
            transport: URLSessionTransport(),
            tokenStore: KeychainTokenStore(),
            saveAddress: { defaults.set($0, forKey: "serverAddress") }
        )
    }
}
