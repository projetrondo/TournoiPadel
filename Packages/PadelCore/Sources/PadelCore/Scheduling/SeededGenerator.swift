import Foundation

/// Générateur pseudo-aléatoire déterministe (SplitMix64).
/// Le mélange et le tirage sont implémentés ici plutôt que via la bibliothèque standard,
/// dont l'algorithme peut changer d'une version de Swift à l'autre : une même graine donne
/// toujours le même planning.
public struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Entier uniforme dans `0..<upperBound` (upperBound > 0).
    public mutating func nextInt(below upperBound: Int) -> Int {
        precondition(upperBound > 0)
        return Int(next() % UInt64(upperBound))
    }

    /// Mélange de Fisher–Yates.
    public mutating func shuffle<T>(_ array: inout [T]) {
        guard array.count > 1 else { return }
        for i in stride(from: array.count - 1, to: 0, by: -1) {
            array.swapAt(i, nextInt(below: i + 1))
        }
    }

    public mutating func shuffled<T>(_ array: [T]) -> [T] {
        var copy = array
        shuffle(&copy)
        return copy
    }

    /// Générateur dérivé d'une graine et d'un « sel » (ex. numéro de tour), sans corrélation
    /// entre sels voisins : la graine combinée passe deux fois par la fonction de mélange.
    public static func derived(seed: UInt64, salt: UInt64) -> SeededGenerator {
        var mixer = SeededGenerator(seed: seed ^ (salt &* 0xBF58_476D_1CE4_E5B9))
        _ = mixer.next()
        return SeededGenerator(seed: mixer.next())
    }

    /// Nouvelle graine dérivée, pour des sous-générations indépendantes.
    public mutating func fork() -> SeededGenerator {
        SeededGenerator(seed: next())
    }
}
