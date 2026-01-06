import SwiftUI

struct MainMenuView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            GeometryReader { proxy in
                let size = proxy.size
                let isLandscape = size.width > size.height
                let imageName = isLandscape ? "bg-landscape" : "bg-portrait"

                Color.clear
                    .ignoresSafeArea()
                    .overlay(
                        Image(imageName),
                        alignment: .center
                    )
                    .clipped()
            }

            VStack(spacing: 24) {
                Spacer()

                ArcadeTitle()
                    .padding(.horizontal)

                Text("Retro bomb-blasting fun!")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.black.opacity(0.85))
                    )

                Spacer()

                NavigationLink {
                    GameView()
                } label: {
                    Text("Start Game")
                        .font(.title3).bold()
                        .padding(.vertical, 14)
                        .padding(.horizontal, 32)
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                Spacer()
            }
            .padding()
        }
        .ignoresSafeArea()
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { AudioManager.shared.restartBGM() }
    }
}

#Preview {
    NavigationStack { MainMenuView() }
}

