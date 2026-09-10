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

1. **Real-Time Ingestion & Frontend WebSocket Streaming**:
   - The backend continuously polls the Vexa REST API (`poll_transcripts_from_vexa`) to fetch new speech utterances. Chunks are persisted to `transcript_chunks` with precise UTC timestamps and speaker attributions.
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

6. **Live Thinking Stream (Real-Time Persona Reasoning)**:
   - As the Tech Lead, Product Manager, and Scrum Master deliberate during initial analysis, debate rounds, and master synthesis, each agent emits intermediate step-by-step reasoning ("thoughts").
   - These cognitive reasoning packets include persona identity, current deliberation phase, UTC timestamp, and natural-language rationale.
   - Captured in real-time by the backend, thoughts are streamed to active frontend clients via WebSocket (`summary_thought` event) and persisted in an in-memory buffer queryable via `GET /api/meetings/{id}/summary-thoughts`.

7. **Lead Synthesis (Scrum Master Persona)**:
   - The Scrum Master agent consumes the raw transcript, pre-meeting historical memory, parallel initial analyses, and full multi-round debate logs.
   - Synthesizes the master JSON summary containing: meeting title, executive summary, pending-to-schedule items, parking-lot topics, and actionable to-dos with assignees and tags. Tailored prompts adjust extraction focus based on `meeting_type` (`general`, `daily_standup`, `sprint_planning`).

8. **Transcript Revision & Re-Summarization Workflow with Cancellation**:
   - Meeting participants and administrators can audit the raw transcript, fix misattributed speakers, edit erroneous ASR text, delete noisy chunks, or manually insert missed speech segments.
   - All edits preserve original utterance text and speaker identity in `transcript_chunks` (`original_text`, `original_speaker`) enabling zero-loss one-click rollback.
   - Users can trigger an on-demand re-summarization (`POST /api/meetings/{id}/resummarize`), which invalidates the stale summary, resets live thoughts, and re-executes the complete multi-agent debate pipeline against the revised transcript.
   - If a re-summarization was triggered accidentally or takes too long, users can cancel it immediately via `POST /api/meetings/{id}/stop-summary`, which halts the background asyncio task and broadcasts a `summary_stopped` event.

9. **Persistence, Vector Indexing & Email Distribution**:
   - Final JSON summary and structured debate logs are stored in PostgreSQL (`meetings.summary` and `meetings.discussion_log`).
   - Extracted decisions, technical debt, and blockers are indexed in Mem0 for future cross-meeting recall.
   - An automated, professionally styled HTML meeting report is generated and previewed via `GET /api/meetings/{id}/email-preview`. Upon confirmation, the report is dispatched via the **Resend HTTP API** (`POST /api/meetings/{id}/send-email`) directly over HTTPS (port 443), overcoming standard cloud VM outbound SMTP port blocks (ports 25/465/587).

10. **Hardware Acceleration & Host Routing Topology**:
    - **Apple Silicon macOS**: Leverages native Apple Metal acceleration by executing Ollama on the host machine and routing container traffic through `http://host.docker.internal:11434`. The Docker Ollama container is safely stopped to prevent memory duplication, allowing models like `qwen2.5:14b` and `hermes3:8b` to execute at peak unified-memory bandwidth.
    - **Linux NVIDIA GPU**: Leverages the NVIDIA Container Toolkit with `nvidia-smi -pm 1` (persistence mode enabled), dedicating 16GB+ VRAM, allocating `shm_size: 2gb` to eliminate tensor IPC bus errors, configuring `OLLAMA_NUM_PARALLEL: "2"` for concurrent persona inference, and setting `oom_score_adj: -500` to safeguard the PostgreSQL database from kernel memory termination.

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
| **Email Distribution** | Resend HTTP API | HTTPS REST (`api.resend.com`) | Cloud-friendly HTML report distribution bypassing SMTP blocks |
| **Browser Features** | Chrome Dev APIs | Document Picture-in-Picture | Floating mini-window overlay during live meetings |
| **Sensor Submodule** | Node.js / Puppeteer | Vexa Framework (Node 20+) | Headless browser bot & WebRTC audio capture |
| **Local ASR** | OpenAI Whisper | Local Whisper Weights (`small.en`) | On-premise speech-to-text transcription |

---

### 2.2 FastAPI REST API & WebSocket Streaming Structure

#### 1. Authentication Endpoints (`app/api/auth.py`)
- `POST /api/auth/signup`: User registration with bcrypt password hashing (`email`, `name`, `password`, `confirm_password`, optional `photo_b64`).
- `POST /api/auth/login`: Authenticate existing user with email and password, returning opaque cookie session tokens (`mm_session`).
- `POST /api/auth/logout`: Revoke active session token and clear HTTP-only cookie.
- `GET /api/auth/me`: Retrieve authenticated user profile (`id`, `name`, `email`, `has_photo`, `photo_url`).
- `PATCH /api/auth/me`: Update profile display name and avatar photo (`photo_b64` Base64 string, max 500 KB).
- `GET /api/auth/photo/{user_id}`: Retrieve raw profile avatar image binary data (`image/jpeg`).

#### 2. Team Workspace & Customization Endpoints (`app/api/teams.py`)
- `GET /api/teams`: List all teams that the authenticated user belongs to.
- `POST /api/teams`: Create a new team workspace.
- `GET /api/teams/{team_id}`: Retrieve team details, membership count, and active member roster.
- `PATCH /api/teams/{team_id}`: Rename team workspace (owner only).
- `POST /api/teams/{team_id}/leave`: Leave a team workspace.
- `GET /api/teams/{team_id}/invite`: Retrieve or refresh team invite token.
- `POST /api/teams/join/{invite_token}`: Join a team workspace via invite token.
- `GET /api/teams/{team_id}/members`: List team members, agile roles (`scrum_master`, `product_manager`, `team_member`), and notification preferences.
- `DELETE /api/teams/{team_id}/members/{user_id}`: Remove member from team (owner only).
- `PATCH /api/teams/{team_id}/members/{user_id}`: Update agile role (`scrum_master`, `product_manager`, `team_member`) and notification preferences JSONB array.
- `GET /api/teams/{team_id}/topics`: List team categorization topics with hex color codes.
- `POST /api/teams/{team_id}/topics`: Create a new topic label with name and hex color.
- `PATCH /api/teams/{team_id}/topics/{topic_id}`: Update topic name or hex color badge.
- `DELETE /api/teams/{team_id}/topics/{topic_id}`: Delete topic from team workspace.
- `POST /api/meetings/{meeting_id}/topics/{topic_id}`: Tag a meeting with a team topic.
- `DELETE /api/meetings/{meeting_id}/topics/{topic_id}`: Remove topic tag from meeting.
- `GET /api/teams/{team_id}/prompts`: Retrieve team prompt customization overrides.
- `PUT /api/teams/{team_id}/prompts/{prompt_key}`: Set custom persona prompt template override.
- `DELETE /api/teams/{team_id}/prompts/{prompt_key}`: Revert custom prompt to global system default.

#### 3. Meeting Lifecycle & Control Endpoints (`app/main.py`)
- `POST /api/meetings/start`: Deploy Vexa bot to meeting URL with specified `meeting_type` (`general`, `daily_standup`, `sprint_planning`).
- `POST /api/meetings/{meeting_id}/leave`: Disconnect bot and trigger background multi-agent synthesis pipeline.
- `POST /api/meetings/{meeting_id}/redispatch`: Redeploy Vexa bot to an existing meeting and resume background transcript polling and health monitoring.
- `POST /api/meetings/{meeting_id}/resummarize`: Trigger background multi-agent re-summarization on modified transcript chunks with live thought streaming.
- `POST /api/meetings/{meeting_id}/stop-summary`: Cancel active background summarization tasks and broadcast `summary_stopped` via WebSockets.
- `GET /api/meetings/{meeting_id}/summary-thoughts`: Retrieve live deliberation thoughts and reasoning emitted by Scrum Master, Tech Lead, and PM personas.
- `GET /api/meetings`: List accessible meetings with filters, topic tags, meeting type, and speaker attributions.
- `GET /api/meetings/{meeting_id}`: Retrieve detailed meeting summary, debate logs, speaker mappings, and summarization state.
- `PATCH /api/meetings/{meeting_id}`: Rename meeting title or update `meeting_type`.
- `DELETE /api/meetings/{meeting_id}`: Delete meeting record, cascading deletion to transcript chunks and action items.
- `POST /api/meetings/{meeting_id}/explain`: Generate Instant Clarity technical or business explanation for recent speech window (Redis 60s TTL cached).

#### 4. Transcript Auditing & Editing Endpoints (`app/main.py`)
- `GET /api/meetings/{meeting_id}/transcript`: Retrieve chronologically ordered transcript chunks with audit metadata (`is_edited`, `original_text`, `original_speaker`, `edited_at`).
- `PATCH /api/meetings/{meeting_id}/transcript/{chunk_id}`: Edit chunk speaker or text, preserving original version on first edit and setting `is_edited=True`, `edited_at`, `edited_by`.
- `POST /api/meetings/{meeting_id}/transcript/{chunk_id}/revert`: One-click rollback restoring raw `original_text` and `original_speaker`.
- `DELETE /api/meetings/{meeting_id}/transcript/{chunk_id}`: Delete a transcript chunk from the meeting record.
- `POST /api/meetings/{meeting_id}/transcript`: Manually insert a new transcript chunk with custom timestamp and speaker attribution.

#### 5. Action Item Kanban Endpoints (`app/main.py`)
- `GET /api/actions`: List system-wide action items categorized by type (`parking_lot`, `to_do`, `to_schedule`, `blocker`) and status (`pending`, `accepted`, `rejected`).
- `GET /api/meetings/{meeting_id}/actions`: List action items specific to a meeting grouped by category and status.
- `POST /api/meetings/{meeting_id}/actions`: Manually create action items with category (`parking_lot`, `to_do`, `to_schedule`, `blocker`), assignee user ID, tags, and status.
- `PATCH /api/meetings/{meeting_id}/actions/{action_id}`: Update action item status (`accepted`, `pending`, `rejected`), assignee ID, tags, or description content.
- `DELETE /api/meetings/{meeting_id}/actions/{action_id}`: Remove an action item.

#### 6. Email Report Distribution Endpoints (`app/main.py`)
- `GET /api/meetings/{meeting_id}/email-preview`: Render full HTML meeting summary email with inline styling for preview iframe.
- `POST /api/meetings/{meeting_id}/send-email`: Dispatch HTML meeting report to selected recipient user IDs via Resend HTTP API.

#### 7. System Diagnostics & Health Endpoints (`app/api/system.py` & `app/main.py`)
- `GET /api/system/status`: Real-time cross-platform diagnostics probing Ollama (base URL resolution, host vs container, latency, installed models, active VRAM/RAM loaded models), PostgreSQL, Redis, Qdrant, STT / Whisper Service, and host platform OS.
- `GET /health`: Basic liveness check returning standard status `{"status": "ok"}`.

#### 8. Vexa Ingress & WebSocket Streaming (`app/main.py` & `app/api/websockets.py`)
- `POST /api/vexa/webhook`: Ingress handler for Vexa bot status updates and completion webhooks (authenticated via Bearer secret header).
- `WS /api/ws/ingest/{meeting_id}`: Real-time WebSocket channel streaming transcript utterances, live agent action proposals, live summary thoughts, and completion events to frontend clients and Document PiP windows.

---

### 2.3 Relational Database Schema (PostgreSQL 15)

The database schema is defined in `backend/app/db/models.py` using SQLAlchemy 2.0 ORM:

```
+------------------+         +----------------------------+         +-------------------+
|      users       |         |      team_memberships      |         |       teams       |
+------------------+         +----------------------------+         +-------------------+
| id (PK)          | <-----+ | id (PK)                    | +-----> | id (PK)           |
| name             |         | user_id (FK)               |         | name              |
| email (Unique)   |         | team_id (FK)               |         | owner_id (FK)     |
| password_hash    |         | role (SM/PM/Member)        |         | invite_token (UQ) |
| photo (Binary)   |         | notification_preferences   |         | created_at        |
| created_at       |         |   (JSONB)                  |         +-------------------+
+------------------+         | joined_at                  |                   |
         ^                   +----------------------------+                   |
         |                                                                    |
         |                   +----------------------------+                   |
         +------------------ |          meetings          | <-----------------+
         | created_by (FK)   +----------------------------+   team_id (FK)
         |                   | id (PK)                    |
         |                   | vexa_meeting_id (UQ)       |
         |                   | title                      |
         |                   | status                     |
         |                   | meeting_type               |
         |                   | summary JSONB              |
         |                   | discussion_log JSONB       |
         |                   | speakers JSONB             |
         |                   | created_at                 |
         |                   +----------------------------+
         |                                 |
         |          +----------------------+----------------------+
         |          |                                             |
         |          v                                             v
+-----------------------------+             +-----------------------------+
|      transcript_chunks      |             |        agent_actions        |
+-----------------------------+             +-----------------------------+
| id (PK)                     |             | id (PK)                     |
| meeting_id (FK)             |             | meeting_id (FK)             |
| speaker                     |             | assignee_id (FK) -----------> (users.id)
| text                        |             | agent_role                  |
| timestamp                   |             | action_type                 |
| is_edited (Boolean)         |             | content                     |
| original_text (Text)        |             | status                      |
| original_speaker (String)   |             | tags JSONB                  |
| edited_at (DateTime)        |             +-----------------------------+
| edited_by (FK -> users.id)  |
+-----------------------------+
```

#### Detailed Table Specifications:
1. **`users`**: Stores user identity, bcrypt credentials (`password_hash`), binary profile avatars (`photo` up to 500 KB), and timestamps.
2. **`sessions`**: Manages HTTP cookie login sessions mapped to `user_id` with opaque tokens (`mm_session`).
3. **`teams`**: Represents organizational workspaces with unique `invite_token` strings and `owner_id` foreign keys.
4. **`team_memberships`**: M2M junction table mapping users to teams, enforcing `(user_id, team_id)` uniqueness. Tracks agile team roles (`scrum_master`, `product_manager`, `team_member`) and role-tailored `notification_preferences` (JSONB array of event/topic keys such as `type:blocker`, `type:to_do`, `business`, `technical`).
5. **`meetings`**: Central meeting record storing operational execution status (`pending`, `running`, `completed`, `failed`), agile mode (`meeting_type`: `general`, `daily_standup`, `sprint_planning`), `summary` (JSONB master synthesis report), `discussion_log` (JSONB cross-functional debate rounds), and `speakers` (JSONB speaker attribution list).
6. **`transcript_chunks`**: High-frequency speech utterance table recording chronologically ordered speech segments (`speaker`, `text`, `timestamp`). Features complete audit trail tracking: `is_edited` (Boolean flag), raw fallback history (`original_text`, `original_speaker`), `edited_at` (UTC timestamp), and `edited_by` (FK to `users.id`), supporting one-click rollbacks.
7. **`agent_actions`**: Stores proposals extracted by LLM personas or manually created by users (`parking_lot`, `to_do`, `to_schedule`, `blocker`), approval workflow status (`pending`, `accepted`, `rejected`), assigned team member (`assignee_id` FK to `users.id`), and flexible tag categorization (`tags` JSONB array).
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
   - Ollama parameters: `OLLAMA_NUM_PARALLEL: "2"`, `OLLAMA_MAX_VRAM: "16384"`, `OLLAMA_KEEP_ALIVE: "60s"`.
   - Docker container tuning: `shm_size: "2gb"`, `oom_score_adj: -500`.
   - Host driver setup: NVIDIA Driver 535+, NVIDIA Container Toolkit, persistence mode enabled (`nvidia-smi -pm 1`).

2. **Apple Silicon macOS Profile**:
   - Utilizes native metal acceleration by running Ollama natively on macOS host (`http://host.docker.internal:11434`).
   - Unified memory configuration permits running `qwen2.5:14b` with high token generation speeds.

3. **Windows WSL2 Profile**:
   - Executes Docker Desktop inside WSL2 Ubuntu environment with CUDA passthrough.

4. **CPU Fallback Profile**:
   - Operates entirely on host CPU using quantized models (`hermes3:8b` Q4_K_M quantization).

#### Automated Setup Script (`setup.sh`), Model Switching & Makefile Automation

The root `setup.sh` script automates environment detection, docker container initialization, Vexa sensor provisioning, database migrations, and LLM model pulling. The platform also provides hot-rebuild capabilities and interactive model-switching tooling:

```bash
# Execute standard interactive setup and cold-start bootstrap
make setup          # Or: ./setup.sh

# Non-Interactive Mode (skips prompts, ideal for CI/CD or headless VMs)
./setup.sh --non-interactive

# Rebuild stack images without cold-starting or data loss (Backend, Frontend, Vexa)
make rebuild

# Interactive AI model switcher (swaps Ollama LLMs and Whisper STT sizes in .env)
./change_models.sh

# Or manage individual stack zones via Makefile
make all            # Bootstrap full stack (Vexa sensor + Core brain platform)
make vexa-up        # Start Vexa sensor zone containers
make app-up         # Start backend, database, redis, vector DB, and frontend
make app-restart    # Restart backend and frontend containers
make status         # View container status across all stack zones
make logs           # Tail backend logs
make down           # Gracefully shut down all containers
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

### 4.1 System Diagnostic & Health Endpoints

MeetingMind-AI provides granular, real-time diagnostic probing across all underlying microservices and hardware inference layers:

- **Unified System Diagnostics (`GET /api/system/status`)**:
  Performs real-time, non-blocking asynchronous health checks across all backend subsystems and returns unified JSON telemetry:
  - **Ollama Engine**: Probes base URL (`_extract_ollama_base_url`), detects deployment environment (`host` via `host.docker.internal` vs `docker` container), checks engine version and round-trip HTTP latency, enumerates installed tags, verifies presence of configured models (`hermes3:8b`, `qwen2.5:14b`), and inspects `/api/ps` to track active VRAM/RAM model footprint.
  - **PostgreSQL Database**: Executes `SELECT 1` ping and reports query latency in milliseconds.
  - **Redis Cache & Broker**: Executes `aioredis.ping()` and reports socket latency.
  - **Qdrant Vector Database**: Queries `/healthz` and verifies semantic collection accessibility.
  - **Vexa STT Service**: Verifies Whisper transcription API connectivity (`http://transcription-api:80`).
  - **Platform Metadata**: Reports host operating system and UTC timestamp.
- **Basic Liveness Probe (`GET /health`)**:
  Lightweight health endpoint returning `{"status": "ok"}` for container orchestrators and reverse proxies.
- **Vexa Bot Ingress Status**:
  `GET http://localhost:8056/health` verifies sensor gateway status.

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
