import PandoraCore
import SwiftUI

/// Feedback row on the Now Playing screen: thumbs up, thumbs down and
/// "hide this song" (sleep). Tapping the active rating removes it again
/// (pithos' `Song.rate` toggles love/ban off).
struct FeedbackBar: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        HStack(spacing: 28) {
            ratingButton(.loved, systemImage: "hand.thumbsup", label: "Thumbs up")
            ratingButton(.banned, systemImage: "hand.thumbsdown", label: "Thumbs down")
            Button {
                store.send(.sleepCurrentTrack)
            } label: {
                Image(systemName: "moon.zzz")
                    .font(.title2)
                    .frame(width: 48, height: 48)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Hide this song for a few hours")
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
            store.send(isActive ? .removeCurrentRating : .rateCurrentTrack(rating))
        } label: {
            Image(systemName: isActive ? "\(systemImage).fill" : systemImage)
                .font(.title2)
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                .frame(width: 48, height: 48)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(isActive ? "On" : "Off")
    }
}
