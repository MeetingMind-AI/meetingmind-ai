# Setup Profiles

MeetingMind AI relies heavily on local Docker containers and local Ollama inference. The optimal configuration and setup commands depend on your operating system and hardware.

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

# Start the stack in detached mode
docker compose up -d

# Pull the required models into the running Ollama container
docker compose exec ollama ollama pull llama3.1
docker compose exec ollama ollama pull nomic-embed-text
```

## 2. macOS (Apple Silicon - M1/M2/M3)

Docker Desktop on macOS runs inside a Linux VM. While Docker can't directly access the Apple Neural Engine/GPU as efficiently as native apps, Ollama provides native macOS binaries that perform exceptionally well. For the best experience on macOS, run Ollama *outside* of Docker.

**Prerequisites:**
- Docker Desktop installed.
- [Ollama for macOS](https://ollama.com/download/mac) installed directly on your host machine.

**Configuration:**
1. In `docker-compose.yml`, comment out or remove the `ollama` service, as you will run it natively.
2. In your backend environment (or `.env` file), point the `OLLAMA_BASE_URL` and Mem0 configs to your host machine:
```env
# Since Docker on Mac maps the host to host.docker.internal
OLLAMA_BASE_URL=http://host.docker.internal:11434
MEM0_OLLAMA_URL=http://host.docker.internal:11434
```

**Setup Commands:**
```bash
# Run these commands in your Mac terminal (not in Docker)
ollama pull llama3.1
ollama pull nomic-embed-text

# Start the rest of the stack via Docker
docker compose up -d
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

docker compose up -d
docker compose exec ollama ollama pull llama3.1
docker compose exec ollama ollama pull nomic-embed-text
```

## 4. CPU-Only (Fallback)

If you do not have a dedicated GPU or an Apple Silicon chip, you can still run the stack, but inference will be significantly slower.

**Configuration (`docker-compose.yml`):**
Remove the `deploy` block from the `ollama` service so Docker doesn't look for an NVIDIA driver.
```yaml
ollama:
  image: ollama/ollama:latest
  # No deploy block needed
```

**Setup Commands:**
```bash
docker compose up -d
docker compose exec ollama ollama pull llama3.1
docker compose exec ollama ollama pull nomic-embed-text
```

*Note: In CPU-only mode, it is highly recommended to set `OLLAMA_NUM_PARALLEL: "1"` to prevent context thrashing.*
