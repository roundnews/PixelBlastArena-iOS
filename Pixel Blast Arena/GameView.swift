import SwiftUI
import SpriteKit

struct GameView: View {
    @State private var isPaused: Bool = false
    @State private var enemiesLeft: Int = 0
    @State private var level: Int = 1
    @State private var isGameOver: Bool = false
    @State private var didWin: Bool = false
    @State private var activePowerup: PowerupType?
    @State private var powerupSecondsRemaining: Int = 0
    @State private var powerupTimer: Timer?
    @State private var announcedPowerup: PowerupType?
    @State private var announcementWorkItem: DispatchWorkItem?
    @State private var showCheatAnnouncement: Bool = false
    @State private var cheatAnnouncementWorkItem: DispatchWorkItem?
    @State private var showPortalHint: Bool = false
    @State private var portalHintWorkItem: DispatchWorkItem?
    @State private var showBombHint: Bool = false
    @State private var hasShownBombHint: Bool = false
    @State private var bombHintWorkItem: DispatchWorkItem?

    @State private var scene: GameScene = {
        let s = GameScene()
        s.scaleMode = .resizeFill
        return s
    }()

    var body: some View {
        ZStack {
            SpriteView(scene: scene)
                .simultaneousGesture(
                    TapGesture(count: 2).onEnded {
                        if !isPaused && !isGameOver {
                            scene.placeBomb()
                        }
                    }
                )
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
                        if !hasShownBombHint {
                            hasShownBombHint = true
                            bombHintWorkItem?.cancel()
                            showBombHint = true
                            let work = DispatchWorkItem {
                                self.showBombHint = false
                            }
                            bombHintWorkItem = work
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
                        }
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

            if let p = announcedPowerup {
                VStack {
                    Spacer()
                    Text(powerupTitle(for: p))
                        .font(.title3).bold()
                        .foregroundStyle(.white)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .background(Color.black.opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .shadow(radius: 6)
                    Spacer()
                }
                .allowsHitTesting(false)
                .transition(.opacity.combined(with: .scale))
            }
            if showCheatAnnouncement {
                VStack {
                    Spacer()
                    Text("Cheat Active")
                        .font(.title3).bold()
                        .foregroundStyle(.white)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .background(Color.black.opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .shadow(radius: 6)
                    Spacer()
                }
                .allowsHitTesting(false)
                .transition(.opacity.combined(with: .scale))
            }
            if showPortalHint {
                VStack {
                    Spacer()
                    Text("Portal Inactive\nDestroy all monsters")
                        .multilineTextAlignment(.center)
                        .font(.title3).bold()
                        .foregroundStyle(.white)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .background(Color.black.opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .shadow(radius: 6)
                    Spacer()
                }
                .allowsHitTesting(false)
                .transition(.opacity.combined(with: .scale))
            }
            if showBombHint {
                VStack {
                    Spacer()
                    Text("Also Double Tap to place bombs")
                        .font(.title3).bold()
                        .foregroundStyle(.white)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .background(Color.black.opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .shadow(radius: 6)
                    Spacer()
                }
                .allowsHitTesting(false)
                .transition(.opacity.combined(with: .scale))
            }

            if powerupSecondsRemaining > 0 {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text("\(powerupSecondsRemaining)s")
                            .font(.headline).bold()
                            .foregroundStyle(.white)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(Color.black.opacity(0.6))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .shadow(radius: 4)
                    }
                    .padding(.trailing)
                    .padding(.bottom)
                }
                .allowsHitTesting(false)
            }

            if isPaused && !isGameOver {
                PauseOverlay(resume: {
                    scene.togglePause()
                    isPaused = false
                }, restart: {
                    scene.startNewGame()
                    powerupTimer?.invalidate()
                    powerupTimer = nil
                    activePowerup = nil
                    powerupSecondsRemaining = 0
                    announcementWorkItem?.cancel()
                    announcementWorkItem = nil
                    announcedPowerup = nil
                    self.cheatAnnouncementWorkItem?.cancel()
                    self.cheatAnnouncementWorkItem = nil
                    self.showCheatAnnouncement = false
                    self.portalHintWorkItem?.cancel()
                    self.portalHintWorkItem = nil
                    self.showPortalHint = false
                    self.bombHintWorkItem?.cancel()
                    self.bombHintWorkItem = nil
                    self.showBombHint = false
                    self.hasShownBombHint = false
                    isPaused = false
                    isGameOver = false
                })
            }

            if isGameOver {
                GameOverOverlay(didWin: didWin, restart: {
                    scene.startNewGame()
                    powerupTimer?.invalidate()
                    powerupTimer = nil
                    activePowerup = nil
                    powerupSecondsRemaining = 0
                    announcementWorkItem?.cancel()
                    announcementWorkItem = nil
                    announcedPowerup = nil
                    self.cheatAnnouncementWorkItem?.cancel()
                    self.cheatAnnouncementWorkItem = nil
                    self.showCheatAnnouncement = false
                    self.portalHintWorkItem?.cancel()
                    self.portalHintWorkItem = nil
                    self.showPortalHint = false
                    self.bombHintWorkItem?.cancel()
                    self.bombHintWorkItem = nil
                    self.showBombHint = false
                    self.hasShownBombHint = false
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
                    self.powerupTimer?.invalidate()
                    self.powerupTimer = nil
                    self.activePowerup = nil
                    self.powerupSecondsRemaining = 0
                    self.announcementWorkItem?.cancel()
                    self.announcementWorkItem = nil
                    self.announcedPowerup = nil
                }
            }
            scene.onPowerupCollected = { type in
                DispatchQueue.main.async {
                    // Show 3-second center announcement (non-blocking)
                    self.announcementWorkItem?.cancel()
                    self.announcedPowerup = type
                    let work = DispatchWorkItem {
                        self.announcedPowerup = nil
                    }
                    self.announcementWorkItem = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)

                    // Start/refresh countdown for timed powerups
                    let duration = self.powerupDuration(for: type)
                    self.powerupSecondsRemaining = duration
                    self.powerupTimer?.invalidate()

                    if duration > 0 {
                        self.powerupTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { t in
                            if self.powerupSecondsRemaining > 1 {
                                self.powerupSecondsRemaining -= 1
                            } else {
                                t.invalidate()
                                self.powerupTimer = nil
                                self.powerupSecondsRemaining = 0
                                scene.expireTimedPowerup()
                            }
                        }
                    } else {
                        // No timer for permanent effects
                    }
                }
            }
            scene.onCheatActivated = {
                DispatchQueue.main.async {
                    self.cheatAnnouncementWorkItem?.cancel()
                    self.showCheatAnnouncement = true
                    let work = DispatchWorkItem {
                        self.showCheatAnnouncement = false
                    }
                    self.cheatAnnouncementWorkItem = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
                }
            }
            scene.onPortalHint = {
                DispatchQueue.main.async {
                    self.portalHintWorkItem?.cancel()
                    self.showPortalHint = true
                    let work = DispatchWorkItem {
                        self.showPortalHint = false
                    }
                    self.portalHintWorkItem = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
                }
            }
            // Initialize HUD state
            self.enemiesLeft = scene.enemiesCount
            self.level = scene.level
            self.isPaused = scene.isGamePaused
        }
        .onDisappear {
            powerupTimer?.invalidate()
            powerupTimer = nil
            announcementWorkItem?.cancel()
            announcementWorkItem = nil
            cheatAnnouncementWorkItem?.cancel()
            cheatAnnouncementWorkItem = nil
            showCheatAnnouncement = false
            portalHintWorkItem?.cancel()
            portalHintWorkItem = nil
            showPortalHint = false
            bombHintWorkItem?.cancel()
            bombHintWorkItem = nil
            showBombHint = false
        }
    }

    private func powerupTitle(for type: PowerupType) -> String {
        switch type {
        case .powerBomb: return "Power Bomb"
        case .speedIncrease: return "Speed Up"
        case .speedDecrease: return "Speed Down"
        case .passThrough: return "Pass Through"
        case .moreBombs: return "More Bombs!"
        }
    }

    private func powerupDuration(for type: PowerupType) -> Int {
        switch type {
        case .powerBomb, .speedIncrease, .speedDecrease, .passThrough:
            return 10
        case .moreBombs:
            return 0
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

