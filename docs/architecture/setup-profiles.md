# Setup Profiles

MeetingMind AI relies heavily on local Docker containers and local Ollama inference. The optimal configuration and setup commands depend on your operating system and hardware.

> For all profiles, the recommended way to bootstrap the stack is `make setup` (or `./setup.sh`), which handles environment detection, container startup, database migrations, and model pulling automatically. Manual commands are listed below for reference.

## 1. Linux (NVIDIA GPU - Recommended)

This is the production-grade deployment profile. It leverages the native NVIDIA Container Toolkit to pass your GPU directly into Docker for maximum performance on Ollama.

**Prerequisites:**
- Docker and Docker Compose installed.
- [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html) installed.

**Configuration (`docker-compose.yml`):**
Ensure the `ollama` service in your compose file is configured to use the GPU:
```yaml
ollama:
  image: ollama/ollama:latest
  deploy:
    resources:
      reservations:
        devices:
          - driver: nvidia
            count: 1
            capabilities: [gpu]
```

**Setup Commands:**
```bash
# Clone the repository with submodules
git clone --recurse-submodules https://github.com/MeetingMind-AI/meetingmind-ai.git
cd meetingmind-ai

# Run the automated setup (recommended)
make setup

# Or manually: start the stack, then pull models into the Ollama container
docker compose up -d
docker compose exec ollama ollama pull hermes3:8b
docker compose exec ollama ollama pull nomic-embed-text
```

## 2. macOS (Apple Silicon - M1/M2/M3/M4)

Docker Desktop on macOS runs inside a Linux VM with no Metal GPU passthrough. Ollama provides native macOS binaries that use Metal acceleration. For the best performance on Apple Silicon, run Ollama natively on the host and route Docker containers through `host.docker.internal`.

The automated `setup.sh` script detects Apple Silicon and handles this routing automatically. See [Apple Silicon Optimization Guide](../apple-silicon-optimization.md) for full details.

**Prerequisites:**
- Docker Desktop installed.
- [Ollama for macOS](https://ollama.com/download/mac) installed directly on your host machine.

**Configuration:**
`setup.sh` sets these values in `.env` automatically on Mac. If configuring manually:
```env
OLLAMA_URL=http://host.docker.internal:11434/api/generate
MEM0_OLLAMA_URL=http://host.docker.internal:11434
```

**Setup Commands:**
```bash
# Pull models natively on the host (not inside Docker)
ollama pull hermes3:8b
ollama pull nomic-embed-text

# Run automated setup (stops the Docker Ollama container automatically on Mac)
make setup
```

## 3. Windows (WSL2 with NVIDIA GPU)

Windows Subsystem for Linux (WSL2) natively supports GPU passthrough for Docker Desktop.

**Prerequisites:**
- Windows 11 (or Windows 10 version 21H2+).
- Docker Desktop installed with the **WSL2 backend** enabled.
- Latest NVIDIA Windows drivers (the WSL drivers are built-in).

**Configuration:**
You can use the exact same `docker-compose.yml` configuration as the **Linux** profile above. Docker Desktop handles the WSL NVIDIA runtime automatically.

**Setup Commands:**
```bash
# Open your WSL2 terminal (e.g., Ubuntu)
git clone --recurse-submodules https://github.com/MeetingMind-AI/meetingmind-ai.git
cd meetingmind-ai

make setup

# Or manually:
docker compose up -d
docker compose exec ollama ollama pull hermes3:8b
docker compose exec ollama ollama pull nomic-embed-text
```

## 4. CPU-Only (Fallback)

If you do not have a dedicated GPU or an Apple Silicon chip, you can still run the stack, but inference will be significantly slower. The quantized `hermes3:8b` (Q4_K_M) is the recommended model for CPU use.

**Configuration (`docker-compose.yml`):**
Remove the `deploy` block from the `ollama` service so Docker doesn't look for an NVIDIA driver.
```yaml
ollama:
  image: ollama/ollama:latest
  # No deploy block needed
```

**Setup Commands:**
```bash
make setup

# Or manually:
docker compose up -d
docker compose exec ollama ollama pull hermes3:8b
docker compose exec ollama ollama pull nomic-embed-text
```

*Note: In CPU-only mode, set `OLLAMA_NUM_PARALLEL: "1"` in `docker-compose.yml` to prevent context thrashing and reduce memory pressure.*
