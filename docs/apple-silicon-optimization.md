# Apple Silicon Optimization Guide

## The Problem
Docker Desktop on macOS runs containers in a Linux VM with NO Metal GPU passthrough. Ollama falls back to CPU-only, consuming all available cores and starving the Whisper transcription worker.

---

## Option A: Native Ollama (Recommended for Apple Silicon)

### How the Host URL Works
When running services inside Docker containers, `localhost` refers to the container itself, NOT your Mac host. 
Docker Desktop automatically maps the special DNS name `host.docker.internal` to your host Mac's IP address.

Since native Ollama listens on port **11434** by default on your Mac:
* **Base URL**: `http://host.docker.internal:11434`
* **Generate Endpoint**: `http://host.docker.internal:11434/api/generate`

---

### Step-by-Step Setup & Verification

#### 1. Start Native Ollama on host Mac
Ensure Ollama is running natively (either launch the Ollama app or run in terminal):
```bash
ollama serve
```

#### 2. Pull the required models natively
```bash
ollama pull hermes3:8b
ollama pull nomic-embed-text
```

#### 3. Verify native Ollama URL from host Mac
Run this curl command in your host terminal to verify native Ollama is active on port 11434:
```bash
curl http://localhost:11434/api/tags
```
*(You should get a JSON response listing `hermes3:8b` and `nomic-embed-text`)*

#### 4. Update `.env` configuration
In your project root `.env` file:
```env
OLLAMA_URL=http://host.docker.internal:11434/api/generate
MEM0_OLLAMA_URL=http://host.docker.internal:11434
```

#### 5. Verify URL connectivity from inside Docker container
To verify the container can reach your host Mac's native Ollama, run:
```bash
docker compose exec backend curl -s http://host.docker.internal:11434/api/tags
```

#### 6. Stop Docker Ollama & restart backend
```bash
# Stop CPU-heavy container
docker compose stop ollama

# Restart backend to switch to native Ollama
docker compose restart backend
```

* **Performance Boost**: ~30–45 tokens/sec on base M-series, 70–110+ tokens/sec on Pro/Max/Ultra (Metal GPU) vs 2–10 tokens/sec (Docker CPU).
* **RAM Usage**: `hermes3:8b` uses ~5GB RAM natively, shared with macOS via Unified Memory.

---

## Option B: Docker with CPU Limits (Fallback)
- The `docker-compose.yml` limits Ollama to 8 CPU cores (adjustable via `OLLAMA_CPU_LIMIT` in `.env`)
- Whisper worker limits are set in `vexa/deploy/transcription/.env` (2 cores reserved, 4 cores max by default)
- Tuning guidance by chip:
  - **M4 Pro (14 cores)**: `OLLAMA_CPU_LIMIT=8` in `.env`, `STT_CPU_LIMIT=4` in `vexa/deploy/transcription/.env`
  - **M3/M2 Pro (12 cores)**: `OLLAMA_CPU_LIMIT=6` in `.env`, `STT_CPU_LIMIT=4` in `vexa/deploy/transcription/.env`
  - **M1/M2 (8 cores)**: `OLLAMA_CPU_LIMIT=4` in `.env`, `STT_CPU_LIMIT=3` in `vexa/deploy/transcription/.env`

---

## Whisper Model Selection for CPU
- `small.en` (default): Best accuracy/speed on English meetings with 4+ CPU cores (~18x real-time)
- `base.en`: Use if constrained — faster but lower accuracy; English-only meetings only
- `medium`/`large-v3-turbo`: Only on GPU; too slow for real-time transcription on CPU
- `BEAM_SIZE=1` + `BEST_OF=1`: Approximately 5x faster with minimal WER increase (~1%)

---

## Docker Desktop Settings
- **CPU Cores**: Allocate at least 8–10 CPU cores to the Docker VM (Settings > Resources)
- **Memory**:
  - **With Native Ollama (Recommended):** Allocate **~5GB RAM** to Docker (only PostgreSQL, Qdrant, Redis, Whisper STT, and Node/FastAPI run inside Docker; Ollama runs directly on the macOS host with Metal GPU acceleration).
  - **With Docker Ollama (Fallback):** Allocate at least **10GB–12GB RAM** to Docker.
- **File Sharing**: Enable VirtioFS for faster file I/O

---

## Linux NVIDIA — No Changes Required
The existing GPU compose files remain untouched.
