import SwiftUI

// MARK: - Glass Card
/// Glassmorphism-style card component used throughout the app.
struct GlassCard<Content: View>: View {
    let cornerRadius: CGFloat
    let content: () -> Content

    init(cornerRadius: CGFloat = 16, @ViewBuilder content: @escaping () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content
    }

    var body: some View {
        content()
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.15), Color.white.opacity(0.05)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)
            )
    }
}

// MARK: - Haya Background
struct HayaBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.hayaGradientTop, Color.hayaGradientBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Subtle mesh overlay
            RadialGradient(
                colors: [Color.hayaBlue.opacity(0.08), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 400
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [Color.hayaGold.opacity(0.05), .clear],
                center: .bottomTrailing,
                startRadius: 0,
                endRadius: 350
            )
            .ignoresSafeArea()
        }
    }
}
