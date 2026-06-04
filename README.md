# MeetingMind AI Monorepo

Self-hosted, offline-first multi-agent meeting assistant for Agile operations.

This repository orchestrates two main zones:

- `vexa/` (Sensor Zone): meeting bot and transcript capture
- `backend/` (Brain Zone): FastAPI orchestration, transcript ingestion, and AI summarization

## 📚 Documentation

See the full documentation index in [docs/README.md](docs/README.md).

## Architecture

- **Sensor Zone (`vexa/`)**
  - Runs the Vexa bot stack locally (Supports both CPU and GPU setups).
  - Exposes:
    - API Gateway: `http://localhost:8056`
    - Admin API: `http://localhost:8057`
    - Dashboard: `http://localhost:3001`
- **Brain Zone (`backend/`)**
  - FastAPI service on `http://localhost:8000`
  - PostgreSQL + Redis
  - Ollama container on `http://ollama:11434` (accessible within the Docker network)
  - Mem0 semantic memory layer (mem0ai) for cross-meeting context
  - Uses fully merged, clean transcripts via Vexa REST API polling (WebSocket ingestion removed)

## Prerequisites

- Docker + Docker Compose
- NVIDIA Container Toolkit (Linux GPU hosts)
- Python 3.11+ (if running services outside Docker)
- Mem0 configuration (defaults to Ollama)
- Ollama model pulled inside the Docker container (see Step 6)
- Vexa stack running locally (from `vexa/`)
- Enable NVIDIA Persistence Mode on the host to prevent GPU power-down latency spikes:
  ```bash
  sudo nvidia-smi -pm 1
  ```
  This keeps the driver and GPU awake between transcript chunks, avoiding cold-start delays.

## 🚀 Quickstart & Deployment

This project requires two zones to be running: **The Sensor Zone** (Vexa) and **The Brain Zone** (MeetingMind Backend).

### Step 1: Start Vexa (The Sensor Zone)
Navigate to the Vexa directory (`cd vexa`). Depending on your hardware, configure Vexa before starting it.

Start by copying the Vexa env example and setting the required fields:

```bash
cp vexa/deploy/env-example vexa/.env
```

#### For macOS / CPU Only:
1. Edit `vexa/.env` and set:
   ```env
   LOCAL_TRANSCRIPTION=true
   TRANSCRIPTION_SERVICE_URL=http://host.docker.internal:8083/v1/audio/transcriptions
   TRANSCRIPTION_SERVICE_TOKEN=local
   ```
2. Edit `vexa/deploy/compose/Makefile` to use `docker-compose.cpu.yml` for the transcription service.
3. Edit `vexa/services/transcription-service/nginx.conf` and comment out worker 2 and 3.

#### For Linux / Nvidia GPU:
1. Ensure Nvidia Container Toolkit is installed.
2. Edit `vexa/.env` and set:
   ```env
   LOCAL_TRANSCRIPTION=true
   TRANSCRIPTION_SERVICE_URL=http://172.17.0.1:8083/v1/audio/transcriptions
   TRANSCRIPTION_SERVICE_TOKEN=local
   ```
3. Keep the default `Makefile` and `nginx.conf` configurations (they use the GPU by default).

**Start the stack:**
```bash
# Pull the bot image first to prevent 404s
docker pull vexaai/vexa-bot:latest
make all
```

### Step 2: Mint your Vexa API Key
To allow the backend to dispatch bots, you must mint an API Key from Vexa's Admin API.

**Option A — Via the Vexa Dashboard (recommended):**
Open `http://localhost:3001` in your browser to access the Vexa Dashboard. From there you can:
- Generate API keys under the settings/admin section.
- Launch test meetings to verify Vexa is working.
- Monitor bot status and view live transcripts in real time.

**Option B — Via the Admin API (curl):**

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
Set your newly minted key in the root `.env` file so `docker-compose.yml` can load it via interpolation:
```env
VEXA_API_KEY=your_long_token_string_here
```

### Step 4: Boot the System
Start the backend, database, and local LLM containers:
```bash
docker compose up -d
```

### Step 5: Access the Web UI

Once the containers are up, open the app in your browser:

| Scenario | URL |
|---|---|
| Running on your local machine | `http://localhost:3000` |
| Accessing a remote Linux server / VM | `https://<server-ip>` |

> **Why does the browser show "Not Secure"?**
>
> The frontend container generates a **self-signed SSL certificate** at build time. Because it is not signed by a trusted Certificate Authority, browsers flag it as untrusted. This is expected behaviour for a self-hosted POC — the connection is still encrypted.
>
> **To accept the certificate and proceed (one-time per browser):**
> - **Chrome / Edge**: Click **Advanced** → **Proceed to \<address\> (unsafe)**
> - **Firefox**: Click **Advanced…** → **Accept the Risk and Continue**
> - **Safari**: Click **Show Details** → **visit this website**
>
> **Tip:** If you are accessing from your local machine, `http://localhost:3000` works without any certificate warning because browsers treat `localhost` as a secure context.

### Step 6: Initialize the Database
Because this relies on a local PostgreSQL container, you must generate the tables on the first run:
```bash
docker compose exec backend alembic revision --autogenerate -m "initial_tables"
docker compose exec backend alembic upgrade head
```

### Step 7: Download the LLM
The Ollama container boots up empty. You must pull the `llama3.1` model before starting your first meeting:
```bash
docker compose exec ollama ollama run llama3.1
```
(Once it says "success", type `/bye` to exit).

Mem0 uses an Ollama embedder by default, so also pull the embedding model once:

```bash
docker compose exec ollama ollama pull nomic-embed-text
```
