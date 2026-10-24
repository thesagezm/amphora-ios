import SwiftUI

/// M1 login screen: email + password → `AppStore.Intent.login`. Errors from
/// the typed PandoraCore layer are rendered verbatim from the store; no
/// networking or session logic lives here. Brand look: violet-lifted
/// gradient floor, gold sign-in button — the same tokens the Android port
/// uses.
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
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer(minLength: 32)

                brandHeader

                if let message = store.lastErrorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .accessibilityAddTraits(.isStaticText)
                }

                VStack(spacing: 12) {
                    fieldCard {
                        TextField("Email", text: $email)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.emailAddress)
                            .submitLabel(.next)
                            .focused($focusedField, equals: .email)
                            .onSubmit { focusedField = .password }
                            .accessibilityLabel("Email")
                    }
                    fieldCard {
                        SecureField("Password", text: $password)
                            .textContentType(.password)
                            .submitLabel(.go)
                            .focused($focusedField, equals: .password)
                            .onSubmit(submit)
                            .accessibilityLabel("Password")
                    }
                }

                Button(action: submit) {
                    ZStack {
                        if isSigningIn {
                            ProgressView()
                                .tint(Color.black.opacity(0.85))
                        } else {
                            Text("Sign In")
                                .font(.headline)
                        }
                    }
                    .foregroundStyle(Color.black.opacity(0.85))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 50)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.radiusM, style: .continuous))
                    .shadow(color: Theme.accent.opacity(0.30), radius: 14, y: 5)
                }
                .buttonStyle(.plain)
                .disabled(isSigningIn)
                .accessibilityLabel(isSigningIn ? "Signing in" : "Sign In")

                Spacer(minLength: 32)
            }
            .padding(24)
        }
        .interactiveDismissDisabled(isSigningIn)
    }

    private var brandHeader: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 72, weight: .light))
                .foregroundStyle(Theme.brandGradient)
                .accessibilityHidden(true)
            Text("Amphora")
                .font(Font.system(size: 38, weight: .heavy, design: .rounded))
                .foregroundStyle(.primary)
            Text("Sign in with your Pandora account")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    /// One rounded surface card holding a text field.
    private func fieldCard<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.stroke)
            )
            .foregroundStyle(.primary)
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
