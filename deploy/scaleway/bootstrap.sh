#!/usr/bin/env bash
#
# Runs ON the Scaleway GPU server (streamed in over SSH by cloud.sh up).
# Idempotent: first run does a full cold start; later runs just bring the
# already-provisioned stack back up fast (models/DB persist on the volume).
#
# Expects these env vars (passed over SSH, never stored in metadata):
#   MM_GH_PAT MM_REPO_URL MM_REPO_BRANCH MM_DATA_LABEL MM_DATA_MOUNT
#   MM_RESEND_API_KEY MM_EMAIL_FROM
#
set -euo pipefail

: "${MM_DATA_LABEL:=MMDATA}"
: "${MM_DATA_MOUNT:=/mnt/data}"
APP_DIR="${MM_DATA_MOUNT}/meetingmind-ai"
MARKER="${MM_DATA_MOUNT}/.provisioned"

log() { printf '\033[1;36m[boot]\033[0m %s\n' "$*"; }

# --- 1. Mount the persistent data volume ------------------------------------
log "Locating persistent data volume..."

# The non-boot disk = the extra block device (our SBS data volume). Retry with
# a bus rescan to tolerate hot-plug latency after attach.
find_data_disk() {
  local root_src root_disk
  root_src="$(findmnt -no SOURCE / 2>/dev/null)"
  root_disk="/dev/$(lsblk -no PKNAME "${root_src}" 2>/dev/null | head -n1)"
  lsblk -dpno NAME,TYPE | awk -v r="${root_disk}" '$2=="disk" && $1!=r {print $1; exit}'
}

if blkid -L "${MM_DATA_LABEL}" >/dev/null 2>&1; then
  DATA_DEV="$(blkid -L "${MM_DATA_LABEL}")"
  log "Found formatted data volume: ${DATA_DEV}"
else
  DATA_DEV=""
  for attempt in $(seq 1 12); do
    DATA_DEV="$(find_data_disk)"
    [ -n "${DATA_DEV}" ] && break
    log "Data disk not visible yet (attempt ${attempt}) — rescanning bus..."
    for h in /sys/class/scsi_host/host*/scan; do echo "- - -" >"$h" 2>/dev/null || true; done
    partprobe >/dev/null 2>&1 || true
    sleep 5
  done
  if [ -z "${DATA_DEV}" ]; then
    echo "No data disk found after waiting. Current block devices:"; lsblk || true
    exit 1
  fi
  log "Formatting fresh data volume ${DATA_DEV} as ext4 (label ${MM_DATA_LABEL})..."
  mkfs.ext4 -F -L "${MM_DATA_LABEL}" "${DATA_DEV}"
fi

mkdir -p "${MM_DATA_MOUNT}"
mountpoint -q "${MM_DATA_MOUNT}" || mount "${DATA_DEV}" "${MM_DATA_MOUNT}"
if ! grep -q "LABEL=${MM_DATA_LABEL}" /etc/fstab; then
  echo "LABEL=${MM_DATA_LABEL} ${MM_DATA_MOUNT} ext4 defaults,nofail 0 2" >>/etc/fstab
fi

# --- 2. Point Docker's data-root at the persistent volume -------------------
# The GPU OS image ships /etc/docker/daemon.json configured with the NVIDIA
# runtime — we must MERGE data-root in, not overwrite it.
DOCKER_DATA="${MM_DATA_MOUNT}/docker"
mkdir -p "${DOCKER_DATA}"
CURRENT_ROOT="$(docker info -f '{{.DockerRootDir}}' 2>/dev/null || echo '')"
if [ "${CURRENT_ROOT}" != "${DOCKER_DATA}" ]; then
  log "Setting Docker data-root -> ${DOCKER_DATA} (preserving NVIDIA runtime config)..."
  systemctl stop docker docker.socket 2>/dev/null || true
  mkdir -p /etc/docker
  if [ -f /etc/docker/daemon.json ]; then
    tmp="$(mktemp)"
    jq --arg dr "${DOCKER_DATA}" '. + {"data-root":$dr}' /etc/docker/daemon.json >"${tmp}" \
      && mv "${tmp}" /etc/docker/daemon.json
  else
    printf '{ "data-root": "%s" }\n' "${DOCKER_DATA}" >/etc/docker/daemon.json
  fi
  systemctl start docker
  log "Docker restarted on persistent data-root."
else
  log "Docker already on persistent data-root."
fi

# --- 3. Clone or update the repo (+ private submodules) ---------------------
# Auth via a global git header for github.com so it also covers the submodule
# clones (backend/frontend/vexa). This lands in /root/.gitconfig on the
# EPHEMERAL boot disk (destroyed on 'down') — never on the persistent volume
# and never in the repo's own git config.
AUTH_HDR="AUTHORIZATION: basic $(printf 'x-access-token:%s' "${MM_GH_PAT}" | base64 -w0)"
git config --global "http.https://github.com/.extraheader" "${AUTH_HDR}"

if [ -d "${APP_DIR}/.git" ]; then
  log "Updating existing checkout..."
  git -C "${APP_DIR}" fetch origin "${MM_REPO_BRANCH}"
  git -C "${APP_DIR}" checkout "${MM_REPO_BRANCH}"
  git -C "${APP_DIR}" reset --hard "origin/${MM_REPO_BRANCH}"
  git -C "${APP_DIR}" submodule update --init --recursive
else
  log "Cloning ${MM_REPO_URL}..."
  git clone --branch "${MM_REPO_BRANCH}" --recurse-submodules "${MM_REPO_URL}" "${APP_DIR}"
fi
cd "${APP_DIR}"

# --- 4. Enable GPU for Ollama via a compose override ------------------------
# COMPOSE_FILE makes every `docker compose` call (setup.sh + Makefile) merge
# the GPU override automatically, without editing the committed compose file.
export COMPOSE_FILE="docker-compose.yml:deploy/scaleway/docker-compose.gpu.yml"

# --- 5. Bring the stack up --------------------------------------------------
if [ -f "${MARKER}" ]; then
  log "Already provisioned — fast restart (docker volumes/models persisted)."
  make up
else
  log "First-time cold start (this pulls ~6GB of models — be patient)..."
  bash ./setup.sh --non-interactive
  touch "${MARKER}"
fi

# --- 6. Forward optional secrets into the app .env --------------------------
set_env() {
  local key="$1" val="$2"
  [ -n "${val}" ] || return 0
  if grep -q "^${key}=" .env 2>/dev/null; then
    sed -i "s|^${key}=.*|${key}=${val}|" .env
  else
    printf '%s=%s\n' "${key}" "${val}" >>.env
  fi
}
set_env RESEND_API_KEY "${MM_RESEND_API_KEY:-}"
set_env EMAIL_FROM "${MM_EMAIL_FROM:-}"
if [ -n "${MM_RESEND_API_KEY:-}" ]; then
  log "Applying email config (restarting backend)..."
  make app-restart 2>/dev/null || docker compose up -d backend
fi

log "Bootstrap complete."
