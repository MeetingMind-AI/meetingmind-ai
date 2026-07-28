#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log_step() {
  printf "[>>] %s\n" "$1"
}

log_ok() {
  printf "[OK] %s\n" "$1"
}

log_warn() {
  printf "[!!] %s\n" "$1"
}

die() {
  printf "[ER] %s\n" "$1" >&2
  exit 1
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    die "Missing required command: $1"
  fi
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
  die "Docker Compose not found (docker compose or docker-compose)"
}

countdown_spinner() {
  local seconds="$1"
  local spin='|/-\\'
  local i=0
  while [ "$seconds" -gt 0 ]; do
    i=$(( (i + 1) % 4 ))
    printf "\r[>>] Waiting %s seconds for Vexa Admin API... %s" "$seconds" "${spin:$i:1}"
    sleep 1
    seconds=$((seconds - 1))
  done
  printf "\r[OK] Vexa Admin API wait complete.           \n"
}

update_env_key() {
  local file_path="$1"
  local key="$2"
  local value="$3"
  if [ ! -f "$file_path" ]; then
    die "Env file not found: $file_path"
  fi
  if grep -q "^${key}=" "$file_path"; then
    sed -i "s|^${key}=.*|${key}=${value}|" "$file_path"
  else
    printf "\n%s=%s\n" "$key" "$value" >> "$file_path"
  fi
}

json_get() {
  local key="$1"
  if command -v python3 >/dev/null 2>&1; then
    python3 -c "import json,sys; data=json.load(sys.stdin); print(data.get('$key',''))"
    return 0
  fi
  sed -n "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p"
}

NON_INTERACTIVE=false

prompt_yes_no() {
  local prompt="$1"
  local default="$2"
  local reply
  if [ "$NON_INTERACTIVE" = "true" ]; then
    return 1 # Default to NO in non-interactive mode for optional features
  fi
  while true; do
    read -r -p "$prompt" reply
    reply="${reply:-$default}"
    case "$reply" in
      y|Y|yes|YES) return 0 ;;
      n|N|no|NO) return 1 ;;
      *) printf "Please answer yes or no.\n" ;;
    esac
  done
}

main() {
  for arg in "$@"; do
    case "$arg" in
      -y|--non-interactive|--yes) NON_INTERACTIVE=true ;;
    esac
  done

  cd "$SCRIPT_DIR"

  log_step "Validating host dependencies"
  require_cmd docker
  require_cmd curl
  detect_compose
  log_ok "Dependencies detected"

  if command -v nvidia-smi >/dev/null 2>&1; then
    if nvidia-smi -q -d PERSISTENCE >/dev/null 2>&1; then
      if nvidia-smi -q -d PERSISTENCE | grep -q "Persistence Mode[[:space:]]*:[[:space:]]*Enabled"; then
        log_ok "NVIDIA persistence mode already enabled"
      else
        if prompt_yes_no "Optimize A2 GPU response times by enabling Persistence Mode? (Requires sudo) [y/N]: " "n"; then
          sudo nvidia-smi -pm 1
          log_ok "NVIDIA persistence mode enabled"
        else
          log_warn "Skipping NVIDIA persistence mode"
        fi
      fi
    fi
  fi

  log_step "Interactive configuration"
  SMTP_PASSWORD=""
  SMTP_FROM=""
  if prompt_yes_no "Configure email alerts? [y/N]: " "n"; then
    read -r -s -p "SMTP_PASSWORD: " SMTP_PASSWORD
    printf "\n"
    read -r -p "SMTP_FROM: " SMTP_FROM
  fi

  log_step "Writing global .env"
  cat > ./.env <<EOF
# Generated MeetingMind Application Context
DATABASE_URL=postgresql://meetingmind:meetingmind@postgres:5432/meetingmind
REDIS_URL=redis://redis:6379/0
VEXA_API_URL=http://host.docker.internal:8056/bots
VEXA_WS_URL=ws://host.docker.internal:8056/ws
OLLAMA_URL=http://ollama:11434/api/generate
OLLAMA_MODEL=hermes3:8b
OLLAMA_FINAL_MODEL=qwen2.5:14b
OLLAMA_TIMEOUT_SECONDS=120
MEM0_ENABLED=true
MEM0_SEARCH_ENABLED=true
MEM0_SAVE_ENABLED=true
MEM0_OLLAMA_URL=http://ollama:11434
MEM0_LLM_MODEL=hermes3:8b
MEM0_EMBED_MODEL=nomic-embed-text
MEM0_QDRANT_URL=http://qdrant:6333

# Generated Security Layer
VEXA_API_KEY=
EOF
  log_ok "Global .env created"

  log_step "Preparing Vexa environment"
  if [ -f "./vexa/deploy/env-example" ]; then
    cp ./vexa/deploy/env-example ./vexa/.env
  elif [ -f "./vexa/env-example" ]; then
    cp ./vexa/env-example ./vexa/.env
  else
    die "Vexa env example not found"
  fi
  log_ok "Vexa .env prepared"

  log_step "Pulling Vexa bot image"
  docker pull vexaai/vexa-bot:latest
  log_ok "Vexa bot image pulled"

  log_step "Starting core services (postgres, redis, qdrant)"
  "${COMPOSE_CMD[@]}" up -d postgres redis qdrant
  log_ok "Core services started"

  log_step "Starting Vexa services"
  "${COMPOSE_CMD[@]}" -f ./vexa/deploy/compose/docker-compose.yml --env-file ./vexa/.env up -d
  log_ok "Vexa services started"
  countdown_spinner 10

  log_step "Provisioning Vexa API key"
  user_response="$(curl -sS -X POST "http://localhost:8057/admin/users" \
    -H "Content-Type: application/json" \
    -H "X-Admin-API-Key: changeme" \
    -d '{"name":"meetingmind","email":"meetingmind@local"}')"
  user_id="$(printf "%s" "$user_response" | json_get "id")"
  if [ -z "$user_id" ]; then
    die "Failed to parse Vexa user id"
  fi

  token_response="$(curl -sS -X POST "http://localhost:8057/admin/users/${user_id}/tokens" \
    -H "Content-Type: application/json" \
    -H "X-Admin-API-Key: changeme" \
    -d '{"scopes":["bot","tx","browser"]}')"
  vexa_token="$(printf "%s" "$token_response" | json_get "token")"
  if [ -z "$vexa_token" ]; then
    die "Failed to parse Vexa token"
  fi
  log_ok "Vexa API key minted"

  log_step "Injecting Vexa API key into env files"
  update_env_key "./.env" "VEXA_API_KEY" "$vexa_token"
  update_env_key "./vexa/.env" "VEXA_API_KEY" "$vexa_token"
  log_ok "Env files updated"

  log_step "Starting full MeetingMind stack"
  "${COMPOSE_CMD[@]}" up -d
  log_ok "MeetingMind stack started"

  log_step "Running database migrations"
  "${COMPOSE_CMD[@]}" exec -T backend alembic revision --autogenerate -m "initial_tables"
  "${COMPOSE_CMD[@]}" exec -T backend alembic upgrade head
  log_ok "Database migrations complete"

  log_step "Pulling Ollama models"
  "${COMPOSE_CMD[@]}" exec -T ollama ollama pull hermes3:8b
  "${COMPOSE_CMD[@]}" exec -T ollama ollama pull qwen2.5:14b
  "${COMPOSE_CMD[@]}" exec -T ollama ollama pull nomic-embed-text
  log_ok "Ollama models pulled"

  log_ok "Setup complete"
}

main "$@"
