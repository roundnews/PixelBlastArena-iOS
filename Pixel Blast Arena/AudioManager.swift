import Foundation
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif

final class AudioManager {
    static let shared = AudioManager()
    private var bgmPlayer: AVAudioPlayer?

    private init() {}

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
        p.volume = 0.8
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
}
