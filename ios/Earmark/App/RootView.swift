import SwiftUI

/// Placeholder until app-shell (Phase 3): proves the pipeline from CI to the iPhone (Checkpoint A).
struct RootView: View {
    static let title = "Earmark"
    static let subtitle = "Listen and read in sync"

    var body: some View {
        ZStack {
            BackdropView()
            VStack(spacing: 10) {
                Image(systemName: "headphones")
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 40))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text(Self.title)
                    .font(.largeTitle.weight(.bold))
                    .accessibilityIdentifier("launch-title")
                Text(Self.subtitle)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("The pipeline works. Sign-in and your library come next.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
            .padding(28)
            .frame(maxWidth: 340)
            .glassEffect(.regular, in: .rect(cornerRadius: 32))
            .padding(20)
        }
    }
}

/// Soft colour behind the glass so it has something to refract. Plain colour under Reduce Transparency.
private struct BackdropView: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if reduceTransparency {
            Color(.systemBackground).ignoresSafeArea()
        } else {
            ZStack {
                Color(.systemBackground)
                Circle().fill(Color.accentColor.opacity(0.35)).frame(width: 320).blur(radius: 70).offset(x: -90, y: -200)
                Circle().fill(Color.orange.opacity(0.25)).frame(width: 280).blur(radius: 80).offset(x: 120, y: 160)
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)
        }
    }
}

#Preview {
    RootView()
}
