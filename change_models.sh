#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

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

update_env_key() {
  local file_path="$1"
  local key="$2"
  local value="$3"
  if [ ! -f "$file_path" ]; then
    die "Env file not found: $file_path"
  fi
  if grep -q "^${key}=" "$file_path"; then
    if [[ "$OSTYPE" == "darwin"* ]]; then
      sed -i '' "s|^${key}=.*|${key}=${value}|" "$file_path"
    else
      sed -i "s|^${key}=.*|${key}=${value}|" "$file_path"
    fi
  else
    printf "\n%s=%s\n" "$key" "$value" >> "$file_path"
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
  die "Docker Compose not found"
}

main() {
  detect_compose

  printf "\n=== MeetingMind AI Model Configurator ===\n\n"
  
  echo "Current Local LLM Model (Ollama):"
  grep "^OLLAMA_MODEL=" .env || echo "Not set"
  printf "\n"
  
  echo "Current Whisper Transcription Size:"
  grep "^MODEL_SIZE=" vexa/deploy/transcription/.env || echo "Not set"
  printf "\n"

  read -r -p "Enter new LLM Model name (e.g. hermes3:8b, qwen2.5:7b, or press Enter to skip): " new_llm
  read -r -p "Enter new Whisper Model size (tiny, base, small, medium, large-v3, or press Enter to skip): " new_whisper

  if [ -n "$new_llm" ]; then
    log_step "Updating LLM Model to $new_llm"
    update_env_key "./.env" "OLLAMA_MODEL" "$new_llm"
    update_env_key "./.env" "OLLAMA_FINAL_MODEL" "$new_llm"
    update_env_key "./.env" "MEM0_LLM_MODEL" "$new_llm"
    
    log_step "Restarting backend..."
    "${COMPOSE_CMD[@]}" restart backend
    log_ok "Backend restarted with $new_llm"
  fi

  if [ -n "$new_whisper" ]; then
    log_step "Updating Whisper Model to $new_whisper"
    update_env_key "./vexa/deploy/transcription/.env" "MODEL_SIZE" "$new_whisper"
    
    log_step "Restarting Transcription Service..."
    (cd ./vexa/deploy/transcription && "${COMPOSE_CMD[@]}" -p vexa_stt -f docker-compose.cpu.yml up -d --force-recreate)
    log_ok "Transcription Service restarted with $new_whisper"
  fi

  printf "\n[OK] Configuration complete!\n"
}

main "$@"
