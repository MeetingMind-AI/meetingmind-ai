# Transcript Editing, Auditing & Re-Summarization

## 1. Overview & Problem Statement

In any meeting intelligence platform, transcript accuracy is paramount. Automatic Speech Recognition (ASR) engines—even state-of-the-art models like Whisper—regularly encounter real-world challenges:
- **Jargon & Acronyms**: Misinterpretation of technical frameworks, proprietary repo names, or domain acronyms (e.g., "K8s" transcribed as "skates", "Qdrant" as "quadrant").
- **Speaker Misattribution**: Overlapping speakers or imperfect audio separation causing statements to be credited to the wrong participant.
- **Audio Dropouts**: Missed sentences due to momentary packet loss or background noise.

Traditional meeting assistants process transcripts once and bake mistakes into the final summary forever. **MeetingMind AI** introduces a complete **Transcript Auditing, Editing, and Re-Summarization Lifecycle** with zero-loss rollback, manual chunk insertion, live thought streaming, and cancellation support.

---

## 2. Architecture & Data Model

Transcript revisions and audit history are tracked directly in the PostgreSQL relational schema (`backend/app/db/models.py`):

```
+-------------------------------------------------------------------------+
|                           transcript_chunks                             |
+-------------------------------------------------------------------------+
| id                  Integer, Primary Key                                |
| meeting_id          Integer, Foreign Key -> meetings.id (CASCADE)       |
| speaker             String(120), Active speaker attribute               |
| text                Text, Active utterance text                         |
| timestamp           DateTime(timezone=True), Utterance start timestamp  |
| is_edited           Boolean, Default False (True once edited)           |
| original_text       Text, Nullable (Preserved raw speech text)          |
| original_speaker    String(120), Nullable (Preserved raw speaker)       |
| edited_at           DateTime(timezone=True), Nullable (UTC timestamp)   |
| edited_by           Integer, Foreign Key -> users.id (Nullable)         |
+-------------------------------------------------------------------------+
```

### Audit Trail Guarantees
- **Non-Destructive First Edit**: When a transcript chunk is edited for the first time, `original_text` and `original_speaker` are automatically snapshotted from their current values before changes are applied. Subsequent edits update `text` and `speaker` while preserving the immutable original raw capture.
- **Audit Metadata**: `is_edited` is set to `True`, `edited_at` records the exact UTC timestamp, and `edited_by` attributes the edit to the authenticated user ID.
- **Dynamic Speaker Synchronization**: If an utterance is reassigned to a new speaker not previously recorded, the meeting's `speakers` JSONB column in `meetings` is automatically updated to include the new participant.

---

## 3. End-to-End Workflow

```
       Raw Vexa ASR Utterance
                 │
                 ▼
     [ Persisted in PostgreSQL ]
                 │
                 ├── Reviewer edits text or speaker
                 │   (PATCH /api/meetings/{id}/transcript/{chunk_id})
                 │   ──> Snapshots original_text & original_speaker
                 │   ──> Sets is_edited = True
                 │
                 ├── Reviewer inserts missed remark
                 │   (POST /api/meetings/{id}/transcript)
                 │
                 ├── Reviewer rolls back mistake
                 │   (POST /api/meetings/{id}/transcript/{chunk_id}/revert)
                 │   ──> Restores original text & clears edit flag
                 │
                 ▼
       [ Cleaned Transcript ]
                 │
                 ▼
  Trigger Re-Summarization (POST /api/meetings/{id}/resummarize)
                 │
                 ├── Invalidates existing summary
                 ├── Emits Live Thoughts over WebSockets & /summary-thoughts
                 │   (Tech Lead, Product Manager, Scrum Master reasoning)
                 │
                 ├── Optional: Cancel mid-stream
                 │   (POST /api/meetings/{id}/stop-summary)
                 │   ──> Halts asyncio task & broadcasts summary_stopped
                 │
                 ▼
    [ Updated Master Summary & Kanban Actions ]
```

---

## 4. REST API Specification

### 4.1 Fetch Transcript with Audit Status
```http
GET /api/meetings/{meeting_id}/transcript
```
Retrieves all transcript chunks ordered chronologically by `timestamp asc`. Each chunk includes audit attributes:
```json
{
  "chunks": [
    {
      "id": 142,
      "speaker": "Sarah (Tech Lead)",
      "text": "We need to migrate the vector collection to Qdrant.",
      "timestamp": "2026-09-10T14:15:30Z",
      "is_edited": true,
      "original_text": "We need to migrate the vector collection to quadrant.",
      "original_speaker": "Speaker 2",
      "edited_at": "2026-09-10T14:22:10Z"
    }
  ]
}
```

### 4.2 Edit Transcript Chunk
```http
PATCH /api/meetings/{meeting_id}/transcript/{chunk_id}
Content-Type: application/json

{
  "speaker": "Sarah (Tech Lead)",
  "text": "We need to migrate the vector collection to Qdrant."
}
```
Requires workspace membership. On first edit, automatically copies current text and speaker into `original_text` and `original_speaker`.

### 4.3 Revert to Original Raw Utterance
```http
POST /api/meetings/{meeting_id}/transcript/{chunk_id}/revert
```
Restores `text = original_text` and `speaker = original_speaker`, setting `is_edited = false` and clearing the audit fields.

### 4.4 Delete Transcript Chunk
```http
DELETE /api/meetings/{meeting_id}/transcript/{chunk_id}
```
Permanently removes an erroneous or noisy utterance from the meeting transcript.

### 4.5 Manually Insert Transcript Chunk
```http
POST /api/meetings/{meeting_id}/transcript
Content-Type: application/json

{
  "speaker": "Dave",
  "text": "Agreed, let's benchmark memory allocation before release.",
  "timestamp": "2026-09-10T14:18:00Z"
}
```
Inserts a new utterance tagged as `is_edited = true`, updating the meeting speaker list if necessary.

---

## 5. Re-Summarization & Live Thinking Stream

### 5.1 Triggering Re-Summarization
```http
POST /api/meetings/{meeting_id}/resummarize
```
1. **Safety Check**: Cancels any already-running summarization task for this meeting.
2. **State Reset**: Clears `meeting.summary = None` so the UI immediately reflects generation in progress.
3. **Background Task**: Spawns an asynchronous task executing `ControllerAgent.generate_final_report()`.

### 5.2 Live Thinking Stream
During re-summarization, each persona emits intermediate deliberation thoughts:
- **Tech Lead**: Identifies architectural trade-offs, refactoring requirements, and technical debt.
- **Product Manager**: Analyzes feature scope, user impact, and roadmap alignment.
- **Scrum Master**: Synthesizes conflicting constraints and structures actionable items.

Thoughts are pushed immediately to all connected clients over the WebSocket:
```json
{
  "type": "summary_thought",
  "thought": {
    "agent": "tech_lead",
    "stage": "initial_analysis",
    "thought": "Examining database migration strategy from revised transcript chunk #142...",
    "timestamp": 1725974550.25
  }
}
```
Clients reconnecting mid-process can fetch all active thoughts via:
```http
GET /api/meetings/{meeting_id}/summary-thoughts
```

### 5.3 In-Flight Cancellation
```http
POST /api/meetings/{meeting_id}/stop-summary
```
If re-summarization was triggered accidentally or takes too long on constrained hardware:
1. Calls `task.cancel()` on the running asyncio background task.
2. Broadcasts `{"type": "summary_stopped", "meeting_id": 42}` over WebSockets.
3. Leaves existing meeting chunks intact, allowing the user to make further adjustments before re-running.

---

## 6. Frontend UI Walkthrough (`Review.jsx`)

On the meeting **Review** page (`frontend/src/pages/Review.jsx`):
1. **Visual Audit Indicators**: Edited utterances display an amber **"Edited"** badge. Hovering shows the original speaker and text.
2. **One-Click Revert**: Click **"Revert"** next to an edited chunk to restore the raw ASR text instantly.
3. **Manual Insertion Bar**: An **"Add Utterance"** button allows inserting comments made outside the microphone range.
4. **Re-Summarize Action**:
   - The **"Re-Summarize"** button in the header triggers `POST /api/meetings/{id}/resummarize`.
   - A live progress drawer expands, displaying the **Live Thinking Stream** with animated persona badges (`Tech Lead`, `Product Manager`, `Scrum Master`).
   - A **"Stop"** button allows terminating execution at any second.
