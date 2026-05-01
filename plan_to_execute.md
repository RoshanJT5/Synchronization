# Syncronization — Master Execution Plan

> **Last Revised**: 2026-05-01  
> **Website**: https://syncronization.vercel.app  
> **Purpose**: Authoritative, ground-truth plan for all remaining and completed work. Written
> so any agent — low or high parameter — can open this file and understand exactly what has
> been done, what still needs doing, and **why** each decision was made.

---

## 📐 Architecture Overview

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                        SYNCRONIZATION SYSTEM                                 │
│                                                                              │
│  ┌─────────────────────┐      HTTPS      ┌─────────────────────────────────┐│
│  │  Chrome Extension   │ ─────────────► │   Cloud Signaling Server        ││
│  │  (sends tab audio)  │ ◄───────────── │   syncronization.vercel.app     ││
│  └─────────────────────┘    signaling   └─────────────────────────────────┘│
│           │                                            ▲                    │
│           │  Direct P2P WebRTC (after handshake)       │ HTTPS signaling    │
│           │  ◄──────────── Audio flows here ──────────►│                    │
│           ▼                                            │                    │
│  ┌─────────────────────┐                    ┌──────────┴──────────────────┐ │
│  │   Android App       │ ─────────────────► │  Mobile WebRTC Receiver     │ │
│  │   (plays audio)     │                    │  (flutter_webrtc)           │ │
│  └─────────────────────┘                    └─────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Why Cloud Signaling (Not Local / Bluetooth)
| Approach | Verdict | Reason |
|----------|---------|--------|
| Local IP (`192.168.1.5:3001`) | ❌ BROKEN | Windows Firewall blocks port 3001. Requires user to manually open firewall rules. Not viable for end-users. |
| Bluetooth | ❌ NOT SUITABLE | Browser extensions cannot access Bluetooth hardware. Max 350 kbps = audible quality loss for music. Requires manual phone pairing. |
| Cloud Signaling (Vercel) | ✅ CORRECT | Works through any firewall. Zero user configuration. After 2-second handshake, audio is P2P (cloud not in audio path). Industry-standard approach (Google Cast, AirPlay 2). |

### Brand Design Tokens (All UI must use these)
| Token | Value | Usage |
|-------|-------|-------|
| Accent Purple | `#a855f7` | Buttons, focus borders, quality indicators, sliders |
| Deep Purple | `#7c3aed` | Gradient ends, pressed states |
| Background | `#030303` | App/extension background |
| Card Surface | `#0f0f12` | Card backgrounds |
| Elevated Surface | `#16161a` | Input fields, secondary cards |
| Border | `rgba(255,255,255,0.08)` | All borders |
| Text Primary | `#f8fafc` | Headings, labels |
| Text Dim | `#94a3b8` | Subtitles, placeholders |
| Success Green | `#22c55e` | Connected state, excellent signal |
| Error Red | `#ef4444` | Error state, poor signal |

---

## ✅ Progress Tracker — What Is Already Done

These tasks were completed in the current session. **Do NOT redo them.**

| Task | Status | Files Changed |
|------|--------|---------------|
| Fix extension `SIGNALING_SERVER` URL | ✅ Done | `extension/src/offscreen.ts` line 6 |
| Fix extension `CONNECT_PAGE_URL` | ✅ Done | `extension/src/App.tsx` line 6 |
| Fix extension default `mobileServerUrl` | ✅ Done | `extension/src/App.tsx` line 15 |
| Remove manual IP input field from extension UI | ✅ Done | `extension/src/App.tsx` lines 150–159 |
| Add "Cloud Relay Active" badge to extension | ✅ Done | `extension/src/App.tsx` |
| Rebuild extension (`npm run build`) | ✅ Done | `extension/dist/` updated |
| Add `ConnectionQuality` enum | ✅ Done | `mobile/lib/services/webrtc_service.dart` line 13 |
| Add volume state and `setVolume()` method | ✅ Done | `mobile/lib/services/webrtc_service.dart` lines 26–35, 268–272 |
| Add RTT stats polling timer | ✅ Done | `mobile/lib/services/webrtc_service.dart` lines 231–266 |
| Add volume slider to connected view | ✅ Done | `mobile/lib/screens/home_screen.dart` |
| Add quality indicator to connected view | ✅ Done | `mobile/lib/screens/home_screen.dart` |
| Update `home_screen.dart` fallback URL | ✅ Done | `mobile/lib/screens/home_screen.dart` line 57 |
| Delete 1.67 GB heap dump file | ✅ Done | `mobile/android/java_pid11512.hprof` removed |
| Delete conflicting `settings.gradle` | ✅ Done | `mobile/android/settings.gradle` removed |
| Remove duplicate Kotlin package folder | ✅ Done | `com/syncronization/syncronization/` removed |
| Update `.gitignore` | ✅ Done | `C:\Syncronization\.gitignore` |
| Fix stray `}` brace bug in `webrtc_service.dart` | ✅ Done | Line 273 removed |
| Flutter `clean` + `pub get` | ✅ Done | Dependencies resolved |
| Fix volume API (0.12.x compatibility) | ✅ Done | `webrtc_service.dart` |
| Update website content for cloud flow | ✅ Done | `web/index.html` |
| Package extension ZIP | ✅ Done | `web/downloads/syncronization-extension.zip` |
| Build release APK (arm64) | ✅ Done | `web/downloads/syncronization-app.apk` |
| Create `vercel.json` routing | ✅ Done | `web/vercel.json` |
| Fix redirect page query params | ✅ Done | `web/connect/index.html` |

---

## 🔧 Remaining Tasks

### TASK R1 — Initialize Git Repository
**Priority: HIGH — Nothing can be pushed without this**

The project at `C:\Syncronization` does not have a `.git` folder. Git commands like `git push` will fail with "not a git repository."

**Steps**:
```powershell
# From C:\Syncronization
git init
git branch -M main
```

If the project already has a remote GitHub repo, link it:
```powershell
# Replace the URL with the actual GitHub remote
git remote add origin https://github.com/YOUR_USERNAME/syncronization.git
```

If no repo exists, create one at https://github.com/new (name: `syncronization`) then run the above.

---

### TASK R2 — Push Code to GitHub
**Priority: HIGH**  
**Depends on**: TASK R1

```powershell
# From C:\Syncronization
git add -A
git status    # Review what will be committed — should see NO .hprof files
git commit -m "feat: cloud signaling via vercel, volume slider, connection quality indicator"
git push -u origin main
```

**Expected result**: All source files pushed. Total repo size should be well under 50 MB because:
- The 1.67 GB heap dump was deleted
- `extension/dist/` is in `.gitignore`
- `mobile/build/` is in `.gitignore`
- `mobile/android/.gradle/` is in `.gitignore`

---

### TASK R3 — Deploy Signaling Server to Render (Separate from Vercel Website)

**IMPORTANT ARCHITECTURAL CLARIFICATION**:

`syncronization.vercel.app` is the **static website** (HTML/CSS/JS). Vercel hosts static files and serverless functions only — it cannot run a persistent WebSocket server (Socket.IO requires persistent TCP connections, which Vercel's serverless architecture does not support).

The **signaling server** (`signaling-server/server.js`) is a Node.js Express + Socket.IO app. It must run on a platform that supports persistent connections. The correct platform is **Render** (already confirmed working) or **Railway**.

**Current correct URLs**:
| Component | URL | Platform |
|-----------|-----|----------|
| Website (static) | `https://syncronization.vercel.app` | Vercel ✅ |
| Signaling Server | `https://syncronization-server.onrender.com` | Render ✅ |

**The extension code was updated to point to `syncronization.vercel.app` for signaling. This is wrong and must be corrected.**

**Files to fix**:

#### R3a. `extension/src/offscreen.ts` — Line 6
```typescript
// CURRENT (may fail for WebSocket connections):
const SIGNALING_SERVER = 'https://syncronization.vercel.app';

// CORRECT:
const SIGNALING_SERVER = 'https://syncronization-server.onrender.com';
```

#### R3b. `extension/src/App.tsx` — Lines 5–6, 15
```typescript
// CURRENT:
const SIGNALING_SERVER = 'https://syncronization.vercel.app';
const CONNECT_PAGE_URL = 'https://syncronization.vercel.app/';  // ← This one is CORRECT (website)
const [mobileServerUrl, setMobileServerUrl] = useState('https://syncronization.vercel.app');

// CORRECT:
const SIGNALING_SERVER = 'https://syncronization-server.onrender.com';
const CONNECT_PAGE_URL = 'https://syncronization.vercel.app/';  // ← Keep this, website is on Vercel
const [mobileServerUrl, setMobileServerUrl] = useState('https://syncronization-server.onrender.com');
```

#### R3c. `mobile/lib/screens/home_screen.dart` — Line 57
```dart
// CURRENT:
final server = uri.queryParameters['server'] ?? 'https://syncronization.vercel.app';

// CORRECT:
final server = uri.queryParameters['server'] ?? 'https://syncronization-server.onrender.com';
```

After edits, rebuild the extension:
```powershell
cd C:\Syncronization\extension
npm run build
```

**Verification**: Open `https://syncronization-server.onrender.com/socket.io/?EIO=4&transport=polling`  
If it returns a string starting with `0{`, the server is live. If it times out (Render free tier sleeps after 15 minutes of no traffic), wait 30 seconds and retry — it cold-starts automatically.

---

### TASK R4 — Run Mobile App and Test End-to-End Connection
**Priority: HIGH**  
**Depends on**: TASK R3 complete, phone connected via USB

```powershell
# From C:\Syncronization\mobile
flutter run --android-skip-build-dependency-validation
```

**Test flow**:
1. Open the Chrome extension popup
2. Verify it shows "Cloud Relay Active" badge (not an IP input)
3. Click **Start Streaming**
4. Scan the QR code with the Android app
5. Connection should establish within 3–5 seconds
6. Audio should play through the phone speaker
7. Verify the **volume slider** appears when connected
8. Verify the **quality dot** appears and shows MEASURING… → EXCELLENT/GOOD

**Success criteria**: No `SocketException` or `Connection refused` errors in the logs.

---

### TASK R5 — Build and Upload Android APK for Website Download
**Priority: MEDIUM**

The website at `syncronization.vercel.app` has a "Download APK" button. This button checks for a file at `web/downloads/syncronization-app.apk`. If the file is missing, the button shows "APK not uploaded yet."

**Steps**:

1. Build the release APK:
```powershell
# From C:\Syncronization\mobile
flutter build apk --split-per-abi --android-skip-build-dependency-validation
```

Output files will be at:
```
mobile/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk  ← Use this one (modern phones)
mobile/build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk
mobile/build/app/outputs/flutter-apk/app-x86_64-release.apk
```

2. Copy the ARM64 APK to the website downloads folder:
```powershell
# From C:\Syncronization
Copy-Item "mobile\build\app\outputs\flutter-apk\app-arm64-v8a-release.apk" `
          "web\downloads\syncronization-app.apk"
```

3. Commit and push to trigger Vercel redeploy:
```powershell
git add web/downloads/syncronization-app.apk
git commit -m "feat: add Android APK v1.0.0"
git push origin main
```

> [!NOTE]
> If the APK exceeds GitHub's 100 MB file size limit, use Git LFS:
> ```powershell
> git lfs install
> git lfs track "*.apk"
> git add .gitattributes
> ```
> Or upload the APK directly to Vercel Blob Storage / an S3 bucket and update the download link in `web/index.html`.

---

### TASK R6 — Configure Vercel for Custom Routing (Connect Page)
**Priority: LOW**

The website has a `/connect` subdirectory that serves the deep-link redirect page (the page that opens when a user scans the QR code from the extension).

Verify `vercel.json` or `netlify.toml` correctly routes `/connect/*` requests. Check `web/connect/index.html` exists and that Vercel serves it.

Currently a `netlify.toml` exists at the root — if deploying to Vercel, ensure a `vercel.json` is created with equivalent routing:

```json
{
  "rewrites": [
    { "source": "/connect/(.*)", "destination": "/connect/index.html" },
    { "source": "/(.*)", "destination": "/index.html" }
  ]
}
```

Place this at `C:\Syncronization\web\vercel.json` or `C:\Syncronization\vercel.json`.

---

## 📋 Final Master Checklist

### 🔴 Critical (Must Do Before App Works)
- [ ] **R1** — Initialize Git: `git init` then `git remote add origin <URL>`
- [x] **R3a** — Fix `offscreen.ts`: signaling URL → `https://syncronization-server.onrender.com`
- [x] **R3b** — Fix `App.tsx`: `SIGNALING_SERVER` and `mobileServerUrl` → Render URL
- [x] **R3c** — Fix `home_screen.dart` line 57: fallback → Render URL
- [x] **R3d** — Rebuild extension: `npm run build` in `extension/`
- [ ] **R4** — Test end-to-end: scan QR → connection → audio plays on phone

### 🟡 Important (Do After App Works)
- [ ] **R2** — Push to GitHub: `git add -A && git commit && git push`
- [x] **R5** — Build APK: `flutter build apk --split-per-abi`
- [x] **R5b** — Place APK in `web/downloads/` and push

### 🟢 Nice to Have
- [x] **R6** — Add `vercel.json` routing config for the `/connect` redirect page
- [ ] Test multi-device: scan same QR on 2 phones — both should receive audio simultaneously

---

## 🗂️ File Reference Map

| File | Purpose | Status |
|------|---------|--------|
| `extension/src/App.tsx` | Extension UI + QR generation | ⚠️ Needs R3b fix |
| `extension/src/offscreen.ts` | Extension WebRTC + Socket.IO client | ⚠️ Needs R3a fix |
| `extension/src/background.ts` | Extension service worker | ✅ Untouched |
| `mobile/lib/services/webrtc_service.dart` | Mobile signaling + WebRTC + volume + quality | ✅ Complete |
| `mobile/lib/screens/home_screen.dart` | Mobile UI with slider + quality indicator | ⚠️ Needs R3c fix |
| `mobile/lib/theme/app_theme.dart` | Brand colors — do not modify | ✅ Reference |
| `mobile/android/settings.gradle.kts` | Kotlin DSL Gradle config (Kotlin 2.2.20) | ✅ Correct |
| `mobile/android/app/src/main/kotlin/com/syncronization/app/MainActivity.kt` | Flutter Android entry point | ✅ Correct |
| `mobile/android/app/src/main/AndroidManifest.xml` | Android permissions + network config | ✅ Correct |
| `mobile/android/app/src/main/res/xml/network_security_config.xml` | Cleartext HTTP exceptions for dev | ✅ Correct |
| `signaling-server/server.js` | Node.js + Socket.IO signaling relay | ✅ Deployed on Render |
| `web/index.html` | Landing page (on Vercel) | ✅ Live |
| `web/connect/` | Deep-link redirect page | ✅ Live |
| `web/downloads/syncronization-app.apk` | Android APK (not yet uploaded) | ❌ Missing |
| `.gitignore` | Excludes build artifacts + heap dumps | ✅ Updated |

---

## 🐛 Known Bugs Fixed This Session

| Bug | Fix Applied | File |
|-----|------------|------|
| Extension QR encoded local IP `192.168.1.5:3001` | Changed `SIGNALING_SERVER` + `mobileServerUrl` to cloud URL | `App.tsx`, `offscreen.ts` |
| Mobile app tried to connect to local IP (blocked by Windows Firewall) | Updated fallback server URL in `_connectToSession()` | `home_screen.dart` |
| 1.67 GB `.hprof` file blocking `git push` | Deleted file, added `*.hprof` to `.gitignore` | Repository root |
| `settings.gradle` (Groovy) conflicting with `settings.gradle.kts` (Kotlin) | Deleted old `settings.gradle` | `mobile/android/` |
| Duplicate `com.syncronization.syncronization` Kotlin package causing unresolved references | Deleted duplicate folder | `mobile/android/app/src/main/kotlin/` |
| Stray `}` brace broke `WebRTCService` class structure | Removed extra brace at line 273 | `webrtc_service.dart` |

---

## 🔑 Key Technical Decisions

### Why Render for signaling, not Vercel?
Vercel runs serverless functions that terminate after each request. Socket.IO needs a **persistent, long-lived TCP connection**. Vercel's infrastructure kills idle connections after ~10 seconds, which will silently drop WebSocket upgrades. Render's free tier runs a real Node.js process 24/7 (with a 15-min sleep if no traffic).

### Why WebRTC not a simple audio stream to a server?
WebRTC establishes a **direct device-to-device** connection after signaling. Audio never touches the signaling server. This gives <50ms latency (typically 10–30ms on LAN) which is imperceptible. A server-relay would add at least 100–200ms and would cost bandwidth on the cloud server.

### Why `flutter_webrtc` not `just_audio`?
The audio source is a Chrome tab's MediaStream. It is transmitted as a WebRTC track. `flutter_webrtc` receives this track natively. `just_audio` plays local files or HTTP streams — it cannot consume a WebRTC track. Volume control is implemented via `RTCVideoRenderer.volume`.

---

*Maintained by: Antigravity | Project: Syncronization v1.0*
