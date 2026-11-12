import Foundation
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
    @State private var isConfirmingClearHistory = false

    var body: some View {
        List {
            appearanceSection
            lastFmSection
            contentSection
            librarySection
            supportSection
            aboutSection
            accountSection
        }
        .listStyle(.plain)
        .amphoraListBackground()
        .background(Theme.background.ignoresSafeArea())
        .miniPlayer()
        .navigationTitle("Settings")
        .onAppear {
            Task { await store.refreshArtworkCacheSize() }
        }
        .alert(
            "Clear play history?",
            isPresented: $isConfirmingClearHistory
        ) {
            Button("Clear History", role: .destructive) {
                store.send(.clearHistory)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The recently played list on this device is emptied. Your Pandora account and its listening data are not affected.")
        }
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

    // MARK: Account

    private var contentSection: some View {
        Section {
            HStack {
                Label("Explicit Content", systemImage: "e.square")
                Spacer()
                Text(store.isExplicitContentFilterEnabled ? "Filtered" : "Allowed")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .amphoraCardRow()
        } header: {
            sectionHeader("Account", icon: "person.crop.circle")
        } footer: {
            Text(
                "Pandora's explicit-content filter is an account setting — "
                    + "it applies to every station. Change it on pandora.com."
            )
        }
    }

    // MARK: Library

    private var librarySection: some View {
        Section {
            historyRow
            artworkCacheRow
        } header: {
            sectionHeader("Library", icon: "externaldrive")
        } footer: {
            Text("Both live on this device only — clearing them never changes your Pandora account.")
        }
    }

    private var historyRow: some View {
        Button(role: .destructive) {
            isConfirmingClearHistory = true
        } label: {
            HStack {
                Label("Clear Play History", systemImage: "clock.arrow.circlepath")
                Spacer()
                Text(historySummary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .amphoraCardRow()
        .disabled(store.history.isEmpty)
    }

    private var artworkCacheRow: some View {
        Button {
            store.send(.clearArtworkCache)
        } label: {
            HStack {
                Label("Clear Artwork Cache", systemImage: "photo.stack")
                Spacer()
                Text(cacheSummary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .amphoraCardRow()
        .disabled(store.artworkCacheBytes == 0)
    }

    private var historySummary: String {
        let count = store.history.count
        return count == 0 ? "Empty" : "\(count) \(count == 1 ? "play" : "plays")"
    }

    private var cacheSummary: String {
        let bytes = store.artworkCacheBytes
        if bytes == 0 { return "Empty" }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
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
        .buttonStyle(PressableButtonStyle())
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
            if let activity = store.scrobbler.lastActivity {
                Label {
                    Text(activity)
                        .font(.footnote)
                        .foregroundStyle(store.scrobbler.lastActivityIsError ? .yellow : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: store.scrobbler.lastActivityIsError
                        ? "exclamationmark.triangle.fill"
                        : "checkmark.circle.fill")
                        .foregroundStyle(store.scrobbler.lastActivityIsError ? .yellow : Theme.accentText)
                }
                .font(.footnote)
                .amphoraCardRow()
            }
            if let profileURL = URL(string: "https://www.last.fm/user/\(name)") {
                Link(destination: profileURL) {
                    Label("Open Last.fm Profile", systemImage: "safari")
                }
                .amphoraCardRow()
            }
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
                .onChange(of: username) { _, _ in store.scrobbler.clearAuthError() }
            SecureField("Last.fm password", text: $password)
                .textContentType(.password)
                .amphoraCardRow()
                .onChange(of: password) { _, _ in store.scrobbler.clearAuthError() }
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
