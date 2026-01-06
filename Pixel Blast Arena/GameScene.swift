import SpriteKit
import SwiftUI

enum PowerupType: CaseIterable, Equatable {
    case powerBomb
    case speedIncrease
    case speedDecrease
    case passThrough
    case moreBombs
}
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
    private var playerNode = SKSpriteNode()

    // Player animation frames
    private var playerRightFrames: [SKTexture] = []
    private var playerUpFrames: [SKTexture] = []
    private var playerDownFrames: [SKTexture] = []
    private var lastDirection: Direction = .down

    private var monsterRightFrames: [SKTexture] = []
    private var monsterUpFrames: [SKTexture] = []
    private var monsterDownFrames: [SKTexture] = []
    private var powerupFrames: [SKTexture] = []

    private var enemyNodes: [SKSpriteNode] = []
    private var powerups: [GridPoint: PowerupType] = [:]
    private var powerupNodes: [GridPoint: SKSpriteNode] = [:]
    private var activePowerup: PowerupType? = nil
    private var pendingPassThroughExpiry: Bool = false
    private var maxConcurrentBombs: Int = 1

    private var currentBombsCount: Int = 0
    // Allow the player to step off a freshly placed bomb for a brief window
    private var escapeBombPosition: GridPoint?
    private var escapeWindowDeadline: CFTimeInterval = 0

    // Portal
    private var portalFrames: [SKTexture] = []
    private var portalNode: SKSpriteNode?
    private var portalGridPosition: GridPoint?
    private var isPortalActive: Bool = false

    var onPauseChanged: ((Bool) -> Void)?
    var onHUDUpdate: ((Int, Int) -> Void)?
    var onGameOver: ((Bool) -> Void)?
    var onPowerupCollected: ((PowerupType) -> Void)?
    var onCheatActivated: (() -> Void)?

    // Timing
    private var lastUpdateTime: TimeInterval = 0

    // Cheat state
    private var isInvincible: Bool = false
    private var cheatBuffer: [Direction] = []
    private let cheatPattern: [Direction] = [.up, .up, .down, .left, .right, .up, .up, .down, .left, .right]

    // Ensure scene setup runs only once per scene instance
    private var didSetup: Bool = false

    // MARK: - Scene lifecycle
    override func didMove(to view: SKView) {
        // Prevent double-initialization if the same scene instance is presented again
        if didSetup {
            // Still update camera reference just in case
            camera = cameraNode
            return
        }
        didSetup = true

        backgroundColor = .black
        tileSize = computedTileSize(for: size)
        loadExplosionFrames()
        loadPlayerFrames()
        loadMonsterFrames()
        loadPortalFrames()
        loadPowerupFrames()

        if worldNode.parent == nil { addChild(worldNode) }
        buildMap()
        spawnPlayer()
        spawnEnemies(count: 3)

        if cameraNode.parent == nil { addChild(cameraNode) }
        camera = cameraNode
        updateCamera()
        onHUDUpdate?(enemies.count, level)
    }

    // MARK: - Map
    private func buildMap() {
        tileMap = TileMap(cols: cols, rows: rows, tileSize: tileSize)
        tileMap.generateBasicLayout()
        renderTiles()
        isPortalActive = false
        placePortalAtLeftBottom()
    }

    private func renderTiles() {
        guard let map = tileMap else { return }
        // Render tiles as colored squares or textures for wall/crate
        for r in 0..<rows {
            for c in 0..<cols {
                let tile = map.tileAt(col: c, row: r)
                // Always create a base colored tile; for crates, use the navigable (empty) tile color behind the texture
                let baseColor: SKColor = (tile.type == .crate) ? Tile(type: .empty).skColor : tile.skColor
                let node = SKSpriteNode(color: baseColor, size: CGSize(width: tileSize, height: tileSize))
                node.position = positionFor(col: c, row: r)
                node.zPosition = 0
                node.name = "tile_\(c)_\(r)"
                worldNode.addChild(node)

                // If this tile is a crate, add a crate overlay texture above the base tile to avoid showing scene background through transparent pixels
                if tile.type == .crate {
                    let tex = SKTexture(imageNamed: "brick")
                    tex.filteringMode = .nearest
                    let overlay = SKSpriteNode(texture: tex, size: CGSize(width: tileSize * 1.8, height: tileSize * 1.8))
                    overlay.position = node.position
                    overlay.zPosition = 1
                    overlay.name = "crateOverlay_\(c)_\(r)"
                    worldNode.addChild(overlay)
                }
            }
        }
    }

    private func refreshTile(at col: Int, row: Int) {
        let baseName = "tile_\(col)_\(row)"
        if let node = worldNode.childNode(withName: baseName) as? SKSpriteNode {
            let tile = tileMap.tileAt(col: col, row: row)
            // Always ensure base colored tile is correct; for crates, use the navigable (empty) tile color behind the texture
            let baseColor: SKColor = (tile.type == .crate) ? Tile(type: .empty).skColor : tile.skColor
            node.texture = nil
            node.color = baseColor
            node.size = CGSize(width: tileSize, height: tileSize)

            // Manage crate overlay separately
            let overlayName = "crateOverlay_\(col)_\(row)"
            if tile.type == .crate {
                if worldNode.childNode(withName: overlayName) == nil {
                    let tex = SKTexture(imageNamed: "brick")
                    tex.filteringMode = .nearest
                    let overlay = SKSpriteNode(texture: tex, size: CGSize(width: tileSize * 1.8, height: tileSize * 1.8))
                    overlay.position = node.position
                    overlay.zPosition = 1
                    overlay.name = overlayName
                    worldNode.addChild(overlay)
                }
            } else {
                if let overlay = worldNode.childNode(withName: overlayName) as? SKSpriteNode {
                    overlay.removeFromParent()
                }
            }
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
        let initialTexture = playerDownFrames.first ?? playerRightFrames.first
        playerNode = SKSpriteNode(texture: initialTexture)
        playerNode.size = CGSize(width: tileSize * 1.4, height: tileSize * 1.4)
        playerNode.position = positionFor(col: player.gridPosition.col, row: player.gridPosition.row)
        playerNode.zPosition = 10
        playerNode.xScale = 1.0
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

        // Record input for cheat detection
        recordCheatInput(direction)

        let target = GridPoint(col: player.gridPosition.col + delta.dc, row: player.gridPosition.row + delta.dr)
        movePlayer(to: target)
    }

    private func recordCheatInput(_ direction: Direction) {
        cheatBuffer.append(direction)
        // Keep only the last N inputs where N is the pattern length
        if cheatBuffer.count > cheatPattern.count {
            cheatBuffer.removeFirst(cheatBuffer.count - cheatPattern.count)
        }
        if cheatBuffer == cheatPattern {
            activateCheatInvincibility()
            cheatBuffer.removeAll()
        }
    }

    private func activateCheatInvincibility() {
        isInvincible = true
        // Force pass-through powerup active and make sure it doesn't auto-expire
        activePowerup = .passThrough
        pendingPassThroughExpiry = false
        onCheatActivated?()
    }

    private func movePlayer(to target: GridPoint) {
        // Primary rule: normal walkability check allowing stepping off a placed bomb
        var canMove = tileMap.isWalkableForPlayer(from: player.gridPosition, to: target)
        if !canMove, (activePowerup == .passThrough || isInvincible) {
            // Allow movement onto crates while pass-through is active (but not walls or bombs)
            if tileMap.inBounds(col: target.col, row: target.row) {
                let t = tileMap.tileAt(col: target.col, row: target.row).type
                if t != .wall && !tileMap.hasBomb(at: target) { canMove = true }
            }
        }
        if !canMove, let escapePos = escapeBombPosition, escapePos == player.gridPosition, CACurrentMediaTime() < escapeWindowDeadline {
            // During the brief escape window, allow moving off the bomb tile as long as destination is empty and not a wall
            let destType = tileMap.tileAt(col: target.col, row: target.row).type
            let destHasBomb = tileMap.hasBomb(at: target)
            if destType == .empty && !destHasBomb { canMove = true }
        }

        guard canMove else { return }

        // Insert capturing previous grid position before update
        let previous = player.gridPosition

        // Update grid state first
        player.gridPosition = target
        escapeBombPosition = nil
        let newPos = positionFor(col: target.col, row: target.row)

        // Apply movement immediately to avoid any action conflicts
        playerNode.removeAction(forKey: "move")
        playerNode.position = newPos

        // Collect powerup if present
        if let type = powerups.removeValue(forKey: target) {
            if let node = powerupNodes.removeValue(forKey: target) { node.removeFromParent() }
            applyPowerup(type)
            onPowerupCollected?(type)
        }
        // If pass-through timer expired earlier, only end effect when standing on a non-crate tile
        if pendingPassThroughExpiry {
            let tileType = tileMap.tileAt(col: player.gridPosition.col, row: player.gridPosition.row).type
            if tileType != .crate {
                activePowerup = nil
                pendingPassThroughExpiry = false
            }
        }
        // Enter active portal: play entry effect then advance level
        if isPortalActive, let pPos = portalGridPosition, player.gridPosition == pPos {
            isPortalActive = false
            if let pNode = portalNode {
                let pulse = SKAction.sequence([
                    SKAction.scale(to: 1.1, duration: 0.12),
                    SKAction.scale(to: 1.0, duration: 0.12)
                ])
                pNode.run(pulse)
            }
            let vanish = SKAction.group([
                SKAction.scale(to: 0.2, duration: 0.25),
                SKAction.fadeOut(withDuration: 0.25)
            ])
            playerNode.run(vanish) { [weak self] in
                self?.nextLevel()
            }
            return
        }

        // Determine direction from delta and animate frames
        let dx = target.col - previous.col
        let dy = target.row - previous.row
        if abs(dx) > 0 || abs(dy) > 0 {
            if abs(dx) > abs(dy) {
                // Horizontal movement
                if dx > 0 {
                    animatePlayer(direction: .right)
                } else {
                    animatePlayer(direction: .left)
                }
            } else {
                // Vertical movement
                if dy > 0 {
                    animatePlayer(direction: .up)
                } else {
                    animatePlayer(direction: .down)
                }
            }
        }

        // Small feedback pulse
        let pulse = SKAction.sequence([
            SKAction.scale(to: 0.96, duration: 0.05),
            SKAction.scale(to: 1.0, duration: 0.05)
        ])
        playerNode.run(pulse, withKey: "move")
    }

    private func animatePlayer(direction: Direction) {
        lastDirection = direction
        playerNode.removeAction(forKey: "walk")

        switch direction {
        case .right:
            playerNode.xScale = 1.0
            if !playerRightFrames.isEmpty {
                let action = SKAction.animate(with: playerRightFrames, timePerFrame: 0.1, resize: false, restore: false)
                playerNode.run(action, withKey: "walk")
                playerNode.texture = playerRightFrames.last
            }
        case .left:
            playerNode.xScale = -1.0
            if !playerRightFrames.isEmpty {
                let action = SKAction.animate(with: playerRightFrames, timePerFrame: 0.1, resize: false, restore: false)
                playerNode.run(action, withKey: "walk")
                playerNode.texture = playerRightFrames.last
            }
        case .up:
            playerNode.xScale = 1.0
            if !playerUpFrames.isEmpty {
                let action = SKAction.animate(with: playerUpFrames, timePerFrame: 0.1, resize: false, restore: false)
                playerNode.run(action, withKey: "walk")
                playerNode.texture = playerUpFrames.last
            }
        case .down:
            playerNode.xScale = 1.0
            if !playerDownFrames.isEmpty {
                let action = SKAction.animate(with: playerDownFrames, timePerFrame: 0.1, resize: false, restore: false)
                playerNode.run(action, withKey: "walk")
                playerNode.texture = playerDownFrames.last
            }
        }
    }

    private func animateEnemy(node: SKSpriteNode, direction: Direction) {
        node.removeAction(forKey: "enemyWalk")
        switch direction {
        case .right:
            node.xScale = 1.0
            if !monsterRightFrames.isEmpty {
                let action = SKAction.animate(with: monsterRightFrames, timePerFrame: 0.12, resize: false, restore: false)
                node.run(action, withKey: "enemyWalk")
                node.texture = monsterRightFrames.last
            }
        case .left:
            node.xScale = -1.0
            if !monsterRightFrames.isEmpty {
                let action = SKAction.animate(with: monsterRightFrames, timePerFrame: 0.12, resize: false, restore: false)
                node.run(action, withKey: "enemyWalk")
                node.texture = monsterRightFrames.last
            }
        case .up:
            node.xScale = 1.0
            if !monsterUpFrames.isEmpty {
                let action = SKAction.animate(with: monsterUpFrames, timePerFrame: 0.12, resize: false, restore: false)
                node.run(action, withKey: "enemyWalk")
                node.texture = monsterUpFrames.last
            }
        case .down:
            node.xScale = 1.0
            if !monsterDownFrames.isEmpty {
                let action = SKAction.animate(with: monsterDownFrames, timePerFrame: 0.12, resize: false, restore: false)
                node.run(action, withKey: "enemyWalk")
                node.texture = monsterDownFrames.last
            }
        }
    }

    // MARK: - Bombs
    func placeBomb() {
        let gp = player.gridPosition
        // Enforce max concurrent bombs
        if currentBombsCount >= maxConcurrentBombs { return }
        let bomb = Bomb(position: gp)
        tileMap.place(bomb: bomb)
        currentBombsCount += 1

        let tex = SKTexture(imageNamed: "bomb")
        tex.filteringMode = .nearest
        let bombNode = SKSpriteNode(texture: tex, size: CGSize(width: tileSize * 1.7, height: tileSize * 1.7))
        bombNode.position = positionFor(col: gp.col, row: gp.row)
        bombNode.zPosition = 5
        bombNode.name = "bomb_\(gp.col)_\(gp.row)"
        worldNode.addChild(bombNode)

        escapeBombPosition = gp
        escapeWindowDeadline = CACurrentMediaTime() + 1.0

        // SFX: bomb placed
        AudioManager.shared.playSFX(named: "bomb-place")

        // Simple countdown animation
        let pulse = SKAction.sequence([
            SKAction.scale(to: 1.1, duration: 0.2),
            SKAction.scale(to: 1.0, duration: 0.2)
        ])
        let countdown = SKAction.repeat(pulse, count: Int(bomb.fuseTime / 0.4))
        bombNode.run(countdown) { [weak self] in
            guard let self = self else { return }
            // If this bomb already exploded via a chain reaction, skip
            if !self.tileMap.hasBomb(at: bomb.position) { return }
            self.explode(bomb: bomb, bombNode: bombNode)
        }
    }

    private func explode(bomb: Bomb, bombNode: SKSpriteNode) {
        bombNode.removeFromParent()
        tileMap.removeBomb(at: bomb.position)
        currentBombsCount = max(0, currentBombsCount - 1)

        // SFX: bomb explode
        AudioManager.shared.playSFX(named: "bomb-explode")

        let affected = tileMap.explosionTiles(from: bomb.position, range: bomb.range)
        // Chain reaction: trigger any bombs caught in the blast immediately
        for gp in affected {
            if tileMap.hasBomb(at: gp) {
                if let chainedNode = worldNode.childNode(withName: "bomb_\(gp.col)_\(gp.row)") as? SKSpriteNode {
                    // Cancel its countdown and detonate shortly for visual chain effect
                    chainedNode.removeAllActions()
                    let chainedBomb = Bomb(position: gp)
                    let delay = SKAction.wait(forDuration: 0.08)
                    chainedNode.run(.sequence([delay, .run { [weak self] in
                        guard let self = self else { return }
                        // Skip if already exploded
                        if !self.tileMap.hasBomb(at: chainedBomb.position) { return }
                        self.explode(bomb: chainedBomb, bombNode: chainedNode)
                    }]))
                } else {
                    // If no node found, ensure state stays consistent
                    tileMap.removeBomb(at: gp)
                    currentBombsCount = max(0, currentBombsCount - 1)
                }
            }
        }
        // Spawn explosion tiles
        for gp in affected {
            // Destroy powerups caught in the blast
            if let node = powerupNodes.removeValue(forKey: gp) {
                node.removeFromParent()
                powerups.removeValue(forKey: gp)
            }
            spawnExplosion(at: gp)
            // Destroy crates
            if tileMap.tileAt(col: gp.col, row: gp.row).type == .crate {
                tileMap.setTile(type: .empty, at: gp)
                refreshTile(at: gp.col, row: gp.row)
                // 33% chance to spawn a powerup on destroyed crate
                if Int.random(in: 0..<3) == 0 {
                    spawnPowerup(at: gp)
                }
            }
        }

        // Damage player (unless invincible)
        if affected.contains(player.gridPosition) && !isInvincible {
            gameOver(youWin: false)
        }

        // Damage enemies
        for (idx, enemy) in enemies.enumerated().reversed() {
            if affected.contains(enemy.gridPosition) {
                if let node = enemyNodes[safe: idx] {
                    node.removeFromParent()
                }
                if enemyNodes.indices.contains(idx) {
                    enemyNodes.remove(at: idx)
                }
                enemies.remove(at: idx)
            }
        }

        onHUDUpdate?(enemies.count, level)

        // Activate portal when all enemies are gone
        if enemies.isEmpty {
            activatePortal()
        }
    }

    private func spawnExplosion(at gp: GridPoint) {
        if !explosionFrames.isEmpty {
            let node = SKSpriteNode(texture: explosionFrames.first)
            node.size = CGSize(width: tileSize, height: tileSize)
            node.position = positionFor(col: gp.col, row: gp.row)
            node.zPosition = 8
            worldNode.addChild(node)

            let animate = SKAction.animate(with: explosionFrames, timePerFrame: 0.06, resize: false, restore: false)
            node.run(.sequence([animate, .removeFromParent()]))
            return
        }

        // Fallback: simple colored tile effect
        let node = SKSpriteNode(color: .yellow, size: CGSize(width: tileSize, height: tileSize))
        node.position = positionFor(col: gp.col, row: gp.row)
        node.zPosition = 8
        worldNode.addChild(node)

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

    private func spawnPowerup(at gp: GridPoint) {
        guard powerups[gp] == nil else { return }
        guard tileMap.inBounds(col: gp.col, row: gp.row) else { return }
        // Choose a random powerup type
        guard let type = PowerupType.allCases.randomElement() else { return }
        powerups[gp] = type

        // Animated powerup using 4-frame ping-pong if available
        var node: SKSpriteNode
        if !powerupFrames.isEmpty {
            node = SKSpriteNode(texture: powerupFrames.first)
            node.size = CGSize(width: tileSize * 1.2, height: tileSize * 1.2)
            let forward = powerupFrames
            let backward = Array(powerupFrames.dropFirst().dropLast().reversed())
            let pingPong = forward + backward
            let anim = SKAction.animate(with: pingPong, timePerFrame: 0.12, resize: false, restore: false)
            node.run(.repeatForever(anim), withKey: "powerupAnim")
        } else {
            let tex = SKTexture(imageNamed: "powerup")
            if tex.size() != .zero {
                tex.filteringMode = .nearest
                node = SKSpriteNode(texture: tex)
                node.size = CGSize(width: tileSize * 1.2, height: tileSize * 1.2)
            } else {
                node = SKSpriteNode(color: .cyan, size: CGSize(width: tileSize * 0.9, height: tileSize * 0.9))
            }
        }
        node.position = positionFor(col: gp.col, row: gp.row)
        node.zPosition = 6
        node.name = "powerup_\(gp.col)_\(gp.row)"
        worldNode.addChild(node)
        powerupNodes[gp] = node
    }

    // MARK: - Enemies
    private func spawnEnemies(count: Int) {
        enemies.removeAll()
        enemyNodes.forEach { $0.removeFromParent() }
        enemyNodes.removeAll()

        var spawned = 0
        var attempts = 0
        let playerStart = GridPoint(col: 1, row: 1)
        let minManhattanDistance = 6
        let bottomSafeMarginRows = 3 // rows 1..3 are considered a safe margin

        while spawned < count && attempts < 400 {
            attempts += 1
            let col = Int.random(in: 3..<(cols-2))
            let row = Int.random(in: 3..<(rows-2))

            // Enforce bottom safe margin: avoid spawning in the bottom N inner rows
            if row <= bottomSafeMarginRows { continue }

            // Enforce minimum Manhattan distance from player start
            let dist = abs(col - playerStart.col) + abs(row - playerStart.row)
            if dist < minManhattanDistance { continue }

            if tileMap.isWalkable(col: col, row: row) {
                var e = Enemy()
                e.gridPosition = GridPoint(col: col, row: row)
                clearNeighborCrates(around: e.gridPosition)
                enemies.append(e)
                let initialTexture = monsterDownFrames.first ?? monsterRightFrames.first
                let node: SKSpriteNode
                if let tex = initialTexture {
                    node = SKSpriteNode(texture: tex)
                    node.size = CGSize(width: tileSize * 1.8, height: tileSize * 1.8)
                    animateEnemy(node: node, direction: .down)
                } else {
                    node = SKSpriteNode(color: .red, size: CGSize(width: tileSize*0.8, height: tileSize*0.8))
                }
                node.position = positionFor(col: col, row: row)
                node.zPosition = 9
                enemyNodes.append(node)
                worldNode.addChild(node)
                spawned += 1
            }
        }
    }

    private func clearNeighborCrates(around gp: GridPoint) {
        let neighbors = [
            GridPoint(col: gp.col + 1, row: gp.row),
            GridPoint(col: gp.col - 1, row: gp.row),
            GridPoint(col: gp.col, row: gp.row + 1),
            GridPoint(col: gp.col, row: gp.row - 1)
        ]
        for n in neighbors {
            if tileMap.inBounds(col: n.col, row: n.row),
               tileMap.tileAt(col: n.col, row: n.row).type == .crate {
                tileMap.setTile(type: .empty, at: n)
                refreshTile(at: n.col, row: n.row)
            }
        }
    }

    private func updateEnemies(deltaTime: TimeInterval) {
        // Random stepping every 0.3s approx
        for (i, var enemy) in enemies.enumerated() {
            enemy.timeSinceLastMove += deltaTime
            var didMoveThisTick = false

            if enemy.timeSinceLastMove > 0.3 {
                enemy.timeSinceLastMove = 0

                // Candidate directions (right, left, up, down as grid deltas)
                let dirs: [GridPoint] = [
                    GridPoint(col: 1, row: 0), GridPoint(col: -1, row: 0),
                    GridPoint(col: 0, row: 1), GridPoint(col: 0, row: -1)
                ]

                // First pass: random order try
                let shuffled = dirs.shuffled()
                for d in shuffled {
                    let target = GridPoint(col: enemy.gridPosition.col + d.col, row: enemy.gridPosition.row + d.row)
                    if tileMap.isWalkable(col: target.col, row: target.row) {
                        let prev = enemy.gridPosition
                        enemy.gridPosition = target
                        didMoveThisTick = true
                        enemy.failedMoveAttempts = 0

                        if let node = enemyNodes[safe: i] {
                            let pos = positionFor(col: target.col, row: target.row)
                            let dx = target.col - prev.col
                            let dy = target.row - prev.row
                            let dir: Direction = (abs(dx) > abs(dy)) ? (dx > 0 ? .right : .left) : (dy > 0 ? .up : .down)
                            animateEnemy(node: node, direction: dir)
                            node.run(SKAction.move(to: pos, duration: 0.16)) {
                                node.position = pos // snap to grid center to avoid drift
                            }
                        }
                        break
                    }
                }

                // Fallback pass: if still stuck after several failures, bias toward open space
                if !didMoveThisTick {
                    enemy.failedMoveAttempts += 1
                    if enemy.failedMoveAttempts >= 5 {
                        // Score each direction by openness up to 3 tiles ahead
                        func opennessScore(for d: GridPoint) -> Int {
                            var score = 0
                            var step = 1
                            while step <= 3 {
                                let c = enemy.gridPosition.col + d.col * step
                                let r = enemy.gridPosition.row + d.row * step
                                if !tileMap.inBounds(col: c, row: r) { break }
                                if tileMap.hasBomb(at: GridPoint(col: c, row: r)) { break }
                                let t = tileMap.tileAt(col: c, row: r).type
                                if t != .empty { break }
                                score += 1
                                step += 1
                            }
                            return score
                        }

                        let scored = dirs.map { (dir: $0, score: opennessScore(for: $0)) }
                            .sorted { $0.score > $1.score }

                        for item in scored {
                            // Skip directions with zero openness to avoid headbutting a wall
                            if item.score == 0 { continue }
                            let target = GridPoint(col: enemy.gridPosition.col + item.dir.col, row: enemy.gridPosition.row + item.dir.row)
                            if tileMap.isWalkable(col: target.col, row: target.row) {
                                let prev = enemy.gridPosition
                                enemy.gridPosition = target
                                didMoveThisTick = true
                                enemy.failedMoveAttempts = 0

                                if let node = enemyNodes[safe: i] {
                                    let pos = positionFor(col: target.col, row: target.row)
                                    let dx = target.col - prev.col
                                    let dy = target.row - prev.row
                                    let dir: Direction = (abs(dx) > abs(dy)) ? (dx > 0 ? .right : .left) : (dy > 0 ? .up : .down)
                                    animateEnemy(node: node, direction: dir)
                                    node.run(SKAction.move(to: pos, duration: 0.16)) {
                                        node.position = pos // snap to grid center to avoid drift
                                    }
                                }
                                break
                            }
                        }
                    }
                }
            }

            if i < enemies.count {
                enemies[i] = enemy
            }
        }

        // Player collision (unless invincible)
        for enemy in enemies {
            if enemy.gridPosition == player.gridPosition {
                if !isInvincible {
                    gameOver(youWin: false)
                }
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
        // Removed the block that creates and adds a game over label as per instructions
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
        playerNode.size = CGSize(width: tileSize * 1.4, height: tileSize * 1.4)
        playerNode.position = positionFor(col: player.gridPosition.col, row: player.gridPosition.row)
        playerNode.zPosition = 10
        worldNode.addChild(playerNode)

        // Re-add powerups
        powerupNodes.removeAll()
        for (gp, _) in powerups {
            let node: SKSpriteNode
            if !powerupFrames.isEmpty {
                node = SKSpriteNode(texture: powerupFrames.first)
                node.size = CGSize(width: tileSize * 1.2, height: tileSize * 1.2)
                let forward = powerupFrames
                let backward = Array(powerupFrames.dropFirst().dropLast().reversed())
                let pingPong = forward + backward
                let anim = SKAction.animate(with: pingPong, timePerFrame: 0.12, resize: false, restore: false)
                node.run(.repeatForever(anim), withKey: "powerupAnim")
            } else {
                let tex = SKTexture(imageNamed: "powerup")
                if tex.size() != .zero {
                    tex.filteringMode = .nearest
                    node = SKSpriteNode(texture: tex)
                    node.size = CGSize(width: tileSize * 1.2, height: tileSize * 1.2)
                } else {
                    node = SKSpriteNode(color: .cyan, size: CGSize(width: tileSize * 0.9, height: tileSize * 0.9))
                }
            }
            node.position = positionFor(col: gp.col, row: gp.row)
            node.zPosition = 6
            node.name = "powerup_\(gp.col)_\(gp.row)"
            worldNode.addChild(node)
            powerupNodes[gp] = node
        }

        // Re-add enemies
        enemyNodes.removeAll()
        for e in enemies {
            let initialTexture = monsterDownFrames.first ?? monsterRightFrames.first
            let node: SKSpriteNode
            if let tex = initialTexture {
                node = SKSpriteNode(texture: tex)
                node.size = CGSize(width: tileSize * 1.8, height: tileSize * 1.8)
            } else {
                node = SKSpriteNode(color: .red, size: CGSize(width: tileSize*0.8, height: tileSize*0.8))
            }
            node.position = positionFor(col: e.gridPosition.col, row: e.gridPosition.row)
            node.zPosition = 9
            enemyNodes.append(node)
            worldNode.addChild(node)
        }

        // Re-add portal
        if let pPos = portalGridPosition {
            let node: SKSpriteNode
            if !portalFrames.isEmpty {
                node = SKSpriteNode(texture: portalFrames.first)
                node.size = CGSize(width: tileSize * 1.8, height: tileSize * 3.0)
            } else {
                let tex = SKTexture(imageNamed: "portal")
                if tex.size() != .zero {
                    tex.filteringMode = .nearest
                    node = SKSpriteNode(texture: tex)
                    node.size = CGSize(width: tileSize * 1.8, height: tileSize * 3.0)
                } else {
                    node = SKSpriteNode(color: .magenta, size: CGSize(width: tileSize, height: tileSize))
                }
            }
            node.position = positionFor(col: pPos.col, row: pPos.row)
            node.zPosition = 7
            portalNode = node
            worldNode.addChild(node)
            updatePortalAppearance()
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

    private func loadPlayerFrames() {
        playerRightFrames.removeAll()
        playerUpFrames.removeAll()
        playerDownFrames.removeAll()

        // Helper to slice a 4-frame horizontal strip with given top/bottom pixel margins
        func sliceFrames(from baseName: String, topMarginPx: CGFloat, bottomMarginPx: CGFloat) -> [SKTexture] {
            var frames: [SKTexture] = []
            #if canImport(UIKit)
            if let img = UIImage(named: baseName) {
                let pixelHeight = img.size.height * img.scale
                let topFrac = max(0, min(1, topMarginPx / pixelHeight))
                let bottomFrac = max(0, min(1, bottomMarginPx / pixelHeight))
                let frameHeight = max(0, 1 - topFrac - bottomFrac)
                let baseTex = SKTexture(imageNamed: baseName)
                baseTex.filteringMode = .nearest
                for i in 0..<4 {
                    let x = CGFloat(i) * 0.25
                    let rect = CGRect(x: x, y: bottomFrac, width: 0.25, height: frameHeight)
                    let tex = SKTexture(rect: rect, in: baseTex)
                    tex.filteringMode = .nearest
                    frames.append(tex)
                }
            }
            #else
            let baseTex = SKTexture(imageNamed: baseName)
            baseTex.filteringMode = .nearest
            for i in 0..<4 {
                let x = CGFloat(i) * 0.25
                let rect = CGRect(x: x, y: 0.0, width: 0.25, height: 1.0)
                let tex = SKTexture(rect: rect, in: baseTex)
                tex.filteringMode = .nearest
                frames.append(tex)
            }
            #endif
            return frames
        }

        // Load right/left frames and up/down frames
        let rightStrip = sliceFrames(from: "left-right", topMarginPx: 300, bottomMarginPx: 200)
        if !rightStrip.isEmpty { playerRightFrames = rightStrip }

        let upDownStrip = sliceFrames(from: "up-down", topMarginPx: 300, bottomMarginPx: 200)
        if upDownStrip.count == 4 {
            playerUpFrames = Array(upDownStrip[0...1])
            playerDownFrames = Array(upDownStrip[2...3])
        }
    }

    private func loadMonsterFrames() {
        monsterRightFrames.removeAll()
        monsterUpFrames.removeAll()
        monsterDownFrames.removeAll()

        func slice4(from baseName: String) -> [SKTexture] {
            var frames: [SKTexture] = []
            let baseTex = SKTexture(imageNamed: baseName)
            if baseTex.size() != .zero {
                baseTex.filteringMode = .nearest
                for i in 0..<4 {
                    let x = CGFloat(i) * 0.25
                    let rect = CGRect(x: x, y: 0.0, width: 0.25, height: 1.0)
                    let tex = SKTexture(rect: rect, in: baseTex)
                    tex.filteringMode = .nearest
                    frames.append(tex)
                }
            }
            return frames
        }

        // Load right/left frames and up/down frames for monsters
        let rightStrip = slice4(from: "monster-left-right")
        if !rightStrip.isEmpty { monsterRightFrames = rightStrip }

        let upDownStrip = slice4(from: "monster-up-down")
        if upDownStrip.count == 4 {
            monsterUpFrames = Array(upDownStrip[0...1])
            monsterDownFrames = Array(upDownStrip[2...3])
        }
    }

    private func loadPortalFrames() {
        portalFrames.removeAll()
        let baseTex = SKTexture(imageNamed: "portal")
        if baseTex.size() != .zero {
            baseTex.filteringMode = .nearest
            var frames: [SKTexture] = []
            for i in 0..<4 {
                let x = CGFloat(i) * 0.25
                let rect = CGRect(x: x, y: 0.0, width: 0.25, height: 1.0)
                let tex = SKTexture(rect: rect, in: baseTex)
                tex.filteringMode = .nearest
                frames.append(tex)
            }
            portalFrames = frames
        }
    }

    private func loadPowerupFrames() {
        powerupFrames.removeAll()
        let baseTex = SKTexture(imageNamed: "powerup")
        if baseTex.size() != .zero {
            baseTex.filteringMode = .nearest
            var frames: [SKTexture] = []
            for i in 0..<4 {
                let x = CGFloat(i) * 0.25
                let rect = CGRect(x: x, y: 0.0, width: 0.25, height: 1.0)
                let tex = SKTexture(rect: rect, in: baseTex)
                tex.filteringMode = .nearest
                frames.append(tex)
            }
            powerupFrames = frames
        }
    }

    private func placePortalAtLeftBottom() {
        // Remove any existing portal node
        if let node = portalNode { node.removeFromParent() }
        portalNode = nil
        portalGridPosition = nil

        guard let map = tileMap else { return }

        // Fixed position: first column (col 1), 4th cell from bottom (row 4)
        let gp = GridPoint(col: 1, row: 4)
        guard map.inBounds(col: gp.col, row: gp.row) else { return }

        // Ensure the portal tile and its immediate below/right/up neighbors are empty and refresh them visually
        tileMap.setTile(type: TileType.empty, at: gp)
        let below = GridPoint(col: gp.col, row: gp.row - 1)
        let right = GridPoint(col: gp.col + 1, row: gp.row)
        let up = GridPoint(col: gp.col, row: gp.row + 1)
        if map.inBounds(col: below.col, row: below.row) { tileMap.setTile(type: TileType.empty, at: below) }
        if map.inBounds(col: right.col, row: right.row) { tileMap.setTile(type: TileType.empty, at: right) }
        if map.inBounds(col: up.col, row: up.row) { tileMap.setTile(type: TileType.empty, at: up) }

        refreshTile(at: gp.col, row: gp.row)
        if map.inBounds(col: below.col, row: below.row) { refreshTile(at: below.col, row: below.row) }
        if map.inBounds(col: right.col, row: right.row) { refreshTile(at: right.col, row: right.row) }
        if map.inBounds(col: up.col, row: up.row) { refreshTile(at: up.col, row: up.row) }

        portalGridPosition = gp

        guard let pPos = portalGridPosition else { return }
        let node: SKSpriteNode
        if !portalFrames.isEmpty {
            node = SKSpriteNode(texture: portalFrames.first)
            node.size = CGSize(width: tileSize * 1.8, height: tileSize * 3.0)
        } else {
            let tex = SKTexture(imageNamed: "portal")
            if tex.size() != .zero {
                tex.filteringMode = .nearest
                node = SKSpriteNode(texture: tex)
                node.size = CGSize(width: tileSize * 1.8, height: tileSize * 3.0)
            } else {
                node = SKSpriteNode(color: SKColor.magenta, size: CGSize(width: tileSize, height: tileSize))
            }
        }
        node.position = positionFor(col: pPos.col, row: pPos.row)
        node.zPosition = 7
        portalNode = node
        worldNode.addChild(node)
        updatePortalAppearance()
    }

    private func updatePortalAppearance() {
        guard let node = portalNode else { return }
        node.removeAction(forKey: "portalAnim")
        if isPortalActive, portalFrames.count >= 4 {
            // Active: cycle through frames 1,2,3 continuously
            let activeFrames = Array(portalFrames.dropFirst())
            let anim = SKAction.animate(with: activeFrames, timePerFrame: 0.15, resize: false, restore: false)
            node.run(.repeatForever(anim), withKey: "portalAnim")
        } else {
            // Inactive: show first frame only
            if let first = portalFrames.first { node.texture = first }
        }
    }

    private func activatePortal() {
        isPortalActive = true
        updatePortalAppearance()
    }

    private func nextLevel() {
        level += 1
        // Keep maxConcurrentBombs as-is; reset current placed bombs handled in restart()
        restart()
    }

    func restart() {
        // Clean up any lingering game-over labels from prior sessions
        self.enumerateChildNodes(withName: "gameOverLabel") { node, _ in
            node.removeFromParent()
        }
        // Defensive: remove any SKLabelNode with typical game-over texts
        for child in self.children {
            if let label = child as? SKLabelNode, let text = label.text?.uppercased(), (text.contains("GAME OVER") || text.contains("YOU WIN")) {
                label.removeFromParent()
            }
        }

        escapeBombPosition = nil
        escapeWindowDeadline = 0
        isPortalActive = false
        portalNode = nil
        portalGridPosition = nil
        currentBombsCount = 0

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

    private func applyPowerup(_ type: PowerupType) {
        switch type {
        case .moreBombs:
            if maxConcurrentBombs < 5 { maxConcurrentBombs += 1 }
            // Do not set activePowerup for permanent effect
        case .passThrough:
            activePowerup = .passThrough
            pendingPassThroughExpiry = false
        case .powerBomb:
            activePowerup = .powerBomb
        case .speedIncrease:
            activePowerup = .speedIncrease
        case .speedDecrease:
            activePowerup = .speedDecrease
        }
    }

    func expireTimedPowerup() {
        // Only timed powerups expire; pass-through defers until player reaches non-crate tile
        switch activePowerup {
        case .some(.passThrough):
            if isInvincible {
                // Do not expire pass-through while invincible cheat is active
                break
            }
            pendingPassThroughExpiry = true
        case .some(.powerBomb), .some(.speedIncrease), .some(.speedDecrease):
            activePowerup = nil
        default:
            break
        }
    }
}

// MARK: - Helpers & Models used here
fileprivate extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}

