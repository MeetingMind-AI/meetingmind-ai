# Meeting Report Email

## Goal

After a meeting is processed and its summary is available, team members can send an HTML email report directly from the **Review** page. The report is generated server-side from the meeting summary and action items, previewed inline via an iframe, and delivered through the **Resend HTTP API**.

> **Why Resend instead of SMTP?** Cloud VM providers (AWS, GCP, Hetzner, etc.) block outbound SMTP ports (587, 465) at the network level to prevent spam. Direct SMTP connections fail silently regardless of credentials. Resend exposes an HTTPS API that is never blocked.

---

## How It Works

```
Review Page (completed meeting)
        │
        │  GET /api/meetings/{id}/email-preview
        ▼
   backend: build_email_html(meeting, actions)
        │
        │  returns { html: "<full HTML string>" }
        ▼
   iframe (srcdoc) renders the preview inline
        │
        │  user selects recipients (team member checkboxes)
        │
        │  POST /api/meetings/{id}/send-email
        │  body: { recipient_ids: [1, 2, 3] }
        ▼
   backend: resolves emails from DB, calls Resend API
        │
        │  POST https://api.resend.com/emails
        │  Authorization: Bearer <RESEND_API_KEY>
        ▼
   team members receive the HTML email
```

---

## Email Structure

The HTML email is generated entirely in Python using f-strings with inline CSS (required for email client compatibility). It renders in Gmail, Outlook, and Apple Mail.

| Section | Source field |
|---|---|
| **Executive Summary** | `summary.scrum_master.summary` |
| **Technical Decisions** | `summary.tech_lead.technical_decisions` + `architecture` |
| **Business Decisions** | `summary.product_manager.feature_requests` + `ux_topics` + `roadmap_alignment` |
| **Action Items** | `agent_actions` where `action_type = to_do` and `status != rejected` |
| **Parking Lot** | `agent_actions` where `action_type = parking_lot` and `status != rejected` |
| **To Schedule** | `agent_actions` where `action_type = to_schedule` and `status != rejected` |

Sections are skipped if the underlying data is empty or null — the email is always compact and relevant.

Action items display colour-coded status badges:
- **Approved** (green) — `status: accepted`
- **Suggestion** (amber) — `status: pending`

---

## Files Changed

### New files

| File | Purpose |
|---|---|
| `backend/app/engine/email_service.py` | `build_email_html(meeting, actions)` — generates the full HTML string. `send_meeting_email(to_emails, subject, html)` — POSTs to Resend API via `httpx`. |

### Modified files

| File | What changed |
|---|---|
| `backend/app/main.py` | Added `GET /api/meetings/{id}/email-preview` and `POST /api/meetings/{id}/send-email` endpoints; added `EmailSendRequest` Pydantic model. |
| `frontend/src/api.js` | Added `getEmailPreview(meetingId)` and `sendMeetingEmail(meetingId, recipientIds)`. |
| `frontend/src/pages/Review.jsx` | Added email section at the bottom of the Review page: collapsible iframe preview, recipient checkbox dropdown, Send button. |
| `frontend/src/pages/Review.css` | Added `rv-email-*` CSS classes for the email section. |
| `docker-compose.yml` | Added `RESEND_API_KEY` and `EMAIL_FROM` env vars to the `backend` service. |

---

## API Endpoints

### `GET /api/meetings/{meeting_id}/email-preview`

Returns the full HTML string of the email without sending it. Used to populate the iframe preview on the Review page.

**Response:**
```json
{ "html": "<!DOCTYPE html>..." }
```

### `POST /api/meetings/{meeting_id}/send-email`

Sends the email to the selected recipients.

**Request body:**
```json
{ "recipient_ids": [1, 2, 3] }
```

**Response:**
```json
{ "ok": true, "sent_to": ["alice@team.com", "bob@team.com"] }
```

Both endpoints require the caller to be an authenticated team member (`mm_session` cookie).

---

## Environment Variables

Add to `.env` at the repo root (never committed — listed in `.gitignore`):

```env
RESEND_API_KEY=re_xxxxxxxxxxxxxxxxxxxx
EMAIL_FROM=MeetingMind <noreply@yourdomain.com>
```

These are injected into the `backend` container via `docker-compose.yml`:

```yaml
RESEND_API_KEY: ${RESEND_API_KEY:-}
EMAIL_FROM: ${EMAIL_FROM:-MeetingMind <onboarding@resend.dev>}
```

If `RESEND_API_KEY` is empty the send endpoint raises a `RuntimeError`. If `EMAIL_FROM` is not set, the fallback sender `onboarding@resend.dev` is used (Resend's shared test address — functional but shows as Resend's domain).

---

## Setting Up Resend

### 1. Get an API key

Sign up at [resend.com](https://resend.com) → **API Keys** → Create key. Free tier: **100 emails/day**, **3 000 emails/month**.

### 2. Verify your domain (optional but recommended)

Without domain verification, emails send from `onboarding@resend.dev`. To send from your own address:

1. Go to **Resend → Domains → Add Domain** and enter your domain (e.g. `zinberlabs.com`).
2. Add the DNS records shown by Resend to your DNS provider:

| Type | Name | Value |
|---|---|---|
| TXT | `resend._domainkey` | DKIM public key (provided by Resend) |
| MX | `send` | `feedback-smtp.us-east-1.amazonses.com` |
| TXT | `send` | `v=spf1 include:amazonses.com ~all` |

3. Click **Verify** in Resend. Propagation takes a few minutes to up to 24 hours.
4. Update `.env`:
   ```env
   EMAIL_FROM=MeetingMind <noreply@zinberlabs.com>
   ```
5. Restart the backend: `docker compose up -d backend`

---

## Frontend: Review Page Email Section

The email section lives **inside** the `rv-content` container (after the transcript section) so it inherits the `max-width: 1200px` layout of all other Review sections.

**Collapsed state (default):**
- 200 px tall iframe preview with a fade-out gradient at the bottom
- "Expand" / "Collapse" toggle button
- Recipient dropdown (checkboxes, all members pre-selected)
- "Send Report" button

**Expanded state:**
- Full-height iframe (720 px) — no scrollbar, full email visible
- Same controls below

The recipient dropdown uses `useRef` and a click-outside listener, matching the pattern of `MeetingTopicTags.jsx`.

The **"Email Team"** quick-action button in the Review header scrolls the section into view (`scrollIntoView({ behavior: 'smooth' })`).

---

## Known Limitations

- **Free tier rate limit:** 100 emails/day on Resend free plan. Exceeding this returns a `429` error from the Resend API, surfaced as an error message below the Send button.
- **Domain reputation:** Without a verified custom domain, emails may land in spam. Verifying `zinberlabs.com` and warming up the domain resolves this.
- **No scheduling:** Emails are sent immediately on button click. There is no queue or retry logic.
- **Recipients must have emails in the DB:** The endpoint fetches emails from the `users` table. Team members without a registered email address are silently skipped.
