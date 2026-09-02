# On-demand GPU on Scaleway — pay only while you code

MeetingMind runs on a **Scaleway L4 GPU instance that you create and destroy on
demand**. While it's down you pay **€0 for compute** — only a small monthly cost
for the persistent data volume that keeps your models and database between
sessions.

- **Up** → creates the GPU box, attaches the persistent volume, boots the whole
  stack, prints the public IP.
- **Down** → deletes the server + boot disk + public IP. Keeps the data volume.
- **Status** → tells you if the box is currently up (and billing).

Two ways to drive it: **GitHub Actions buttons** (default) or `make cloud-*`
locally.

---

## Cost model (why this exists)

| State | What runs | Roughly costs |
|---|---|---|
| Up (coding) | L4 GPU instance | ~€0.75/h |
| Down (idle) | Persistent 100 GB volume only | a few € / month |
| Volume deleted by hand | nothing | €0 |

Scaleway bills GPU instances **by the hour and stops the moment the server is
deleted** — unlike a Hetzner dedicated GEX box, which bills monthly whether on or
off. That difference is the whole reason this targets Scaleway.

---

## One-time setup

### 1. A Scaleway account + API keys
Create an API key in the Scaleway console (Identity & Access Management → API
keys). You'll get an **Access Key** and **Secret Key**, and you can read your
**Project ID** and **Organization ID** from the console.

### 2. An SSH keypair for the box
Generate a dedicated keypair (don't reuse a personal one):

```bash
ssh-keygen -t ed25519 -f meetingmind_deploy -N "" -C "meetingmind-cloud"
```

- `meetingmind_deploy`     → the **private** key (secret `MM_SSH_PRIVATE_KEY`)
- `meetingmind_deploy.pub` → the **public** key (secret `MM_SSH_PUBLIC_KEY`)

### 3. A GitHub token that can read the submodules
The three submodules (`backend`, `frontend`, `vexa`) are private repos in the
`MeetingMind-AI` org. Create a **fine-grained PAT** with **read** access to those
repos → secret `MM_GH_PAT`.

### 4. Add the secrets to GitHub
Repo → **Settings → Secrets and variables → Actions → New repository secret**:

| Secret | Value |
|---|---|
| `SCW_ACCESS_KEY` | Scaleway access key |
| `SCW_SECRET_KEY` | Scaleway secret key |
| `SCW_DEFAULT_PROJECT_ID` | Scaleway project ID |
| `SCW_DEFAULT_ORGANIZATION_ID` | Scaleway organization ID |
| `MM_SSH_PRIVATE_KEY` | contents of `meetingmind_deploy` |
| `MM_SSH_PUBLIC_KEY` | contents of `meetingmind_deploy.pub` |
| `MM_GH_PAT` | GitHub read PAT for the submodules |
| `MM_RESEND_API_KEY` | *(optional)* email reports |
| `MM_EMAIL_FROM` | *(optional)* e.g. `MeetingMind <onboarding@resend.dev>` |

---

## Daily use

**Start coding:** Actions tab → **☁️ Cloud — Up** → *Run workflow*. When it
finishes, the run summary shows the IP and URLs. Open `https://<ip>` (accept the
self-signed cert).

**Stop coding:** Actions tab → **🌙 Cloud — Down** → *Run workflow*. Billing for
the GPU stops. Your meetings, models, and DB stay on the volume for next time.

**Check:** **🔎 Cloud — Status**.

Locally instead of buttons (needs the same vars exported in your shell):

```bash
make cloud-up
make cloud-status
make cloud-down
```

The first **Up** is a cold start: it formats the volume, sets Docker's
`data-root` onto it, clones the repo, and pulls ~6 GB of models — **give it
10–20 min and watch the logs**. Every later Up reuses the volume and is only a
couple of minutes.

---

## ⚠️ Things to verify on your first run (I could not test against a live account)

1. **Volume type.** The script defaults to `MM_VOLUME_TYPE=b_ssd` (legacy
   detachable block SSD). If your project is on **Scaleway Block Storage (SBS)**
   only and volume creation fails, set `MM_VOLUME_TYPE=sbs_volume` in
   `config.env` and re-run. Everything else is identical.
2. **GPU image label.** Defaults to `ubuntu_noble_gpu_os_12`. If Scaleway has
   moved to `ubuntu_noble_gpu_os_13`, bump `MM_IMAGE` in `config.env`.
3. **`scw` flag drift.** The `server delete` / `volume detach` flags occasionally
   change between CLI versions. If **Down** can't detach the data volume, it
   prints a warning and stops before deleting — check the console, then adjust
   the two `scw instance volume detach` lines in `cloud.sh`.
4. **GPU stock.** L4 can be out of stock in a zone. Re-run Up with a different
   `zone` input (`fr-par-1`, `pl-waw-2`).

## Guardrails baked in
- The data volume is **never deleted** by these scripts — only by you, by hand.
- `up` and `down` share a GitHub Actions `concurrency` group, so they can't race.
- The GitHub PAT is passed to the box over SSH env and used via a git auth
  header — it is **not** written into instance metadata or the repo's git config.
