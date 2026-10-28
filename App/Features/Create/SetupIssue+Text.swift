import PadelCore

extension SetupIssue {
    var message: String {
        switch self {
        case .missingName:
            String(localized: "Donnez un nom au tournoi.", bundle: .appLanguage)
        case .nameTooLong(let maximum):
            String(localized: "Le nom du tournoi ne doit pas dépasser \(maximum) caractères.", bundle: .appLanguage)
        case .notEnoughPlayers(let minimum):
            String(localized: "Ajoutez au moins \(minimum) joueurs.", bundle: .appLanguage)
        case .tooManyPlayers(let maximum):
            String(localized: "\(maximum) joueurs maximum.", bundle: .appLanguage)
        case .emptyPlayerName:
            String(localized: "Un joueur n'a pas de nom.", bundle: .appLanguage)
        case .duplicatePlayerNames(let names):
            String(localized: "Noms en double : \(names.formatted(.list(type: .and).locale(.appLanguage))). Ajoutez une initiale pour les distinguer.", bundle: .appLanguage)
        case .invalidCourtCount(let range):
            String(localized: "Le nombre de terrains doit être compris entre \(range.lowerBound) et \(range.upperBound).", bundle: .appLanguage)
        case .invalidPoints(let range):
            String(localized: "Le nombre de points doit être compris entre \(range.lowerBound) et \(range.upperBound).", bundle: .appLanguage)
        case .invalidRoundCount(let range):
            String(localized: "Le nombre de tours doit être compris entre \(range.lowerBound) et \(range.upperBound).", bundle: .appLanguage)
        case .missingLevels:
            String(localized: "Indiquez le niveau de chaque joueur, ou choisissez un premier tour aléatoire.", bundle: .appLanguage)
        case .unusedCourts(let usable):
            String(localized: "Avec ce nombre de joueurs, seuls \(usable) terrain(s) seront utilisés.", bundle: .appLanguage)
        case .restingPlayers(let perRound):
            String(localized: "\(perRound) joueur(s) en pause à chaque tour, à tour de rôle.", bundle: .appLanguage)
        case .unequalMatchCount(let suggestions):
            if suggestions.isEmpty {
                String(localized: "Tout le monde ne jouera pas le même nombre de matchs.", bundle: .appLanguage)
            } else {
                String(localized: "Tout le monde ne jouera pas le même nombre de matchs. Valeurs équitables proches : \(suggestions.map(String.init).formatted(.list(type: .or))) tours.", bundle: .appLanguage)
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
