# Getting Meeting Info from Vexa

MeetingMind uses [Vexa](https://vexa.ai) as the bot service that joins Google Meet and Teams sessions to capture audio and transcripts. At the end of each meeting, we also pull structured metadata from Vexa — specifically who was in the room.

---

## Who Are the Speakers?

The field is called **speakers** (not participants) because Vexa populates it from the platform's speaker/audio detection system. When the bot joins a meeting, it tracks who is actively recognized in the room via WebRTC events. This means:

- **Google Meet and Teams both support this** — Vexa exposes a `data.participants` field in its `/meetings` API response, which contains the names of everyone Vexa detected.
- **It includes silent attendees** — the list is not limited to people who spoke; anyone the platform surfaced to the bot counts.
- **System entries are filtered out** — Teams sometimes injects entries like `"Meeting audio"` into the list. These are stripped before storing.

The column was named `speakers` to better reflect the actual source of truth (Vexa's audio/speaker tracking layer) and to distinguish it from a strict "invited attendees" list which we don't have access to.

---

## How the Sync Works

When a meeting ends — either by the user clicking **End Meeting** or the bot being removed — the backend runs a finalization flow in the background:

1. The Vexa bot is stopped (`DELETE /bots/{platform}/{native_id}`)
2. The final transcript is fetched from Vexa
3. Speakers are fetched from Vexa's `/meetings` endpoint
4. The AI final report is generated

Step 3 uses a **retry strategy with progressive delays**:

| Attempt | Wait before trying |
|--------:|-------------------|
| 1st | 2 seconds |
| 2nd | 8 seconds |
| 3rd | 20 seconds |

The reason for retrying is that Vexa may not have finalized the meeting record immediately after the bot stops. The first attempt often succeeds, but short or abruptly ended meetings sometimes need the extra wait. If all three attempts return an empty list, we give up and leave the field empty — it can be backfilled later if needed.

---

## Why We Can't Get the Meeting Title

Vexa's `/meetings` API response has no title or room name field. We checked every field across 105 historical meetings on both Google Meet and Teams — there is no meeting name anywhere in the payload.

The title MeetingMind currently stores is auto-generated as `{platform}:{native_meeting_id}` (e.g. `google_meet:abc-defg-hij`), which is stripped to just the native ID when shown in the UI. Users can rename meetings manually from the dashboard.

It's possible Vexa exposes meeting names through a different endpoint or a newer version of the API that wasn't explored. Worth revisiting if Vexa releases updated documentation or if the use case becomes critical.

---

## Backfilling Past Meetings

When the `speakers` column was first added, a one-time backfill script was run to populate existing meetings using the same Vexa `/meetings` endpoint. About 50% of historical meetings had speaker data available; the rest were too old or too short for Vexa to have captured anyone.
