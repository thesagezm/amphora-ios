import SwiftUI

/// About Amphora: what the app is, what it's built on, and the people
/// whose work it stands on — acknowledged by name, as they deserve.
struct AboutView: View {
    var body: some View {
        List {
            introSection
            acknowledgementsSection
            versionSection
        }
        .listStyle(.plain)
        .amphoraListBackground()
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Intro

    private var introSection: some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(Theme.brandGradient)
                    .accessibilityHidden(true)
                Text("Amphora")
                    .font(Font.system(.title2, design: .rounded).weight(.bold))
                Text(
                    "A personal, unofficial Pandora client. "
                        + "Not affiliated with, endorsed by, or connected to "
                        + "Pandora Media, LLC."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    // MARK: Acknowledgements

    private var acknowledgementsSection: some View {
        Section {
            acknowledgementRow(
                "Pithos",
                detail: "The Linux Pandora client whose feature set Amphora mirrors — and whose scrobble rule we follow."
            )
            acknowledgementRow(
                "pydora, libpiano & pianobar",
                detail: "Open-source Pandora clients whose reverse-engineered protocol notes made this app possible."
            )
            acknowledgementRow(
                "CryptoSwift",
                detail: "Blowfish-ECB encryption for Pandora's legacy login. © Marcin Krzyżanowski, Apache 2.0."
            )
            acknowledgementRow(
                "Last.fm",
                detail: "Scrobbling via their public API (auth.getMobileSession, track.updateNowPlaying, track.scrobble)."
            )
            acknowledgementRow(
                "LRCLIB",
                detail: "Synced lyrics, free of charge, at lrclib.net."
            )
            acknowledgementRow(
                "Google Translate",
                detail: "On-device-requested translations for non-English lyrics."
            )
        } header: {
            Label("Acknowledgements", systemImage: "heart")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(nil)
        }
    }

    private func acknowledgementRow(_ name: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(name)
                .font(.body.weight(.medium))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .amphoraCardRow()
    }

    // MARK: Version

    private var versionSection: some View {
        Section {
            HStack {
                Text("Version")
                    .foregroundStyle(.primary)
                Spacer()
                Text(versionText)
                    .foregroundStyle(.secondary)
            }
            .font(.footnote)
            .amphoraCardRow()
        }
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(version) (\(build))"
    }
}
