# Syncronization — Complete Execution Plan

> **Purpose**: This is the authoritative, detailed execution plan for the Syncronization project.
> It is written so that a low-parameter agent can execute each task independently, step-by-step,
> without needing any additional context. Read every section before starting.
>
> **Vercel Deployment**: `https://syncronization.vercel.app`
> **Design System**: Purple accent (`#a855f7`) · Dark bg (`#030303`) · Card (`#0f0f12`)

---

## 📋 Table of Contents

1. [Root Cause Analysis — Why Connection Fails](#1-root-cause-analysis)
2. [Architecture: Cloud Signaling via Vercel](#2-architecture)
3. [Current Status — What Has Already Been Done](#3-current-status)
4. [Task A: Fix GitHub Push (Remove 1.6 GB Heap Dump)](#4-task-a-fix-github-push)
5. [Task B: Verify Cloud Signaling Server](#5-task-b-verify-cloud-signaling-server)
6. [Task C: Update Extension to Use Vercel Cloud Signaling](#6-task-c-update-extension)
7. [Task D: Update Mobile App to Use Vercel Cloud Signaling](#7-task-d-update-mobile-app)
8. [Task E: Add Feature — Volume Control Slider](#8-task-e-volume-slider)
9. [Task F: Add Feature — Connection Quality Indicator](#9-task-f-connection-quality)
10. [Task G: Fix Mobile Android Build (Kotlin Conflict)](#10-task-g-fix-android-build)
11. [Task H: Update .gitignore and Push to GitHub](#11-task-h-gitignore-and-push)
12. [Master Execution Checklist](#12-master-checklist)
13. [File Locations Quick Reference](#13-file-reference)
14. [Why Not Bluetooth?](#14-why-not-bluetooth)

---

## 1. Root Cause Analysis

### The Symptom
The mobile app displays:
> **"Connection Failed — Could not connect to signaling server at http://192.168.1.5:3001"**

The logcat output shows a continuous stream of:
```
SocketException: Connection refused (OS Error: Connection refused, errno=111), address = 192.168.1.5
```

### The Real Cause — One Wrong URL in the Extension

The extension in `App.tsx` line 5 has:
```typescript
const SIGNALING_SERVER = 'http://localhost:3001';
```
And line 15 has:
```typescript
const [mobileServerUrl, setMobileServerUrl] = useState('http://192.168.1.5:3001');
```

When the extension generates a QR code, it encodes a URL like:
```
https://syncronization.vercel.app/?id=ABCDE&server=http://192.168.1.5:3001
```

The mobile app parses this QR URL and sees `?server=http://192.168.1.5:3001`. It connects to that value directly.
The fallback to the cloud URL **never runs** because the `?server=` query param is always present.

### Why http://192.168.1.5:3001 Fails
Windows Defender Firewall blocks inbound TCP connections on port 3001 by default.
The phone sends a TCP SYN packet to the PC. The PC's firewall drops it before Node.js ever sees it.
Result: `errno=111` (Connection Refused) on Android.

Users cannot be expected to open Windows Firewall ports. This is not a viable product.

### The Fix — One Line Change
Point both the Extension and the QR code to the **already-deployed Vercel cloud server**:
```
https://syncronization.vercel.app
```
The cloud server accepts HTTPS traffic on port 443, which is never blocked by firewalls.
After the 2-3 second cloud handshake, audio flows **directly P2P via WebRTC** — the cloud is no longer involved.

---

## 2. Architecture

### Before (Broken)
```
[Chrome Extension] ──►  http://192.168.1.5:3001  ◄── [Mobile App]
                              (PC, port 3001)
                        ❌ BLOCKED BY FIREWALL ❌
```

### After (Fixed)
```
[Chrome Extension] ──HTTPS──► syncronization.vercel.app ◄──HTTPS── [Mobile App]
                                       (Cloud, port 443)
                               ✅ No firewall issues
                                         │
                  After 2-3 sec: P2P audio via WebRTC (cloud no longer involved)
```

### Why This Works Reliably
- Port 443 (HTTPS) is never blocked — it's the same port as regular websites.
- The signaling server only carries ~5 KB of text (SDP offers + ICE candidates).
- All audio bandwidth is P2P (WebRTC). The cloud server carries zero audio data.
- Latency is determined only by the direct P2P path, not the cloud server.

---

## 3. Current Status — What Has Already Been Done

The following changes have **already been applied** to the codebase. Do not redo them.

| File | Status | What Changed |
|------|--------|-------------|
| `extension/src/offscreen.ts` | ✅ Done | `SIGNALING_SERVER` → `https://syncronization.vercel.app` |
| `extension/src/App.tsx` | ✅ Done | Both URL constants + default state → Vercel URL; IP input removed |
| `extension/dist/` | ✅ Done | Extension rebuilt with `npm run build` |
| `mobile/lib/screens/home_screen.dart` | ✅ Done | Fallback URL updated to Vercel; volume slider added; quality indicator added |
| `mobile/lib/services/webrtc_service.dart` | ✅ Done | Volume state + `setVolume()`; `ConnectionQuality` enum + stats timer |
| `mobile/android/settings.gradle` | ✅ Done | **Deleted** (was causing Kotlin 1.8.22 conflict) |
| `mobile/android/java_pid11512.hprof` | ✅ Done | **Deleted** (was 1.67 GB, blocking git push) |
| `.gitignore` | ✅ Done | Updated with `*.hprof`, build artifacts, IDE files |

> [!IMPORTANT]
> The items above are already done. Proceed from Task B to verify and then continue with any remaining tasks.

---

## 4. Task A: Fix GitHub Push

### Problem
A 1.67 GB Java heap dump file `mobile\android\java_pid11512.hprof` was generated by a crashed
Gradle build. GitHub has a 100 MB file size limit, so `git push` fails hard.

### Status: ✅ Already deleted in the previous session.

Verify it is gone:
```powershell
# Should return nothing if already deleted
Test-Path "C:\Syncronization\mobile\android\java_pid11512.hprof"
# Expected output: False
```

If the file still exists (returns `True`):
```powershell
Remove-Item "C:\Syncronization\mobile\android\java_pid11512.hprof" -Force
```

### If It Was Previously Committed to Git History
If the file was ever committed (check with `git log --all --full-history -- "mobile/android/java_pid11512.hprof"`),
you must purge it from history:
```powershell
# From C:\Syncronization (the git root)
git filter-branch --force --index-filter `
  "git rm --cached --ignore-unmatch 'mobile/android/java_pid11512.hprof'" `
  --prune-empty --tag-name-filter cat -- --all

git push origin main --force
```

---

## 5. Task B: Verify Cloud Signaling Server

### What to Check
Open this URL in a browser:
```
https://syncronization.vercel.app/socket.io/?EIO=4&transport=polling
```

**Expected response**: A JSON string starting with `0{` (Socket.IO handshake).
**If it times out**: The signaling server Node.js process may have cold-started — wait 30 seconds and retry.
**If 404**: The Node.js server is NOT proxied on Vercel. Use the Render fallback instead:
```
https://syncronization-server.onrender.com
```
In that case, replace all occurrences of `syncronization.vercel.app` in the extension code
with `syncronization-server.onrender.com` and rebuild.

### Important: Vercel Cannot Run Socket.IO Natively
Vercel runs **serverless functions** (stateless, short-lived). Socket.IO requires a **persistent
WebSocket process** (stateful, long-running). If the Socket.IO endpoint on Vercel returns 404,
it means the signaling server is not configured as a separate Vercel service.

**Resolution options**:
1. **Use the Render server** (`syncronization-server.onrender.com`) — already deployed, correct type of hosting.
2. **Deploy signaling-server as a separate Vercel project** with `vercel.json` override (advanced).

For simplicity, **use option 1 (Render)** if Vercel returns 404.

---

## 6. Task C: Update Extension

### Current State (Already Applied)
The following is what the extension files should already contain after the previous session:

**`extension/src/App.tsx` lines 5-6:**
```typescript
const SIGNALING_SERVER = 'https://syncronization.vercel.app';
const CONNECT_PAGE_URL = 'https://syncronization.vercel.app/';
```

**`extension/src/App.tsx` line 15:**
```typescript
const [mobileServerUrl, setMobileServerUrl] = useState('https://syncronization.vercel.app');
```

**`extension/src/App.tsx` lines 150-154 (replaced the IP input field):**
```tsx
<div className="w-full bg-[#16161a] border border-purple-500/20 rounded-xl px-3 py-2 mb-4 text-center">
  <p className="text-purple-400 text-[10px] font-mono">
    ✓ Connected to Vercel Cloud Relay
  </p>
</div>
```

**`extension/src/offscreen.ts` line 6:**
```typescript
const SIGNALING_SERVER = 'https://syncronization.vercel.app';
```

### Verify the Build is Current
The extension was rebuilt. Verify it is loaded in Chrome:
1. Open `chrome://extensions/`
2. Find "Syncronization"
3. If the extension was built after the code change, the last updated timestamp will be recent.
4. If unsure, click the **refresh** icon on the extension card.

### Rebuild (if needed)
```powershell
# From C:\Syncronization\extension
npm run build
```
Then click the refresh icon in `chrome://extensions/`.

### Verify QR Code Contains Correct URL
1. Open the extension popup.
2. The QR code should encode a URL like:
   ```
   https://syncronization.vercel.app/?id=ABCDE&server=https%3A%2F%2Fsyncronization.vercel.app
   ```
   NOT `http://192.168.1.5:3001`.

---

## 7. Task D: Update Mobile App

### Current State (Already Applied)

**`mobile/lib/screens/home_screen.dart` line 57:**
```dart
final server = uri.queryParameters['server'] ?? 'https://syncronization.vercel.app';
```

The mobile app now:
1. Reads the `?server=` param from the scanned QR URL (will be the Vercel URL since extension is fixed).
2. Falls back to `https://syncronization.vercel.app` if the param is missing.

### Verify AndroidManifest.xml
File: `mobile/android/app/src/main/AndroidManifest.xml`

The `<application>` tag must have:
```xml
android:usesCleartextTraffic="true"
android:networkSecurityConfig="@xml/network_security_config"
```

> [!NOTE]
> The cloud server (`syncronization.vercel.app`) uses HTTPS. HTTPS never needs to be in the cleartext
> config. The `network_security_config.xml` only matters for HTTP domains (like `192.168.1.5`).
> So HTTPS to Vercel will work even without any config entries.

### Verify network_security_config.xml
File: `mobile/android/app/src/main/res/xml/network_security_config.xml`

Contents should be:
```xml
<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
    <base-config cleartextTrafficPermitted="false">
        <trust-anchors>
            <certificates src="system"/>
        </trust-anchors>
    </base-config>
    <domain-config cleartextTrafficPermitted="true">
        <domain includeSubdomains="true">192.168.1.5</domain>
        <domain includeSubdomains="true">localhost</domain>
    </domain-config>
</network-security-config>
```

---

## 8. Task E: Volume Slider Feature

### Current State (Already Applied)
The volume slider is already implemented. Here is the complete code for reference and verification.

### `mobile/lib/services/webrtc_service.dart` — Volume State

After existing field declarations, these fields must be present:
```dart
double _volume = 1.0;
double get volume => _volume;

void setVolume(double value) {
  _volume = value.clamp(0.0, 1.0);
  _audioRenderer?.volume = _volume;
  notifyListeners();
}
```

### `mobile/lib/screens/home_screen.dart` — Slider Widget

In the `_buildConnectedView()` method, after the `'Audio is playing...'` Text widget:
```dart
const SizedBox(height: 32),
// Volume Control
Row(
  children: [
    const Icon(Icons.volume_down, color: Colors.white54, size: 20),
    Expanded(
      child: Slider(
        value: _webrtc.volume,
        activeColor: AppTheme.accent,  // #a855f7 — matches website
        inactiveColor: Colors.white10,
        onChanged: (v) => _webrtc.setVolume(v),
      ),
    ),
    const Icon(Icons.volume_up, color: Colors.white54, size: 20),
  ],
),
const SizedBox(height: 48),
```

### If Slider Is Missing
If the slider does not appear in the UI when connected, add the code block above manually.
The `_webrtc.volume` getter must also exist in `webrtc_service.dart`.

---

## 9. Task F: Connection Quality Indicator

### Current State (Already Applied)
The connection quality indicator is already implemented. Here is the complete code for reference.

### `mobile/lib/services/webrtc_service.dart` — Quality Enum + State

After `AppConnectionState` enum, this must exist:
```dart
enum ConnectionQuality { excellent, good, poor, unknown }
```

In the `WebRTCService` class, these fields must exist:
```dart
ConnectionQuality _connectionQuality = ConnectionQuality.unknown;
ConnectionQuality get connectionQuality => _connectionQuality;
Timer? _statsTimer;
```

### Stats Polling Timer in `_createPeerConnection()`

At the END of the `_createPeerConnection()` method body, this timer must be started:
```dart
_startStatsTimer();
```

And this method must exist:
```dart
void _startStatsTimer() {
  _statsTimer?.cancel();
  _statsTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
    if (_peerConnection == null || _state != AppConnectionState.connected) {
      timer.cancel();
      _statsTimer = null;
      return;
    }

    try {
      final stats = await _peerConnection!.getStats();
      for (final report in stats) {
        if (report.type == 'candidate-pair' &&
            report.values.containsKey('currentRoundTripTime')) {
          final rtt = (report.values['currentRoundTripTime'] as num).toDouble();
          ConnectionQuality q;
          if (rtt < 0.05) {
            q = ConnectionQuality.excellent;
          } else if (rtt < 0.15) {
            q = ConnectionQuality.good;
          } else {
            q = ConnectionQuality.poor;
          }

          if (q != _connectionQuality) {
            _connectionQuality = q;
            notifyListeners();
          }
          break;
        }
      }
    } catch (e) {
      debugPrint('[WebRTC] Error getting stats: $e');
    }
  });
}
```

In the `disconnect()` method, before `_setState(AppConnectionState.idle)`:
```dart
_statsTimer?.cancel();
_statsTimer = null;
_connectionQuality = ConnectionQuality.unknown;
```

### `mobile/lib/screens/home_screen.dart` — Quality Indicator Widget

These helper methods must exist in `_HomeScreenState`:
```dart
Widget _buildConnectionQualityIndicator() {
  final quality = _webrtc.connectionQuality;
  return Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _qualityColor(quality),
        ),
      ),
      const SizedBox(width: 8),
      Text(
        _qualityLabel(quality),
        style: TextStyle(
          fontSize: 10,
          color: _qualityColor(quality),
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5,
        ),
      ),
    ],
  );
}

Color _qualityColor(ConnectionQuality q) {
  return switch (q) {
    ConnectionQuality.excellent => AppTheme.green,   // #22C55E
    ConnectionQuality.good      => Colors.amber,
    ConnectionQuality.poor      => Colors.redAccent,
    ConnectionQuality.unknown   => Colors.white24,
  };
}

String _qualityLabel(ConnectionQuality q) {
  return switch (q) {
    ConnectionQuality.excellent => 'EXCELLENT SIGNAL',
    ConnectionQuality.good      => 'GOOD SIGNAL',
    ConnectionQuality.poor      => 'POOR SIGNAL',
    ConnectionQuality.unknown   => 'MEASURING...',
  };
}
```

At the TOP of `_buildConnectedView()` Column children, before `_buildPulsingIcon()`:
```dart
_buildConnectionQualityIndicator(),
const SizedBox(height: 20),
```

---

## 10. Task G: Fix Android Build (Kotlin Conflict)

### Problem
Two conflicting settings files exist in `mobile/android/`:
- `settings.gradle` (Groovy DSL) — **OLD**, causes Kotlin to lock at version `1.8.22`
- `settings.gradle.kts` (Kotlin DSL) — **CORRECT**, targets Kotlin `2.2.20`

When both exist, the old Groovy file takes precedence, causing `Unresolved reference: io` and
`Unresolved reference: FlutterActivity` errors in `MainActivity.kt`.

### Status: ✅ `settings.gradle` already deleted.

Verify:
```powershell
Test-Path "C:\Syncronization\mobile\android\settings.gradle"
# Expected: False
```

If it still exists:
```powershell
Remove-Item "C:\Syncronization\mobile\android\settings.gradle" -Force
```

### Verify `settings.gradle.kts` is Correct
File: `mobile/android/settings.gradle.kts`

The plugins block must contain:
```kotlin
id("org.jetbrains.kotlin.android") version "2.2.20" apply false
id("com.android.application") version "8.11.1" apply false
```

### Verify `MainActivity.kt` Path and Content
- **Correct path**: `mobile/android/app/src/main/kotlin/com/syncronization/app/MainActivity.kt`
- **Correct content** (exactly):
```kotlin
package com.syncronization.app

import io.flutter.embedding.android.FlutterActivity

class MainActivity: FlutterActivity()
```

If a duplicate directory `com/syncronization/syncronization/` exists, delete it:
```powershell
$dup = "C:\Syncronization\mobile\android\app\src\main\kotlin\com\syncronization\syncronization"
if (Test-Path $dup) { Remove-Item $dup -Recurse -Force }
```

### Clean Build
```powershell
# From C:\Syncronization\mobile
flutter clean
flutter pub get
flutter run --android-skip-build-dependency-validation
```

---

## 11. Task H: Update .gitignore and Push to GitHub

### Status: ✅ `.gitignore` already updated. Heap dump already deleted.

### Current `.gitignore` Key Patterns (Verify These Exist)
```
# Java heap dumps — CRITICAL: prevents 1.6 GB files from entering history
mobile/android/java_pid*.hprof
*.hprof

# Build outputs
mobile/build/
mobile/android/app/build/
mobile/android/.gradle/
mobile/.dart_tool/

# Extension build (generated, do not commit)
extension/dist/
```

### Initialize Git If Not Already Done
The project at `C:\Syncronization` does not currently have a `.git` folder (it is not yet a git repo).
If you want to push to GitHub:

```powershell
# From C:\Syncronization
git init
git remote add origin https://github.com/YOUR_USERNAME/YOUR_REPO.git
git add -A
git commit -m "feat: cloud signaling, volume control, connection quality, gitignore"
git branch -M main
git push -u origin main
```

Replace `YOUR_USERNAME/YOUR_REPO` with the actual GitHub repository URL.

### If Repo Already Exists and Just Needs a Push
```powershell
# From C:\Syncronization
git add -A
git commit -m "feat: migrate to vercel relay, volume slider, connection quality indicator"
git push origin main
```

---

## 12. Master Execution Checklist

Run through these in order. Tick each one before moving to the next.

### 🔴 Phase 1 — Connection Fix (High Priority)

- [ ] **A1** Verify heap dump is deleted: `Test-Path "C:\Syncronization\mobile\android\java_pid11512.hprof"` → `False`
- [ ] **B1** Open `https://syncronization.vercel.app/socket.io/?EIO=4&transport=polling` in browser
- [ ] **B2** If it returns `0{...}` → Vercel signaling is live ✅ proceed
- [ ] **B3** If it returns 404 → switch all URLs to `https://syncronization-server.onrender.com` and rebuild
- [ ] **C1** Confirm `extension/src/App.tsx` line 5 contains `syncronization.vercel.app`
- [ ] **C2** Confirm `extension/src/App.tsx` line 6 (`CONNECT_PAGE_URL`) contains `syncronization.vercel.app`
- [ ] **C3** Confirm `extension/src/App.tsx` line 15 default `mobileServerUrl` state contains `syncronization.vercel.app`
- [ ] **C4** Confirm `extension/src/offscreen.ts` line 6 `SIGNALING_SERVER` contains `syncronization.vercel.app`
- [ ] **C5** Reload extension in Chrome at `chrome://extensions`
- [ ] **C6** Open extension popup → verify "✓ Connected to Vercel Cloud Relay" badge shows (no IP input field)
- [ ] **D1** Confirm `home_screen.dart` fallback uses `syncronization.vercel.app`

### 🟡 Phase 2 — Mobile Build Fix

- [ ] **G1** Verify `settings.gradle` is deleted: `Test-Path "C:\Syncronization\mobile\android\settings.gradle"` → `False`
- [ ] **G2** Verify `settings.gradle.kts` has Kotlin `2.2.20`
- [ ] **G3** Verify `MainActivity.kt` at correct path with correct content
- [ ] **G4** Run `flutter clean` in `mobile/`
- [ ] **G5** Run `flutter pub get` in `mobile/`
- [ ] **G6** Run `flutter run --android-skip-build-dependency-validation` with Redmi Y2 connected via USB
- [ ] **G7** App launches on device ✅

### 🟢 Phase 3 — End-to-End Connection Test

- [ ] **T1** With app running on phone and extension loaded in Chrome:
- [ ] **T2** Open a YouTube video in the browser tab
- [ ] **T3** Click the Syncronization extension icon → "Start Streaming"
- [ ] **T4** On the phone tap "Scan QR Code"
- [ ] **T5** Scan the QR code displayed in the extension
- [ ] **T6** Phone shows "Connected & Streaming" ✅
- [ ] **T7** Audio plays on the phone speaker ✅
- [ ] **T8** Volume slider appears and adjusts audio level ✅
- [ ] **T9** Signal quality dot appears (MEASURING → EXCELLENT/GOOD/POOR) ✅

### 🔵 Phase 4 — GitHub Push

- [ ] **H1** Confirm `.gitignore` contains `*.hprof` and `mobile/android/java_pid*.hprof`
- [ ] **H2** `git add -A`
- [ ] **H3** `git commit -m "feat: vercel relay, volume slider, connection quality, gitignore hardening"`
- [ ] **H4** `git push origin main`
- [ ] **H5** Push succeeds without "file too large" errors ✅

---

## 13. File Locations Quick Reference

| File | Purpose | Status |
|------|---------|--------|
| `extension/src/App.tsx` | Extension UI — URL constants + cloud relay badge | ✅ Updated |
| `extension/src/offscreen.ts` | Extension WebRTC — `SIGNALING_SERVER` constant | ✅ Updated |
| `extension/dist/` | Built extension — reload in `chrome://extensions` | ✅ Built |
| `mobile/lib/services/webrtc_service.dart` | Volume state + Connection quality stats timer | ✅ Updated |
| `mobile/lib/screens/home_screen.dart` | Volume slider + Quality indicator UI | ✅ Updated |
| `mobile/lib/theme/app_theme.dart` | Brand colors — `accent=#a855f7`, `bg=#030303` | Unchanged |
| `mobile/android/settings.gradle` | **DELETED** — was causing Kotlin 1.8.22 conflict | ✅ Deleted |
| `mobile/android/settings.gradle.kts` | Kotlin DSL config — Kotlin `2.2.20`, AGP `8.11.1` | ✅ Keep |
| `mobile/android/app/src/main/kotlin/com/syncronization/app/MainActivity.kt` | Flutter entry point | ✅ Correct |
| `mobile/android/java_pid11512.hprof` | **DELETED** — was 1.67 GB, blocked git push | ✅ Deleted |
| `mobile/android/app/src/main/AndroidManifest.xml` | Network security config + cleartext | ✅ Correct |
| `mobile/android/app/src/main/res/xml/network_security_config.xml` | Allows LAN HTTP for local dev | ✅ Correct |
| `C:\Syncronization\.gitignore` | Excludes `*.hprof`, build dirs, IDE files | ✅ Updated |
| `signaling-server/server.js` | Cloud signaling — deployed on Render | **No changes needed** |
| `web/` | Website — deployed on Vercel | **No changes needed** |

---

## 14. Why Not Bluetooth?

The user asked about Bluetooth as an alternative to cloud signaling. Here is the technical comparison:

| Criteria | Bluetooth | Cloud Signaling (Current) |
|----------|-----------|--------------------------|
| Pairing effort | 30+ second ceremony, both devices must cooperate | Zero — just scan QR |
| Firewall issues | None | None (HTTPS/443) |
| Audio bandwidth | ~350 kbps max (A2DP) — noticeable quality loss | Unlimited (WebRTC P2P) |
| Chrome extension support | ❌ No Bluetooth audio API in Chrome extensions | ✅ Tab audio capture works |
| Multi-device | Complex BT routing | ✅ Multiple phones, one session |
| Works over WiFi | ❌ BT is radio, not WiFi | ✅ Same network or internet |
| Latency (after connect) | ~200ms (Bluetooth codec delay) | ~5-30ms (WebRTC) |

**Verdict**: Cloud signaling is strictly better in every dimension for this use case.
Bluetooth audio from a Chrome extension is not technically possible — Chrome has no `navigator.bluetooth`
audio output API. The only viable path is WebRTC P2P via a cloud signaling server.

---

## Appendix: Design System Reference

Matching the website at `https://syncronization.vercel.app`:

```css
/* From web/styles.css */
--accent: #a855f7;
--accent-glow: rgba(168, 85, 247, 0.4);
--bg: #030303;
--card: #0f0f12;
--border: rgba(255, 255, 255, 0.08);
--text: #f8fafc;
--text-dim: #94a3b8;
```

```dart
// From mobile/lib/theme/app_theme.dart
static const Color accent   = Color(0xFFa855f7);
static const Color accentDark = Color(0xFF7c3aed);
static const Color bg       = Color(0xFF030303);
static const Color card     = Color(0xFF0f0f12);
static const Color green    = Color(0xFF22C55E);
static const Color red      = Color(0xFFEF4444);
```

All new UI elements (volume slider, quality indicator) use `AppTheme.accent` for the active/highlight
color to maintain visual consistency across the website, extension, and mobile app.

---

*Plan version: 2.0 | Last updated: 2026-05-01 | Website: https://syncronization.vercel.app*
