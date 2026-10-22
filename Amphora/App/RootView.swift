import SwiftUI

struct RootView: View {
    var body: some View {
        ZStack {
            Color.primaryBackground.ignoresSafeArea()
            content
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("Amphora")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(.tint)
            Text("Signing in — nothing to play yet.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
    }
}

#Preview {
    RootView()
}

extension ShapeStyle where Self == Color {
    static var primaryBackground: Color {
        Color(red: 0.07, green: 0.07, blue: 0.09)
    }
}
