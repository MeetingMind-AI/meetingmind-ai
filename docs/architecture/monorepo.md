# MeetingMind AI Monorepo Guide

## Repository Layout

- `backend/`: FastAPI backend (BOLAA controller/worker logic)
- `frontend/`: frontend application
- `vexa/`: Vexa submodule and bot services
- `docker-compose.yml`: root local orchestration for backend/frontend/data services

## Hardware & Performance Tuning (Linux + NVIDIA)

The root `docker-compose.yml` applies several Linux-specific optimizations for a 16GB NVIDIA A2 GPU:

- **VRAM utilization:** `OLLAMA_NUM_PARALLEL: "2"` is tuned for 16GB cards so the Tech Lead and Product Manager agents can run in parallel using Llama 3.1 8B (`q4_K_M`) plus `nomic-embed-text` without hitting OOM.
- **Model eviction:** `OLLAMA_KEEP_ALIVE="60s"` aggressively clears idle models from VRAM after a meeting ends, keeping host resources free.
- **Shared memory:** `shm_size: '2gb'` is set on both `ollama` and `postgres` to prevent Linux bus errors during heavy tensor mutations and database workloads.
- **OOM killer protection:** `oom_score_adj: -500` is applied to PostgreSQL so the kernel is less likely to terminate the database under RAM pressure.

## Ollama Parallel Requests

The Ollama service is configured with `OLLAMA_NUM_PARALLEL=2`, allowing it to process up to **2 concurrent inference requests** per loaded model. In this case, the TECH LEAD and PM bots can run in parallel.

Each parallel slot allocates additional GPU/CPU memory for the KV cache. For `llama3.1` (8B), expect roughly **1–2 GB of extra memory per slot**. To adjust the concurrency level, change the `OLLAMA_NUM_PARALLEL` value in `docker-compose.yml`:

```yaml
ollama:
  environment:
    OLLAMA_NUM_PARALLEL: "2"   # increase or decrease based on available memory
```

Requests beyond the parallel limit are queued automatically (up to 512 by default).

The Ollama container is capped for 16 GB VRAM with `OLLAMA_MAX_VRAM=16384` and `OLLAMA_KV_CACHE_TYPE=q8_0` in `docker-compose.yml`.

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

## Semantic Memory (Mem0)

Mem0 is wired into the final report pipeline to give cross-meeting continuity using Ollama for both LLM and embeddings (no OpenAI key required unless you reconfigure it):

- Before initial analysis, the backend searches Mem0 using the first 1000 characters of the transcript (fallback: "General agile meeting") and injects the results into the prompt context.
- After the report is generated, Tech Lead, Product Manager, and Scrum Master findings are saved into Mem0 under `user_id="team_{team_id}"` (fallback `global_team` when no team ID is provided).
- The frontend does not call Mem0 directly; memory influences the backend summaries only.
- Instant Clarity explanations are cached for 60 seconds using Redis by hashed prompt (transcript context + persona).

### Configuration

Mem0 is enabled by default and can be tuned via environment variables:

```env
MEM0_ENABLED=true
MEM0_OLLAMA_URL=http://ollama:11434
MEM0_LLM_MODEL=llama3.1
MEM0_EMBED_MODEL=nomic-embed-text
MEM0_SAVE_ENABLED=true
MEM0_SEARCH_ENABLED=true
```

To minimize GPU/VRAM contention with user-facing AI work, you can disable memory search and/or saving, or point Mem0 to a separate Ollama instance (CPU-only) via `MEM0_OLLAMA_URL`.

When using local models, Mem0 requires explicit vector dimensions. This project pins the embedding dimensions to 768 (matching `nomic-embed-text`).

### Testing Mem0

1. Ensure Ollama is running and the embedding model is pulled (`nomic-embed-text`) if you keep the defaults.
2. Complete a meeting so `generate_final_report` runs and stores memories.
3. Verify memories were stored by querying Mem0 from the backend container:

```bash
docker compose exec backend python - <<'PY'
from mem0 import Memory

config = {
    "vector_store": {
        "provider": "qdrant",
        "config": {
            "collection_name": "meetingmind",
            "embedding_model_dims": 768,
        }
    },
    "llm": {
        "provider": "ollama",
        "config": {
            "model": "llama3.1",
            "ollama_base_url": "http://ollama:11434",
            "temperature": 0.1,
        },
    },
    "embedder": {
        "provider": "ollama",
        "config": {
            "model": "nomic-embed-text",
            "ollama_base_url": "http://ollama:11434",
        },
    },
}

memory = Memory.from_config(config)
print(memory.search("Tech Lead findings", filters={"user_id": "team_1"}))
PY
```

## 🤖 Multi-Persona Discussion System

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

## Operational Notes

- Root Compose warning about `version` was removed from `docker-compose.yml`.
- For secure deployments, move secrets (API keys, DB credentials) to environment files or secret managers.

## 🤖 Vexa Submodule: Troubleshooting & Updates

Vexa is a highly integrated piece of architecture that interacts directly with our host VM. Because of this, standard Docker commands can sometimes cause unexpected issues. Follow these guides to resolve crashes and safely apply updates.

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

(Note: If Git throws a pathspec error, your fork is outdated. Sync your fork on GitHub first, or run `git fetch https://github.com/Vexa-ai/vexa.git --tags`).

#### Step 2: Update your `.env`

Compare your `vexa/.env` with `vexa/deploy/env-example` and merge any new required variables before restarting. Do not carry forward an older `.env` without adding newly introduced keys.

#### Step 3: Start Vexa

Use the Makefile for your chosen deployment mode:

```bash
make all
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

If you are running Ollama directly on the Linux host rather than inside Docker, it binds to `127.0.0.1` by default, blocking Docker containers. To fix this, edit the systemd service:

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

If the Vexa API Gateway rejects the WebSocket connection, ensure your WebSocket client passes the API key as a URL parameter rather than a header, as Python websockets can strip headers across Docker bridges: `ws://host.docker.internal:8056/ws?api_key=your_key_here`

### 4. Submodule Update Issues (Pulling on VM)

Since we just want the VM to reflect the latest pushed code from GitHub, you can discard those local changes on the VM by running this:

```bash
git submodule foreach git reset --hard
```

After doing that, run the submodule update again:

```bash
git submodule update --init --recursive
```

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
