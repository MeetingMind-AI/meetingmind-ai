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

## Quick Start

1. Start Vexa stack (inside `vexa/`):
   - Use the Vexa project instructions (`make all` in the Vexa repo setup).
2. Start monorepo services (from repo root):
   - `docker-compose up -d --build`
3. Verify health:
   - Backend: `http://localhost:8000/health`
   - Backend docs: `http://localhost:8000/docs`

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

## Troubleshooting

- If WS subscription fails, confirm:
  - `VEXA_API_KEY` in backend container matches the key used for Vexa API calls.
  - Vexa API Gateway is reachable at `host.docker.internal:8056` from backend container.
- If summaries fail, confirm:
  - Ollama is reachable at `host.docker.internal:11434`
  - model configured in backend exists in Ollama (`llama3` by default)

## Development Workflow

- Backend code: `backend/app`
- Run backend tests/checks as available per module
- Keep API changes documented in `backend/README.md`
