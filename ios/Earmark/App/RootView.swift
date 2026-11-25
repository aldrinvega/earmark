import SwiftUI

/// The app's first screen: the sign-in the first time, then the tabs.
struct RootView: View {
    static let title = "Earmark"
    static let subtitle = "Listen and read in sync"
    static let heading = "Connect your library"

    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        Group {
            if !environment.signIn.hasRestored {
                BlobBackdrop(style: .dark)
            } else if let client = environment.signIn.client {
                MainTabsView(client: client, signIn: environment.signIn)
            } else {
                NavigationStack { SignInView(model: environment.signIn) }
            }
        }
        .task { await environment.signIn.restore() }
    }
}

#Preview {
    RootView().environment(AppEnvironment())
}
