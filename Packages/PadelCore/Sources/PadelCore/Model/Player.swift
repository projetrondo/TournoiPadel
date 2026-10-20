import Foundation

public struct Player: Codable, Identifiable, Hashable, Sendable {
    public static let levelRange = 1...5

    public let id: UUID
    /// Prénom ou surnom, unique dans un tournoi (sans tenir compte de la casse ni des accents).
    public var name: String
    /// Niveau optionnel de 1 (débutant) à 5 (confirmé), utilisé pour le premier tour Mexicano.
    public var level: Int?

    public init(id: UUID = UUID(), name: String, level: Int? = nil) {
        self.id = id
        self.name = name
        self.level = level
    }

    /// Clé de comparaison des noms : sans espaces superflus, sans casse ni accents.
    public static func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
    }
}
