import PandoraCore
import SwiftUI
import UIKit

/// Artwork for an internet-radio station.
///
/// Most stations have no favicon at all, and the ones that do usually
/// serve a 16×16 pixel icon — blown up to the full player's size that
/// reads as "no artwork" (or as a blurry smudge). So the fallback is
/// generated: the station's initials over a deterministic gradient whose
/// hue comes from the station name — the same color on every launch and
/// on every device (`RadioStationIdentity`, in PandoraCore).
///
/// The real favicon still wins when it is good enough for the slot it
/// is shown in: `minimumArtworkPixels` is the caller's requirement — a
/// 44 pt list row needs far less than the full player's ~400 pt cover.
struct RadioStationArtwork: View {
    let stationName: String
    let faviconURL: String?
    var cornerRadius: CGFloat = Theme.radiusS
    /// The smallest favicon still worth showing in this slot. Below it
    /// the generated tile is used instead — a 16×16 icon stretched over
    /// a 44 pt row (or a 400 pt cover) looks worse than the tile.
    var minimumArtworkPixels: CGFloat = 64

    @State private var image: UIImage?
    @State private var loadTask: Task<Void, Never>?

    /// The smallest favicon still worth showing on the lock screen
    /// (which draws the cover at roughly 60–120 pt). Below it, the
    /// generated tile is used.
    static let lockScreenMinimumPixels: CGFloat = 120

    var body: some View {
        ZStack {
            tile
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onAppear {
            startLoad()
        }
        .onChange(of: faviconURL) {
            startLoad()
        }
        .onDisappear {
            loadTask?.cancel()
        }
        .accessibilityHidden(true)
    }

    /// The generated tile: the station's initials over a gradient.
    private var tile: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(
                    colors: Self.gradientColors(for: stationName),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Text(RadioStationIdentity.initials(for: stationName))
                    .font(
                        .system(
                            size: max(11, geo.size.width * 0.38),
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(.white.opacity(0.95))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .padding(.horizontal, geo.size.width * 0.08)
            }
        }
    }

    /// The gradient of the generated tile. Two stops around the
    /// station's hue: a brighter one in the top corner, a deeper one in
    /// the bottom — the same shape as the app's brand gradient, but
    /// colored by the station's name.
    static func gradientColors(for name: String) -> [Color] {
        let hue = RadioStationIdentity.hue(for: name)
        return [
            Color(hue: hue, saturation: 0.55, brightness: 0.62),
            Color(
                hue: (hue + 0.08).truncatingRemainder(dividingBy: 1),
                saturation: 0.72,
                brightness: 0.34
            )
        ]
    }

    private func startLoad() {
        loadTask?.cancel()
        image = nil
        guard let faviconURL, !faviconURL.isEmpty else { return }
        loadTask = Task {
            let loaded = await ArtworkCache.shared.image(for: faviconURL)
            guard !Task.isCancelled else { return }
            // The decoded artwork is scale 1 (it comes from a CGImage),
            // so its size in points is its size in pixels.
            guard let loaded,
                  loaded.size.width >= minimumArtworkPixels,
                  loaded.size.height >= minimumArtworkPixels
            else { return }
            image = loaded
        }
    }
}

/// The generated tile as a bitmap — for the lock screen, which wants a
/// `UIImage` rather than a SwiftUI view. The gradient and the initials
/// are the same ones the view draws.
@MainActor
enum RadioStationArtworkRenderer {
    /// The tile for a station name, square and `size` points wide.
    static func tileImage(for stationName: String, size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            let hue = RadioStationIdentity.hue(for: stationName)
            let start = UIColor(hue: hue, saturation: 0.55, brightness: 0.62, alpha: 1)
            let end = UIColor(
                hue: (hue + 0.08).truncatingRemainder(dividingBy: 1),
                saturation: 0.72,
                brightness: 0.34,
                alpha: 1
            )
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [start.cgColor, end.cgColor] as CFArray,
                locations: [0, 1]
            ) {
                context.cgContext.drawLinearGradient(
                    gradient,
                    start: .zero,
                    end: CGPoint(x: size.width, y: size.height),
                    options: []
                )
            }

            let fontSize = max(11, size.width * 0.38)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: fontSize, weight: .bold),
                .foregroundColor: UIColor.white.withAlphaComponent(0.95)
            ]
            let text = RadioStationIdentity.initials(for: stationName) as NSString
            let textSize = text.size(withAttributes: attributes)
            text.draw(
                at: CGPoint(
                    x: (size.width - textSize.width) / 2,
                    y: (size.height - textSize.height) / 2
                ),
                withAttributes: attributes
            )
        }
    }
}
