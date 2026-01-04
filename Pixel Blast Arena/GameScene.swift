import SpriteKit
import SwiftUI

final class GameScene: SKScene {
    // Grid/world
    private let cols = 26
    private let rows = 22
    private var tileSize: CGFloat = 32
    private let worldNode = SKNode()

    // Camera
    private let cameraNode = SKCameraNode()
    private let playerScreenYFraction: CGFloat = 0.30

    // Map and entities
    private var tileMap: TileMap!
    private var player = Player()
    private var enemies: [Enemy] = []
    var level: Int = 1
    var enemiesCount: Int { enemies.count }

    // Nodes
    private var explosionFrames: [SKTexture] = []
    private var playerNode = SKSpriteNode(color: .green, size: CGSize(width: 28, height: 28))
    private var enemyNodes: [SKSpriteNode] = []

    private var escapeBombPosition: GridPoint?
    private var escapeWindowDeadline: TimeInterval = 0

    var onPauseChanged: ((Bool) -> Void)?
    var onHUDUpdate: ((Int, Int) -> Void)?
    var onGameOver: ((Bool) -> Void)?

    // Timing
    private var lastUpdateTime: TimeInterval = 0

    // MARK: - Scene lifecycle
    override func didMove(to view: SKView) {
        backgroundColor = .black
        tileSize = computedTileSize(for: size)
        loadExplosionFrames()

        addChild(worldNode)
        buildMap()
        spawnPlayer()
        spawnEnemies(count: 3)

        // Camera
        addChild(cameraNode)
        camera = cameraNode
        updateCamera()
        onHUDUpdate?(enemies.count, level)
    }

    // MARK: - Map
    private func buildMap() {
        tileMap = TileMap(cols: cols, rows: rows, tileSize: tileSize)
        tileMap.generateBasicLayout()
        renderTiles()
    }

    private func renderTiles() {
        guard let map = tileMap else { return }
        // Render tiles as colored squares
        for r in 0..<rows {
            for c in 0..<cols {
                let tile = map.tileAt(col: c, row: r)
                let node = SKSpriteNode(color: tile.skColor, size: CGSize(width: tileSize, height: tileSize))
                node.position = positionFor(col: c, row: r)
                node.zPosition = 0
                node.name = "tile_\(c)_\(r)"
                // Removed node.isAntialiased = false as per instructions
                worldNode.addChild(node)
            }
        }
    }

    private func refreshTile(at col: Int, row: Int) {
        let name = "tile_\(col)_\(row)"
        if let node = worldNode.childNode(withName: name) as? SKSpriteNode {
            let tile = tileMap.tileAt(col: col, row: row)
            node.color = tile.skColor
        }
    }

    private func positionFor(col: Int, row: Int) -> CGPoint {
        let x = CGFloat(col) * tileSize + tileSize/2
        let y = CGFloat(row) * tileSize + tileSize/2
        return CGPoint(x: x, y: y)
    }

    // MARK: - Player
    private func spawnPlayer() {
        player.gridPosition = GridPoint(col: 1, row: 1)
        playerNode.size = CGSize(width: tileSize * 0.9, height: tileSize * 0.9)
        playerNode.position = positionFor(col: player.gridPosition.col, row: player.gridPosition.row)
        playerNode.zPosition = 10
        worldNode.addChild(playerNode)
    }

    func handleMove(direction: Direction) {
        let delta: (dc: Int, dr: Int)
        switch direction {
        case .up: delta = (0, 1)
        case .down: delta = (0, -1)
        case .left: delta = (-1, 0)
        case .right: delta = (1, 0)
        }
        let target = GridPoint(col: player.gridPosition.col + delta.dc, row: player.gridPosition.row + delta.dr)
        movePlayer(to: target)
    }

    private func movePlayer(to target: GridPoint) {
        // Primary rule: normal walkability check allowing stepping off a placed bomb
        var canMove = tileMap.isWalkableForPlayer(from: player.gridPosition, to: target)
        if !canMove, let escapePos = escapeBombPosition, escapePos == player.gridPosition, CACurrentMediaTime() < escapeWindowDeadline {
            // During the brief escape window, allow moving off the bomb tile as long as destination is empty and not a wall
            let destType = tileMap.tileAt(col: target.col, row: target.row).type
            let destHasBomb = tileMap.hasBomb(at: target)
            if destType == .empty && !destHasBomb { canMove = true }
        }

        guard canMove else { return }

        // Update grid state first
        player.gridPosition = target
        escapeBombPosition = nil
        let newPos = positionFor(col: target.col, row: target.row)

        // Apply movement immediately to avoid any action conflicts
        playerNode.removeAction(forKey: "move")
        playerNode.position = newPos
        // Small feedback pulse
        let pulse = SKAction.sequence([
            SKAction.scale(to: 0.96, duration: 0.05),
            SKAction.scale(to: 1.0, duration: 0.05)
        ])
        playerNode.run(pulse, withKey: "move")
    }

    // MARK: - Bombs
    func placeBomb() {
        let gp = player.gridPosition
        guard tileMap.canPlaceBomb(at: gp) else { return }
        let bomb = Bomb(position: gp)
        tileMap.place(bomb: bomb)

        let bombNode = SKSpriteNode(color: .orange, size: CGSize(width: tileSize*0.8, height: tileSize*0.8))
        bombNode.position = positionFor(col: gp.col, row: gp.row)
        bombNode.zPosition = 5
        bombNode.name = "bomb_\(gp.col)_\(gp.row)"
        worldNode.addChild(bombNode)

        escapeBombPosition = gp
        escapeWindowDeadline = CACurrentMediaTime() + 1.0

        // Simple countdown animation
        let pulse = SKAction.sequence([
            SKAction.scale(to: 1.1, duration: 0.2),
            SKAction.scale(to: 1.0, duration: 0.2)
        ])
        let countdown = SKAction.repeat(pulse, count: Int(bomb.fuseTime / 0.4))
        bombNode.run(countdown) { [weak self] in
            self?.explode(bomb: bomb, bombNode: bombNode)
        }
    }

    private func explode(bomb: Bomb, bombNode: SKSpriteNode) {
        bombNode.removeFromParent()
        tileMap.removeBomb(at: bomb.position)

        let affected = tileMap.explosionTiles(from: bomb.position, range: bomb.range)
        // Spawn explosion tiles
        for gp in affected {
            spawnExplosion(at: gp)
            // Destroy crates
            if tileMap.tileAt(col: gp.col, row: gp.row).type == .crate {
                tileMap.setTile(type: .empty, at: gp)
                refreshTile(at: gp.col, row: gp.row)
            }
        }

        // Damage player
        if affected.contains(player.gridPosition) {
            gameOver(youWin: false)
        }

        // Damage enemies
        for (idx, enemy) in enemies.enumerated().reversed() {
            if affected.contains(enemy.gridPosition) {
                if let node = enemyNodes[safe: idx] {
                    node.removeFromParent()
                }
                enemies.remove(at: idx)
            }
        }

        onHUDUpdate?(enemies.count, level)

        // Win condition
        if enemies.isEmpty {
            gameOver(youWin: true)
        }
    }

    private func spawnExplosion(at gp: GridPoint) {
        if !explosionFrames.isEmpty {
            let node = SKSpriteNode(texture: explosionFrames.first)
            node.size = CGSize(width: tileSize, height: tileSize)
            node.position = positionFor(col: gp.col, row: gp.row)
            node.zPosition = 8
            worldNode.addChild(node)
            // Removed node.isAntialiased = false as per instructions

            let animate = SKAction.animate(with: explosionFrames, timePerFrame: 0.06, resize: false, restore: false)
            node.run(.sequence([animate, .removeFromParent()]))
            return
        }

        // Fallback: simple colored tile effect
        let node = SKSpriteNode(color: .yellow, size: CGSize(width: tileSize, height: tileSize))
        node.position = positionFor(col: gp.col, row: gp.row)
        node.zPosition = 8
        worldNode.addChild(node)
        // Removed node.isAntialiased = false as per instructions

        let appear = SKAction.group([
            SKAction.fadeAlpha(to: 0.95, duration: 0.05),
            SKAction.scale(to: 1.05, duration: 0.05)
        ])
        let stay = SKAction.wait(forDuration: 0.15)
        let disappear = SKAction.group([
            SKAction.fadeOut(withDuration: 0.12),
            SKAction.scale(to: 1.2, duration: 0.12)
        ])
        node.run(.sequence([appear, stay, disappear, .removeFromParent()]))
    }

    // MARK: - Enemies
    private func spawnEnemies(count: Int) {
        enemies.removeAll()
        enemyNodes.forEach { $0.removeFromParent() }
        enemyNodes.removeAll()

        var spawned = 0
        var attempts = 0
        while spawned < count && attempts < 200 {
            attempts += 1
            let col = Int.random(in: 3..<(cols-2))
            let row = Int.random(in: 3..<(rows-2))
            if tileMap.isWalkable(col: col, row: row) {
                var e = Enemy()
                e.gridPosition = GridPoint(col: col, row: row)
                enemies.append(e)
                let node = SKSpriteNode(color: .red, size: CGSize(width: tileSize*0.8, height: tileSize*0.8))
                node.position = positionFor(col: col, row: row)
                node.zPosition = 9
                enemyNodes.append(node)
                worldNode.addChild(node)
                spawned += 1
            }
        }
    }

    private func updateEnemies(deltaTime: TimeInterval) {
        // Random stepping every 0.3s approx
        for (i, var enemy) in enemies.enumerated() {
            enemy.timeSinceLastMove += deltaTime
            if enemy.timeSinceLastMove > 0.3 {
                enemy.timeSinceLastMove = 0
                let dirs: [GridPoint] = [
                    GridPoint(col: 1, row: 0), GridPoint(col: -1, row: 0),
                    GridPoint(col: 0, row: 1), GridPoint(col: 0, row: -1)
                ]
                let shuffled = dirs.shuffled()
                for d in shuffled {
                    let target = GridPoint(col: enemy.gridPosition.col + d.col, row: enemy.gridPosition.row + d.row)
                    if tileMap.isWalkable(col: target.col, row: target.row) {
                        enemy.gridPosition = target
                        enemies[i] = enemy
                        if let node = enemyNodes[safe: i] {
                            let pos = positionFor(col: target.col, row: target.row)
                            node.run(SKAction.move(to: pos, duration: 0.16))
                        }
                        break
                    }
                }
            } else {
                enemies[i] = enemy
            }
        }

        // Player collision
        for enemy in enemies {
            if enemy.gridPosition == player.gridPosition {
                gameOver(youWin: false)
                break
            }
        }
    }

    // MARK: - Camera
    override func didFinishUpdate() {
        updateCamera()
    }

    private func updateCamera() {
        let viewW = size.width
        let viewH = size.height

        let worldW = CGFloat(cols) * tileSize
        let worldH = CGFloat(rows) * tileSize

        let offsetFactor = playerScreenYFraction - 0.5 // -0.20
        let yOffset = offsetFactor * viewH

        var targetX = playerNode.position.x
        var targetY = playerNode.position.y - yOffset

        let halfW = viewW / 2
        let halfH = viewH / 2

        if worldW <= viewW { targetX = worldW / 2 } else { targetX = min(max(targetX, halfW), worldW - halfW) }
        if worldH <= viewH { targetY = worldH / 2 } else { targetY = min(max(targetY, halfH), worldH - halfH) }

        // Smooth follow
        let current = cameraNode.position
        let desired = CGPoint(x: targetX, y: targetY)
        cameraNode.position = CGPoint(
            x: current.x + (desired.x - current.x) * 0.15,
            y: current.y + (desired.y - current.y) * 0.15
        )
    }

    // MARK: - Update loop
    override func update(_ currentTime: TimeInterval) {
        let dt = lastUpdateTime == 0 ? 0 : currentTime - lastUpdateTime
        lastUpdateTime = currentTime
        updateEnemies(deltaTime: dt)
    }

    // MARK: - Game state
    private(set) var isGamePaused = false
    func togglePause() {
        isGamePaused.toggle()
        isPaused = isGamePaused
        onPauseChanged?(isGamePaused)
    }

    private func gameOver(youWin: Bool) {
        onGameOver?(youWin)
        onPauseChanged?(true)
        isPaused = true
        isGamePaused = true
        // Simple overlay as label node for now
        let text = youWin ? "YOU WIN" : "GAME OVER"
        let label = SKLabelNode(text: text)
        label.fontName = ".AppleSystemUIFontBold"
        label.fontSize = 48
        label.fontColor = .white
        label.zPosition = 100
        label.position = CGPoint(x: cameraNode.position.x, y: cameraNode.position.y)
        addChild(label)
    }

    private func computedTileSize(for viewSize: CGSize) -> CGFloat {
        // Ensure world is larger than the viewport in both axes to allow scrolling
        let neededW = viewSize.width / CGFloat(cols) + 1
        let neededH = viewSize.height / CGFloat(rows) + 1
        return ceil(max(neededW, neededH))
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        tileSize = computedTileSize(for: size)
        guard tileMap != nil else { return }
        rebuildWorldPreservingEntities()
    }

    private func rebuildWorldPreservingEntities() {
        guard tileMap != nil else { return }
        // Remove all tile/bomb/explosion nodes and rebuild tiles, then re-add entities at their grid positions
        worldNode.removeAllChildren()
        renderTiles()

        // Re-add player
        playerNode.size = CGSize(width: tileSize * 0.9, height: tileSize * 0.9)
        playerNode.position = positionFor(col: player.gridPosition.col, row: player.gridPosition.row)
        playerNode.zPosition = 10
        worldNode.addChild(playerNode)

        // Re-add enemies
        enemyNodes.removeAll()
        for e in enemies {
            let node = SKSpriteNode(color: .red, size: CGSize(width: tileSize*0.8, height: tileSize*0.8))
            node.position = positionFor(col: e.gridPosition.col, row: e.gridPosition.row)
            node.zPosition = 9
            enemyNodes.append(node)
            worldNode.addChild(node)
        }

        updateCamera()
    }

    private func loadExplosionFrames() {
        var frames: [SKTexture] = []
        #if canImport(UIKit)
        for i in 0..<12 {
            let name = "explosion_\(i)"
            if UIImage(named: name) != nil {
                let tex = SKTexture(imageNamed: name)
                tex.filteringMode = .nearest
                frames.append(tex)
            } else {
                break
            }
        }
        #endif
        explosionFrames = frames
    }

    func restart() {
        isPaused = false
        isGamePaused = false
        onPauseChanged?(false)
        enemies.removeAll()
        enemyNodes.forEach { $0.removeFromParent() }
        enemyNodes.removeAll()
        worldNode.removeAllChildren()
        buildMap()
        spawnPlayer()
        spawnEnemies(count: 3)
        onHUDUpdate?(enemies.count, level)
        updateCamera()
    }
}

// MARK: - Helpers & Models used here
fileprivate extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}

