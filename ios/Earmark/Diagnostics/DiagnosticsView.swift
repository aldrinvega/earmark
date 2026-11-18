import SwiftUI

/// Settings → Diagnostics (a placeholder home until app-shell adds Settings).
struct DiagnosticsView: View {
    var body: some View {
        List {
            Section {
                NavigationLink("Align test chapter") {
                    AlignTestView()
                }
                .accessibilityIdentifier("open-align-test")
            } header: {
                Text("Read-along spike")
            } footer: {
                Text("Runs the bundled public-domain chapter through the on-device speech engines and checks how well "
                     + "the narration lines up with the text. Audio never leaves this iPhone.")
            }
        }
        .navigationTitle("Diagnostics")
    }
}
