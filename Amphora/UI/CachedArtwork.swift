import SwiftUI

/// Artwork view backed by the shared `ArtworkCache` (decoded images,
/// memory + disk tiers). Shows a placeholder while loading and when the
/// artwork cannot be loaded; cancels the load when the view disappears.
struct CachedArtwork: View {
    let urlString: String?
    var cornerRadius: CGFloat = 10
    var fallbackSystemImage: String = "music.note"

    @State private var image: UIImage?
    @State private var didFail = false

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
        .task(id: urlString) {
            guard let urlString, let url = URL(string: urlString) else {
                didFail = true
                return
            }
            let loaded = await ArtworkCache.shared.image(for: url)
            guard !Task.isCancelled else { return }
            if let loaded {
                image = loaded
            } else {
                didFail = true
            }
        }
        .accessibilityHidden(true)
    }
}
