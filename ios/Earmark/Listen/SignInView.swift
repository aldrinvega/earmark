import AppFeatures
import SwiftUI

/// "Connect your library": the dark sign-in from the design.
struct SignInView: View {
    @Bindable var model: SignInModel

    var body: some View {
        ZStack {
            BlobBackdrop(style: .dark)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Image(systemName: "headphones")
                        .font(.system(size: 28, weight: .regular))
                        .foregroundStyle(Theme.gold)
                        .frame(width: 64, height: 64)
                        .glassEffect(.regular, in: .rect(cornerRadius: 20))
                        .accessibilityHidden(true)
                    Text(RootView.heading)
                        .font(Theme.serif(34, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.top, 20)
                        .accessibilityIdentifier("launch-title")
                    Text("Sign in to your Audiobookshelf server to stream your audiobooks.")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.82))
                        .padding(.top, 10)
                    form.padding(.top, 28)
                }
                .padding(.horizontal, 22)
                .padding(.top, 48)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 14) {
            field("SERVER ADDRESS") {
                TextField("", text: $model.serverAddress,
                          prompt: Text("https://your-mac.your-tailnet.ts.net:8443").foregroundStyle(.white.opacity(0.55)))
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("server-address")
            }
            field("USERNAME") {
                TextField("", text: $model.username, prompt: Text("Username").foregroundStyle(.white.opacity(0.55)))
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("username")
            }
            field("PASSWORD") {
                SecureField("", text: $model.password, prompt: Text("Password").foregroundStyle(.white.opacity(0.55)))
                    .textContentType(.password)
                    .accessibilityIdentifier("password")
            }
            if let message = model.errorMessage {
                Text(message)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.coral)
                    .accessibilityIdentifier("sign-in-error")
            }
            Button {
                Task { await model.signIn() }
            } label: {
                ZStack {
                    Text("Sign in").font(.system(size: 16, weight: .semibold))
                    if model.isWorking { HStack { Spacer(); ProgressView().tint(Theme.aubergine) } .padding(.trailing, 20) }
                }
                .foregroundStyle(Theme.aubergine)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(.white, in: Capsule())
                .opacity(model.canSignIn ? 1 : 0.5)
            }
            .disabled(!model.canSignIn)
            .padding(.top, 4)
            .accessibilityIdentifier("sign-in")
            HStack {
                Text("Works over Tailscale")
                Spacer()
                NavigationLink {
                    DiagnosticsView()
                } label: {
                    Text("Advanced").fontWeight(.semibold).foregroundStyle(Color(hex: 0xF1D9A6))
                }
                .accessibilityIdentifier("open-diagnostics")
            }
            .font(.system(size: 13))
            .foregroundStyle(.white.opacity(0.75))
            .padding(.top, 6)
        }
        .padding(20)
        .glassEffect(.regular, in: .rect(cornerRadius: 36))
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 12, weight: .semibold)).tracking(0.7).foregroundStyle(.white.opacity(0.78))
            content()
                .font(.system(size: 15))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(minHeight: 50)
                .background(.white.opacity(0.1), in: .rect(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.22), lineWidth: 1))
        }
    }
}
