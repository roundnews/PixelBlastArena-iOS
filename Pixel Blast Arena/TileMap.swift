import CoreGraphics
import SwiftUI
import SpriteKit

struct GridPoint: Equatable, Hashable {
    var col: Int
    var row: Int
    
    static func +(lhs: GridPoint, rhs: GridPoint) -> GridPoint {
        GridPoint(col: lhs.col + rhs.col, row: lhs.row + rhs.row)
    }
}

enum TileType {
    case empty
    case wall      // solid, indestructible
    case crate     // breakable
}

struct Tile {
    var type: TileType

    var skColor: SKColor {
        switch type {
        case .empty: return SKColor(white: 0.08, alpha: 1.0)
        case .wall: return SKColor(white: 0.25, alpha: 1.0)
        case .crate: return SKColor.brown
        }
    }
}

struct TileMap {
    let cols: Int
    let rows: Int
    let tileSize: CGFloat

    private(set) var tiles: [Tile]
    private var bombs: Set<GridPoint> = []

    init(cols: Int, rows: Int, tileSize: CGFloat) {
        self.cols = cols
        self.rows = rows
        self.tileSize = tileSize
        self.tiles = Array(repeating: Tile(type: .empty), count: cols * rows)
    }

    mutating func generateBasicLayout() {
        // Outer walls
        for c in 0..<cols {
            setTile(type: .wall, at: GridPoint(col: c, row: 0))
            setTile(type: .wall, at: GridPoint(col: c, row: rows - 1))
        }
        for r in 0..<rows {
            setTile(type: .wall, at: GridPoint(col: 0, row: r))
            setTile(type: .wall, at: GridPoint(col: cols - 1, row: r))
        }

        // Internal pillars (every other tile)
        for r in stride(from: 2, to: rows - 2, by: 2) {
            for c in stride(from: 2, to: cols - 2, by: 2) {
                setTile(type: .wall, at: GridPoint(col: c, row: r))
            }
        }

        // Random crates
        for r in 1..<(rows-1) {
            for c in 1..<(cols-1) {
                let gp = GridPoint(col: c, row: r)
                if tileAt(col: c, row: r).type == .empty {
                    // Keep a 4x4 safe area around the player spawn (top-left corner)
                    let inSafeZone = (c <= 4 && r <= 4)
                    if !inSafeZone && Bool.random() {
                        setTile(type: .crate, at: gp)
                    }
                }
            }
        }

        // Ensure starting area is clear (top-left 4x4)
        for r in 1...4 { for c in 1...4 { setTile(type: .empty, at: GridPoint(col: c, row: r)) } }
    }

    func index(col: Int, row: Int) -> Int { row * cols + col }

    func inBounds(col: Int, row: Int) -> Bool {
        col >= 0 && row >= 0 && col < cols && row < rows
    }

    func tileAt(col: Int, row: Int) -> Tile {
        guard inBounds(col: col, row: row) else { return Tile(type: .wall) }
        return tiles[index(col: col, row: row)]
    }

    mutating func setTile(type: TileType, at gp: GridPoint) {
        guard inBounds(col: gp.col, row: gp.row) else { return }
        tiles[index(col: gp.col, row: gp.row)] = Tile(type: type)
    }

    func isWalkable(col: Int, row: Int) -> Bool {
        inBounds(col: col, row: row) && tileAt(col: col, row: row).type == .empty && !bombs.contains(GridPoint(col: col, row: row))
    }
    
    func isWalkableForPlayer(from: GridPoint, to: GridPoint) -> Bool {
        // Allow stepping off a freshly placed bomb: ignore the bomb at the player's current tile
        guard inBounds(col: to.col, row: to.row) else { return false }
        guard tileAt(col: to.col, row: to.row).type == .empty else { return false }
        // Can't step into a bomb
        if bombs.contains(to) { return false }
        return true
    }

    func canPlaceBomb(at gp: GridPoint) -> Bool {
        inBounds(col: gp.col, row: gp.row) && tileAt(col: gp.col, row: gp.row).type == .empty && !bombs.contains(gp)
    }

    mutating func place(bomb: Bomb) {
        bombs.insert(bomb.position)
    }

    mutating func removeBomb(at gp: GridPoint) {
        bombs.remove(gp)
    }
    
    func hasBomb(at gp: GridPoint) -> Bool {
        return bombs.contains(gp)
    }

    func explosionTiles(from origin: GridPoint, range: Int) -> [GridPoint] {
        var result: Set<GridPoint> = [origin]
        let directions = [
            GridPoint(col: 1, row: 0),
            GridPoint(col: -1, row: 0),
            GridPoint(col: 0, row: 1),
            GridPoint(col: 0, row: -1)
        ]
        
        for dir in directions {
            for step in 1...range {
                let pos = GridPoint(col: origin.col + dir.col * step, row: origin.row + dir.row * step)
                if !inBounds(col: pos.col, row: pos.row) { break }
                let tileType = tileAt(col: pos.col, row: pos.row).type
                if tileType == .wall { break }
                result.insert(pos)
                if tileType == .crate { break }
            }
        }
        
        return Array(result)
    }
}
