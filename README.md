# EAGLE — Own the court. (TournoiPadel)

Application iPhone gratuite pour organiser des tournois de padel **Americano** et **Mexicano**
entre amis : création en quelques secondes, génération des matchs, saisie des scores, classement
individuel en direct. Sans compte, sans publicité, sans abonnement.

> État : **phase 6** — création, moteurs Americano et Mexicano, saisie et correction des scores,
> classement, résultats, partage entre iPhone (CloudKit, **désactivé tant que le compte Apple
> Developer n'existe pas** — voir [`docs/PARTAGE.md`](docs/PARTAGE.md)). Voir [`docs/PHASE1-ARCHITECTURE.md`](docs/PHASE1-ARCHITECTURE.md).

## Fonctionnalités clés

- Americano et Mexicano, 4 à 32 joueurs, 1 à 8 terrains, pauses tournantes équitables.
- Points par match : 16, 21, 24, 32 ou personnalisé ; total fixe, premier à N, ou libre.
- **Tours libres** : on joue jusqu'à la fin du créneau et on **arrête quand on veut**, même en
  plein tour ; le classement final est calculé sur les matchs joués.
- Saisie rapide des scores, corrections tracées, classement en direct, résultats partageables.

## Organisation du dépôt

| Dossier | Contenu |
|---|---|
| `Packages/PadelCore` | Moteur en Swift pur (Foundation seulement) : modèle, règles, planification, persistance. Testable sur macOS **et Linux**. |
| `App` | Application SwiftUI (iOS 17+) : écrans, services, design system, ressources. |
| `AppTests` | Tests de l'application (bibliothèque de tournois, formulaire de création). |
| `project.yml` | Définition du projet Xcode pour [XcodeGen](https://github.com/yonaskolb/XcodeGen). Le `.xcodeproj` est généré, pas versionné. |
| `.github/workflows/ci.yml` | Intégration continue : tests du moteur sous Linux, compilation + tests + captures d'écran de l'app sur macOS. |
| `docs/` | Architecture, règles métier, décisions. |

## Compiler et tester

### Sans Mac : intégration continue GitHub

Chaque `git push` déclenche `.github/workflows/ci.yml` :
1. **Moteur (Linux)** : `swift test` sur `PadelCore`.
2. **Application (macOS)** : génération du projet, compilation, tests sur simulateur iPhone,
   captures d'écran de l'accueil (clair et sombre).

Les résultats sont visibles dans l'onglet **Actions** du dépôt (artefact `ios-build` : rapport,
journal complet, captures). Une copie du rapport est aussi poussée sur la branche `ci-results`.

### Avec un Mac

```bash
brew install xcodegen
xcodegen generate              # crée PadelBuddy.xcodeproj
open PadelBuddy.xcodeproj      # puis ⌘R pour lancer, ⌘U pour les tests
```

### Moteur seul (macOS ou Linux, Swift 6)

```bash
swift test --package-path Packages/PadelCore
```

## Options de lancement (développement)

| Argument | Effet |
|---|---|
| `-ui-testing` | Stockage en mémoire : aucune donnée réelle lue ni écrite. |
| `-demo-data` | Avec `-ui-testing`, charge trois tournois fictifs (brouillon, en cours, terminé). |
| `-demo-open <état>` | Ouvre le premier tournoi `draft`, `inProgress` ou `finished`. |
| `-demo-tab <onglet>` | Onglet affiché : `matches`, `standings`, `results`, `info`. |
| `-demo-score` | Ouvre la saisie du premier match non joué. |

## Sauvegarde locale

Un fichier JSON par tournoi dans `Application Support/Tournaments/`, écrit de façon atomique à
chaque modification et protégé par le chiffrement iOS. Un fichier illisible n'est jamais effacé :
il est déplacé dans `Tournaments/Unreadable/`. Le champ `schemaVersion` permet les migrations.

## Publication

- [`docs/PUBLICATION.md`](docs/PUBLICATION.md) : de l'inscription Apple Developer à l'App Store, sans Mac
  (workflow `TestFlight` lancé depuis l'onglet Actions).
- [`docs/APPSTORE.md`](docs/APPSTORE.md) : textes de la fiche, mots-clés, questionnaire de confidentialité.
- [`docs/site/confidentialite.html`](docs/site/confidentialite.html) : politique de confidentialité à héberger.

## Coûts

- Développement et CI : gratuits (dépôt public ; dépôt privé limité à ~200 min macOS/mois).
- Test sur iPhone (TestFlight) et publication : **Apple Developer Program, 99 €/an**.
- Synchronisation CloudKit (phase 6) : gratuite, ralentie et non facturée au-delà des quotas.
