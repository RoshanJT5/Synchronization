# Fix: Audio Stops After 10-15 Minutes

## Root Cause Analysis

After deep investigation across all layers (server, extension, mobile), I found **multiple compounding issues** that all converge around the 10-15 minute mark. Your Render theory is partially correct, but the problem is bigger than that.

### 🔴 Cause 1: Render Free Tier Sleeps After 15 Minutes (CONFIRMED)

Render's free tier **spins down the server after 15 minutes of inactivity**. While active WebSocket connections *should* count as traffic, there is a critical subtlety:

- The extension's `offscreen.ts` Socket.IO connection uses the server for signalling only at the start, then WebRTC takes over for audio. After the initial handshake, the signalling socket sends **no periodic messages**. 
- The Render server sees no inbound traffic → it sleeps → all socket connections are **terminated**.
- When the server goes to sleep, the Socket.IO `disconnect` event fires, which triggers `activeSessions.delete()` on the server side.
- When the server wakes back up (30-60 second cold start), **all WebSocket state (rooms, sessions) is gone**.

> [!IMPORTANT]
> Audio should survive this because WebRTC is P2P (audio doesn't go through the server). BUT: the `disconnect` event on the mobile side triggers `_setState(AppConnectionState.reconnecting)`, and the mobile socket client's limited reconnection (only 20 attempts) will exhaust and leave the app in a broken state.

### 🔴 Cause 2: Mobile Socket.IO Reconnection Attempts Are Capped at 20

In [webrtc_service.dart](file:///c:/Synchronization/mobile/lib/services/webrtc_service.dart#L130):
```dart
.setReconnectionAttempts(20)
```

With `reconnectionDelay: 1000ms` and `reconnectionDelayMax: 8000ms`, 20 attempts will be exhausted within **~2-3 minutes**. After that, the socket gives up permanently. Any subsequent signalling need (new peer joins, ICE re-negotiation) is impossible.

### 🔴 Cause 3: No Keepalive Ping on the Offscreen Socket (Extension Side)

In [offscreen.ts](file:///c:/Synchronization/extension/src/offscreen.ts#L70-L74), the socket that handles WebRTC signalling sends a single `announce-session` on connect, then **nothing**. The Socket.IO ping/pong mechanism (10s interval, 20s timeout) generates internal frames, but Render may not count these as "inbound traffic" for its sleep timer — Render looks for HTTP-level or WebSocket message-level activity, and low-level pings may not qualify.

### 🟡 Cause 4: No WebRTC ICE Restart on Failure

In both [offscreen.ts](file:///c:/Synchronization/extension/src/offscreen.ts#L164-L176) and [webrtc_service.dart](file:///c:/Synchronization/mobile/lib/services/webrtc_service.dart#L294-L304), when a peer connection goes to `failed` or `disconnected`, the peer is simply removed. There is no attempt to re-negotiate or restart ICE, which means any transient network hiccup after 10+ minutes kills the audio permanently.

### 🟡 Cause 5: Session TTL is Only 20 Seconds

In [server.js](file:///c:/Synchronization/signaling-server/server.js#L77):
```js
const SESSION_TTL_MS = 20000; // 20 seconds
```

If the extension heartbeat (`announce-session` every 5s) misses a couple of beats due to network jitter, the session is pruned. Meanwhile, the extension `offscreen.ts` does NOT send any heartbeats at all after the initial announce.

---

## Proposed Changes

### Server: `signaling-server/server.js`

#### [MODIFY] [server.js](file:///c:/Synchronization/signaling-server/server.js)

1. **Add a self-ping keepalive** to prevent Render from sleeping. The server will HTTP-ping its own health endpoint every 13 minutes. This costs zero external services and is the industry-standard pattern.
2. **Increase `SESSION_TTL_MS`** from 20s to 90s — tolerant of network jitter and socket.io reconnection delays.
3. **Add a `/health` endpoint** for external monitoring and internal self-ping target.

---

### Extension: `extension/src/offscreen.ts`

#### [MODIFY] [offscreen.ts](file:///c:/Synchronization/extension/src/offscreen.ts)

1. **Add a periodic heartbeat** on the offscreen socket — emit `session-heartbeat` every 30 seconds. This keeps the Render server aware of the active session AND generates traffic that prevents Render from sleeping.
2. **Add ICE restart logic** — when a peer connection goes to `disconnected` or `failed`, attempt an ICE restart instead of silently dropping the peer.

---

### Mobile: `mobile/lib/services/webrtc_service.dart`

#### [MODIFY] [webrtc_service.dart](file:///c:/Synchronization/mobile/lib/services/webrtc_service.dart)

1. **Set reconnection attempts to unlimited** (`double.infinity` / a very high number).
2. **Add ICE restart handling** — on peer `disconnected`/`failed`, attempt to re-negotiate instead of dropping.
3. **Add a socket-level keepalive** — periodically emit a `session-heartbeat` so the signalling connection stays warm.

---

## Verification Plan

### Automated Tests
- Run `npm start` locally for the signaling server and verify the `/health` endpoint responds.
- Rebuild the extension and verify no build errors.
- Run `flutter analyze` on the mobile app.

### Manual Verification
- Deploy to Render and let a session run for 20+ minutes — audio should not drop.
- Monitor Render logs to see the self-ping preventing sleep.
