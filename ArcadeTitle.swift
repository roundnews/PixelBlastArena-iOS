import SwiftUI

struct ArcadeTitle: View {
    var body: some View {
        VStack(spacing: -10) {
            word("PIXEL", fill: .orange, highlight: .yellow)
            word("BLAST", fill: .cyan, highlight: .white.opacity(0.9))
            word("ARENA", fill: .white, highlight: .white.opacity(0.85))
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 22)
        .background(plaque)
        .shadow(color: .black.opacity(0.45), radius: 18, x: 0, y: 14)
    }

    // MARK: - Word styling
    private func word(_ text: String, fill: Color, highlight: Color) -> some View {
        ZStack {
            // 1) Big dark outline (bottom-most)
            Text(text)
                .font(.system(size: 64, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.85))
                .offset(x: 0, y: 6)
                .blur(radius: 0.2)

            // 2) Colored fill (middle)
            Text(text)
                .font(.system(size: 64, weight: .heavy, design: .rounded))
                .foregroundStyle(fillGradient(for: fill))
                .shadow(color: fill.opacity(0.35), radius: 6, x: 0, y: 0) // subtle glow

            // 3) Bright highlight stroke / glow (top-most)
            Text(text)
                .font(.system(size: 64, weight: .heavy, design: .rounded))
                .foregroundStyle(.clear)
                .overlay(
                    Text(text)
                        .font(.system(size: 64, weight: .heavy, design: .rounded))
                        .foregroundStyle(highlight.opacity(0.95))
                        .shadow(color: highlight.opacity(0.7), radius: 2, x: 0, y: 0)
                        .shadow(color: highlight.opacity(0.5), radius: 3, x: 0, y: 0)
                        .blur(radius: 0.2)
                        .opacity(0.9)
                )

            // 4) Drop shadow for depth
            Text(text)
                .font(.system(size: 64, weight: .heavy, design: .rounded))
                .foregroundStyle(.clear)
                .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 6)
        }
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Gradients
    private func fillGradient(for base: Color) -> LinearGradient {
        LinearGradient(
            colors: [
                base.opacity(1.0),
                base.opacity(0.85),
                base.opacity(1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Background plaque
    private var plaque: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.08, green: 0.12, blue: 0.25),
                        Color(red: 0.05, green: 0.08, blue: 0.18)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 2)
            )
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        ArcadeTitle()
            .padding(.top, 40)
    }
}
