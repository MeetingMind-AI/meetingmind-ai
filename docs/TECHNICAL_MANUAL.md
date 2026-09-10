# MeetingMind AI: Self-Hosted, Offline-First Multi-Agent Meeting Assistant for Agile Operations
## Technical Manual & System Architecture Specification

---

### Executive Summary & System Abstract

**MeetingMind-AI** is an academic-grade, self-hosted, offline-first multi-agent meeting assistant engineered specifically for Agile software engineering teams and university research laboratories. Modern cloud-based automated meeting tools (such as Otter.ai, Fireflies.ai, and Zoom AI Companion) introduce fundamental structural deficiencies:
1. **Privacy & Data Residency Vulnerabilities**: Transmitting raw, confidential meeting audio and proprietary codebase discussions to third-party cloud infrastructure violates enterprise security policies, academic IP non-disclosure agreements, and regulatory frameworks (e.g., GDPR, HIPAA).
2. **Contextual Loss in Single-Prompt LLMs**: Naive, single-prompt summarization algorithms compress complex technical debates into generic bullet points. They fail to represent domain-specific trade-offs between architectural technical debt and product milestone delivery schedules.
3. **Lack of Continuous Long-Term Memory**: Existing tools process each meeting in isolated silos, lacking cross-meeting memory of historical agreements, unresolved blockers, or ongoing team commitments.

MeetingMind-AI resolves these challenges through a unified, offline-first monorepo platform. The system combines local automatic speech recognition (ASR via local Whisper models), local open-weight Large Language Models (LLMs via Ollama), long-term semantic vector memory (Mem0 backed by Qdrant), and a multi-agent debate framework based on the **BOLAA** (Orchestrated Multi-Agent Discussion) paradigm.

This document serves as the official technical manual for academic evaluation, software architecture review, and deployment verification by university faculty, computer science researchers, and system administrators.

---

## 1. System Architecture & Conceptual Design

### 1.1 Dual-Zone Architectural Topology & Component Interactions

MeetingMind-AI is architected around a strict **Dual-Zone Decoupled Topology**, separating real-time audio perception sensors from core intelligence, persistent storage, and cognitive orchestration.

```
+-----------------------------------------------------------------------------------+
|                                 FRONTEND ZONE                                     |
|  React 18 SPA + Vite + Nginx Reverse Proxy (Ports 3000 / 443 SSL)                 |
|  Features: Live Meeting Dashboard, Global Action Kanban, PiP Floating Mini-Panel  |
+-----------------------------------------------------------------------------------+
                                         |
                             HTTP REST / WebSockets
                                         v
+-----------------------------------------------------------------------------------+
|                                  BRAIN ZONE                                       |
|  FastAPI Orchestration Engine (`backend/app/main.py`)                              |
|  -------------------------------------------------------------------------------  |
|  • Authentication & Multi-Tenant Access Control (`app/api/auth.py`, `teams.py`)   |
|  • Multi-Agent Cognitive Controller (`app/engine/controller.py`)                 |
|  • Vexa Gateway Client (`app/engine/vexa_client.py`)                             |
|  • Semantic Memory Bridge (`mem0` + Qdrant Vector Engine)                         |
|  • Local LLM Orchestration (`httpx` -> Ollama REST API)                           |
+-----------------------------------------------------------------------------------+
       |                  |                    |                   |
       v                  v                    v                   v
 PostgreSQL 15         Redis 7               Qdrant              Ollama
 (Relational DB)     (Cache/State)        (Vector Store)    (Local LLM Engine)
       ^                                                           ^
       |                                                           |
       +---------------------------- REST -------------------------+
                                     |
                                     v
+-----------------------------------------------------------------------------------+
|                                 SENSOR ZONE                                       |
|  Vexa Headless Bot Engine (`vexa/` submodule)                                     |
|  -------------------------------------------------------------------------------  |
|  • Headless Chromium Puppeteer Bot (Google Meet / MS Teams Ingestion)            |
|  • Local Whisper Audio Speech-to-Text & Speaker Attribution                      |
|  • Webhooks (Port 8056/8057) & Internal Gateway Interfaces                        |
+-----------------------------------------------------------------------------------+
```

#### 1. Sensor Zone (`vexa/` Submodule)
- **Headless Ingestion Bots**: Spawns containerized Node.js/Puppeteer Chromium instances to join Google Meet, Microsoft Teams, or Zoom calls as headless participants.
- **Local Audio Processing**: Captures WebRTC audio streams directly from the virtual browser context, passing raw PCM streams to local Whisper ASR models.
- **Gateway Server**: Exposes REST interfaces on port `8056` for bot lifecycle management (`POST /bots`, `DELETE /bots/{platform}/{id}`) and admin monitoring on port `8057`.

#### 2. Brain Zone (`backend/`)
- **FastAPI Core Gateway (Port 8000)**: Serves as the central API gateway managing authentication, team isolation, meeting lifecycles, and WebSocket streaming.
- **Relational Storage (PostgreSQL 15)**: Persists user credentials, team memberships, meeting metadata, structured transcript chunks, and action item records.
- **Transient State & Caching (Redis 7)**: Provides sub-millisecond session state management, real-time query caching for Instant Clarity, and pub/sub message routing.
- **Vector Memory (Qdrant + Mem0)**: Stores semantic embeddings of past meeting decisions, technical debt items, and team commitments for cross-meeting memory retrieval.
- **Local LLM Engine (Ollama on Port 11434)**: Executes open-weight LLMs (`hermes3:8b`, `qwen2.5:14b`, `nomic-embed-text`) with hardware-accelerated local inference.

---

### 1.2 Offline-First & Privacy Architecture

MeetingMind-AI is built on a **Zero-Cloud-Dependency Security Posture**. The system operates entirely within a self-contained local network boundary or air-gapped environment.

```
                    AIR-GAPPED SECURITY BOUNDARY
+--------------------------------------------------------------------+
|                                                                    |
|  +-------------------+       REST        +----------------------+  |
|  |  FastAPI Backend  | <---------------> |  Ollama LLM Engine   |  |
|  +-------------------+                   |  • hermes3:8b        |  |
|            |                             |  • qwen2.5:14b       |  |
|            |                             |  • nomic-embed-text  |  |
|            v                             +----------------------+  |
|  +-------------------+                                             |
|  |  Qdrant Vector DB | <--- Mem0 Semantic Embeddings               |
|  +-------------------+                                             |
|            |                                                       |
|            v                                                       |
|  +-------------------+                                             |
|  |   PostgreSQL 15   | <--- Encrypted Relational State             |
|  +-------------------+                                             |
|                                                                    |
+--------------------------------------------------------------------+
       X NO EXTERNAL API CALLS (OpenAI, Anthropic, AWS, Cloud STT) X
```

#### Privacy & Security Guarantees:
- **100% Local Inference**: All language generation, extraction, and debate tasks are executed via Ollama instances using open-weight models (`hermes3:8b` and `qwen2.5:14b`).
- **Local Embedding Vector Space**: Text vectorization for long-term memory utilizes `nomic-embed-text` running locally within Ollama, ensuring vector search indexes remain on-premise.
- **Local Automatic Speech Recognition**: Audio stream transcription is executed inside the Vexa container using local Whisper weights, preventing raw audio or transcripts from leaving the local host.
- **Zero Third-Party Telemetry**: Neither user data, transcripts, embeddings, nor metadata are transmitted to external endpoints.

---

### 1.3 Multi-Agent Meeting Pipeline (BOLAA Orchestration Framework)

The cognitive core of MeetingMind-AI is managed by the `ControllerAgent` (`backend/app/engine/controller.py`) implementing a multi-stage **BOLAA (Orchestrated Multi-Agent Discussion)** pipeline:

```
        Live Transcript Chunks + Pre-Meeting Mem0 Historical Context
                                   │
                                   ▼
                  ┌──────────────────────────────────┐
                  │  Step 1: Independent Analysis    │
                  │  (Parallel Agent Execution)      │
                  └────────────────┬─────────────────┘
                                   │
                 ┌─────────────────┴─────────────────┐
                 ▼                                   ▼
       ┌──────────────────┐                ┌──────────────────┐
       │    Tech Lead     │                │ Product Manager  │
       │  (Architecture & │                │  (Features, UX & │
       │  Technical Debt) │                │     Roadmap)     │
       └────────┬─────────┘                └────────┬─────────┘
                │                                   │
                └─────────────────┬─────────────────┘
                                  │
                                  ▼
                  ┌──────────────────────────────────┐
                  │  Step 2: Cross-Functional Debate │
                  │  (DiscussionEngine - N Rounds)   │
                  │  • Agreements                    │
                  │  • Challenges                    │
                  │  • Additions                     │
                  │  • Refined Positions             │
                  └────────────────┬─────────────────┘
                                   │
                                   ▼
                  ┌──────────────────────────────────┐
                  │  Step 3: Master Synthesis        │
                  │  Scrum Master (Lead Synthesizer) │
                  │  • Executive Summary             │
                  │  • Pending to Schedule           │
                  │  • Parking Lot Items             │
                  │  • Actionable To-Dos             │
                  └────────────────┬─────────────────┘
                                   │
                                   ▼
             PostgreSQL + Mem0 Vector DB + Resend HTTP Email Distribution
```

#### Pipeline Execution Stages:

1. **Real-Time Ingestion & WebSocket Streaming**:
   - Vexa streams speech utterances to the backend. Chunks are persisted to `transcript_chunks` with precise UTC timestamps and speaker attributions.
   - Real-time micro-summarization runs via the Scrum Master persona, extracting proposals (`parking_lot`, `to_do`, `to_schedule`, `blocker`) and broadcasting them live to connected clients over WebSockets (`/api/ws/ingest/{meeting_id}`).

2. **Instant Clarity Engine**:
   - Participants can query live meeting context (`POST /api/meetings/{id}/explain`) for instant technical or business clarifications of speech in the last $X$ minutes.
   - To guarantee real-time response times and minimize compute overhead, the engine employs a **Redis 60-second TTL cache**. Cache keys are constructed using SHA-256 hashes of system prompts, query parameters, and meeting transcript windows.

3. **Pre-Meeting Context Retrieval (Mem0)**:
   - Before executing post-meeting analysis, the backend queries Mem0 (`Qdrant` vector space) for historical team memories under `team_{team_id}`. Past architecture decisions and open blockers are injected into the agent prompt context.

4. **Parallel Independent Persona Analysis**:
   - **Tech Lead Persona**: Analyzes transcript strictly through an engineering lens, identifying architectural trade-offs, code refactoring requirements, technical debt, and infrastructure risks.
   - **Product Manager Persona**: Analyzes transcript from a product management perspective, extracting feature scope changes, user story requirements, release blockers, and roadmap priorities.

5. **Multi-Round Cross-Functional Debate (`DiscussionEngine`)**:
   - The agents enter an $N$-round debate ($N \ge 1$, default 1). Each agent reviews the counterpart's initial findings and responds across four structured analytical dimensions:
     - **Agreements**: Alignment points between engineering and product requirements.
     - **Challenges**: Technical infeasibility claims or scope creep objections.
     - **Additions**: Critical missing considerations uncovered during review.
     - **Refined Positions**: Updated persona recommendations reflecting counterarguments.

6. **Lead Synthesis (Scrum Master Persona)**:
   - The Scrum Master agent consumes the raw transcript, pre-meeting historical memory, parallel initial analyses, and full multi-round debate logs.
   - Synthesizes the master JSON summary containing: title, executive summary, pending-to-schedule items, parking-lot topics, and actionable to-do items with assignees and tags.

7. **Persistence, Vector Indexing & Email Distribution**:
   - Final JSON summary and structured debate logs are stored in PostgreSQL (`meetings.summary` and `meetings.discussion_log`).
   - Extracted decisions and blockers are indexed in Mem0 for future meeting recall.
   - An automated HTML meeting report is generated and sent via the Resend HTTP API to selected team members.

---

## 2. Prototype Implementation & Component Details

### 2.1 Technology Stack & Core Dependencies

| Layer | Technology / Framework | Specification / Version | Purpose |
|---|---|---|---|
| **Backend Framework** | Python / FastAPI | 3.11+, FastAPI 0.110+ | Asynchronous REST gateway & WebSocket server |
| **ORM & Migrations** | SQLAlchemy / Alembic | SQLAlchemy 2.0+, Alembic 1.13+ | Relational database ORM & schema versioning |
| **Relational Database** | PostgreSQL | 15.0+ (JSONB enabled) | Primary persistent data store |
| **Transient Caching** | Redis | 7.0+ | Sub-second caching for Instant Clarity & sessions |
| **Vector Engine** | Qdrant / Mem0 | Qdrant 1.8+, Mem0 0.1+ | Semantic long-term vector memory store |
| **Local LLM Engine** | Ollama | 0.1.30+ | Local model execution (`hermes3:8b`, `qwen2.5:14b`) |
| **Local Embeddings** | Nomic Embed Text | `nomic-embed-text` | Local vector embedding model via Ollama |
| **Frontend Framework** | React / Vite | React 18, Vite 5 | SPA interface with real-time UI components |
| **Reverse Proxy** | Nginx | 1.25+ (SSL TLS 1.3) | Secure HTTPS reverse proxy & static file host |
| **Browser Features** | Chrome Dev APIs | Document Picture-in-Picture | Floating mini-window overlay during live meetings |
| **Sensor Submodule** | Node.js / Puppeteer | Vexa Framework (Node 20+) | Headless browser bot & WebRTC audio capture |
| **Local ASR** | OpenAI Whisper | Local Whisper Weights | On-premise speech-to-text transcription |

---

### 2.2 FastAPI REST API & WebSocket Streaming Structure

#### 1. Authentication Endpoints (`app/api/auth.py`)
- `POST /api/auth/register`: User registration with bcrypt password hashing.
- `POST /api/auth/login`: User login, returning opaque cookie session tokens (`mm_session`).
- `POST /api/auth/logout`: Terminate session and invalidate cookie.
- `GET /api/auth/me`: Retrieve authenticated user profile.
- `POST /api/auth/photo`: Upload binary avatar photo (JPEG/PNG).

#### 2. Team Workspace Endpoints (`app/api/teams.py`)
- `POST /api/teams`: Create new team workspace.
- `GET /api/teams`: List user team memberships.
- `POST /api/teams/join`: Join team via unique invite token.
- `GET /api/teams/{id}/members`: List team members and assigned roles.
- `POST /api/teams/{id}/prompts`: Configure custom persona prompt overrides.

#### 3. Meeting Lifecycle & Control Endpoints (`app/main.py`)
- `POST /api/meetings/start`: Deploy Vexa bot to meeting URL and launch background transcript polling tasks.
- `POST /api/meetings/{id}/leave`: Remove Vexa bot and trigger background multi-agent synthesis pipeline.
- `GET /api/meetings`: List accessible meetings with topic tags and speaker attributions.
- `GET /api/meetings/{id}`: Retrieve detailed meeting summary and debate log.
- `PATCH /api/meetings/{id}`: Rename meeting title.
- `DELETE /api/meetings/{id}`: Delete meeting record, transcript chunks, and action items.
- `GET /api/meetings/{id}/transcript`: Retrieve chronologically ordered transcript chunks.
- `POST /api/meetings/{id}/explain`: Generate Instant Clarity technical/business explanation.

#### 4. Action Item Kanban Endpoints (`app/main.py`)
- `GET /api/actions`: List all system action items categorized by type (`parking_lot`, `to_do`, `to_schedule`) and status (`pending`, `accepted`, `rejected`).
- `GET /api/meetings/{id}/actions`: List action items specific to a single meeting.
- `PATCH /api/actions/{id}`: Update action item status or assign user.

#### 5. Vexa Ingress & Streaming (`app/main.py` & `app/api/websockets.py`)
- `POST /api/vexa/webhook`: Ingress handler for Vexa bot status updates and completion webhooks (authenticated via Bearer secret header).
- `WS /api/ws/ingest/{meeting_id}`: Real-time WebSocket channel streaming transcript utterances and live agent action proposals to active frontend clients and PiP windows.

---

### 2.3 Relational Database Schema (PostgreSQL 15)

The database schema is defined in `backend/app/db/models.py` using SQLAlchemy 2.0 ORM:

```
+------------------+         +-----------------------+         +-------------------+
|      users       |         |   team_memberships    |         |       teams       |
+------------------+         +-----------------------+         +-------------------+
| id (PK)          | <-----+ | id (PK)               | +-----> | id (PK)           |
| name             |         | user_id (FK)          |         | name              |
| email (Unique)   |         | team_id (FK)          |         | owner_id (FK)     |
| password_hash    |         | role                  |         | invite_token (UQ) |
| photo (Binary)   |         | notification_tags JSON|         | created_at        |
| created_at       |         +-----------------------+         +-------------------+
+------------------+                                                     |
         ^                                                               |
         |                   +-----------------------+                   |
         +------------------ |       meetings        | <-----------------+
         | created_by (FK)   +-----------------------+   team_id (FK)
         |                   | id (PK)               |
         |                   | vexa_meeting_id (UQ)  |
         |                   | title                 |
         |                   | status                |
         |                   | summary JSONB         |
         |                   | discussion_log JSONB  |
         |                   | speakers JSONB        |
         |                   | created_at            |
         |                   +-----------------------+
         |                               |
         |          +--------------------+--------------------+
         |          |                                         |
         |          v                                         v
+-----------------------+                         +-----------------------+
|   transcript_chunks   |                         |     agent_actions     |
+-----------------------+                         +-----------------------+
| id (PK)               |                         | id (PK)               |
| meeting_id (FK)       |                         | meeting_id (FK)       |
| speaker               |                         | assignee_id (FK) -----> (users.id)
| text                  |                         | agent_role            |
| timestamp             |                         | action_type           |
+-----------------------+                         | content               |
                                                  | status                |
                                                  | tags JSONB            |
                                                  +-----------------------+
```

#### Detailed Table Specifications:
1. **`users`**: Stores user identity, bcrypt credentials (`password_hash`), binary profile avatars (`photo`), and timestamps.
2. **`sessions`**: Manages HTTP cookie login sessions mapped to `user_id`.
3. **`teams`**: Represents organizational workspaces with unique `invite_token` strings and `owner_id` foreign keys.
4. **`team_memberships`**: M2M junction table mapping users to teams, enforcing `(user_id, team_id)` uniqueness and defining user roles (`owner`, `admin`, `member`) and notification preferences.
5. **`meetings`**: Central meeting record storing execution status (`pending`, `running`, `completed`, `failed`), `summary` (JSONB master report), `discussion_log` (JSONB debate rounds), and `speakers` (JSONB speaker attribution list).
6. **`transcript_chunks`**: High-frequency table recording chronologically ordered speech utterances (`speaker`, `text`, `timestamp`).
7. **`agent_actions`**: Stores proposals extracted by LLM agents (`parking_lot`, `to_do`, `to_schedule`), proposal approval state (`pending`, `accepted`, `rejected`), assigned team member (`assignee_id`), and category tags.
8. **`topics`**: Categorization labels with hex color codes bound to teams.
9. **`meeting_topics`**: Junction table linking meetings to topics via composite primary keys.
10. **`team_prompt_configs`**: Team-specific prompt overrides for agent roles (`tech_lead`, `product_manager`, `scrum_master`).

---

### 2.4 Vexa Headless Bot & Speech-to-Text Gateway Integration

The `vexa_client.py` module orchestrates interaction between the Brain Zone and the Vexa Sensor Zone:

1. **Bot Deployment (`start_meeting`)**:
   - Issues an HTTP `POST http://host.docker.internal:8056/bots` request with payload containing target platform (`google_meet`, `teams`), native meeting ID/URL, and optional passcode.
   - Vexa provisions a headless Chromium container that joins the call and streams audio to local Whisper instances.

2. **Real-Time Polling & Monitoring**:
   - `poll_transcripts_from_vexa`: Runs continuous background polling loops, fetching transcript increments and saving new utterances to `transcript_chunks`.
   - `monitor_meeting_until_terminal`: Monitors bot operational health and detects meeting termination events.

3. **Post-Meeting Final Synchronization**:
   - `sync_final_transcript_from_vexa`: Performs a full-fidelity transcript fetch upon meeting conclusion to capture trailing speech segments.
   - `sync_speakers_from_vexa`: Extracts speaker metadata and updates the `meetings.speakers` JSONB column.

---

### 2.5 Operational Setup & Test Verification Suites

#### Hardware Optimization & Deployment Profiles

The platform supports four deployment profiles tuned for varying hardware environments:

1. **Linux NVIDIA GPU Profile (Recommended Production Setup)**:
   - Configured in `docker-compose.yml` for dedicated GPU acceleration.
   - Ollama parameters: `OLLAMA_NUM_PARALLEL: "2"`, `OLLAMA_MAX_VRAM: "16384"`, `OLLAMA_KEEP_ALIVE: "10h"`.
   - Docker container tuning: `shm_size: "2gb"`, `oom_score_adj: -500`.
   - Host driver setup: NVIDIA Driver 535+, NVIDIA Container Toolkit, persistence mode enabled (`nvidia-smi -pm 1`).

2. **Apple Silicon macOS Profile**:
   - Utilizes native metal acceleration by running Ollama natively on macOS host (`http://host.docker.internal:11434`).
   - Unified memory configuration permits running `qwen2.5:14b` with high token generation speeds.

3. **Windows WSL2 Profile**:
   - Executes Docker Desktop inside WSL2 Ubuntu environment with CUDA passthrough.

4. **CPU Fallback Profile**:
   - Operates entirely on host CPU using quantized models (`hermes3:8b` Q4_K_M quantization).

#### Automated Setup Script (`setup.sh`) & Makefile Automation

The root `setup.sh` script automates environment detection, docker container initialization, database migrations, and LLM model pulling:

```bash
# Execute environment setup and service startup
./setup.sh

# Or manage individual stack zones via Makefile
make all        # Bootstrap full stack (Vexa sensor + Core brain platform)
make vexa-up    # Start Vexa sensor zone containers
make app-up     # Start backend, database, redis, vector DB, and frontend
make status     # View container status across all stack zones
make logs       # Tail backend logs
make down       # Gracefully shut down all containers
```

#### Test Verification Suites

The codebase includes comprehensive programmatic verification test suites:

- **`test_backend_cleanup.py`**: Validates backend module import integrity, verifies removal of legacy code, and tests core helper functionality with zero missing dependency errors.
- **`backend/scripts/test_memory.py`**: Verifies Mem0 vector memory initialization, embedding generation via `nomic-embed-text`, and Qdrant search operations.
- **`test_env.py`**: Inspects environment variable compliance and configuration keys.
- **`test_mock.py`**: Runs mock end-to-end meeting lifecycle simulations without external bot dependencies.

---

## 3. Envisioned Scenario & Agile Operations Walkthrough

### 3.1 University Computer Science Lab & Student Sprint Ceremonies

To illustrate practical utility, consider a **University Computer Science Department** operating an advanced software engineering research lab. The lab runs weekly Agile sprint ceremonies for an undergraduate capstone project developing a distributed GPU memory allocator.

#### Team Member Roles:
- **Professor / Lab Director (Agile Product Owner)**: Defines research goals, project deadlines, and external thesis requirements.
- **PhD Researcher / Senior Architect (Tech Lead persona counterpart)**: Focuses on CUDA memory management correctness, kernel performance, and technical debt.
- **Student Scrum Facilitator (Scrum Master persona counterpart)**: Tracks sprint backlog velocity, unblocks team members, and assigns tasks.
- **Student Developers (Team Members)**: Implement C++/CUDA code and unit tests.

---

### 3.2 End-to-End Workflow Execution Walkthrough

```
+-----------------------------------------------------------------------------------+
|  1. PRE-MEETING INITIALIZATION                                                    |
|  • Student Scrum Facilitator dispatches Vexa bot to Google Meet URL.               |
|  • Mem0 queries Qdrant for team memories under `team_1` (e.g., past decision on   |
|    allocator page locking).                                                       |
+-----------------------------------------------------------------------------------+
                                         │
                                         ▼
+-----------------------------------------------------------------------------------+
|  2. LIVE MEETING & INSTANT CLARITY                                                |
|  • Vexa transcribes audio in real time via local Whisper ASR.                    |
|  • Discussion turns to CUDA memory fragmentation.                                  |
|  • Student developer submits Instant Clarity query (`/explain` in technical mode).|
|  • System checks Redis cache (SHA-256 hash match) & returns instant technical     |
|    explanation of the last 5 minutes of speech.                                   |
+-----------------------------------------------------------------------------------+
                                         │
                                         ▼
+-----------------------------------------------------------------------------------+
|  3. REAL-TIME PIP TRIAGE                                                          |
|  • Real-time Scrum Master micro-summaries detect a blocker regarding benchmark    |
|    hardware availability.                                                         |
|  • Floating Picture-in-Picture window alerts participants. Facilitator clicks      |
|    "Accept" to convert proposal into an active Kanban action item.                |
+-----------------------------------------------------------------------------------+
                                         │
                                         ▼
+-----------------------------------------------------------------------------------+
|  4. POST-MEETING MULTI-AGENT DEBATE & SYNTHESIS                                    |
|  • Vexa leaves call. Background task initiates multi-agent pipeline.              |
|  • Tech Lead Agent identifies technical debt: memory pool alignment requires      |
|    refactoring before benchmarking.                                              |
|  • Product Manager Agent pushes for immediate benchmarks to meet thesis deadline. |
|  • DiscussionEngine executes 1-round debate: Tech Lead challenges PM's timeline;  |
|    PM agrees to allocate 2 days for refactoring prior to benchmarking.           |
|  • Scrum Master Agent synthesizes master JSON summary report.                      |
+-----------------------------------------------------------------------------------+
                                         │
                                         ▼
+-----------------------------------------------------------------------------------+
|  5. DISTRIBUTION & MEMORY INDEXING                                                |
|  • Master report saved to PostgreSQL (`meetings.summary`).                        |
|  • Final action items indexed into Mem0 vector space for future recall.           |
|  • Automated HTML report emailed to Professor, PhD Researcher, and Students.      |
+-----------------------------------------------------------------------------------+
```

---

### 3.3 Categorized Action Item Extraction Specifications

Action items extracted during live meetings or post-meeting synthesis are strictly categorized into four operational buckets:

1. **`parking_lot`**: Topics deferred for future meetings due to scope or time constraints (e.g., *Refactoring benchmark scripts to support multi-GPU clusters*).
2. **`to_do`**: Actionable tasks assigned to team members with concrete deliverables (e.g., *Implement CUDA custom memory pool class in `allocator.cu`*).
3. **`to_schedule`**: Follow-up discussions or review sessions requiring calendar scheduling (e.g., *Schedule code review session with PhD Lead for Friday*).
4. **`blocker`**: Critical impediments preventing progress on current tasks (e.g., *NVIDIA RTX 4090 lab server is currently undergoing OS maintenance*).

---

### 3.4 Systematic Evaluation: Single-Prompt LLM vs. MeetingMind Multi-Agent Assistant

| Architectural Dimension | Generic Single-Prompt Cloud Assistants (e.g., Otter.ai, Fireflies.ai) | MeetingMind-AI Multi-Agent Assistant |
|---|---|---|
| **Privacy & Data Residency** | Cloud-based; sensitive audio and IP uploaded to external 3rd-party servers. | **100% Offline-First**; local Whisper ASR and local LLMs (Ollama) ensure zero data exfiltration. |
| **Conflict Resolution** | Fails; compresses technical vs product disagreements into single flattened summaries. | **Multi-Persona Debate (BOLAA)**; explicit debate rounds between Tech Lead and PM agents resolve trade-offs. |
| **Technical Debt Focus** | Ignored; generic bullet points omit engineering refactoring nuances. | **Dedicated Tech Lead Persona**; explicitly identifies code smells, architectural debt, and refactoring needs. |
| **Real-Time Assistance** | Passive recording; post-hoc summary available only after call ends. | **Instant Clarity & Live PiP**; real-time Redis-cached Q&A and floating overlay for live item triage. |
| **Long-Term Memory** | Isolated per-meeting summaries without cross-meeting context retrieval. | **Mem0 + Qdrant Vector Store**; queries past decisions across meetings for continuous team context. |
| **Actionable Categorization** | Unstructured list of bullet items without clear operational scope. | **Structured Kanban Categories** (`parking_lot`, `to_do`, `to_schedule`, `blocker`) with state approvals. |
| **Operational Cost** | High recurring monthly SaaS subscription fees per user seat. | **Zero Recurring API Costs**; self-hosted infrastructure running on open-weight local models. |

---

## 4. Verification, Diagnostic Probes, & Maintenance

### 4.1 System Diagnostic Endpoints
- **Health Check**: `GET /health` returns JSON system status (`status: "ok"`, database connectivity, redis ping status).
- **Vexa Bot Ingress Status**: `GET http://localhost:8056/health` verifies sensor gateway status.

### 4.2 Database Migration Protocol (Alembic)
When modifying SQLAlchemy ORM schema in `app/db/models.py`:

```bash
# Generate new migration script
docker compose exec backend alembic revision --autogenerate -m "Add new schema field"

# Apply migration to database
docker compose exec backend alembic upgrade head
```

### 4.3 Submodule Maintenance Protocol (`update_vexa.sh`)
To sync and update the Vexa sensor zone submodule:

```bash
./update_vexa.sh
```

---

## 5. Conclusion & Academic Attestation

MeetingMind-AI demonstrates a robust, production-ready, and academically rigorous architecture for offline-first Agile meeting assistance. By combining decoupled sensor/brain topology, zero-cloud local LLM execution, multi-agent cross-functional debate, and continuous vector memory, the system overcomes the security, contextual, and architectural limitations of traditional meeting tools.
