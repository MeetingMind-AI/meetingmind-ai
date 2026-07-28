#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log_step() {
  printf "[>>] %s\n" "$1"
}

log_ok() {
  printf "[OK] %s\n" "$1"
}

die() {
  printf "[ER] %s\n" "$1" >&2
  exit 1
}

detect_compose() {
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    COMPOSE_CMD=(docker compose)
    return 0
  fi
  if command -v docker-compose >/dev/null 2>&1; then
    COMPOSE_CMD=(docker-compose)
    return 0
  fi
  die "Docker Compose not found"
}

main() {
  cd "$SCRIPT_DIR"
  detect_compose

  log_step "Updating Vexa submodule..."
  git submodule update --remote vexa
  log_ok "Vexa submodule updated"

  log_step "Pulling latest Vexa bot image..."
  docker pull vexaai/vexa-bot:latest
  log_ok "Vexa bot image pulled"

  if [ -f "./vexa/.env" ]; then
    log_step "Restarting Vexa services..."
    "${COMPOSE_CMD[@]}" -f ./vexa/deploy/compose/docker-compose.yml --env-file ./vexa/.env pull
    "${COMPOSE_CMD[@]}" -f ./vexa/deploy/compose/docker-compose.yml --env-file ./vexa/.env up -d
    log_ok "Vexa services restarted"
  else
    log_step "Vexa .env not found. Ensure you have run setup.sh first."
  fi

  log_ok "Update complete!"
}

main "$@"
