# Padel Buddy — Phase 1 : architecture et règles métier

> Statut : **validé** (décisions de la section 10 acceptées : CloudKit public + code, pas de
> propositions de score au MVP, option (a) pour les tours non équitables, stockage JSON).
> Pas de Mac : compilation et tests de l'app via GitHub Actions (macOS).

---

## 1. Contraintes d'environnement (à lire en premier)

| Point | Réalité |
|---|---|
| Compilation iOS | Exige **un Mac avec Xcode**. Impossible sous Linux/Windows. |
| Environnement de Claude Code (cette session) | Conteneur Linux **sans toolchain Swift** (téléchargement de swift.org bloqué par la politique réseau). Je ne peux donc **ni compiler ni exécuter les tests ici** en l'état. |
| Solution proposée | Dépôt GitHub + **GitHub Actions sur runner macOS** : chaque push compile l'app et lance les tests. Je lis les résultats via `gh` et corrige. Vous compilez aussi localement sur votre Mac. |
| Coût GitHub Actions | Gratuit et illimité pour un dépôt **public**. Pour un dépôt **privé** (offre Free) : 2 000 min/mois, mais les minutes macOS comptent ×10, soit ~200 min macOS/mois (≈ 25–40 builds). Suffisant si on reste raisonnable. |

Conséquence de méthode : le **moteur de tournoi** (règles, générateurs, classement) sera un
package Swift **pur Foundation**, sans dépendance UI, testable avec `swift test` sur n'importe
quelle plateforme. C'est là que se trouve le risque fonctionnel, il doit être le plus testé.

---

## 2. Comptes, coûts et règles Apple

| Élément | Coût | Remarques |
|---|---|---|
| Apple Developer Program | **99 €/an** (TTC en France) | Obligatoire pour CloudKit, TestFlight et l'App Store. Sans lui : installation sur votre propre iPhone seulement, profil valable 7 jours, **pas de CloudKit**. |
| CloudKit | **0 €** | Apple ne facture plus de dépassement : au-delà des quotas, les requêtes sont **ralenties (throttling)**, pas facturées. Aucun risque de facture surprise. |
| Hébergement page de repli (optionnel) | 0 € | GitHub Pages. |
| Nom de domaine (optionnel) | ~10 €/an | Seulement si on veut des liens universels sur un domaine propre. Pas nécessaire pour le MVP. |

Règles de publication à anticiper (détaillées en phase 7) :
- SDK minimal imposé par Apple (actuellement Xcode 26 / SDK iOS 26 au minimum ; à revérifier au
  moment de la soumission, Apple relève ce seuil chaque printemps).
- **URL de politique de confidentialité obligatoire**, même pour une app sans collecte
  (hébergeable gratuitement sur GitHub Pages).
- Étiquette de confidentialité App Store + fichier `PrivacyInfo.xcprivacy`.
- Pas de création de compte → pas d'obligation de « suppression de compte ».
- Chiffrement : uniquement HTTPS standard → `ITSAppUsesNonExemptEncryption = NO`.
- Schéma CloudKit à **déployer en production** depuis la console CloudKit avant la publication
  (oubli classique : tout marche en développement, rien en production).
- Disponibilité du nom « Padel Buddy » sur l'App Store à vérifier tôt dans App Store Connect.

---

## 3. Décisions techniques proposées

### 3.1 Plateforme

- **iOS 17 minimum**, iPhone uniquement, portrait (paysage non prioritaire).
  iOS 17 apporte `@Observable`, `ShareLink`, `ImageRenderer`, String Catalogs, et couvre la très
  grande majorité du parc actif.
- Swift 6, SwiftUI, aucune dépendance tierce dans l'app.
- Localisation via **String Catalog** (`Localizable.xcstrings`) : français au lancement, anglais
  ajoutable sans toucher au code.

### 3.2 Stockage local — recommandation : fichiers JSON atomiques (plutôt que SwiftData)

Un tournoi est un **agrégat** : on le lit, le modifie et le synchronise toujours en entier
(quelques Ko, même à 16 joueurs × 15 tours). Proposition :

- Un fichier `<uuid>.json` par tournoi dans `Application Support/Tournaments/`.
- Écriture **atomique** (`Data.write(options: .atomic)` = écriture dans un fichier temporaire puis
  renommage) : un crash ou une coupure de batterie ne peut jamais laisser un fichier à moitié écrit.
- Sauvegarde **à chaque action** (validation de score, correction, génération de tour).
- Champ `schemaVersion` dans le JSON pour gérer les migrations futures.
- Le même format sert pour la synchronisation, l'export et les tests de sauvegarde/restauration.

| | JSON atomique | SwiftData |
|---|---|---|
| Fiabilité | Très élevée, mécanisme simple | Bonne, mais plus de « magie » (migrations, contextes, bugs connus selon versions d'iOS) |
| Testabilité | Totale, y compris hors iOS | Nécessite un environnement Apple |
| Cohérence avec la synchro | Identique au format échangé | Conversion modèle ↔ snapshot à maintenir |
| Requêtes complexes | Inutiles ici (quelques dizaines de tournois) | Atout non nécessaire |

La persistance est derrière un protocole `TournamentStore` : passer à SwiftData plus tard reste
possible sans toucher au moteur ni à l'UI.

### 3.3 Synchronisation — recommandation : CloudKit, base **publique**, organisateur unique écrivain

Options étudiées :

| Option | Pour | Contre | Verdict |
|---|---|---|---|
| **CloudKit base publique + code d'invitation** | Gratuit, sans serveur à maintenir, lecture **sans compte iCloud**, droits d'écriture garantis côté serveur (seul le créateur d'un enregistrement peut le modifier) | Pas de temps réel garanti ; données lisibles par quiconque possède le code ; iPhone uniquement | **Recommandé** |
| CloudKit partage (`CKShare`, base privée) | Contrôle d'accès fin, données chiffrées dans l'iCloud de l'organisateur | **SwiftData ne gère pas le partage** (il faut Core Data + `NSPersistentCloudKitContainer`) ; chaque ami doit avoir un compte iCloud et accepter le partage ; flux plus complexe | Trop lourd pour un MVP |
| Firebase / Supabase | Temps réel, multi-plateforme | Compte et facturation hors Apple, risque de coût, données chez un tiers, plus de déclarations de confidentialité | Écarté |
| Multipeer / AirDrop seulement | Fonctionne sans Internet | Pas de suivi à distance, connexions fragiles | Écarté (éventuellement plus tard en complément) |

**Fonctionnement retenu :**

1. Le tournoi est créé et joué **localement** (source de vérité = l'appareil de l'organisateur).
2. « Partager » publie un enregistrement CloudKit `Tournament` dont l'identifiant est dérivé d'un
   **code à 6 caractères** (alphabet sans caractères ambigus : `ABCDEFGHJKMNPQRSTUVWXYZ23456789`,
   ≈ 887 millions de combinaisons). Contenu : le snapshot JSON + `revision` (entier croissant).
3. Les amis entrent le code (ou ouvrent le lien) → l'app **récupère l'enregistrement par son
   identifiant**. Aucun index de recherche n'est créé : on ne peut pas lister les tournois, il faut
   connaître le code.
4. À chaque modification, l'organisateur sauvegarde localement **puis** pousse le snapshot. Hors
   ligne, l'envoi est mis en file d'attente et réessayé (backoff) ; rien n'est perdu localement.
5. Les spectateurs se rafraîchissent par : tirer-pour-rafraîchir, rafraîchissement périodique
   (~20 s, app au premier plan) et notifications silencieuses CloudKit (`CKQuerySubscription`)
   quand elles arrivent. **Délai typique : quelques secondes ; aucune garantie de temps réel.**
   L'UI affiche toujours « Mis à jour il y a X s » et un bandeau hors ligne.
6. Les spectateurs gardent une copie locale : le tournoi reste consultable sans réseau.

**Quotas** : les quotas de la base publique augmentent avec le nombre d'utilisateurs ; un snapshot
de quelques Ko et un rafraîchissement toutes les 20 s par spectateur restent très loin des limites
pour des groupes d'amis. Taille maximale d'un enregistrement : 1 Mo (on en utilise < 1 %).

**Limites assumées et à afficher honnêtement :**
- iPhone/iPad uniquement (pas d'Android ni de web au MVP) → repli : résumé texte/image partageable.
- L'organisateur doit être connecté à iCloud pour publier. Les spectateurs, non.
- Toute personne qui possède le code peut lire le tournoi (prénoms/surnoms et scores). C'est
  annoncé à l'organisateur, qui peut **dépublier** le tournoi à tout moment.

### 3.4 Droits

| Action | Organisateur | Participant (spectateur) |
|---|---|---|
| Créer, configurer, lancer, terminer, supprimer | ✅ | ❌ |
| Saisir / valider / corriger un score officiel | ✅ | ❌ |
| Générer le tour suivant (Mexicano) | ✅ | ❌ |
| Voir matchs, scores, classement, résultats | ✅ | ✅ |
| Proposer un score (option, cf. §10) | — | ✅ (l'organisateur accepte ou refuse) |
| Publier / dépublier, régénérer le code | ✅ | ❌ |

Garantie **côté serveur** : rôle CloudKit par défaut de la base publique (« Creator » seul peut
modifier). Un participant ne peut pas falsifier le tournoi, même avec une app modifiée.

### 3.5 Conflits et hors ligne

- **Un seul écrivain** (l'organisateur) → pas de conflit entre organisateur et participants.
- **Un seul appareil organisateur par tournoi** : le snapshot contient `organizerDeviceID`. Un autre
  appareil du même compte iCloud peut « Reprendre l'organisation » explicitement (confirmation).
- Écriture CloudKit conditionnelle (`ifServerRecordUnchanged`). Si le serveur a une `revision`
  supérieure (cas rare : reprise d'organisation pendant qu'un ancien appareil était hors ligne),
  l'app **ne remplace rien silencieusement** : elle affiche les matchs divergents et demande lequel
  garder.
- Les propositions de score des participants (si retenues) sont des enregistrements séparés : elles
  n'entrent jamais en conflit avec le snapshot officiel.

### 3.6 Invitations et repli si l'app n'est pas installée

Message envoyé via la feuille de partage iOS (WhatsApp, iMessage…) :

```
🎾 Rejoins le tournoi « Padel du jeudi » sur Padel Buddy
Code : K7M2QP
Ouvrir : padelbuddy://join/K7M2QP
Pas encore l'app ? <lien App Store / TestFlight>
```

- MVP : code + schéma d'URL `padelbuddy://` + lien App Store (TestFlight avant publication).
- Amélioration (phase 6, gratuite) : **lien universel** `https://<vous>.github.io/padelbuddy/join?c=K7M2QP`
  avec page web de repli (instructions + bouton App Store + code affiché). Nécessite un site
  GitHub Pages utilisateur (`<vous>.github.io`) pour héberger `apple-app-site-association`.
- Les personnes sans iPhone reçoivent le **résumé texte/image** des résultats.

### 3.7 Confidentialité

- Aucun compte, aucune analytique, aucun SDK tiers, aucune publicité, aucun suivi.
- Données : nom du tournoi, prénoms/surnoms, niveaux optionnels, scores. Rien d'autre.
- Données publiées uniquement sur action explicite « Partager », supprimables (« Dépublier »).
- Suppression locale d'un tournoi = suppression du fichier + dépublication s'il était partagé.

---

## 4. Architecture du projet

```
PadelBuddy/
├── project.yml                 # Définition du projet Xcode (XcodeGen) → génère PadelBuddy.xcodeproj
├── Packages/
│   └── PadelCore/              # Package Swift pur Foundation — testable partout
│       ├── Sources/PadelCore/
│       │   ├── Model/          # Tournament, Player, Round, Match, Score, Settings…
│       │   ├── Rules/          # Validation des scores, contraintes de création
│       │   ├── Scheduling/     # Planificateur de pauses, Americano, Mexicano, RNG seedé
│       │   ├── Standings/      # Calcul du classement, départages
│       │   └── Codec/          # Encodage JSON versionné
│       └── Tests/PadelCoreTests/
├── App/
│   ├── PadelBuddyApp.swift
│   ├── Features/               # Home, CreateTournament, Matches, Standings, Results, Join, Settings
│   ├── Services/               # TournamentStore (JSON), SyncService (CloudKit), ShareService
│   ├── DesignSystem/           # Couleurs, typo, composants (cartes, boutons, saisie score)
│   └── Resources/              # Assets, Localizable.xcstrings, PrivacyInfo.xcprivacy
├── AppTests/                   # Tests du store, des view models
├── .github/workflows/ci.yml    # Build + tests sur macOS
└── docs/
```

Pourquoi **XcodeGen** : un `.xcodeproj` écrit à la main est fragile et illisible en revue ;
`project.yml` est court, versionnable, et je peux le produire de façon fiable sans Xcode.
Sur votre Mac : `brew install xcodegen && xcodegen` (une commande, ~10 s).

Couches :
- **PadelCore** (domaine) : types valeur (`struct`, `Codable`, `Sendable`), fonctions pures.
  Aucune connaissance de SwiftUI, du disque ou du réseau.
- **Services** : persistance, synchro, partage. Protocoles + implémentations, injectables (mocks
  dans les tests).
- **Features** : vues SwiftUI + view models `@Observable` `@MainActor`. Toute modification passe
  par un `TournamentController` unique qui : applique l'opération du domaine → sauvegarde →
  publie (si partagé). Une seule porte d'entrée = pas de chemin qui oublie de sauvegarder.

---

## 5. Modèle de données (domaine)

```swift
struct Tournament: Codable, Identifiable, Sendable {
    var schemaVersion: Int            // 1
    let id: UUID
    var name: String
    var format: Format                // .americano | .mexicano
    var settings: Settings
    var players: [Player]             // ordre d'inscription = ordre de départage final stable
    var rounds: [Round]
    var status: Status                // .draft | .inProgress | .finished
    var seed: UInt64                  // graine du générateur → plannings reproductibles
    var createdAt: Date
    var updatedAt: Date
    var revision: Int                 // +1 à chaque modification
    var sharing: SharingInfo?         // code, organizerDeviceID, dernière publication
}

struct Settings: Codable, Sendable {
    var courts: Int                   // 1…8
    var scoring: ScoringRule
    var plannedRounds: Int            // nombre de tours prévus (Americano et Mexicano)
    var mexicanoFirstRound: FirstRoundMode   // .random | .byLevel
}

enum ScoringRule: Codable, Sendable {
    case fixedTotal(Int)              // Americano classique : A + B = N (16, 24, 32, perso)
    case raceTo(Int)                  // premier à N : max(A,B) = N, l'autre < N
    case free                         // temps limité : scores libres ≥ 0
}

struct Player: Codable, Identifiable, Sendable {
    let id: UUID
    var name: String                  // prénom/surnom, unique dans le tournoi (insensible à la casse)
    var level: Int?                   // 1…5, optionnel, utilisé pour le 1er tour Mexicano
}

struct Round: Codable, Sendable {
    let index: Int                    // 1-based
    var matches: [Match]
    var resting: [Player.ID]          // joueurs en pause
}

struct Match: Codable, Identifiable, Sendable {
    let id: UUID
    let court: Int
    let teamA: Team                   // Team = (Player.ID, Player.ID)
    let teamB: Team
    var score: Score?                 // nil tant que non saisi
    var state: MatchState             // .scheduled | .inProgress | .completed
    var edits: [ScoreEdit]            // historique des validations/corrections (audit)
}
```

Principe clé : **le classement n'est jamais stocké**, il est recalculé à partir des matchs
terminés. Une correction de score met donc automatiquement tout à jour, sans risque d'incohérence.

---

## 6. Règles de création et contraintes

- 4 à 32 joueurs ; 1 à 8 terrains ; noms non vides et uniques.
- Terrains réellement utilisés par tour : `k = min(terrains, ⌊N / 4⌋)`.
  Si l'organisateur déclare plus de terrains que nécessaire, l'app le signale (« 2 terrains
  suffisent pour 9 joueurs »).
- Joueurs en pause par tour : `b = N − 4k`.
- **Équité des pauses** : chacun pause le même nombre de fois si et seulement si
  `R × b` est un multiple de `N`, soit `R` multiple de `N / pgcd(N, b)`.
  L'app propose donc des **nombres de tours équitables** avec une durée estimée :

| Joueurs | Terrains | Pauses/tour | Tours équitables proposés | Matchs par joueur |
|---|---|---|---|---|
| 4 | 1 | 0 | 3 (chacun avec chacun) | 3 |
| 5 | 1 | 1 | 5 | 4 |
| 6 | 1 | 2 | 3 · 6 · 9 | 2 · 4 · 6 |
| 7 | 1 | 3 | 7 | 4 |
| 8 | 2 | 0 | 7 (chacun avec chacun) | 7 |
| 9 | 2 | 1 | 9 | 8 |
| 10 | 2 | 2 | 5 · 10 | 4 · 8 |
| 12 | 3 | 0 | 11 (chacun avec chacun) | 11 |
| 16 | 4 | 0 | 15 (chacun avec chacun) | 15 |

- Si l'organisateur choisit un nombre de tours non équitable : avertissement explicite
  (« Paul jouera 1 match de moins ») — traitement du classement : cf. décision §10.
- Le tournoi ne peut pas démarrer si une contrainte est violée ; le message dit quoi corriger.

### Validation d'un score

| Règle | Score valide |
|---|---|
| `fixedTotal(N)` | `A + B == N`, `A, B ≥ 0`. Égalité possible si N pair (12–12 = nul). Saisie : on tape A, B est calculé. |
| `raceTo(N)` | `max(A, B) == N` et `min(A, B) < N`. |
| `free` | `A, B ≥ 0`, `A + B > 0`, plafond de cohérence 99. |

Un match ne passe à « terminé » qu'avec un score valide.

---

## 7. Algorithmes de génération

Toute génération utilise un **générateur pseudo-aléatoire seedé** (graine stockée) : même entrée
→ même planning. Indispensable pour des tests déterministes et pour le débogage.

Invariants vérifiés après **chaque** génération (fonction `validate(round:)`, également testée) :
1. un joueur apparaît au plus une fois par tour (matchs + pauses = partition exacte des joueurs) ;
2. chaque équipe contient deux joueurs distincts ;
3. numéros de terrain uniques et ≤ terrains disponibles ;
4. le nombre de pauses vaut `b`.
Si un invariant échoue, la génération est rejetée avec une erreur — jamais un match impossible.

### 7.1 Planificateur de pauses (commun)

Pour chaque tour, les `b` joueurs en pause sont choisis parmi ceux qui ont **le moins de pauses**,
puis le plus de matchs joués, puis ceux dont la dernière pause est la plus ancienne, puis tirage
seedé. Pas de pauses consécutives tant qu'une alternative existe. Avec un nombre de tours
équitable, chacun pause exactement `R × b / N` fois.

### 7.2 Americano (planning complet généré au lancement)

Tous les tours sont générés au départ : les joueurs voient tout le programme.

Pour chaque tour, une fois les pauses fixées, il faut découper les `4k` joueurs actifs en `k`
matchs. Fonction de coût (à minimiser) :

```
coût = 100 × Σ (nombre de fois où ces deux joueurs ont déjà été partenaires)²
     +  10 × Σ (nombre de fois où ces deux joueurs se sont déjà affrontés)
     +   1 × déséquilibre de terrains (optionnel)
```

Implémentation retenue (phase 3, `Packages/PadelCore/Sources/PadelCore/Scheduling/`) :

- **Cas parfaits** — 4k joueurs sans pause, ou 4k+1 joueurs avec une pause par tour
  (4, 5, 8, 9, 12, 13, 16, 17, 20…) : **méthode du cercle** (tournoi toutes rondes, avec un
  joueur fictif si le nombre est impair ; le partenaire du joueur fictif est au repos). Sur un
  cycle, chacun est partenaire de chacun **exactement une fois**. Une recherche locale répartit
  ensuite les paires en matchs pour équilibrer les adversaires.
- **Autres cas** et tours au-delà d'un cycle : pauses choisies par `RestSelector`, puis recherche
  locale (échanges de joueurs entre équipes, plusieurs départs aléatoires) qui minimise le coût
  ci-dessus.
- Plusieurs tentatives complètes (3 à 40 selon la taille) avec des sous-graines différentes, la
  moins coûteuse est gardée. Générateur maison (SplitMix64, mélange de Fisher–Yates) pour que la
  même graine donne toujours le même planning, quelle que soit la version de Swift.
- Chaque planning est contrôlé par `ScheduleValidator` avant d'être enregistré.

Résultats vérifiés par les tests : zéro répétition de partenaire sur un cycle complet pour 4, 5,
8, 9, 12, 13, 16, 17 et 20 joueurs ; aucune répétition non plus pour 6, 7, 10 et 11 joueurs tant
que le nombre de matchs par joueur reste inférieur au nombre de partenaires possibles ; écart
d'au plus un match entre joueurs dans tous les cas (grille 4 à 24 joueurs × 1 à 6 terrains).

Quand des répétitions sont inévitables (ex. 6 joueurs sur 9 tours : 6 matchs pour 5 partenaires
possibles), l'app l'indique : « Certains partenaires se retrouveront 2 fois ».

### 7.3 Mexicano (tour par tour)

Tour 1 : aléatoire seedé, ou par niveau (joueurs triés par niveau puis mêmes règles que les tours
suivants).

Le tour `n + 1` n'est généré qu'**une fois tous les matchs du tour `n` validés**, sur action de
l'organisateur.

Stratégie explicite :
1. Calculer le classement de **classement d'appariement** : moyenne de points par match joué
   (pour ne pas pénaliser ceux qui viennent de pauser), puis différence moyenne, puis classement
   précédent, puis ordre d'inscription.
2. Choisir les pauses (§7.1).
3. Trier les actifs selon ce classement et former des **groupes de 4 consécutifs**
   (1–4, 5–8, …). Le groupe 1 va sur le terrain 1.
4. Dans un groupe classé a > b > c > d, trois appariements sont possibles :
   - **a+d contre b+c** (préféré : équipes équilibrées, règle Mexicano standard),
   - a+c contre b+d,
   - a+b contre c+d (dernier recours).
5. Pour limiter les répétitions, on autorise aussi l'**échange d'un joueur à la frontière** de
   deux groupes voisins (4ᵉ et 5ᵉ, etc.). On évalue **toutes** les combinaisons
   (3ᵏ appariements × 2ᵏ⁻¹ échanges : 648 combinaisons pour 4 terrains, ~840 000 pour 8 — on
   bascule vers une recherche locale au-delà de 6 terrains) avec le coût :

```
coût = 1000 × répétitions de partenaire
     +   50 × échange de frontière utilisé
     +   10 × répétitions d'adversaire
     +    2 × appariement non préféré (a+c/b+d = 1, a+b/c+d = 3)
```

Résultat : les joueurs proches au classement jouent ensemble, les équipes sont équilibrées, et un
partenaire ne se répète que si aucune combinaison ne l'évite.

Égalités : les ex aequo sont départagés de façon **déterministe** (critères ci-dessus) — jamais au
hasard d'un tour à l'autre.

Corrections : corriger un score d'un tour passé recalcule le classement mais **ne modifie jamais
un tour déjà généré**. Si aucun score n'a encore été saisi dans le tour en cours, l'app propose
(sans l'imposer) « Régénérer le tour N avec le classement corrigé ».

---

## 8. Classement et départage

Statistiques par joueur : matchs joués, points marqués, points encaissés, différence,
victoires / nuls / défaites, points par match.

Ordre du classement :
1. **Points marqués** (total) ;
2. **Victoires** ;
3. **Différence de points** ;
4. Sinon **ex aequo** : même position affichée (ex. « 3= »). Pour le podium et le « meilleur
   joueur », les ex aequo sont présentés ensemble.

Dans un match de format `fixedTotal`, un 12–12 est un nul (ni victoire ni défaite).
Ces règles sont affichées dans l'app (bouton « ? » sur le classement).

---

## 9. Écrans et saisie (aperçu pour la phase 2/5)

- Accueil : logo, « Créer un tournoi », « Rejoindre un tournoi », tournois en cours, terminés.
- Création en 3 étapes : format & nom → joueurs → terrains/points/tours (avec explications et
  propositions équitables) → récapitulatif → Lancer.
- Matchs : cartes par tour, terrain, équipes, statut, score en gros caractères.
  Saisie : pavé numérique plein écran ; en `fixedTotal`, le score adverse se calcule seul.
  Valider → retour haptique + animation ; le bouton se désactive immédiatement (opération
  idempotente : impossible de valider deux fois). Bandeau « Annuler » pendant 5 s.
  Corriger → confirmation explicite, ancien score conservé dans l'historique.
- Classement : liste lisible au soleil, détail par joueur.
- Résultats : podium, classement final, stats, partage texte + image (`ImageRenderer` +
  `ShareLink`) — aucune API WhatsApp.

Hors MVP (mentionné pour mémoire) : retrait d'un joueur en cours de tournoi, ajout tardif,
Android/web, statistiques multi-tournois.

---

## 10. Décisions à valider avant la phase 2

1. **Synchronisation** : CloudKit base publique + code, organisateur seul écrivain (recommandé) ?
2. **Propositions de score par les participants** : dans le MVP (phase 6) ou plus tard ?
   Recommandation : plus tard — le MVP reste « l'organisateur saisit, tout le monde voit ».
3. **Nombre de tours non équitable** : (a) seules les valeurs équitables sont proposées, une valeur
   libre reste possible avec avertissement et classement inchangé (total des points) ; ou (b) en cas
   d'inégalité, classement à la moyenne de points par match. Recommandation : (a).
4. **Stockage** : JSON atomique (recommandé) plutôt que SwiftData — sauf objection.
5. **Matériel et comptes** : avez-vous un Mac avec Xcode récent ? Un compte Apple Developer
   (99 €/an) — nécessaire dès la phase 6 (CloudKit), pas avant ?
6. **Compilation automatique** : acceptez-vous un dépôt GitHub (public = CI gratuite illimitée,
   privé = ~200 min macOS/mois) pour que je puisse compiler et tester moi-même ?
