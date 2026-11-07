import PandoraCore
import SwiftUI

/// Add / edit a custom radio station from a raw stream URL (radio R5).
/// Presented from the Radio tab's toolbar button (add) or a custom
/// row's Edit menu (edit). Validation is local — a non-empty name and
/// an http(s) stream URL — and the intent only fires once it passes;
/// saving is synchronous (no network), so the sheet dismisses on Save.
struct RadioStationFormSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// nil = add mode; a station = edit mode.
    let existing: RadioStation?

    @State private var name = ""
    @State private var url = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Station") {
                    TextField("Name", text: $name)
                    TextField("Stream URL", text: $url)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }
                Section {
                    Text("Any direct stream URL works — most stations' MP3 or AAC streams (http or https). Station websites list them, or open their .m3u/.pls file and copy the link inside.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(existing == nil ? "Add Station" : "Edit Station")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!isValid)
                }
            }
        }
        .preferredColorScheme(ThemeController.shared.preferredColorScheme)
        .onAppear {
            if let existing {
                name = existing.name
                url = existing.streamURL
            }
        }
    }

    private var isValid: Bool {
        guard !trimmedName.isEmpty else { return false }
        return Self.streamURL(from: url) != nil
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        guard let streamURL = Self.streamURL(from: url) else { return }
        if let existing {
            store.send(.updateRadioCustomStation(existing, name: trimmedName, url: streamURL))
        } else {
            store.send(.addRadioCustomStation(name: trimmedName, url: streamURL))
        }
        dismiss()
    }

    /// Trims and validates the typed URL: it must parse and carry an
    /// http or https scheme (what AVPlayer can stream). Returns the
    /// trimmed form, or nil when unusable.
    static func streamURL(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let parsed = URL(string: trimmed),
            let scheme = parsed.scheme?.lowercased(),
            scheme == "http" || scheme == "https"
        else { return nil }
        return trimmed
    }
}
