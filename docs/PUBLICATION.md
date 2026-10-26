# Publier Padel Buddy (sans Mac)

Ce guide mène du code actuel à l'App Store. Tout se fait depuis un navigateur et un iPhone :
GitHub Actions compile et signe l'application sur ses machines macOS.

> **Ce qui n'a pas encore pu être vérifié** : la signature, l'envoi sur TestFlight et CloudKit
> exigent un compte Apple Developer. Le workflow `testflight.yml` est écrit selon la
> documentation d'Apple, mais il n'a jamais tourné. Attendez-vous à un ou deux ajustements au
> premier essai.

## 1. Coûts

| Élément | Coût |
|---|---|
| Apple Developer Program | **99 €/an**, obligatoire pour TestFlight, l'App Store et CloudKit |
| CloudKit | 0 € : au-delà des quotas, ralentissement et non facturation |
| GitHub Actions | Dépôt privé : environ 200 min macOS/mois incluses (1 build ≈ 8–10 min). Dépôt public : illimité |
| Hébergement de la politique de confidentialité | 0 € (voir § 5) |
| Publicité, abonnement, paiement | Aucun |

## 2. Inscription (une fois)

1. Inscrivez-vous sur [developer.apple.com/programs](https://developer.apple.com/programs/)
   avec votre identifiant Apple. Comptez de 24 à 48 h de validation, parfois plus.
2. Repérez votre **Team ID** (10 caractères) dans Membership details.

## 3. Créer l'application dans App Store Connect

1. Dans Certificates, Identifiers & Profiles › Identifiers, créez l'identifiant
   `com.projetrondo.padelbuddy`. Cochez **iCloud** (avec CloudKit) si vous activez le partage.
2. Dans [App Store Connect](https://appstoreconnect.apple.com) › Apps › **+** :
   - plateforme iOS ;
   - nom « Padel Buddy », ou une variante si ce nom est pris ;
   - langue principale **Français** ;
   - identifiant `com.projetrondo.padelbuddy` ;
   - SKU au choix, par exemple `padelbuddy`.

## 4. Clé d'API et secrets GitHub

1. App Store Connect › Utilisateurs et accès › Intégrations › **Clés d'API App Store
   Connect** : générez une clé avec le rôle **Admin**, nécessaire pour la signature
   automatique dans le cloud. Notez le **Key ID** et l'**Issuer ID**, puis téléchargez
   `AuthKey_XXXX.p8`. Ce téléchargement n'est possible qu'une fois.
2. Encodez la clé, par exemple depuis un terminal en ligne ou un ordinateur :
   `base64 -i AuthKey_XXXX.p8`.
3. Dans GitHub, dépôt › Settings › Secrets and variables › Actions › **New repository
   secret**, créez :

| Secret | Valeur |
|---|---|
| `APPLE_TEAM_ID` | Team ID (10 caractères) |
| `ASC_KEY_ID` | Key ID de la clé d'API |
| `ASC_ISSUER_ID` | Issuer ID |
| `ASC_KEY_P8_BASE64` | Contenu encodé en base64 du fichier `.p8` |

Ces secrets ne sont jamais affichés dans les journaux. Ne les mettez jamais dans le code.

## 5. Politique de confidentialité (obligatoire)

La page est prête : `docs/site/confidentialite.html`. Avant de la publier, complétez la date
et l'**adresse de contact**.

Hébergements gratuits possibles :
- **GitHub Pages** : gratuit pour un dépôt **public**. Pour un dépôt privé, il faut une offre
  payante. Solution simple : un petit dépôt public dédié, par exemple `padelbuddy-site`, qui
  ne contient que cette page.
- Tout autre hébergeur de pages statiques gratuit.

Reportez ensuite l'adresse dans `AppLinks.privacyPolicy`
(`App/Services/Sync/SyncCoordinator.swift`) et dans App Store Connect.

## 6. Envoyer une version sur TestFlight

1. GitHub › onglet **Actions** › **TestFlight** › **Run workflow**. Cochez « partage CloudKit »
   seulement après l'étape 7.
2. Une dizaine de minutes plus tard, la version apparaît dans App Store Connect › TestFlight,
   après un traitement de 5 à 30 min par Apple.
3. Installez l'app **TestFlight** sur votre iPhone, ajoutez-vous comme testeur interne et
   installez Padel Buddy.
4. Pour vos amis, créez un groupe de **testeurs externes** et activez le lien public. La
   première version externe passe une courte vérification d'Apple. Ce lien peut ensuite
   servir de `AppLinks.download` dans les invitations.

## 7. Activer le partage CloudKit

Suivez `docs/PARTAGE.md`, section « Activer le partage » : conteneur iCloud, réglage
`CLOUDKIT_ENABLED`, puis **déploiement du schéma en production**. Testez avec deux iPhone,
dont un sans compte iCloud.

## 8. Fiche App Store et soumission

- Textes, mots-clés et réponses au questionnaire de confidentialité : voir
  `docs/APPSTORE.md`.
- Captures d'écran : prenez-les sur votre iPhone depuis la version TestFlight, ou demandez-moi
  d'ajouter des captures automatiques au format exigé (6,9 pouces).
- Dans la version › Build, sélectionnez la version TestFlight puis **Soumettre pour
  vérification**. Comptez en général de 24 à 48 h.

## 9. Règles Apple à garder en tête

- **SDK minimal** : Apple exige actuellement le SDK iOS 26 (Xcode 26) ou plus récent. Les workflows
  utilisent l'image `macos-26` de GitHub et sélectionnent le Xcode 26+ le plus récent ; à
  mettre à jour quand Apple relèvera de nouveau ce seuil.
- **Chiffrement** : `ITSAppUsesNonExemptEncryption = NO` est déjà déclaré, car l'app n'utilise
  que le chiffrement standard d'iOS.
- **Comptes** : aucun compte n'est créé, donc pas d'obligation de suppression de compte.
- **Contenu partagé** : les tournois partagés ne sont lisibles qu'avec un code, et il n'y a ni
  fil public ni messagerie. Si Apple pose la question, c'est l'argument à donner.
- **Manifeste de confidentialité** : `App/Resources/PrivacyInfo.xcprivacy` (aucun suivi,
  contenu partagé pour le seul fonctionnement de l'app, UserDefaults justifié).
- **Nom** : « Padel Buddy » est peut-être déjà pris sur l'App Store. Vérifiez à l'étape 3 et
  prévoyez une variante (par exemple « Padel Buddy – Americano »).

## 10. Liste de vérification avant soumission

- [ ] Version TestFlight testée sur au moins deux iPhone, dont un petit écran si possible.
- [ ] Tournoi complet joué en Americano et en Mexicano, avec arrêt en plein tour.
- [ ] Mode avion pendant la saisie des scores : rien n'est perdu.
- [ ] Partage testé : code, lien, lecture seule, retrait du partage. Schéma CloudKit déployé
      en production.
- [ ] Taille de texte maximale et VoiceOver vérifiés sur les écrans principaux.
- [ ] Politique de confidentialité en ligne, adresse de contact renseignée.
- [ ] Fiche App Store remplie, captures envoyées, questionnaire de confidentialité complété.
