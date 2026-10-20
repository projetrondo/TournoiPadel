# Fiche App Store (brouillon)

Textes prêts à coller dans App Store Connect. Les limites de longueur d'Apple sont indiquées
entre parenthèses.

## Informations générales

| Champ | Valeur |
|---|---|
| Nom (30) | Padel Buddy |
| Sous-titre (30) | Tournois Americano & Mexicano |
| Catégorie principale | Sports |
| Catégorie secondaire | Utilitaires (facultatif) |
| Prix | Gratuit |
| Classification par âge | 4+ (aucun contenu sensible, pas de messagerie, pas de contenu généré visible publiquement) |
| Mots-clés (100) | `padel,tournoi,americano,mexicano,classement,score,amis,club,double,match,terrain,sport` (86 caractères) |

## Texte promotionnel (170)

Organisez votre tournoi de padel en quelques secondes : matchs générés automatiquement, scores au bord du terrain, classement en direct.

## Description (4000)

Padel Buddy organise vos tournois de padel entre amis, sans prise de tête.

AMERICANO ET MEXICANO
• Americano : les partenaires changent à chaque tour, chacun marque les points de son équipe.
• Mexicano : après chaque tour, les joueurs de niveau proche se retrouvent pour des matchs serrés.
• De 4 à 32 joueurs, de 1 à 8 terrains. Pauses tournantes équitables quand le nombre de joueurs ne tombe pas juste.

JOUEZ À VOTRE RYTHME
• Matchs en 16, 21, 24, 32 points ou au choix ; total fixe, premier à N points, ou au temps.
• Tours libres : jouez jusqu'à la fin de votre créneau et arrêtez quand vous voulez. Le classement final est calculé sur les matchs joués.

AU BORD DU TERRAIN
• Saisie du score en deux touches : l'app calcule le score de l'équipe adverse.
• Grands boutons, lisible en plein soleil, utilisable à une main.
• Corrections possibles à tout moment, avec confirmation et historique.
• Fonctionne sans réseau : vos scores sont enregistrés immédiatement sur l'iPhone.

CLASSEMENT ET RÉSULTATS
• Classement individuel mis à jour après chaque match : points, victoires, différence.
• Podium, meilleur joueur et statistiques de chacun.
• Partagez les résultats en image ou en texte sur WhatsApp, Messages et ailleurs.

ENTRE AMIS
• Partagez le tournoi avec un code : vos amis suivent les matchs et le classement sur leur iPhone, sans créer de compte.
• L'organisateur reste seul à valider les scores.

GRATUIT ET RESPECTUEUX
• Sans publicité, sans abonnement, sans compte.
• Aucun suivi publicitaire, aucune mesure d'audience.

## Notes pour la vérification d'Apple

> L'application ne nécessite aucun compte. Pour tester : « Créer un tournoi », ajoutez 4 noms
> ou plus, puis « Créer le tournoi » et « Lancer le tournoi ». Touchez un match pour saisir le
> score. Le partage (menu « … » › « Partager le tournoi ») nécessite d'être connecté à iCloud
> pour publier ; pour rejoindre, saisissez le code dans « Rejoindre un tournoi » sur un autre
> appareil. Les tournois partagés ne sont lisibles qu'avec leur code : il n'y a ni contenu
> public, ni recherche, ni messagerie.

## Questionnaire « Confidentialité de l'app »

Réponses cohérentes avec `App/Resources/PrivacyInfo.xcprivacy` :

- **Collectez-vous des données ?** Oui, uniquement si le partage CloudKit est activé dans la
  version publiée. Sans partage, la réponse serait « Non ».
- **Type** : Contenu de l'utilisateur › **Autre contenu de l'utilisateur** (nom du tournoi,
  prénoms ou surnoms saisis, scores).
- **Finalité** : Fonctionnalité de l'app.
- **Lié à l'identité de l'utilisateur ?** Non. Aucun compte ; l'enregistrement CloudKit
  n'expose au développeur qu'un identifiant iCloud pseudonyme propre à l'app.
- **Utilisé pour le suivi ?** Non.

C'est **à vous**, en tant qu'éditeur, de valider ces réponses : elles engagent votre
responsabilité. En cas de doute sur la case « lié à l'identité », répondre « Oui » est plus
prudent et n'a pas d'autre conséquence que l'affichage de l'étiquette.

## Captures d'écran

Format exigé : iPhone 6,9 pouces (1320 × 2868), ou 6,5 pouces selon les règles en vigueur.
Écrans conseillés, dans l'ordre :
1. Saisie du score.
2. Classement.
3. Liste des matchs.
4. Résultats et podium.
5. Création d'un tournoi.
