# Identité EAGLE — « OWN THE COURT. »

Le numéro 1 du classement est **l'Aigle**. Le statut est calculé à partir du classement réel
(`EagleInsights`, dans `PadelCore`) : il n'est jamais attribué à la main et passe au nouveau
numéro 1 dès qu'un score change le classement.

## Palette

| Rôle | Couleur | Usage |
|---|---|---|
| Noir carbone | `#0B0D10` | Fond de l'application (toujours en mode sombre) |
| Gris foncé | `#171A20` | Cartes |
| Vert électrique | `#C6FF00` | Boutons, actions, éléments interactifs (texte carbone dessus) |
| Blanc | `#F5F7FA` | Texte principal |
| Or champion | `#FFC857` | Réservé à l'Aigle (n°1) et aux éléments prestigieux |
| Argent | `#D6DCE4` | 2ᵉ place |
| Bronze | `#D9945B` | 3ᵉ place |

Contrastes mesurés sur fond carbone : 7,7:1 (bronze) à 18:1 (blanc), tous au-dessus du seuil
WCAG AA (4,5:1).

## Emblème

- `eagle-emblem.svg` : or, fond transparent.
- `eagle-emblem-mono.svg` : monochrome (`currentColor`).
- `eagle-emblem-on-dark.svg` : vert électrique sur tuile carbone.
- Dans l'app : `EagleEmblem` (forme SwiftUI vectorielle, mêmes points que les SVG).
- Icône : `App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png`, générée depuis les
  mêmes points (aperçu : `app-icon-preview.png`).

## Vocabulaire (fonctionnalités réelles uniquement)

| Terme | Où | Donnée utilisée |
|---|---|---|
| L'Aigle | Classement, podium, accueil, partage | Rang 1 du classement |
| Defend your crown | Carte de l'Aigle, profil | Tours consécutifs terminés en tête |
| Hunt the Eagle | Lignes du classement, profil | Écart de points avec l'Aigle |
| Rise above | Flèches ▲▼, profil | Places gagnées ou perdues au dernier tour |
| Hall of Eagles | Accueil | Tournois terminés et leur Aigle |
| Eagle Profile | Fiche joueur | Statistiques du tournoi |

Pas de système de défis : « Hunt the Eagle » désigne seulement l'écart à combler.
