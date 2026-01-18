import Foundation

enum GameConstants {
    // Grid
    static let gridColumns: Int = 26
    static let gridRows: Int = 22
    static let defaultTileSize: CGFloat = 32
    
    // Sprites
    static let bombSizeMultiplier: CGFloat = 1.7
    static let playerSizeMultiplier: CGFloat = 1.4
    
    // Timing
    static let defaultFuseTime: Double = 3.8
    static let moveDuration: TimeInterval = 0.22
    static let chainExplosionDelay: TimeInterval = 0.08
    
    // Gameplay
    static let defaultExplosionRange: Int = 2
    static let maxConcurrentBombs: Int = 5
    
    // UI
    static let titleFontSize: CGFloat = 64
}
