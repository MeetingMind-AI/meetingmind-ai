# MeetingMind AI Monorepo

Self-hosted, offline-first multi-agent meeting assistant for Agile operations.

This repository orchestrates two main zones:

- `vexa/` (Sensor Zone): meeting bot and transcript capture
- `backend/` (Brain Zone): FastAPI orchestration, transcript ingestion, and AI summarization

## Architecture

- **Sensor Zone (`vexa/`)**
  - Runs the Vexa bot stack locally.
  - Exposes:
    - API Gateway: `http://localhost:8056`
    - Admin API: `http://localhost:8057`
    - Dashboard: `http://localhost:3001`
- **Brain Zone (`backend/`)**
  - FastAPI service on `http://localhost:8000`
  - PostgreSQL + Redis
  - Ollama endpoint (local): `http://host.docker.internal:11434`

## Repository Layout

- `backend/`: FastAPI backend (BOLAA controller/worker logic)
- `frontend/`: frontend application
- `vexa/`: Vexa submodule and bot services
- `docker-compose.yml`: root local orchestration for backend/frontend/data services

## Prerequisites

- Docker + Docker Compose
- Python 3.11+ (if running services outside Docker)
- Ollama running locally with model available (for example `llama3`)
- Vexa stack running locally (from `vexa/`)

## 🚀 Quickstart & Deployment

This project requires two zones to be running: **The Sensor Zone** (Vexa) and **The Brain Zone** (MeetingMind Backend).

### Step 1: Start Vexa (The Sensor Zone)
Navigate to the Vexa directory and start the headless bot infrastructure:
```bash
make all
```

### Step 2: Mint your Vexa API Key
To allow the backend to dispatch bots, you must mint an API Key from Vexa's Admin API.

**Create a User:**
```bash
curl -X POST "http://localhost:8057/admin/users" \
  -H "Content-Type: application/json" \
  -H "X-Admin-API-Key: changeme" \
  -d '{"email": "bot@example.com", "name": "AI Assistant"}'
```
(Note the "id" returned in the JSON response, e.g., 1)

**Generate the Key:**
```bash
curl -X POST "http://localhost:8057/admin/users/1/tokens" \
  -H "Content-Type: application/json" \
  -H "X-Admin-API-Key: changeme" \
  -d '{"name": "Backend Key", "scopes": ["bot", "tx", "browser"]}'
```
Copy the long string inside the "token" field from the response.

### Step 3: Configure the Backend (The Brain Zone)
In the root of the `backend/` directory, create a `.env` file and add your newly minted key:
```env
# Do not use quotes or trailing spaces
VEXA_API_KEY=your_long_token_string_here
```

### Step 4: Boot the System
Start the backend, database, and local LLM containers:
```bash
docker compose up -d
```

### Step 5: Initialize the Database
Because this relies on a local PostgreSQL container, you must generate the tables on the first run:
```bash
docker compose exec backend alembic revision --autogenerate -m "initial_tables"
docker compose exec backend alembic upgrade head
```

### Step 6: Download the LLM
The Ollama container boots up empty. You must pull the `llama3` model before starting your first meeting:
```bash
docker compose exec ollama ollama run llama3
```
(Once it says "success", type `/bye` to exit).

You are now ready to hit `POST /api/meetings/start`!

## Typical Flow

1. Start meeting bot:
   - `POST /api/meetings/start`
2. Backend subscribes to transcript + status events.
3. Live transcript lines are logged while meeting is active.
4. On completion, backend performs final transcript sync and generates final markdown report.

## Operational Notes

- Root Compose warning about `version` was removed from `docker-compose.yml`.
- For secure deployments, move secrets (API keys, DB credentials) to environment files or secret managers.
- This repo may include submodules; update them with:
  - `git submodule update --init --recursive`

### Submodule Sync Alias

To simplify syncing submodules to their latest commits and pushing those changes to the main repository, you can set up a git alias:

```bash
git config --global alias.sync-modules '!git submodule update --remote && git add . && git commit -m "Auto-synced submodules to latest commits" && git push origin main'
```

Then, you can sync all submodules with a single command:

```bash
git sync-modules
```

## 🛠 Troubleshooting (Linux VM Environments)

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
If you are running Ollama directly on the Linux host rather than inside Docker, it binds to `127.0.0.1` by default, blocking Docker containers.
To fix this, edit the systemd service:
```bash
sudo systemctl edit ollama.service
```
Add the following to expose Ollama to the Docker bridge:
```ini
[Service]
Environment="OLLAMA_HOST=0.0.0.0"
```
Then restart the service: `sudo systemctl daemon-reload && sudo systemctl restart ollama`

### 3. WebSocket "4401" Unauthorized Errors
If the Vexa API Gateway rejects the WebSocket connection, ensure your WebSocket client passes the API key as a URL parameter rather than a header, as Python websockets can strip headers across Docker bridges:
`ws://host.docker.internal:8056/ws?api_key=your_key_here`

## Development Workflow

- Backend code: `backend/app`
- Run backend tests/checks as available per module
- Keep API changes documented in `backend/README.md`
