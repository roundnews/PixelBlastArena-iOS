import Foundation
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif

final class AudioManager: NSObject {
    static let shared = AudioManager()
    private var bgmPlayer: AVAudioPlayer?
    private var sfxPlayers: [AVAudioPlayer] = []
    private var duckingCount: Int = 0
    private var bgmNormalVolume: Float = 0.8
    private var bgmDuckedVolume: Float = 0.35

    private override init() { super.init() }

    func playBGM() {
        // If already playing, do nothing
        if let p = bgmPlayer, p.isPlaying { return }

        // Configure audio session for ambient playback that mixes with others
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.ambient, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            // Non-fatal: continue even if session fails
            print("AudioManager: Failed to set audio session: \(error)")
        }

        // Load data asset first, fallback to bundle resource
        var player: AVAudioPlayer?
        #if canImport(UIKit)
        if let dataAsset = NSDataAsset(name: "bg-music") {
            do {
                player = try AVAudioPlayer(data: dataAsset.data)
            } catch {
                print("AudioManager: Failed to create player from data asset: \(error)")
            }
        }
        #endif

        if player == nil, let url = Bundle.main.url(forResource: "bg-music", withExtension: "mp3") {
            do {
                player = try AVAudioPlayer(contentsOf: url)
            } catch {
                print("AudioManager: Failed to create player from file: \(error)")
            }
        }

        guard let p = player else {
            print("AudioManager: bg-music asset not found.")
            return
        }

        p.numberOfLoops = -1 // loop indefinitely
        bgmNormalVolume = 0.8
        // If currently ducking (due to active SFX), start at ducked volume
        p.volume = (duckingCount > 0) ? bgmDuckedVolume : bgmNormalVolume
        p.prepareToPlay()
        p.play()
        bgmPlayer = p
    }

    func restartBGM() {
        bgmPlayer?.stop()
        bgmPlayer = nil
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [])
        } catch {
            // Non-fatal
        }
        playBGM()
    }

    func stopBGM() {
        bgmPlayer?.stop()
        bgmPlayer = nil
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [])
        } catch {
            // Non-fatal
        }
    }
    
    func playSFX(named name: String, volume: Float = 1.0) {
        var player: AVAudioPlayer?
        #if canImport(UIKit)
        if let dataAsset = NSDataAsset(name: name) {
            do {
                player = try AVAudioPlayer(data: dataAsset.data)
            } catch {
                print("AudioManager: Failed to create SFX player from data asset \(name): \(error)")
            }
        }
        #endif
        if player == nil, let url = Bundle.main.url(forResource: name, withExtension: "mp3") {
            do {
                player = try AVAudioPlayer(contentsOf: url)
            } catch {
                print("AudioManager: Failed to create SFX player from file \(name): \(error)")
            }
        }
        guard let p = player else {
            print("AudioManager: SFX asset not found: \(name)")
            return
        }
        p.volume = max(0.0, min(1.0, volume))
        p.delegate = self
        p.prepareToPlay()

        // Begin ducking background music while this SFX plays
        beginDuckingForSFX()

        p.play()
        sfxPlayers.append(p)
        // For bomb sounds, layer additional copies to perceptually boost loudness
        let extraCopies: Int
        switch name {
        case "bomb-explode": extraCopies = 2
        case "bomb-place": extraCopies = 1
        default: extraCopies = 0
        }
        if extraCopies > 0 {
            for _ in 0..<extraCopies {
                var boostPlayer: AVAudioPlayer?
                #if canImport(UIKit)
                if let dataAsset = NSDataAsset(name: name) {
                    do {
                        boostPlayer = try AVAudioPlayer(data: dataAsset.data)
                    } catch {
                        print("AudioManager: Failed to create boosted SFX from data asset \(name): \(error)")
                    }
                }
                #endif
                if boostPlayer == nil, let url = Bundle.main.url(forResource: name, withExtension: "mp3") {
                    do {
                        boostPlayer = try AVAudioPlayer(contentsOf: url)
                    } catch {
                        print("AudioManager: Failed to create boosted SFX from file \(name): \(error)")
                    }
                }
                if let bp = boostPlayer {
                    bp.volume = max(0.0, min(1.0, volume))
                    bp.delegate = self
                    bp.prepareToPlay()
                    // Keep BGM ducked until all layered copies finish
                    beginDuckingForSFX()
                    bp.play()
                    sfxPlayers.append(bp)
                }
            }
        }
    }
    
    private func beginDuckingForSFX() {
        guard let bgm = bgmPlayer else { return }
        duckingCount += 1
        if duckingCount == 1 {
            bgm.setVolume(bgmDuckedVolume, fadeDuration: 0.05)
        }
    }

    private func endDuckingForSFX() {
        duckingCount = max(0, duckingCount - 1)
        guard let bgm = bgmPlayer else { return }
        if duckingCount == 0 {
            bgm.setVolume(bgmNormalVolume, fadeDuration: 0.1)
        }
    }
}
extension AudioManager: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        endDuckingForSFX()
        if let idx = sfxPlayers.firstIndex(where: { $0 === player }) {
            sfxPlayers.remove(at: idx)
        }
    }
}

