import SwiftUI

/// M1 login screen: email + password → `AppStore.Intent.login`. Errors from
/// the typed PandoraCore layer are rendered verbatim from the store; no
/// networking or session logic lives here.
struct LoginView: View {
    @Environment(AppStore.self) private var store
    @FocusState private var focusedField: Field?

    private enum Field {
        case email
        case password
    }

    @State private var email = ""
    @State private var password = ""

    private var isSigningIn: Bool { store.authPhase == .signingIn }

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 32)

            VStack(spacing: 12) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text("Amphora")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text("Sign in with your Pandora account")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let message = store.lastErrorMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .accessibilityAddTraits(.isStaticText)
            }

            VStack(spacing: 12) {
                TextField("Email", text: $email)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)
                    .submitLabel(.next)
                    .focused($focusedField, equals: .email)
                    .onSubmit { focusedField = .password }
                    .accessibilityLabel("Email")

                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .submitLabel(.go)
                    .focused($focusedField, equals: .password)
                    .onSubmit(submit)
                    .accessibilityLabel("Password")
            }
            .textFieldStyle(.plain)
            .padding(14)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(.primary)

            Button(action: submit) {
                ZStack {
                    if isSigningIn {
                        ProgressView()
                            .tint(.primary)
                    } else {
                        Text("Sign In")
                            .font(.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSigningIn)
            .accessibilityLabel(isSigningIn ? "Signing in" : "Sign In")

            Spacer(minLength: 32)
        }
        .padding(24)
        .interactiveDismissDisabled(isSigningIn)
    }

    private func submit() {
        focusedField = nil
        store.send(.login(username: email, password: password))
    }
}

#Preview {
    LoginView()
        .environment(AppStore())
        .preferredColorScheme(.dark)
}
