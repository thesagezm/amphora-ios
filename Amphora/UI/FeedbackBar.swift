import PandoraCore
import SwiftUI

/// Feedback row on the Now Playing screen: circular surface buttons —
/// thumbs up, thumbs down and "hide this song" (sleep). Tapping the
/// active rating removes it again (pithos' `Song.rate` toggles love/ban
/// off). The active rating fills with the artwork accent.
struct FeedbackBar: View {
    @Environment(AppStore.self) private var store
    let accent: PaletteColor

    var body: some View {
        HStack(spacing: 24) {
            ratingButton(.loved, systemImage: "hand.thumbsup", label: "Thumbs up")
            ratingButton(.banned, systemImage: "hand.thumbsdown", label: "Thumbs down")
            sleepButton
        }
        .frame(maxWidth: .infinity)
    }

    private func ratingButton(
        _ rating: FeedbackRating,
        systemImage: String,
        label: String
    ) -> some View {
        let isActive = store.currentRating == rating
        return Button {
            Haptics.light()
            store.send(isActive ? .removeCurrentRating : .rateCurrentTrack(rating))
        } label: {
            Image(systemName: isActive ? "\(systemImage).fill" : systemImage)
                .font(.title3.weight(.medium))
                .foregroundStyle(
                    isActive
                        ? (accent.isLight ? Color.black.opacity(0.85) : Color.white)
                        : Color.primary
                )
                .frame(width: 52, height: 52)
                .background(isActive ? accent.color : Theme.surface, in: Circle())
                .overlay(Circle().strokeBorder(Theme.stroke))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(isActive ? "On" : "Off")
    }

    private var sleepButton: some View {
        Button {
            Haptics.light()
            store.send(.sleepCurrentTrack)
        } label: {
            Image(systemName: "moon.zzz")
                .font(.title3.weight(.medium))
                .foregroundStyle(.primary)
                .frame(width: 52, height: 52)
                .background(Theme.surface, in: Circle())
                .overlay(Circle().strokeBorder(Theme.stroke))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Hide this song for a few hours")
    }
}
