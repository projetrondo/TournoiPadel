# Comptes et sauvegarde en ligne

Le compte est **facultatif**. Sans compte, l'app fonctionne exactement comme avant, en local. Une fois connecté (Google ou Apple), les sessions, joueurs et tournois sont sauvegardés et retrouvés sur un autre iPhone.

Même principe que Rondo : une API à nous (Symfony + PostgreSQL), sur le même serveur. Google passe par le serveur, et le secret Google ne quitte jamais le serveur. Apple impose d'ajouter « Se connecter avec Apple » dès qu'une app propose Google (règle 4.8 de l'App Store). L'App Store exige aussi la suppression du compte depuis l'app : elle est prévue.

## Ce qu'il y a dans le dépôt

| Élément | Où |
| --- | --- |
| API (comptes, connexion Google et Apple, sauvegarde) | `server/` |
| Mise en ligne (Docker : nginx + PHP-FPM + PostgreSQL) | `server/infra/` |
| Écran « Mon compte », sauvegarde automatique | `App/Features/Account/`, `App/Services/Account/` |
| Règles de fusion (testées) | `Packages/PadelCore/Sources/PadelCore/Sharing/BackupRules.swift` |

Tant que l'adresse de l'API n'est pas renseignée à la compilation, l'entrée « Compte » n'apparaît pas dans l'app.

## Mise en route : 6 étapes

### 1. Un nom de domaine pour l'API

Créez un sous-domaine qui pointe sur le serveur de Rondo, par exemple `api.eagle-padel.fr` (enregistrement DNS A ou CNAME). Remplacez ce nom partout ci-dessous par le vôtre.

### 2. Google Cloud Console (gratuit)

1. https://console.cloud.google.com → créez un projet « EAGLE », ou réutilisez celui de Rondo.
2. **API et services → Écran de consentement OAuth** : type « Externe », nom « EAGLE », adresse de contact. Gardez seulement les portées `openid`, `email`, `profile`. Publiez l'application : sans publication, seuls les comptes de test peuvent se connecter.
3. **Identifiants → Créer des identifiants → ID client OAuth** :
   - type : **Application Web** (et non iOS : c'est le serveur qui échange le code) ;
   - URI de redirection autorisée : `https://api.eagle-padel.fr/auth/google/callback`.
4. Notez l'**ID client** et le **secret client**. Ils vont dans `server/infra/.env`, sur le serveur seulement, jamais dans l'app ni sur GitHub.

### 3. Apple Developer : « Se connecter avec Apple »

1. https://developer.apple.com/account → **Certificates, Identifiers & Profiles → Identifiers**.
2. Ouvrez `com.projetrondo.padelbuddy`, cochez **Sign In with Apple** (« Enable as a primary App ID »), puis **Save**.

Rien d'autre à faire côté Apple : le serveur vérifie lui-même les jetons d'Apple avec ses clés publiques.

### 4. Mettre l'API en ligne sur le serveur

Sur le serveur, en SSH :

```sh
git clone https://github.com/projetrondo/TournoiPadel.git eagle && cd eagle/server/infra
cp .env.example .env
nano .env        # remplir (voir ci-dessous)
./deploy.sh      # construit, démarre, crée les tables, vérifie /health
```

Dans `.env` :

- `PUBLIC_URL=https://api.eagle-padel.fr` ;
- `APP_SECRET`, `TOKEN_SECRET`, `POSTGRES_PASSWORD` : trois valeurs différentes, générées chacune avec `openssl rand -hex 32` ;
- `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET` : étape 2 ;
- `EAGLE_PORT=8120` : changez-le si ce port est déjà pris sur la machine.

Ensuite, Apache (comme pour Rondo) : copiez `server/infra/apache-eagle.conf` dans `/etc/apache2/sites-available/`, activez-le (`a2ensite apache-eagle`), puis obtenez le certificat avec `certbot --apache -d api.eagle-padel.fr`.

Vérification : `https://api.eagle-padel.fr/health` doit répondre `{"status":"ok"}`, et `https://api.eagle-padel.fr/auth/providers` doit répondre `{"google":true,"apple":true}`.

Pour les mises à jour suivantes, relancez `./deploy.sh`.

### 5. Envoyer sur TestFlight avec les comptes activés

GitHub → **Actions → TestFlight → Run workflow**. Dans le champ **api_url**, saisissez `https://api.eagle-padel.fr`, puis lancez.

Le bouton « Compte » apparaît alors en haut à gauche de l'accueil.

Si l'envoi échoue avec un message sur « Sign in with Apple » ou « provisioning profile », vérifiez l'étape 3, puis relancez.

### 6. Tester

1. Ouvrez l'app, touchez le bouton « Compte », puis « Continuer avec Google » ou « Continuer avec Apple ».
2. Créez une session et un tournoi.
3. Sur un autre iPhone (ou après réinstallation), connectez-vous au même compte : la session et le tournoi apparaissent.

## Comment fonctionne la sauvegarde

- Chaque modification est envoyée au serveur deux secondes après la dernière saisie, et au retour dans l'app.
- Une version n'en remplace jamais une plus récente. Si deux iPhone modifient la même version hors ligne, c'est la dernière modification qui l'emporte.
- Hors ligne, rien n'est perdu : la sauvegarde reprend au retour du réseau.
- Une suppression faite sur un iPhone est appliquée aux autres.
- Les tournois suivis en lecture seule (partagés par un ami) ne sont pas sauvegardés : ils appartiennent à leur organisateur.
- **Se déconnecter** arrête la sauvegarde ; les données restent sur l'iPhone.
- **Supprimer mon compte** efface le compte et toute la sauvegarde en ligne ; les données restent sur l'iPhone.

## Sécurité

- Jetons d'accès de 15 minutes, signés par le serveur, et jetons de renouvellement de 90 jours, à usage unique. Sur l'iPhone, ils sont rangés dans le **trousseau**.
- Google : l'échange du code se fait de serveur à serveur. Le retour vers l'app utilise un code de passage à usage unique, valable 2 minutes et lié à un secret que seul l'iPhone qui a commencé la connexion possède (PKCE). Une autre app ne peut donc pas l'utiliser.
- Apple : le serveur vérifie la signature, l'application destinataire, l'échéance et le nonce de chaque jeton.
- Un compte ne voit que ses propres documents. Les tentatives de connexion sont limitées à 30 par adresse IP toutes les 10 minutes.
- Pages à mettre à jour avant publication : la politique de confidentialité (`docs/site/confidentialite.html`, déjà complétée) et, dans App Store Connect, la rubrique **Confidentialité de l'app**. Y déclarer : identifiant de l'utilisateur, nom, adresse e-mail et autre contenu (tournois), tous **liés à l'utilisateur**, pour le **fonctionnement de l'app**, sans suivi publicitaire.

## API (référence rapide)

| Méthode | Adresse | Rôle |
| --- | --- | --- |
| GET | `/auth/providers` | Modes de connexion disponibles |
| POST | `/auth/google/start` `{codeChallenge}` | Adresse Google à ouvrir |
| GET | `/auth/google/callback` | Retour de Google, puis redirection vers `eagle://auth?handoff=…` |
| POST | `/auth/google/redeem` `{handoff, codeVerifier}` | Jetons et compte |
| POST | `/auth/apple` `{identityToken, nonce, name?}` | Jetons et compte |
| POST | `/auth/refresh` `{refreshToken}` · `/auth/logout` | Renouvellement, déconnexion |
| GET / DELETE | `/api/me` | Compte ; suppression du compte |
| GET | `/api/sync?since=N` | Changements depuis le curseur N |
| PUT | `/api/documents/{session\|tournament}/{id}` `{revision, payload}` | Envoi : 200, ou 409 avec la version du serveur |
| DELETE | `/api/documents/{kind}/{id}?revision=N` | Suppression (une trace est conservée pour les autres appareils) |

Tests de l'API : `cd server && composer install && vendor/bin/phpunit`. Ils demandent un PostgreSQL local ; la CI GitHub les lance automatiquement.
