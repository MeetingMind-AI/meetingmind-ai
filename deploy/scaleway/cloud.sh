#!/usr/bin/env bash
#
# MeetingMind AI — Scaleway on-demand GPU lifecycle.
#
#   up      Create the GPU server, attach the persistent data volume,
#           and bring the whole stack online. Prints the public IP + URLs.
#   down    Stop the server, DETACH (keep) the persistent data volume, then
#           delete the server + its boot volume + its public IP. You pay €0
#           while it is down (only the small persistent volume remains).
#   status  Show whether the server exists, its IP, and the data volume.
#
# Everything is keyed off names in config.env, so up/down are idempotent and
# survive across cycles. The persistent data volume is NEVER deleted by this
# script — do that by hand when you truly want to throw the data away.
#
# Required environment (secrets — never commit these):
#   SCW_ACCESS_KEY, SCW_SECRET_KEY,
#   SCW_DEFAULT_PROJECT_ID, SCW_DEFAULT_ORGANIZATION_ID
#   MM_SSH_PRIVATE_KEY   private key (PEM) used to SSH into the box
#   MM_SSH_PUBLIC_KEY    matching public key, injected at boot
#   MM_GH_PAT            GitHub token with read access to MeetingMind-AI repos
# Optional:
#   MM_RESEND_API_KEY, MM_EMAIL_FROM   forwarded into the app .env
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/config.env"

# Scaleway CLI reads SCW_DEFAULT_ZONE for zone-scoped commands.
export SCW_DEFAULT_ZONE="${MM_ZONE}"

log()  { printf '\033[1;36m[cloud]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[ ok ]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[fail]\033[0m %s\n' "$*" >&2; exit 1; }

require_env() {
  local missing=0
  for v in "$@"; do
    if [ -z "${!v:-}" ]; then warn "missing env: $v"; missing=1; fi
  done
  [ "$missing" -eq 0 ] || die "Set the missing environment variables (see README)."
}

# --- Scaleway helpers -------------------------------------------------------

# Return the server ID for MM_SERVER_NAME, or empty string if none exists.
server_id() {
  scw instance server list name="${MM_SERVER_NAME}" -o json 2>/dev/null \
    | jq -r '.[0].id // empty'
}

# Return the persistent data volume ID, or empty string.
data_volume_id() {
  scw instance volume list name="${MM_DATA_VOLUME_NAME}" -o json 2>/dev/null \
    | jq -r '.[0].id // empty'
}

# Ensure the SSH public key is registered in the project so cloud-init injects
# it. We also inject it via user-data as a belt-and-suspenders measure.
ssh_userdata_file() {
  local f="${SCRIPT_DIR}/.userdata.yml"
  cat >"$f" <<EOF
#cloud-config
ssh_authorized_keys:
  - ${MM_SSH_PUBLIC_KEY}
EOF
  printf '%s' "$f"
}

# Ensure the persistent data volume exists; create it if this is the very
# first run. Prints the volume ID.
ensure_data_volume() {
  local vid
  vid="$(data_volume_id)"
  if [ -n "$vid" ]; then
    log "Persistent data volume already exists: ${vid}"
  else
    log "Creating persistent data volume ${MM_DATA_VOLUME_NAME} (${MM_DATA_VOLUME_SIZE}, ${MM_VOLUME_TYPE})..."
    vid="$(scw instance volume create \
             name="${MM_DATA_VOLUME_NAME}" \
             volume-type="${MM_VOLUME_TYPE}" \
             size="${MM_DATA_VOLUME_SIZE}" \
             -o json | jq -r '.volume.id // .id')"
    [ -n "$vid" ] || die "Volume creation failed (check MM_VOLUME_TYPE — see README 'Volume type')."
    ok "Data volume created: ${vid}"
  fi
  printf '%s' "$vid"
}

# --- SSH ---------------------------------------------------------------------

ssh_key_file() {
  local f="${SCRIPT_DIR}/.ssh_key"
  printf '%s\n' "${MM_SSH_PRIVATE_KEY}" >"$f"
  chmod 600 "$f"
  printf '%s' "$f"
}

wait_for_ssh() {
  local ip="$1" key="$2" tries=40
  log "Waiting for SSH on ${ip}..."
  for i in $(seq 1 "$tries"); do
    if ssh -i "$key" -o StrictHostKeyChecking=no -o ConnectTimeout=8 \
           -o UserKnownHostsFile=/dev/null root@"$ip" 'true' 2>/dev/null; then
      ok "SSH is up."
      return 0
    fi
    sleep 10
  done
  die "SSH never came up on ${ip}."
}

# --- Commands ----------------------------------------------------------------

cmd_up() {
  require_env SCW_ACCESS_KEY SCW_SECRET_KEY SCW_DEFAULT_PROJECT_ID \
              MM_SSH_PRIVATE_KEY MM_SSH_PUBLIC_KEY MM_GH_PAT

  local existing
  existing="$(server_id)"
  if [ -n "$existing" ]; then
    warn "Server '${MM_SERVER_NAME}' already exists (${existing}). Reusing it."
  else
    local vid userdata
    vid="$(ensure_data_volume)"
    userdata="$(ssh_userdata_file)"

    log "Creating GPU server ${MM_SERVER_NAME} (${MM_SERVER_TYPE} @ ${MM_ZONE})..."
    scw instance server create \
      name="${MM_SERVER_NAME}" \
      type="${MM_SERVER_TYPE}" \
      image="${MM_IMAGE}" \
      root-volume="block:${MM_ROOT_VOLUME_SIZE}" \
      additional-volumes.0="${vid}" \
      ip=new \
      cloud-init=@"${userdata}" \
      -w >/dev/null
    ok "Server created and running."
  fi

  local ip key
  ip="$(scw instance server list name="${MM_SERVER_NAME}" -o json | jq -r '.[0].public_ip.address // empty')"
  [ -n "$ip" ] || die "Could not determine public IP."
  key="$(ssh_key_file)"
  wait_for_ssh "$ip" "$key"

  log "Running bootstrap on the server (mount volume, configure Docker, start stack)..."
  # Pass secrets over SSH env — never written to instance metadata.
  ssh -i "$key" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      root@"$ip" \
      "MM_GH_PAT='${MM_GH_PAT}' \
       MM_REPO_URL='${MM_REPO_URL}' \
       MM_REPO_BRANCH='${MM_REPO_BRANCH}' \
       MM_DATA_LABEL='${MM_DATA_LABEL}' \
       MM_DATA_MOUNT='${MM_DATA_MOUNT}' \
       MM_RESEND_API_KEY='${MM_RESEND_API_KEY:-}' \
       MM_EMAIL_FROM='${MM_EMAIL_FROM:-}' \
       bash -s" < "${SCRIPT_DIR}/bootstrap.sh"

  ok "Stack is up."
  cat <<EOF

  ================= MeetingMind AI is ONLINE =================
   Public IP : ${ip}
   Frontend  : https://${ip}      (self-signed cert — accept the warning)
   Backend   : http://${ip}:8000
   SSH       : ssh root@${ip}
  ===========================================================
  When you finish coding, run the 'Down' workflow to stop billing.
EOF
  # Expose IP to GitHub Actions summary/output if running in CI.
  if [ -n "${GITHUB_OUTPUT:-}" ]; then echo "public_ip=${ip}" >>"$GITHUB_OUTPUT"; fi
}

cmd_down() {
  require_env SCW_ACCESS_KEY SCW_SECRET_KEY SCW_DEFAULT_PROJECT_ID

  local sid
  sid="$(server_id)"
  if [ -z "$sid" ]; then
    ok "No server named '${MM_SERVER_NAME}' — nothing to delete. You are not being billed for compute."
    return 0
  fi

  log "Powering off ${MM_SERVER_NAME} (${sid})..."
  scw instance server stop "${sid}" -w >/dev/null 2>&1 || warn "stop returned non-zero (maybe already stopped)."

  # Detach the persistent data volume so deleting the server can't take it.
  local vid
  vid="$(data_volume_id)"
  if [ -n "$vid" ]; then
    log "Detaching persistent data volume ${vid} (keeping it)..."
    scw instance volume detach "${vid}" >/dev/null 2>&1 \
      || scw instance volume detach volume-id="${vid}" >/dev/null 2>&1 \
      || scw instance server detach-volume "${sid}" volume-id="${vid}" >/dev/null 2>&1 \
      || warn "Could not detach data volume automatically — verify in console before deleting!"
  fi

  # Capture the public IP so we can release it (a reserved unused IP still costs).
  local ipid
  ipid="$(scw instance server list name="${MM_SERVER_NAME}" -o json | jq -r '.[0].public_ip.id // empty')"

  log "Deleting server + its boot volume..."
  scw instance server delete "${sid}" with-volumes=local with-ip=true >/dev/null 2>&1 \
    || scw instance server delete "${sid}" >/dev/null

  if [ -n "$ipid" ]; then
    scw instance ip delete "${ipid}" >/dev/null 2>&1 || true
  fi

  ok "Server deleted. Compute billing stopped."
  warn "Persistent data volume '${MM_DATA_VOLUME_NAME}' kept (small storage cost). Delete it by hand to go to truly €0."
}

cmd_status() {
  require_env SCW_ACCESS_KEY SCW_SECRET_KEY SCW_DEFAULT_PROJECT_ID
  local sid vid
  sid="$(server_id)"
  vid="$(data_volume_id)"
  if [ -n "$sid" ]; then
    local ip state
    ip="$(scw instance server list name="${MM_SERVER_NAME}" -o json | jq -r '.[0].public_ip.address // "-"')"
    state="$(scw instance server list name="${MM_SERVER_NAME}" -o json | jq -r '.[0].state // "-"')"
    ok "Server '${MM_SERVER_NAME}' EXISTS — state=${state}, ip=${ip}  (billing active)"
  else
    ok "No server — compute billing is OFF."
  fi
  if [ -n "$vid" ]; then
    log "Persistent data volume '${MM_DATA_VOLUME_NAME}' present (${vid})."
  else
    warn "No persistent data volume yet — first 'up' will create it."
  fi
}

case "${1:-}" in
  up)     cmd_up ;;
  down)   cmd_down ;;
  status) cmd_status ;;
  *) die "usage: cloud.sh {up|down|status}" ;;
esac
