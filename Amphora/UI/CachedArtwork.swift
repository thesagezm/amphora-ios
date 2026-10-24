import SwiftUI

/// Artwork view backed by the shared `ArtworkCache` (decoded images,
/// memory + disk tiers). Shows a placeholder while loading and when the
/// artwork cannot be loaded; cancels the load when the view disappears.
///
/// Loads are driven by `.onAppear`/`.onChange` + an owned task instead of
/// `.task(id:)`: `_TaskValueModifier` (the id-flavor's backing modifier)
/// trapped inside SwiftUI's own type-metadata instantiation during launch
/// on iOS 27.0, so the app carries no `.task(id:)` at all.
struct CachedArtwork: View {
    let urlString: String?
    var cornerRadius: CGFloat = 10
    var fallbackSystemImage: String = "music.note"

    @State private var image: UIImage?
    @State private var didFail = false
    @State private var loadTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.quaternary.opacity(0.5))
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if !didFail {
                ProgressView()
                    .controlSize(.small)
                    .tint(.secondary)
            } else {
                Image(systemName: fallbackSystemImage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onAppear {
            startLoad()
        }
        .onChange(of: urlString) {
            startLoad()
        }
        .onDisappear {
            loadTask?.cancel()
        }
        .accessibilityHidden(true)
    }

    private func startLoad() {
        loadTask?.cancel()
        // The cache normalizes the raw URL (Pandora's artwork URLs
        // are not always absolute and are sometimes plain HTTP) and
        // tries fallback candidates itself.
        guard let urlString else {
            didFail = true
            return
        }
        loadTask = Task {
            let loaded = await ArtworkCache.shared.image(for: urlString)
            guard !Task.isCancelled else { return }
            if let loaded {
                image = loaded
                didFail = false
            } else {
                didFail = true
            }
        }
    }
}
