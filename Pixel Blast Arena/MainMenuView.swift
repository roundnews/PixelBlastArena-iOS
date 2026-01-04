import SwiftUI

struct MainMenuView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                Text("Pixel Blast Arena")
                    .font(.largeTitle).bold()
                    .foregroundStyle(.white)
                    .padding(.horizontal)

                Text("Retro bomb-blasting fun!")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))

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
        .toolbar(.hidden, for: .navigationBar)
    }
}

#Preview {
    NavigationStack { MainMenuView() }
}
