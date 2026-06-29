# Signaling Failover System — Setup Guide

## How It Works

```
App / Extension
      │
      ▼
┌─────────────────────────────────────────────┐
│  Cloudflare Worker  (sync-signal.*.workers.dev) │
│                                             │
│  1. Health-check VM  (2 s timeout)         │
│  2a. VM is UP   → proxy to VM              │
│  2b. VM is DOWN → proxy to Render          │
└─────────────────────────────────────────────┘
      │                     │
      ▼                     ▼
 GCP VM :3001         Render Free Tier
 (primary)            (automatic fallback)
```

The app and extension only ever talk to the **one stable Cloudflare Worker URL**.
When the VM goes offline, the Worker silently routes to Render — zero rebuilds, zero downtime.

---

## One-Time Setup (do this once, now)

### Step 1 — Fill in your Render URL

Open [`cloudflare-proxy/wrangler.toml`](file:///c:/Synchronization/cloudflare-proxy/wrangler.toml) and replace the placeholder:

```toml
RENDER_URL = "https://YOUR_APP_NAME.onrender.com"   # ← put your real Render URL here
```

Also uncomment and fill in your Cloudflare Account ID:

```toml
account_id = "PASTE_YOUR_CLOUDFLARE_ACCOUNT_ID_HERE"   # ← find it at dash.cloudflare.com
```

> [!TIP]
> Your Cloudflare Account ID is shown in the right sidebar of any page on dash.cloudflare.com.

---

### Step 2 — Deploy the Cloudflare Proxy Worker

```bash
cd cloudflare-proxy
npx wrangler login        # opens browser — log in to your Cloudflare account (first time only)
npx wrangler deploy       # deploys the Worker
```

After deploy, Wrangler will print something like:

```
Published sync-signal (1.23 sec)
  https://sync-signal.YOUR_ACCOUNT.workers.dev
```

**Copy that URL.**

---

### Step 3 — Update config.json with the Worker URL

Open [`config.json`](file:///c:/Synchronization/config.json) and set `backend_url` to the Worker URL you just copied:

```json
"backend_url": "https://sync-signal.YOUR_ACCOUNT.workers.dev"
```

---

### Step 4 — Run the config updater

```bash
cd ..                    # back to project root
npm run configure        # patches all 6 files with the new URL
```

---

### Step 5 — Rebuild the app and extension (LAST TIME EVER for URL changes)

```bash
# Android app
cd mobile
flutter build apk --release

# Chrome Extension
cd ../extension
npm run build
```

Install the new APK and reload the extension. **After this, you will never need to rebuild just because the server changed.**

---

## Day-to-Day — How Failover Works Automatically

| Situation | What happens |
|-----------|-------------|
| VM is running normally | Worker proxies everything to VM — no latency added (30-second health cache) |
| VM goes offline | Within ≤30 seconds, Worker detects failure and routes all traffic to Render |
| VM comes back online | Within ≤30 seconds, Worker automatically switches back to VM |
| Render is also down | Requests fail (this is a total failure case — both backends are down) |

> [!NOTE]
> The health check result is cached for **30 seconds** inside the Cloudflare Worker's V8 isolate.
> This means there's at most a 30-second window where the Worker might try to hit a just-died VM
> before switching to Render. During that window, Socket.IO will reconnect automatically.

---

## When VM Credits Run Out (Future)

**You don't need to do anything.** The Worker will detect the VM is down and route to Render automatically.

If you want to make Render the permanent primary (instead of waiting for health checks):

1. Open `wrangler.toml`, swap `VM_URL` and `RENDER_URL` values
2. Run `npx wrangler deploy` from the `cloudflare-proxy/` directory

That's it. No app rebuild needed.

---

## When You Start a New VM (Future)

1. Update `config.json` → `backend_url` = new VM IP/URL
2. Run `npm run configure` (updates `wrangler.toml` VM_URL automatically)
3. Run `npx wrangler deploy` from `cloudflare-proxy/`

No app rebuild needed — the app still points to the same Worker URL.

---

## Files Created / Changed

| File | What it does |
|------|-------------|
| [`cloudflare-proxy/worker.js`](file:///c:/Synchronization/cloudflare-proxy/worker.js) | The Worker proxy script |
| [`cloudflare-proxy/wrangler.toml`](file:///c:/Synchronization/cloudflare-proxy/wrangler.toml) | Deployment config (fill in account_id + RENDER_URL) |
| [`config.json`](file:///c:/Synchronization/config.json) | Updated with proxy transition notes |
| [`update-config.js`](file:///c:/Synchronization/update-config.js) | Now also patches `wrangler.toml` VM_URL |
