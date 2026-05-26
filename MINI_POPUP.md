# Mini Floating Panel — POC Documentation

Branch: `poc/mini-popup` (frontend submodule)

## Goal

Add a floating always-on-top mini panel to the Live meeting page that:
- Opens automatically when the user switches to another app or window
- Can also be opened manually via a "Pop out" button in the Live header
- Shows **Explain Technical** and **Explain Business** buttons that call the existing API
- Shows **Parking Lot** proposals captured during the meeting
- Has a **"← Transcript"** button that closes the panel and brings the main meeting window back to front

---

## API Used

**Document Picture-in-Picture API** — `documentPictureInPicture.requestWindow()`

Reference: https://developer.chrome.com/docs/web-platform/document-picture-in-picture

This extends the standard `<video>` Picture-in-Picture API to support arbitrary HTML content in an always-on-top floating window. The window floats above all other applications on the OS level — not just within the browser.

**Browser support:** Chrome 116+, Edge 116+ (confirmed working). Not available in Firefox stable or Safari. Both Chrome and Edge share the same Chromium engine, so any Chromium-based browser at version 116+ should work.

---

## Files Changed

### New files

| File | Purpose |
|---|---|
| `frontend/src/pages/MiniPipContent.jsx` | React component rendered inside the PiP window. Self-contained: manages its own explain state and listens on `BroadcastChannel` for new parking lot proposals. |
| `frontend/src/pages/MiniPopup.jsx` | Fallback route-based popup page (`/popup?meetingId=X&teamId=Y`) used when Document PiP is not available (no HTTPS). Reads initial proposals from `localStorage`. |
| `frontend/src/pages/MiniPopup.css` | Styles for both `MiniPipContent` and `MiniPopup` using the `.mp-*` class namespace. |

### Modified files

| File | What changed |
|---|---|
| `frontend/src/pages/Live.jsx` | Added `openPip()` function, `BroadcastChannel` for real-time proposal broadcasting, `window blur` listener for auto-open, "Pop out" button in the header. |
| `frontend/src/App.jsx` | Added `/popup` route (used by the `window.open()` fallback). |
| `frontend/nginx.conf` | Added HTTPS listener (`listen 443 ssl`), SSL certificate paths, and `Permissions-Policy: document-picture-in-picture=*` header. |
| `frontend/Dockerfile` | Added `openssl` step to generate a self-signed certificate at build time. Exposed port 443. |
| `docker-compose.yml` | Added port mapping `443:443` for HTTPS. |

---

## How the PiP Opening Works

```js
// Live.jsx — simplified
const pipWindow = await documentPictureInPicture.requestWindow({ width: 380, height: 560 })

// Copy all stylesheets from the opener into the PiP document
;[...document.styleSheets].forEach((sheet) => {
  try {
    const css = [...sheet.cssRules].map(r => r.cssText).join('')
    const style = document.createElement('style')
    style.textContent = css
    pipWindow.document.head.appendChild(style)
  } catch {
    // Cross-origin sheet: link by href
    const link = document.createElement('link')
    link.rel = 'stylesheet'
    link.href = sheet.href
    pipWindow.document.head.appendChild(link)
  }
})

// Render React into the PiP document using a separate root
const container = pipWindow.document.createElement('div')
pipWindow.document.body.appendChild(container)
const root = createRoot(container)  // react-dom/client

const mainWindow = window  // capture opener reference before entering PiP context
root.render(
  <MiniPipContent
    onGoBack={() => {
      pipWindow.close()
      mainWindow.focus()  // brings the Live tab back to front
    }}
  />
)

// Cleanup on PiP close
pipWindow.addEventListener('pagehide', () => { root.unmount() })
```

Key points:
- **Stylesheet copying** uses `document.styleSheets` (not `querySelectorAll`) to access parsed CSS rules. Falls back to `<link href>` for cross-origin sheets.
- **React rendering** uses `createRoot` from `react-dom/client` into the PiP document. `createPortal` was considered but rejected — events don't bubble across documents, so interactive elements require a separate React root.
- **`mainWindow.focus()`** must be captured as a closure *before* `requestWindow()` is called, because once inside the PiP context `window` refers to the PiP window.

---

## Challenge 1 — Secure Context Required

**Problem:** `documentPictureInPicture` was `undefined` even on Chrome 148.

**Root cause:** The app was accessed via `http://10.75.4.85:3000` (local network IP). Chrome only exposes the Document PiP API in a [secure context](https://developer.mozilla.org/en-US/docs/Web/Security/Secure_Contexts): `https://` or `http://localhost`. A plain HTTP network IP does not qualify.

**Solution:** Added HTTPS to the nginx/Docker stack using a self-signed certificate generated at build time.

```dockerfile
# frontend/Dockerfile
RUN apk add --no-cache openssl \
    && mkdir -p /etc/nginx/ssl \
    && openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/nginx/ssl/key.pem \
        -out /etc/nginx/ssl/cert.pem \
        -subj "/CN=meetingmind-local" \
    && apk del openssl
```

```nginx
# frontend/nginx.conf
server {
    listen 80;
    listen 443 ssl;
    ssl_certificate     /etc/nginx/ssl/cert.pem;
    ssl_certificate_key /etc/nginx/ssl/key.pem;
    ssl_protocols       TLSv1.2 TLSv1.3;
    add_header Permissions-Policy "document-picture-in-picture=*";
    ...
}
```

Chrome shows a certificate warning on first visit. Click **Advanced → Proceed to [IP] (unsafe)** once. The certificate is self-signed and for dev/POC only — not for production.

---

## Challenge 2 — Port 3443 Blocked on the Network

**Problem:** After exposing HTTPS on port `3443:443`, the browser showed "This site can't be reached" from the remote machine.

**Root cause:** Corporate/office networks often block non-standard ports. Port 3443 was unreachable despite the container and host firewall being open.

**Solution:** Changed the Docker port mapping to `443:443` (standard HTTPS port, always allowed).

```yaml
# docker-compose.yml
frontend:
  ports:
    - "3000:80"
    - "443:443"
```

Access URL: `https://10.75.4.85/teams/1/live/60` (no port number needed).

---

## Challenge 3 — Blur Event Is Not a User Gesture

**Problem:** `documentPictureInPicture.requestWindow()` requires a [transient user activation](https://developer.mozilla.org/en-US/docs/Glossary/Transient_activation) (a direct user click or key press). The `window blur` event fires when the user switches to another window, but Chrome does not treat it as user activation for the current page.

**Result:** Calling `requestWindow()` from a blur handler throws `NotAllowedError`.

**Current implementation:** The blur listener is present and calls `openPip(true)`. The `NotAllowedError` is caught silently (does not show an error to the user). Whether Chrome 148 is lenient enough to allow it depends on the exact gesture — switching windows by clicking the taskbar vs. Alt+Tab may behave differently.

**Fallback:** The "Pop out" button in the Live header always works since it is a direct click event.

```js
// Live.jsx
useEffect(() => {
  if (!parsedMeetingId) return
  const handleBlur = () => openPip(true)  // true = suppress error UI
  window.addEventListener('blur', handleBlur)
  return () => window.removeEventListener('blur', handleBlur)
}, [parsedMeetingId, openPip])
```

---

## Real-Time Proposal Updates

Parking lot proposals are broadcast from `Live.jsx` to `MiniPipContent` via the **BroadcastChannel API** on channel `meeting-{meetingId}`. This allows proposals that arrive after the PiP opens to appear in the panel.

```js
// Live.jsx — broadcasts on every new proposal
channelRef.current?.postMessage({ type: 'proposal', proposal })

// MiniPipContent.jsx — listens for new parking lot proposals
const ch = new BroadcastChannel(`meeting-${meetingId}`)
ch.onmessage = (e) => {
  if (e.data.type === 'proposal' && e.data.proposal.type === 'parking_lot') {
    setProposals(prev => [...prev, e.data.proposal])
  }
}
```

---

## window.open() Fallback

When `documentPictureInPicture` is not in `window` (non-HTTPS context), `openPip()` falls back to `window.open()` targeting the `/popup` route. Proposals at the time of opening are stored in `localStorage` under `mini-popup-{meetingId}` and read by `MiniPopup.jsx` on mount.

This fallback does **not** produce an always-on-top window.

---

## How to Run

```bash
# Build and start
cd ~/meetingmind-ai
docker compose up frontend --build -d

# Access via HTTPS (accept the self-signed cert warning once)
https://<server-ip>/teams/<teamId>/live/<meetingId>
```

---

## Known Limitations

- Self-signed certificate requires a one-time browser exception per device.
- The always-on-top behaviour is Chrome 116+ only. Other browsers get the `window.open()` popup fallback.
- Auto-open on blur (`NotAllowedError`) may not work reliably; the "Pop out" button is the guaranteed trigger.
- The `window.focus()` "back to transcript" button requires Chrome 123+ per the API spec.
