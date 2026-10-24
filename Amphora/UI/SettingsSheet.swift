import PandoraCore
import SwiftUI

/// Settings (Stations toolbar gear). Currently one section: Last.fm
/// scrobbling — connect (`auth.getMobileSession`, password not stored),
/// toggle scrobbling, sign out. The scrobble engine lives in `Scrobbler`;
/// this view dispatches intents only.
struct SettingsSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var username = ""
    @State private var password = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    lastFmRows
                } footer: {
                    Text(
                        "Scrobbles what you play to your Last.fm profile. "
                            + "Tracks shorter than 30 seconds never scrobble; "
                            + "a track counts once you've played past half of it "
                            + "or four minutes — whichever comes first."
                    )
                }
            }
            .amphoraListBackground()
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var lastFmRows: some View {
        switch store.scrobbler.authState {
        case .signedIn(let name):
            signedInRows(name: name)
        case .needsAuth(let message):
            Text(message)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.yellow)
                .amphoraCardRow()
            credentialsRows
        case .signedOut:
            credentialsRows
        }
    }

    private func signedInRows(name: String) -> some View {
        Group {
            Toggle("Scrobble to Last.fm", isOn: enabledBinding)
                .amphoraCardRow()
            HStack {
                Text("Signed in as \(name)")
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
            }
            .font(.footnote)
            .amphoraCardRow()
            Button(role: .destructive) {
                store.send(.signOutLastFm)
                password = ""
            } label: {
                Text("Sign Out of Last.fm")
            }
            .amphoraCardRow()
        }
    }

    private var credentialsRows: some View {
        Group {
            TextField("Last.fm username or email", text: $username)
                .textContentType(.username)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .amphoraCardRow()
            SecureField("Last.fm password", text: $password)
                .textContentType(.password)
                .amphoraCardRow()
            Button {
                store.send(.authenticateLastFm(username: username, password: password))
            } label: {
                HStack {
                    Spacer()
                    if store.scrobbler.isAuthenticating {
                        ProgressView()
                    } else {
                        Text("Connect")
                            .font(.body.weight(.semibold))
                    }
                    Spacer()
                }
            }
            .disabled(store.scrobbler.isAuthenticating)
            .amphoraCardRow()
            if let error = store.scrobbler.authError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.yellow)
                    .amphoraCardRow()
            }
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { store.scrobbler.isEnabled },
            set: { store.send(.setScrobblingEnabled($0)) }
        )
    }
}
