import AVKit
import SwiftUI
import UIKit

/// The system AirPlay route picker, wrapped for SwiftUI.
///
/// `AVRoutePickerView` is UIKit-only — SwiftUI has no equivalent — so
/// this is the one UIKit control the player borrows. It is the same
/// control the system shows in Music and Podcasts: tapping it lists the
/// AirPlay receivers, Bluetooth devices and nearby screens, and picking
/// one hands the audio session over to it.
///
/// Only audio destinations are offered (Amphora is a music app), and the
/// control is tinted with the live theme so it sits in the player's
/// toolbar instead of looking bolted on.
struct AirPlayRoutePicker: UIViewRepresentable {
    /// The tint while the phone's own speaker is the output.
    var tint: UIColor
    /// The tint while an external route is active.
    var activeTint: UIColor

    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.prioritizesVideoDevices = false
        picker.tintColor = tint
        picker.activeTintColor = activeTint
        picker.accessibilityLabel = "AirPlay"
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        uiView.tintColor = tint
        uiView.activeTintColor = activeTint
    }
}

/// The SF Symbol that matches the route the audio is going to.
enum RouteSymbol {
    /// AirPlay receivers get the AirPlay glyph; any other external
    /// device (a Bluetooth speaker, a pair of headphones) gets a
    /// speaker glyph.
    static func name(isAirPlay: Bool) -> String {
        isAirPlay ? "airplayvideo" : "speaker.wave.2.fill"
    }
}
