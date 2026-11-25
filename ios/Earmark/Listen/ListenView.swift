import SwiftUI

/// Entry to listening: sign in the first time, then the library.
struct ListenView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        Group {
            if let client = environment.signIn.client {
                LibraryScreen(client: client, signIn: environment.signIn)
            } else {
                SignInView(model: environment.signIn)
            }
        }
        .task { await environment.signIn.restore() }
    }
}
