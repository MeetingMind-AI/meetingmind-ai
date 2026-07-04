# Troubleshooting Guide

This guide covers common issues and resolutions for deploying and running the MeetingMind AI stack, particularly in Linux VM environments and Docker setups.

## 🤖 Vexa Submodule

Vexa is a highly integrated piece of architecture that interacts directly with our host VM. Because of this, standard Docker commands can sometimes cause unexpected issues.

### ⚠️ Scenario A: The System Crashed After a VM Reboot

If the server is rebooted, the `runtime-api` container will almost always enter a crash loop (`Restarting`). You will see a `500 Failed to start bot container` error in the website UI.

**The Cause:** Linux resets the permissions on `/var/run/docker.sock` upon startup. The `runtime-api` orchestrator needs access to this socket to spawn the headless browser bots, but gets a `Permission denied` error and crashes.

**The Fix (Do NOT rebuild or pull images):** Simply grant permission to the socket and restart the orchestrator.

```bash
sudo chmod 666 /var/run/docker.sock
docker compose -f vexa/deploy/compose/docker-compose.yml restart runtime-api
```

### 🔄 Scenario B: Safely Updating to a New Release

Never update Vexa using standard `docker compose pull` commands (including `IMAGE_TAG=... docker compose pull`). Upstream changes frequently introduce new required `.env` variables and database schema changes. Attempting to pull latest without updating the environment will break the stack.

Always use the official Makefile and pin to a specific release tag.

#### Step 1: Shut Down and Sync the Submodule

Always pull a specific release tag, never the main branch.

```bash
# Safely shut down to release file locks
docker compose -f vexa/deploy/compose/docker-compose.yml down

# Fetch all tags directly from the upstream repository
git -C vexa fetch origin --tags

# Checkout the specific version (e.g., vexa-0.10.6+2)
git -C vexa checkout <exact-tag-name>
```

*(Note: If Git throws a pathspec error, your fork is outdated. Sync your fork on GitHub first, or run `git fetch https://github.com/Vexa-ai/vexa.git --tags`).*

#### Step 2: Update your `.env`

Compare your `vexa/.env` with `vexa/deploy/env-example` and merge any new required variables before restarting. Do not carry forward an older `.env` without adding newly introduced keys.

#### Step 3: Start Vexa

Use the Makefile for your chosen deployment mode:

```bash
make all
```

---

## 🌐 Networking & Docker Environments

If you are deploying this on a Linux server rather than Docker Desktop for Mac/Windows, be aware of standard Linux networking restrictions.

### 1. "Name or service not known" (502 Bad Gateway)

Linux Docker does not natively resolve `host.docker.internal`. If your backend is trying to reach Vexa running on the host, ensure your `docker-compose.yml` includes the host-gateway mapping:

```yaml
services:
  backend:
    extra_hosts:
      - "host.docker.internal:host-gateway"
```

### 2. Ollama Connection Timeouts

If you are running Ollama directly on the Linux host rather than inside Docker, it binds to `127.0.0.1` by default, blocking Docker containers. To fix this, edit the systemd service:

```bash
sudo systemctl edit ollama.service
```

Add the following to expose Ollama to the Docker bridge:

```ini
[Service]
Environment="OLLAMA_HOST=0.0.0.0"
```

Then restart the service: 
```bash
sudo systemctl daemon-reload && sudo systemctl restart ollama
```

### 3. WebSocket "4401" Unauthorized Errors

If the Vexa API Gateway rejects the WebSocket connection, ensure your WebSocket client passes the API key as a URL parameter rather than a header, as Python websockets can strip headers across Docker bridges: 
`ws://host.docker.internal:8056/ws?api_key=your_key_here`

### 4. Submodule Update Issues (Pulling on VM)

Since we just want the VM to reflect the latest pushed code from GitHub, you can discard local changes on the VM by running this:

```bash
git submodule foreach git reset --hard
```

After doing that, run the submodule update again:

```bash
git submodule update --init --recursive
```
