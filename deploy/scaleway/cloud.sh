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

# Diagnostics go to stderr so functions can return a clean value on stdout via
# command substitution (e.g. `vid="$(ensure_data_volume)"`).
log()  { printf '\033[1;36m[cloud]\033[0m %s\n' "$*" >&2; }
ok()   { printf '\033[1;32m[ ok ]\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*" >&2; }
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
# Data lives on a Scaleway Block Storage (SBS) volume — the 'scw block' API.
data_volume_id() {
  scw block volume list name="${MM_DATA_VOLUME_NAME}" zone="${MM_ZONE}" -o json 2>/dev/null \
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
    log "Creating persistent SBS data volume ${MM_DATA_VOLUME_NAME} (${MM_DATA_VOLUME_SIZE}, ${MM_VOLUME_IOPS} IO/s)..."
    vid="$(scw block volume create \
             name="${MM_DATA_VOLUME_NAME}" \
             perf-iops="${MM_VOLUME_IOPS}" \
             from-empty.size="${MM_DATA_VOLUME_SIZE}" \
             zone="${MM_ZONE}" \
             -w -o json | jq -r '.id // .volume.id')"
    [ -n "$vid" ] || die "SBS volume creation failed (check MM_VOLUME_IOPS is 5000 or 15000)."
    ok "Data volume created: ${vid}"
  fi
  printf '%s' "$vid"
}

# Ensure our SSH public key is registered in Scaleway IAM, so it is injected
# into every new server at boot (the reliable path — cloud-init user-data is
# not). Idempotent: matches on the key body (type + base64), ignoring comment.
ensure_ssh_key() {
  local want have
  want="$(printf '%s' "${MM_SSH_PUBLIC_KEY}" | awk '{print $1" "$2}')"
  have="$(scw iam ssh-key list -o json 2>/dev/null | jq -r '.[].public_key' \
          | awk '{print $1" "$2}')" || have=""
  if printf '%s\n' "${have}" | grep -qxF "${want}"; then
    log "SSH key already registered in Scaleway IAM."
  else
    log "Registering SSH public key in Scaleway IAM..."
    scw iam ssh-key create name="meetingmind-cloud" \
      public-key="${MM_SSH_PUBLIC_KEY}" >/dev/null \
      || warn "Could not register SSH key (maybe already present) — continuing."
    ok "SSH key registration step done."
  fi
}

# If the persistent volume is still attached to a DIFFERENT server (leftover
# from a failed run), detach it there so we can attach it to the new server.
free_data_volume() {
  local vid="$1" sid="$2" holder
  holder="$(scw block volume get "${vid}" zone="${MM_ZONE}" -o json 2>/dev/null \
            | jq -r --arg s "${sid}" \
              '[.references[]? | select((.product_resource_type // "")|test("server")) | .product_resource_id] | map(select(. != $s)) | .[0] // empty')" \
    || holder=""
  if [ -n "${holder}" ]; then
    warn "Data volume is attached to another server (${holder}); detaching it there..."
    scw instance server detach-volume server-id="${holder}" volume-id="${vid}" >/dev/null 2>&1 || true
    sleep 5
  fi
}

# True if the SBS volume is currently attached to the given server id.
volume_attached_to() {
  local vid="$1" sid="$2" got
  got="$(scw block volume get "${vid}" zone="${MM_ZONE}" -o json 2>/dev/null \
         | jq -r --arg s "${sid}" 'any(.references[]?; .product_resource_id==$s)')" || got="false"
  [ "${got}" = "true" ]
}

# Poll until the SBS volume reports status=available (i.e. not attached), so a
# just-detached volume is ready to attach. Never blocks on an unknown shape.
wait_volume_available() {
  local vid="$1" st
  for i in $(seq 1 12); do
    st="$(scw block volume get "${vid}" zone="${MM_ZONE}" -o json 2>/dev/null | jq -r '.status // ""')" || st=""
    [ -z "${st}" ] && return 0
    [ "${st}" = "available" ] && return 0
    sleep 5
  done
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

  # Register the SSH key before any server is created so Scaleway injects it.
  ensure_ssh_key

  # The persistent SBS data volume exists across cycles — ensure it first so
  # both the create and reuse paths can attach it.
  local vid sid
  vid="$(ensure_data_volume)"

  # Guard against leftover duplicate servers from earlier failed runs — those
  # confuse volume attachment. Down deletes them all.
  local count
  count="$(scw instance server list name="${MM_SERVER_NAME}" -o json 2>/dev/null | jq -r 'length')" || count=0
  if [ "${count:-0}" -gt 1 ]; then
    die "Found ${count} servers named '${MM_SERVER_NAME}' (leftovers from failed runs). Run 'Cloud — Down' first (it deletes them all), then Up."
  fi

  sid="$(server_id)"
  if [ -n "$sid" ]; then
    # Reuse path: server pre-exists. Ensure the data volume is attached to it.
    warn "Server '${MM_SERVER_NAME}' already exists (${sid}). Reusing it."
    if volume_attached_to "${vid}" "${sid}"; then
      log "Data volume already attached to this server."
    else
      free_data_volume "${vid}" "${sid}"   # detach from any leftover holder
      wait_volume_available "${vid}"
      log "Attaching persistent data volume ${vid}..."
      local err; err="$(mktemp)"
      if ! scw instance server attach-volume \
             server-id="${sid}" volume-id="${vid}" volume-type=sbs_volume >/dev/null 2>"${err}"; then
        if grep -qi "already attached" "${err}"; then
          log "Volume already attached (per API) — continuing."
        else
          warn "attach-volume failed. Real error:"; cat "${err}" >&2 || true
          warn "Volume state:"; scw block volume get "${vid}" zone="${MM_ZONE}" -o json 2>/dev/null | jq -c '{status, references}' >&2 || true
          die "Could not attach data volume ${vid}. Run 'Cloud — Down' with wipe_volume=true, then Up."
        fi
      fi
      ok "Data volume attached."
    fi
  else
    # Create path: attach the data volume INLINE at create time so it is
    # present at boot (no hot-plug latency). Needs a clean volume UUID.
    local userdata
    userdata="$(ssh_userdata_file)"
    log "Creating GPU server ${MM_SERVER_NAME} (${MM_SERVER_TYPE} @ ${MM_ZONE})..."
    scw instance server create \
      name="${MM_SERVER_NAME}" \
      type="${MM_SERVER_TYPE}" \
      image="${MM_IMAGE}" \
      root-volume="sbs:${MM_ROOT_VOLUME_SIZE}:${MM_ROOT_IOPS}" \
      additional-volumes.0="${vid}" \
      ip=new \
      cloud-init=@"${userdata}" \
      -w >/dev/null
    ok "Server created with data volume attached."
    sid="$(server_id)"
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

  local vid
  vid="$(data_volume_id)"

  # Delete EVERY server with our name (failed runs can leave duplicates). For
  # each: detach the persistent volume first, then delete server + boot + IP.
  local ids
  ids="$(scw instance server list name="${MM_SERVER_NAME}" -o json 2>/dev/null | jq -r '.[].id')" || ids=""
  if [ -z "$ids" ]; then
    ok "No server named '${MM_SERVER_NAME}' — no compute billing."
  fi
  local sid ipid
  for sid in $ids; do
    log "Powering off ${sid}..."
    scw instance server stop "${sid}" -w >/dev/null 2>&1 || true
    if [ -n "$vid" ]; then
      scw instance server detach-volume server-id="${sid}" volume-id="${vid}" >/dev/null 2>&1 || true
    fi
    ipid="$(scw instance server get "${sid}" zone="${MM_ZONE}" -o json 2>/dev/null | jq -r '.public_ip.id // empty')" || ipid=""
    # with-volumes=root deletes ONLY the boot volume — never the persistent one.
    log "Deleting server ${sid}..."
    scw instance server delete "${sid}" with-volumes=root with-ip=true force-shutdown=true -w >/dev/null 2>&1 \
      || scw instance server delete "${sid}" with-volumes=root >/dev/null 2>&1 || true
    [ -n "$ipid" ] && scw instance ip delete "${ipid}" >/dev/null 2>&1 || true
  done
  [ -n "$ids" ] && ok "All '${MM_SERVER_NAME}' servers deleted — compute billing stopped."

  # Optional: wipe the persistent data volume too (set MM_WIPE_VOLUME=true).
  # Safe when the volume holds nothing you want; goes to truly €0.
  if [ "${MM_WIPE_VOLUME:-false}" = "true" ] && [ -n "$vid" ]; then
    warn "Wiping persistent data volume ${vid} as requested..."
    wait_volume_available "${vid}"
    if scw block volume delete "${vid}" zone="${MM_ZONE}" >/dev/null 2>&1; then
      ok "Data volume deleted. Now at €0. Next 'Up' creates a fresh one."
    else
      warn "Could not delete volume ${vid} (still attached?). Delete it in the console: Storage → Block."
    fi
  elif [ -n "$vid" ]; then
    warn "Persistent data volume '${MM_DATA_VOLUME_NAME}' kept (small storage cost). Run Down with wipe_volume=true to remove it."
  fi
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
