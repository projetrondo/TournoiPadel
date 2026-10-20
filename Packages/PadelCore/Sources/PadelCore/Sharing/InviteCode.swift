import Foundation

/// Code d'invitation à 6 caractères, sans caractères ambigus (pas de 0/O, 1/I/L).
/// 31⁶ ≈ 887 millions de combinaisons ; le code sert aussi d'identifiant de l'enregistrement
/// en ligne, qui n'est jamais listable : il faut connaître le code pour lire le tournoi.
public struct InviteCode: Hashable, Sendable, CustomStringConvertible {
    public static let alphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
    public static let length = 6

    public let value: String

    /// Accepte une saisie libre : espaces, tirets et minuscules sont tolérés.
    /// Renvoie `nil` si la saisie ne peut pas être un code valide.
    public init?(_ input: String) {
        let cleaned = Self.clean(input)
        guard cleaned.count == Self.length, cleaned.allSatisfy(Self.alphabet.contains) else { return nil }
        value = cleaned
    }

    private init(validated: String) {
        value = validated
    }

    public static func random<G: RandomNumberGenerator>(using generator: inout G) -> InviteCode {
        let characters = (0..<length).map { _ in alphabet[Int.random(in: 0..<alphabet.count, using: &generator)] }
        return InviteCode(validated: String(characters))
    }

    public static func random() -> InviteCode {
        var generator = SystemRandomNumberGenerator()
        return random(using: &generator)
    }

    /// Nettoyage pour la saisie en direct : majuscules, caractères autorisés seulement,
    /// longueur maximale. Les caractères ambigus sont convertis (O→0 n'existe pas : O est refusé).
    public static func clean(_ input: String) -> String {
        String(input.uppercased().filter { alphabet.contains($0) }.prefix(length))
    }

    /// Code présenté par groupes de 3 pour la lecture à voix haute : « K7M 2QP ».
    public var formatted: String {
        "\(value.prefix(3)) \(value.suffix(3))"
    }

    public var description: String { value }

    /// Lien d'ouverture directe dans l'application.
    public var appURL: URL {
        URL(string: "padelbuddy://join/\(value)")!
    }

    /// Extrait un code d'un lien `padelbuddy://join/CODE` (ou `…/join?code=CODE`).
    public init?(url: URL) {
        guard url.scheme == "padelbuddy" else { return nil }
        let pathCode = url.pathComponents.last.flatMap { $0 == "/" ? nil : $0 }
        let host = url.host
        let queryCode = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "code" }?.value
        let candidate = host == "join" ? (pathCode ?? queryCode) : nil
        guard let candidate, let code = InviteCode(candidate) else { return nil }
        self = code
    }
}
