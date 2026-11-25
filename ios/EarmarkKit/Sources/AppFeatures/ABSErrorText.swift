import ABSClient
import Foundation

/// User-facing wording for `ABSError` (the client itself stays free of UI text).
public enum ABSErrorText {
    public static func message(for error: Error, signingIn: Bool = false) -> String {
        guard let error = error as? ABSError else { return "Something went wrong. Try again." }
        switch error {
        case .unreachable:
            return "Can't reach the server. Check that the Mac is on and Tailscale is connected."
        case .unauthorized:
            return signingIn ? "Sign-in failed. Check the username and password." : "Your session expired. Sign in again."
        case .notFound:
            return "The server doesn't have that item."
        case .decoding:
            return "The server sent something Earmark doesn't understand."
        case .server(let status):
            return "The server returned an error (\(status))."
        }
    }
}
