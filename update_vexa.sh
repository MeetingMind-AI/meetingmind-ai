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

  log_step "Cleaning up unused Vexa components (agent-api, terminal, dashboard)..."
  rm -rf ./vexa/core/agent
  rm -rf ./vexa/clients/terminal
  rm -rf ./vexa/clients/dashboard
  
  # Run the compose cleaner script
  python3 clean_vexa.py
  
  log_ok "Unused components removed and compose cleaned"

  log_step "Pulling Vexa bot image..."
  if [ -f "./vexa/.env" ]; then
    VEXA_IMAGE_TAG=$(grep "^IMAGE_TAG=" ./vexa/.env | cut -d'=' -f2 || echo "latest")
  else
    VEXA_IMAGE_TAG="latest"
  fi
  docker pull vexaai/vexa-bot:${VEXA_IMAGE_TAG:-latest}
  log_ok "Vexa bot image pulled"

  if [ -f "./vexa/.env" ]; then
    log_step "Restarting Vexa services..."
    "${COMPOSE_CMD[@]}" -p vexa-v012 -f ./vexa/deploy/compose/docker-compose.yml -f ./vexa.override.yml --env-file ./vexa/.env pull
    "${COMPOSE_CMD[@]}" -p vexa-v012 -f ./vexa/deploy/compose/docker-compose.yml -f ./vexa.override.yml --env-file ./vexa/.env up -d --remove-orphans
    log_ok "Vexa services restarted"

    if [ -f "./vexa/deploy/transcription/.env" ]; then
      log_step "Restarting Transcription Service..."
      (cd ./vexa/deploy/transcription && "${COMPOSE_CMD[@]}" -p vexa_stt -f docker-compose.cpu.yml up -d --remove-orphans)
      log_ok "Transcription Service restarted"
    fi
  else
    log_step "Vexa .env not found. Ensure you have run setup.sh first."
  fi

  log_ok "Update complete!"
}

main "$@"
