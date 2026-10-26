import PandoraCore
import SwiftUI

/// The Settings tab. Everything the app exposes lives here: Appearance
/// (background theme + accent), Last.fm scrobbling, diagnostics, about
/// & acknowledgements, and signing out. The scrobble engine lives in
/// `Scrobbler`; this view dispatches intents only.
struct SettingsView: View {
    @Environment(AppStore.self) private var store

    private var theme: ThemeController { ThemeController.shared }

    @State private var isConfirmingSignOut = false

    var body: some View {
        List {
            appearanceSection
            lastFmSection
            supportSection
            aboutSection
            accountSection
        }
        .listStyle(.plain)
        .amphoraListBackground()
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Settings")
        .confirmationDialog(
            "Sign out of Pandora?",
            isPresented: $isConfirmingSignOut,
            titleVisibility: .visible
        ) {
            Button("Sign Out", role: .destructive) {
                store.send(.signOutPandora)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your stations and history stay on Pandora's servers; playback stops and you'll sign in again next launch.")
        }
    }

    // MARK: Appearance

    private var appearanceSection: some View {
        Section {
            backgroundPicker
            accentRow
        } header: {
            sectionHeader("Appearance", icon: "paintpalette")
        } footer: {
            Text("Applies everywhere immediately. Gradients follow the accent you pick.")
        }
    }

    private var backgroundPicker: some View {
        Picker("Background", selection: appearanceBinding) {
            ForEach(ThemeAppearance.allCases) { appearance in
                Text(appearance.displayName).tag(appearance)
            }
        }
        .pickerStyle(.menu)
        .amphoraCardRow()
    }
    private var accentRow: some View {
        HStack(spacing: 16) {
            Text("Accent")
            Spacer()
            HStack(spacing: 12) {
                ForEach(ThemeAccent.allCases) { accent in
                    AccentSwatch(
                        accent: accent,
                        isSelected: theme.selection.accent == accent
                    ) {
                        theme.setAccent(accent)
                    }
                }
            }
        }
        .frame(minHeight: 44)
        .amphoraCardRow()
    }

    private var appearanceBinding: Binding<ThemeAppearance> {
        Binding(
            get: { theme.selection.appearance },
            set: { theme.setAppearance($0) }
        )
    }

    // MARK: Last.fm

    private var lastFmSection: some View {
        Section {
            LastFmSettings()
        } header: {
            sectionHeader("Last.fm", icon: "dot.radiowaves.left.and.right")
        } footer: {
            Text(
                "Scrobbles what you play to your Last.fm profile. "
                    + "Tracks shorter than 30 seconds never scrobble; "
                    + "a track counts once you've played past half of it "
                    + "or four minutes — whichever comes first."
            )
        }
    }

    // MARK: Support / About / Account

    private var supportSection: some View {
        Section {
            NavigationLink {
                DiagnosticsView()
            } label: {
                Label("Diagnostics & Logs", systemImage: "stethoscope")
            }
            .amphoraCardRow()
        } header: {
            sectionHeader("Support", icon: "wrench.and.screwdriver")
        }
    }

    private var aboutSection: some View {
        Section {
            NavigationLink {
                AboutView()
            } label: {
                Label("About Amphora", systemImage: "info.circle")
            }
            .amphoraCardRow()
        } header: {
            sectionHeader("About", icon: "questionmark.circle")
        }
    }

    private var accountSection: some View {
        Section {
            Button(role: .destructive) {
                isConfirmingSignOut = true
            } label: {
                Label("Sign Out of Pandora", systemImage: "rectangle.portrait.and.arrow.right")
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .amphoraCardRow()
        }
    }

    private func sectionHeader(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(nil)
    }
}

/// One accent color chip: a gradient circle; the selected one wears a
/// soft ring and a checkmark in the accent's legible glyph color.
private struct AccentSwatch: View {
    let accent: ThemeAccent
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button {
            onSelect()
        } label: {
            ZStack {
                Circle()
                    .fill(accent.palette.gradient)
                    .frame(width: 28, height: 28)
                if isSelected {
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.85), lineWidth: 1.5)
                        .frame(width: 34, height: 34)
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(accent.palette.glyph)
                }
            }
            .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accent.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The Last.fm connect/sign-out block (previously its own sheet).
/// Dispatches the same three intents.
private struct LastFmSettings: View {
    @Environment(AppStore.self) private var store

    @State private var username = ""
    @State private var password = ""

    var body: some View {
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
                    .foregroundStyle(Theme.accentText)
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
