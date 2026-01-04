import SwiftUI
import SpriteKit

struct GameView: View {
    @State private var isPaused: Bool = false
    @State private var enemiesLeft: Int = 0
    @State private var level: Int = 1
    @State private var isGameOver: Bool = false
    @State private var didWin: Bool = false

    @State private var scene: GameScene = {
        let s = GameScene()
        s.scaleMode = .resizeFill
        return s
    }()

    var body: some View {
        ZStack {
            SpriteView(scene: scene)
                .background(Color.black)
                .ignoresSafeArea()

            // HUD Top Bar
            VStack {
                HStack {
                    Text("Pixel Blast Arena")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(Color.black.opacity(0.35))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    HStack(spacing: 8) {
                        Text("Lvl \(level)")
                            .font(.subheadline).bold()
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(Color.black.opacity(0.35))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        Text("Enemies \(enemiesLeft)")
                            .font(.subheadline).bold()
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(Color.black.opacity(0.35))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }

                    Spacer()

                    Button {
                        scene.togglePause()
                        isPaused.toggle()
                    } label: {
                        Image(systemName: isPaused ? "play.circle.fill" : "pause.circle.fill")
                            .foregroundStyle(.white)
                            .font(.title2)
                            .padding(10)
                            .background(Color.black.opacity(0.35))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                .padding([.top, .horizontal])
                .padding(.top, 20)

                Spacer()

                // Controls: D-pad + Bomb
                HStack {
                    DPadView { direction in
                        scene.handleMove(direction: direction)
                    }
                    .disabled(isPaused || isGameOver)

                    Spacer()

                    Button {
                        scene.placeBomb()
                    } label: {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(22)
                            .background(.red)
                            .clipShape(Circle())
                            .shadow(radius: 6)
                    }
                    .disabled(isPaused || isGameOver)
                    .padding(.trailing)
                }
                .padding(.bottom)
            }

            if isPaused && !isGameOver {
                PauseOverlay(resume: {
                    scene.togglePause()
                    isPaused = false
                }, restart: {
                    scene.restart()
                    isPaused = false
                    isGameOver = false
                })
            }

            if isGameOver {
                GameOverOverlay(didWin: didWin, restart: {
                    scene.restart()
                    isPaused = false
                    isGameOver = false
                })
            }
        }
        .background(Color.black)
        .ignoresSafeArea()
        .onAppear {
            scene.onPauseChanged = { paused in
                DispatchQueue.main.async { self.isPaused = paused }
            }
            scene.onHUDUpdate = { enemies, lvl in
                DispatchQueue.main.async {
                    self.enemiesLeft = enemies
                    self.level = lvl
                }
            }
            scene.onGameOver = { youWin in
                DispatchQueue.main.async {
                    self.didWin = youWin
                    self.isGameOver = true
                }
            }
            // Initialize HUD state
            self.enemiesLeft = scene.enemiesCount
            self.level = scene.level
            self.isPaused = scene.isGamePaused
        }
    }
}

// Simple on-screen D-pad for grid movement
struct DPadView: View {
    var onTap: (Direction) -> Void

    var body: some View {
        VStack(spacing: 8) {
            Button { onTap(.up) } label: { dpadButton(system: "chevron.up") }
            HStack(spacing: 8) {
                Button { onTap(.left) } label: { dpadButton(system: "chevron.left") }
                Color.clear.frame(width: 44, height: 44)
                Button { onTap(.right) } label: { dpadButton(system: "chevron.right") }
            }
            Button { onTap(.down) } label: { dpadButton(system: "chevron.down") }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.2))
        )
        .padding(.leading)
    }

    @ViewBuilder private func dpadButton(system: String) -> some View {
        Image(systemName: system)
            .font(.title2.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(Color.blue)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(radius: 4)
    }
}

struct PauseOverlay: View {
    var resume: () -> Void
    var restart: () -> Void
    var body: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 16) {
                Text("Paused").font(.title).bold().foregroundStyle(.white)
                HStack(spacing: 16) {
                    Button("Resume", action: resume)
                        .padding(.vertical, 10).padding(.horizontal, 16)
                        .background(.blue).foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Button("Restart", action: restart)
                        .padding(.vertical, 10).padding(.horizontal, 16)
                        .background(.red).foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding(24)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(radius: 12)
        }
    }
}

struct GameOverOverlay: View {
    var didWin: Bool
    var restart: () -> Void
    var body: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea()
            VStack(spacing: 16) {
                Text(didWin ? "You Win!" : "Game Over").font(.largeTitle).bold().foregroundStyle(.white)
                Button("Restart", action: restart)
                    .padding(.vertical, 10).padding(.horizontal, 16)
                    .background(.blue).foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(24)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(radius: 12)
        }
    }
}

#Preview {
    GameView()
}
