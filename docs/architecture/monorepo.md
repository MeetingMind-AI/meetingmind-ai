# MeetingMind AI Monorepo Guide

## Repository Layout

- `backend/`: FastAPI backend (BOLAA controller/worker logic)
- `frontend/`: frontend application
- `vexa/`: Vexa submodule and bot services
- `docker-compose.yml`: root local orchestration for backend/frontend/data services
- `deploy/scaleway/`: on-demand cloud lifecycle — create/destroy a Scaleway L4 GPU box billed only while you use it (see [Cloud Deployment](#cloud-deployment-on-demand-gpu) below)

## Hardware & Performance Tuning (Linux + NVIDIA)

The root `docker-compose.yml` applies several Linux-specific optimizations for a 16GB NVIDIA GPU:

- **VRAM utilization:** `OLLAMA_NUM_PARALLEL: "2"` is tuned for 16GB cards so the Tech Lead and Product Manager agents can run in parallel using `hermes3:8b` (`q4_K_M`) plus `nomic-embed-text` without hitting OOM.
- **Model residency:** `OLLAMA_KEEP_ALIVE="10h"` keeps models warm in VRAM across a working session, avoiding the multi-second reload cost on each new meeting/report. Lower it if you need to free VRAM aggressively between meetings.
- **Shared memory:** `shm_size: '2gb'` is set on both `ollama` and `postgres` to prevent Linux bus errors during heavy tensor mutations and database workloads.
- **OOM killer protection:** `oom_score_adj: -500` is applied to PostgreSQL so the kernel is less likely to terminate the database under RAM pressure.

## Ollama Parallel Requests & Concurrency

The Ollama service is configured with `OLLAMA_NUM_PARALLEL=2`, allowing it to process up to **2 concurrent inference requests** per loaded model. In this case, the Tech Lead and Product Manager bots can run their initial analyses and cross-functional debate turns in parallel.

Each parallel slot allocates additional GPU/CPU memory for the KV cache. For `hermes3:8b`, expect roughly **1–2 GB of extra memory per slot**. To adjust the concurrency level, change the `OLLAMA_NUM_PARALLEL` value in `docker-compose.yml`:

```yaml
ollama:
  environment:
    OLLAMA_NUM_PARALLEL: "2"   # increase or decrease based on available memory
```

Requests beyond the parallel limit are queued automatically (up to 512 by default).

The Ollama container is configured for 16 GB VRAM with `OLLAMA_MAX_VRAM=16384` and `OLLAMA_KV_CACHE_TYPE=q8_0` in `docker-compose.yml`. Larger parameter models can also be configured with appropriate KV cache sizing.

## Typical Flow

1. Start meeting bot:
   - `POST /api/meetings/start`
2. Backend polls the Vexa REST API (`GET /transcripts/{platform}/{native_id}`) periodically for clean, pause-ignored transcript segments.
3. Live transcript lines are logged and inserted into the database.
4. On completion, backend performs final transcript sync and runs the multi-persona report pipeline:
    - **Initial Analysis**: Tech Lead + Product Manager analyze the transcript independently (parallel)
    - **Discussion Rounds**: Tech Lead ↔ Product Manager debate each other's findings (configurable rounds)
    - **Final Synthesis**: Scrum Master receives all analyses + the full debate and produces the final JSON report
    - This final report pipeline runs in the background after `POST /api/meetings/{meeting_id}/leave` returns `202 Accepted`.



## Multi-Persona Discussion System

The final report is generated through a structured debate between AI personas, not a single-shot summary.

### Architecture

```
Transcript
    │
    ├── Tech Lead (initial analysis)      ──┐
    │                                       ├── Discussion Rounds (TL ↔ PM)
    └── Product Manager (initial analysis) ──┘
                                               │
                                               ▼
                                    Scrum Master (final synthesis)
```

| Component | Class | File | Responsibility |
|---|---|---|---|
| LLM Client | `OllamaClient` | `engine/controller.py` | HTTP calls to Ollama |
| Discussion | `DiscussionEngine` | `engine/controller.py` | TL ↔ PM debate orchestration |
| Prompt Builder | `ReportPromptBuilder` | `engine/controller.py` | Assembles SM synthesis prompt |
| Transcript | `TranscriptLoader` | `engine/controller.py` | Reads chunks from DB |
| Orchestrator | `ControllerAgent` | `engine/controller.py` | Ties everything together |

### Discussion Format

During each round, the Tech Lead and Product Manager respond with:
- **Agreements** — Points they confirm from the other persona
- **Challenges** — Points they disagree with (with reasoning)
- **Additions** — New insights surfaced by the debate
- **Refined Position** — Updated assessment incorporating feedback

### Configuration

The number of discussion rounds is controlled by the `num_rounds` parameter on `generate_final_report()`:

| `num_rounds` | Behavior | LLM Calls |
|---|---|---|
| `0` | No discussion (original behavior) | 3 |
| `1` (default) | One round of TL ↔ PM debate | 5 |
| `2` | Two rounds | 7 |
| `N` | N rounds | 2 + 2N + 1 |

The default is set via `DEFAULT_DISCUSSION_ROUNDS` in `engine/controller.py`.

## Setup, Rebuild & Model Switching Scripts

The monorepo provides automated management scripts located at the project root:

| Command / Script | Purpose | Operational Behavior |
|---|---|---|
| `make setup` / `./setup.sh` | Interactive Cold-Start | Configures `.env` files, boots PostgreSQL, Redis, Qdrant, provisions Vexa bot and Whisper STT, runs Alembic migrations, and pulls Ollama models. |
| `./setup.sh --non-interactive` | Headless Automation | Performs full cold-start setup without prompting for optional settings; ideal for CI/CD pipelines and headless VM initialization. |
| `make rebuild` | Safe Code Refresh | Executes `docker compose up -d --build` for main stack and restarts/rebuilds the Vexa sensor stack without wiping database volumes. |
| `./change_models.sh` | Interactive Model Configurator | Prompts for target LLM (`hermes3:8b`, etc.) and Whisper STT model (`small.en`, `large-v3-turbo`), updates `.env` files, and restarts services. |
| `./update_vexa.sh` | Vexa Submodule Update | Pulls the latest commits from the Vexa Git submodule, pulls new Docker images, and restarts Vexa bot containers. |

---

## Environment Variable Configuration Reference

Key environment variables configured in `./.env` (and passed to Docker containers):

| Variable | Default / Example | Purpose |
|---|---|---|
| `OLLAMA_MODEL` | `hermes3:8b` | Primary LLM used for live transcript proposals, Instant Clarity, and persona analysis. |
| `OLLAMA_FINAL_MODEL` | `hermes3:8b` | Model used for final Scrum Master synthesis (defaults to base `OLLAMA_MODEL`). |
| `OLLAMA_URL` | *(platform-dependent — see note below)* | API endpoint for Ollama text generation. |
| `MEM0_OLLAMA_URL` | *(platform-dependent — see note below)* | Ollama root URL for Mem0 memory embeddings. |
| `MEM0_LLM_MODEL` | `hermes3:8b` | LLM used by Mem0 for cross-meeting extraction. |
| `MEM0_EMBED_MODEL` | `nomic-embed-text` | 768-dim vector embedding model. |
| `MEM0_QDRANT_URL` | `http://qdrant:6333` | Vector database host for long-term memory. |
| `VEXA_API_KEY` | *(Auto-generated)* | Bearer authentication token for Vexa sensor bot gateway. |
| `TRANSCRIPTION_SERVICE_URL` | `http://transcription-api:80` | Internal URL for local Whisper STT service. |
| `TRANSCRIPTION_SERVICE_TOKEN` | *(Auto-generated)* | Token for Whisper speech-to-text API. |
| `MODEL_SIZE` | `small.en` | Whisper model size (`small.en` CPU, `large-v3-turbo` GPU). |
| `RESEND_API_KEY` | `re_...` | API key for Resend email distribution (optional). |
| `EMAIL_FROM` | `MeetingMind <onboarding@resend.dev>` | Verified sender email for HTML meeting reports. |

> **Platform note for `OLLAMA_URL` and `MEM0_OLLAMA_URL`:**
> - **Apple Silicon Mac:** `setup.sh` sets `OLLAMA_URL=http://host.docker.internal:11434/api/generate` and `MEM0_OLLAMA_URL=http://host.docker.internal:11434` (host Ollama, Docker Ollama container stopped).
> - **Linux:** `OLLAMA_URL=http://ollama:11434/api/generate` and `MEM0_OLLAMA_URL=http://ollama:11434` (Ollama runs as the `ollama` Docker service inside the Compose network).

---

## Cloud Deployment (on-demand GPU)

For teams without a local GPU, the stack can run on a **Scaleway L4 GPU instance
that is created and fully deleted on demand**, so compute is billed only while
you are actually coding. A small persistent block volume keeps the Ollama
models, Postgres and Qdrant data between sessions; the server, its boot disk and
its public IP are deleted when you stop.

- **Up / Down / Status** are GitHub Actions buttons (`workflow_dispatch`) plus
  `make cloud-up` / `make cloud-down` / `make cloud-status`.
- Lifecycle logic lives in `deploy/scaleway/cloud.sh`; the on-server bootstrap
  (mount volume, point Docker's data-root at it, clone, run `setup.sh`) is in
  `deploy/scaleway/bootstrap.sh`; the GPU override for Ollama is
  `deploy/scaleway/docker-compose.gpu.yml`.
- Full setup (Scaleway API keys, SSH key, submodule token, secrets) and daily
  usage are documented in **[`deploy/scaleway/README.md`](../../deploy/scaleway/README.md)**.

## Operational Notes

- Root Compose warning about `version` was removed from `docker-compose.yml`.
- On Apple Silicon macOS, `setup.sh` and `make app-up` automatically detect host Ollama (port 11434), update `.env` to route through `host.docker.internal:11434`, and stop the Docker Ollama container to conserve unified memory.
- On Linux GPU hosts, NVIDIA Persistence Mode must be enabled via `sudo nvidia-smi -pm 1`.
- For secure deployments, move secrets (API keys, DB credentials) to environment files or secret managers.

## Development Workflow

- Backend code: `backend/app`
- Run backend tests/checks as available per module
- Keep API changes documented in `backend/README.md`
- `test_env.py`: utility for validating float environment variable parsing (e.g. `OLLAMA_TIMEOUT_SECONDS`)

## Working with Submodules

> ⚠️ **All submodule commands must be run from the monolith root** (`meetingmind-ai/`), never from inside a submodule directory.

### First-time setup (after clone or pull)

Initialize and download all submodule contents:

```bash
git submodule update --init --recursive
```

Or clone with submodules in one step:

```bash
git clone --recurse-submodules https://github.com/MeetingMind-AI/meetingmind-ai.git
```

### Pull the latest changes from each subrepo

Fetch the latest `main` branch commits from each submodule's remote:

```bash
git submodule update --remote
```

### Commit and push updated submodule pointers

After pulling subrepo updates, the monolith tracks new commit hashes. Commit and push them:

```bash
git add backend frontend vexa
git commit -m "Update submodules to latest commits"
git push origin main
```

### One-command sync alias (optional)

Set up a git alias to pull, commit, and push submodule updates in one step:

```bash
git config --global alias.sync-modules '!git submodule update --remote && git add . && git commit -m "Auto-synced submodules to latest commits" && git push origin main'
```

Then run from the monolith root:

```bash
git sync-modules
```
