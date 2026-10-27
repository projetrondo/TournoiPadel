#!/bin/sh
# Mise en ligne ou mise à jour de l'API, à lancer sur le serveur depuis le dépôt cloné.
set -eu
cd "$(dirname "$0")"
test -f .env || { echo "infra/.env manquant (modèle : infra/.env.example)"; exit 1; }
set -a; . ./.env; set +a
git pull --ff-only
docker compose --env-file .env up -d --build
docker compose --env-file .env exec -T api php bin/console doctrine:migrations:migrate --no-interaction --allow-no-migration
docker compose --env-file .env exec -T api php bin/console cache:clear
curl -fsS "http://127.0.0.1:${EAGLE_PORT:-8120}/health" && echo " — API en ligne"
