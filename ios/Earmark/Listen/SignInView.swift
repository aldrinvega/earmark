import AppFeatures
import SwiftUI

struct SignInView: View {
    @Bindable var model: SignInModel

    var body: some View {
        Form {
            Section {
                TextField("https://your-mac.your-tailnet.ts.net:8443", text: $model.serverAddress)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("server-address")
            } header: {
                Text("Audiobookshelf server")
            } footer: {
                Text("Use the https address on your tailnet. Your Mac and this iPhone both need Tailscale on.")
            }
            Section("Account") {
                TextField("Username", text: $model.username)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("username")
                SecureField("Password", text: $model.password)
                    .textContentType(.password)
                    .accessibilityIdentifier("password")
            }
            if let message = model.errorMessage {
                Section {
                    Text(message)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("sign-in-error")
                }
            }
            Section {
                Button {
                    Task { await model.signIn() }
                } label: {
                    HStack {
                        Text("Sign in")
                        if model.isWorking { Spacer(); ProgressView() }
                    }
                }
                .disabled(!model.canSignIn)
                .accessibilityIdentifier("sign-in")
            }
        }
        .navigationTitle("Sign in")
    }
}
