import Foundation

/// The set of powerups that can spawn and be collected by the player.
/// - powerBomb: Bomb blast pierces through crates, destroying those hidden behind others/players/enemies in the blast line.
/// - speedIncrease: Player moves 33% faster than normal.
/// - speedDecrease: Player moves 20% slower than normal.
/// - passThrough: Player can pass through crates. Expires only after the player stands on a non-crate tile once the timer ends.
/// - moreBombs: Permanent; increases max concurrent bombs up to 5. No 15s timer.
enum PowerupType: CaseIterable, Equatable {
    case powerBomb
    case speedIncrease
    case speedDecrease
    case passThrough
    case moreBombs
}
