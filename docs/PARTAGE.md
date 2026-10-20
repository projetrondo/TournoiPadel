# Partage entre iPhone (phase 6)

## En bref

- L'organisateur **publie** son tournoi et reçoit un **code à 6 caractères** (ex. `K7M 2QP`).
- Il envoie l'invitation par la feuille de partage iOS (WhatsApp, iMessage, etc.).
- Les amis ouvrent le lien `padelbuddy://join/K7M2QP` ou saisissent le code dans
  « Rejoindre un tournoi ». Ils suivent les matchs, les scores et le classement en **lecture seule**.
- L'organisateur reste **le seul à saisir et valider les scores**.

## Droits

| Action | Organisateur | Spectateur |
|---|---|---|
| Créer, lancer, terminer, supprimer | ✅ | ❌ |
| Saisir, valider, corriger un score | ✅ | ❌ |
| Générer / recomposer un tour Mexicano | ✅ | ❌ |
| Publier, envoyer l'invitation, retirer du partage | ✅ | ❌ |
| Voir les matchs, les scores, le classement, les résultats | ✅ | ✅ |
| Ne plus suivre (retirer sa copie locale) | — | ✅ |

Garanties :
- **Dans l'app** : une copie de spectateur refuse toute modification (`SyncError.readOnly`).
- **Côté serveur** : dans la base publique CloudKit, seul le créateur d'un enregistrement peut
  le modifier (rôle « Creator » par défaut). Une app modifiée ne peut donc pas falsifier un
  tournoi.

## Fonctionnement technique

- **Service** : CloudKit, **base publique** du conteneur `iCloud.com.projetrondo.padelbuddy`.
- **Données** : un enregistrement `SharedTournament` par tournoi, d'identifiant `T_<code>`.
  Il contient `payload` (le tournoi complet en JSON, quelques Ko), `revision`,
  `organizerDeviceID` et `schemaVersion`.
- **Lecture par identifiant uniquement** : aucune requête ni index de recherche, donc impossible
  de lister les tournois. Il faut connaître le code.
- **Ordre des opérations** : chaque modification est enregistrée sur l'iPhone, **puis** envoyée
  en ligne, avec un regroupement de 1,5 s. Si l'envoi échoue, le score reste sur l'iPhone et
  l'app retente automatiquement :
  - à intervalles croissants (2 s, 4 s, 8 s… au plus 2 min) ;
  - au retour du réseau ;
  - au retour de l'app au premier plan.
- **Spectateurs** :
  - rafraîchissement toutes les ~20 s quand l'écran du tournoi est affiché, ou en tirant vers
    le bas ;
  - la copie locale reste consultable hors ligne ;
  - **pas de temps réel garanti** : l'app affiche « Mis à jour il y a … ».

## Conflits et hors ligne

| Situation | Comportement |
|---|---|
| Organisateur hors ligne | Les scores sont enregistrés sur l'iPhone. L'état « en attente d'envoi » est affiché, l'envoi part au retour du réseau. |
| Spectateur hors ligne | La dernière version reçue reste affichée, avec l'heure de mise à jour. |
| Version reçue plus ancienne que la copie locale | Ignorée : on ne revient jamais en arrière. |
| Version en ligne plus récente publiée depuis un **autre appareil** | Rien n'est écrasé. L'état « conflit » est affiché à l'organisateur. |
| Tournoi retiré du partage | Le spectateur garde la dernière version, avec la mention « retiré du partage ». |
| Code déjà pris (très improbable) | Un nouveau code est tiré automatiquement. |

Choix du MVP : **un seul appareil organisateur par tournoi**. Il n'y a pas de fusion
automatique entre deux appareils organisateurs, et c'est volontaire.

## Personnes qui n'ont pas l'app

- **Lien direct** : le message d'invitation contient le code et le lien `padelbuddy://`, qui
  ouvre l'app si elle est installée. Selon l'application de messagerie, ce type de lien
  n'est pas toujours cliquable : le code reste lisible.
- **Lien de téléchargement** : tant que l'app n'est pas sur l'App Store ou TestFlight,
  `AppLinks.download` est vide. Le message invite alors à demander le lien à l'organisateur.
  À renseigner dans `App/Services/Sync/SyncCoordinator.swift` dès qu'il existe.
- **Sans iPhone** (Android, etc.) : ces personnes reçoivent le **résumé des résultats** en
  texte ou en image (onglet Résultats).
- **Amélioration possible, gratuite** : un lien universel `https://<compte>.github.io/...` avec
  une page web de repli (bouton de téléchargement et code affiché).

## Coûts et limites

- CloudKit : **gratuit**. Au-delà des quotas, Apple ralentit les requêtes au lieu de les
  facturer.
- Les quotas de la base publique augmentent avec le nombre d'utilisateurs. Un tournoi pèse
  quelques Ko (limite : 1 Mo par enregistrement), ce qui reste très loin des limites pour des
  groupes d'amis.
- Nécessite l'**Apple Developer Program (99 €/an)**.

## État actuel : partage désactivé

Sans compte Apple Developer, CloudKit est **désactivé** (`CLOUDKIT_ENABLED: "NO"` dans
`project.yml`). L'app :
- fonctionne entièrement en local ;
- explique que le partage arrive dans la version publiée ;
- n'appelle jamais CloudKit. Un appel sans autorisation iCloud ferait planter l'app.

Ce qui est testé :
- **Moteur** (`PadelCore`, sous Linux et macOS) : codes d'invitation, règles de
  synchronisation, ordre des révisions, conflits, rétrocompatibilité des fichiers.
- **Application** (simulateur, CI) : partage, rejoindre, suivi des scores, lecture seule,
  file d'attente hors ligne, conflit, retrait du partage, avec un **serveur simulé en mémoire**
  (`InMemorySyncService`).
- **Pas encore testé contre les vrais serveurs CloudKit** : c'est impossible sans compte.

## Activer le partage (une fois le compte Apple Developer actif)

1. Sur [developer.apple.com](https://developer.apple.com) › Certificates, Identifiers & Profiles :
   - créer l'identifiant d'app `com.projetrondo.padelbuddy` avec la capacité **iCloud
     (CloudKit)** ;
   - créer le conteneur `iCloud.com.projetrondo.padelbuddy` et l'associer à l'app.
2. Dans `project.yml` :
   - passer `CLOUDKIT_ENABLED` à `"YES"` ;
   - renseigner `DEVELOPMENT_TEAM` (identifiant d'équipe à 10 caractères).
3. Lancer l'app une première fois en développement (TestFlight ou appareil de test) et publier
   un tournoi : CloudKit crée alors le type `SharedTournament` dans l'environnement de
   développement.
4. Dans la [console CloudKit](https://icloud.developer.apple.com) :
   - vérifier les champs : `payload` (Bytes), `revision` (Int64), `organizerDeviceID`
     (String), `schemaVersion` (Int64) ;
   - **ne créer aucun index « Queryable » ou « Searchable »** ;
   - vérifier les rôles de sécurité de `SharedTournament` : _World = Read,
     _Icloud = Create, _Creator = Write ;
   - **Deploy Schema Changes** vers la production. Sans cette étape, le partage ne marchera
     pas dans la version App Store.
5. Tester avec deux iPhone, dont un sans compte iCloud, qui doit pouvoir suivre le tournoi.
