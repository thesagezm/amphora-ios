import PandoraCore
import SwiftUI

/// The rating row on the Now Playing screen — Apple-Music-plain: two
/// large glyphs, no filled circles. The active rating turns the accent;
/// tapping it removes it again (pithos' `Song.rate` toggles love/ban
/// off). The former third button (hide-song, moon icon — the cause of
/// the "two sleep timers" confusion) now lives in the player's
/// ellipsis menu with a distinct ear.slash glyph.
struct FeedbackBar: View {
    @Environment(AppStore.self) private var store
    let accent: PaletteColor

    var body: some View {
        HStack(spacing: 64) {
            ratingButton(.loved, systemImage: "hand.thumbsup", label: "Thumbs up")
            ratingButton(.banned, systemImage: "hand.thumbsdown", label: "Thumbs down")
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
                .font(.title2.weight(.medium))
                .foregroundStyle(isActive ? accent.color : Color.primary)
                .frame(width: 52, height: 52)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(label)
        .accessibilityValue(isActive ? "On" : "Off")
    }
}
