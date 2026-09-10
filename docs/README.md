# MeetingMind AI Documentation Hub

Welcome to the central documentation hub for **MeetingMind AI**—a self-hosted, offline-first multi-agent meeting assistant engineered for Agile software engineering operations.

## Core System Specifications

- **[Technical Manual & System Architecture](TECHNICAL_MANUAL.md)**: Flagship architectural document covering the dual-zone topology, BOLAA multi-agent orchestration, PostgreSQL 15 database schema, complete REST API specification, and academic evaluation.

## Architecture & Infrastructure

- **[Monorepo Guide](architecture/monorepo.md)**: Monorepo layout, Git submodule management, hardware performance tuning, Ollama concurrency, and setup automation scripts.
- **[Backend Architecture](architecture/backend.md)**: FastAPI asynchronous REST gateway, ControllerAgent orchestration, WebSocket streaming, and background task lifecycle.
- **[Frontend Architecture](architecture/frontend.md)**: React 18 + Vite SPA design, real-time live meeting interface, Kanban boards, and Document PiP integration.
- **[System Dependencies](architecture/dependencies.md)**: Deep dive into core dependencies: Ollama LLM (`hermes3:8b`), Mem0 + Qdrant semantic memory, Vexa sensor bots, Resend HTTP email API, and Chrome Document PiP.
- **[Setup Profiles](architecture/setup-profiles.md)**: Configuration profiles for Linux NVIDIA GPU, Apple Silicon macOS, Windows WSL2, and CPU fallback.
- **[Apple Silicon Metal Optimization](apple-silicon-optimization.md)**: Native host routing via `host.docker.internal:11434` for high-throughput Metal GPU acceleration.
- **[Troubleshooting Guide](architecture/troubleshooting.md)**: Diagnostic routines for common issues across Docker, Vexa, database migrations, and Ollama model pulls.

## APIs & Integrations

- **[REST API & Database Schema](TECHNICAL_MANUAL.md#22-fastapi-rest-api--websocket-streaming-structure)**: Complete endpoints catalog across Auth, Teams, Meetings, Transcript Auditing, Action Items, Email Distribution, and System Diagnostics.
- **[Vexa Bot Ingress & Speaker Detection](api/vexa-integration.md)**: Sensor zone integration, headless Chromium bot deployment, audio ingestion, and speaker attribution.

## Feature Guides

- **[Transcript Auditing, Editing & Re-Summarization](features/transcript-editing-resummarize.md)**: Utterance editing lifecycle, audit trail (`original_text`, `original_speaker`, `edited_at`), one-click rollback, manual chunk insertion, and re-summarization with live thought streaming and cancellation.
- **[Agile Roles & Tailored Notifications](features/agile-roles-notifications.md)**: Agile team roles (`scrum_master`, `product_manager`, `team_member`), customizable notification profiles, and real-time proposal/insight filtering.
- **[Mini Floating Panel (Document Picture-in-Picture)](features/mini-popup-pip.md)**: Chrome Document PiP API integration for always-on-top meeting assistance and live proposal triage without leaving your call.
- **[Meeting Report Email Distribution](features/email-report.md)**: Automated HTML report generation and HTTPS delivery through the Resend HTTP API, overcoming cloud VM SMTP port restrictions.
