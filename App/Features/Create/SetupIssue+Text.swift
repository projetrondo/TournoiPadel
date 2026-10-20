import PadelCore

extension SetupIssue {
    var message: String {
        switch self {
        case .missingName:
            String(localized: "Donnez un nom au tournoi.")
        case .nameTooLong(let maximum):
            String(localized: "Le nom du tournoi ne doit pas dépasser \(maximum) caractères.")
        case .notEnoughPlayers(let minimum):
            String(localized: "Ajoutez au moins \(minimum) joueurs.")
        case .tooManyPlayers(let maximum):
            String(localized: "\(maximum) joueurs maximum.")
        case .emptyPlayerName:
            String(localized: "Un joueur n'a pas de nom.")
        case .duplicatePlayerNames(let names):
            String(localized: "Noms en double : \(names.formatted(.list(type: .and))). Ajoutez une initiale pour les distinguer.")
        case .invalidCourtCount(let range):
            String(localized: "Le nombre de terrains doit être compris entre \(range.lowerBound) et \(range.upperBound).")
        case .invalidPoints(let range):
            String(localized: "Le nombre de points doit être compris entre \(range.lowerBound) et \(range.upperBound).")
        case .invalidRoundCount(let range):
            String(localized: "Le nombre de tours doit être compris entre \(range.lowerBound) et \(range.upperBound).")
        case .missingLevels:
            String(localized: "Indiquez le niveau de chaque joueur, ou choisissez un premier tour aléatoire.")
        case .unusedCourts(let usable):
            String(localized: "Avec ce nombre de joueurs, seuls \(usable) terrain(s) seront utilisés.")
        case .restingPlayers(let perRound):
            String(localized: "\(perRound) joueur(s) en pause à chaque tour, à tour de rôle.")
        case .unequalMatchCount(let suggestions):
            if suggestions.isEmpty {
                String(localized: "Tout le monde ne jouera pas le même nombre de matchs.")
            } else {
                String(localized: "Tout le monde ne jouera pas le même nombre de matchs. Valeurs équitables proches : \(suggestions.map(String.init).formatted(.list(type: .or))) tours.")
            }
        }
    }

    /// Certains points sont déjà expliqués ailleurs dans le formulaire.
    var isShownInIssueList: Bool {
        switch self {
        case .restingPlayers: false
        default: true
        }
    }
}
