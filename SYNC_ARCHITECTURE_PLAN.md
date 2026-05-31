# Synchronization Playback Sync Plan

## Goal

Make host and receiver playback feel perfectly synchronized by syncing playback clocks, not by reacting to network messages as they arrive.

True mathematical 100% sync is not possible on consumer phones because Android audio output, Bluetooth devices, decoders, and network timing all add variable latency. The practical goal is to keep drift below the human-noticeable range, ideally under 20-40ms, while avoiding stutter, repeated seeking, or muted receiver playback.

## Core Idea

The app should not send `play now`.

Instead, the host sends:

```text
play position P at host time T
```

The receiver gets this command before `T`, converts host time to receiver time using clock calibration, seeks to `P`, waits, and starts locally at the scheduled moment.

This removes message delivery delay from the start moment. Network latency still exists, but it happens before the scheduled start instead of after the user presses play.

## Current Architecture

The phone-to-phone flow is:

1. Host selects a media file.
2. Host starts a LAN HTTP server.
3. Host announces a session over the signaling server.
4. Receiver joins and opens a WebRTC data channel.
5. Host sends `streamReady` with an HTTP audio URL.
6. Receiver loads that URL using `just_audio`.
7. Host sends play/pause/seek/sync commands over the data channel.
8. Receiver corrects drift using speed changes and occasional seeks.

This is a good foundation. The weak point is that playback commands are currently treated too much like immediate commands, so video+audio mode can show a small consistent receiver lag.

## Proposed Protocol

### 1. Clock Calibration

Use ping/pong messages to estimate:

- RTT: round-trip time between host and receiver.
- one-way delay: approximately `RTT / 2`.
- clock offset: receiver wall-clock minus estimated host wall-clock.

The receiver can then convert host timestamps into local receiver timestamps:

```text
receiverStartTime = hostStartTime + receiverClockOffset
```

The existing app already has most of this. The implementation should use it for scheduled playback, not only for drift correction.

### 2. Stream Readiness

After `streamReady`, the receiver should:

1. Configure audio session.
2. Load the stream URL.
3. Seek to the requested position if needed.
4. Mark itself loaded.
5. Reply with `readyToPlay`.

Future improvement: include real buffer depth if available.

Example:

```json
{
  "action": "readyToPlay",
  "positionMs": 0,
  "sentAtMs": 1234567890
}
```

### 3. Scheduled Start

When the host user presses play:

1. Host captures current media position `P`.
2. Host chooses a start time in the near future, for example `now + 900ms`.
3. Host sends `scheduledPlay(positionMs: P, startAtMs: T)`.
4. Host also waits until `T` before starting local playback.
5. Receiver seeks to `P`, waits until its converted local time, then plays.

This means both sides start from the same position at the same logical time.

### 4. Pause And Seek

Pause and seek can stay mostly immediate, but the cleaner long-term model is:

- `scheduledPause(positionMs, startAtMs)`
- `scheduledSeek(positionMs, startAtMs)`

The app now uses scheduled pause and scheduled seek, and resume/play uses the same scheduled clock path in audio-only and video+audio modes.

Resume after pause should be treated like a fresh synchronized start:

1. Host captures the paused media position.
2. Host picks a near-future `startAtMs`, using the measured guest RTT as extra safety margin.
3. Host sends `scheduledPlay(positionMs, startAtMs)` twice with a short stagger, just like other playback commands.
4. Host updates the UI immediately to a logical "playing/scheduled" state, then starts the local decoder at `startAtMs`.
5. Receiver seeks before the start time when possible. If the command is handled after `startAtMs`, it seeks to `positionMs + overdueMs` so it catches the host clock instead of starting late.

This gives play-after-pause the same "time clock" behavior as initial playback and prevents audio-only resumes from accumulating a fixed delay.

Pause also creates a tiny resume anchor 30ms before the scheduled paused position. On the next play, the host and guests seek to that anchor and start together using `scheduledPlay`. This turns the pause button into a practical resync tool: if small drift has built up, pausing and playing again re-locks both devices to the same clocked position without a noticeable jump for the listener.

### 5. Continuous Correction

After playback starts:

- Host sends `syncCheck` every 250ms.
- Receiver compares expected position with actual position.
- Small drift uses speed changes, not seeking.
- Large drift uses a hard seek with cooldown.

This protects audio from stuttering while still pulling the receiver toward the host.

## Drift Correction Rules

Suggested tuning:

- Drift under 25ms: do nothing.
- Drift 25-650ms: adjust speed temporarily.
- Drift over 650ms: hard seek, but no more than once every 1.8 seconds.
- Host emergency force-seek: only above 2000ms and no more than once every 5 seconds.

Reasoning:

- Small speed correction feels smoother than repeated seek.
- Video container audio streams can stall if the receiver is forced to seek too frequently.
- A small consistent lag should not be ignored, especially in video+audio mode.

## Buffering Model

Your packet idea maps to buffer readiness.

Instead of caring whether the host has 3 packets and receiver has 2 packets, the app should care whether each device has enough buffered media to start safely.

Initial practical version:

- Receiver reports ready after `setUrl` completes.
- Host schedules playback at least 900ms in the future.

Future stronger version:

- Receiver reports buffered duration.
- Host waits until every receiver has at least 2-3 seconds buffered.
- If a receiver falls behind, only that receiver is corrected.

## Implementation Stages

### Stage 1: Scheduled Play

Files:

- `mobile/lib/models/sync_command.dart`
- `mobile/lib/services/host_session_controller.dart`
- `mobile/lib/services/guest_session_controller.dart`

Add:

- `readyToPlay`
- `scheduledPlay`
- `startAtMs` field
- host-side delayed local play
- receiver-side delayed local play

### Stage 2: Better Readiness

Track receiver readiness per data channel.

Host behavior:

- Send `streamReady`.
- Wait for `readyToPlay`.
- If user presses play before ready, queue scheduled play until ready or use a longer delay.

### Stage 3: Scheduled Pause/Seek

Extend scheduled timestamps to pause and seek so every transport control follows the same clock.

### Stage 4: Buffer Depth

If the media package exposes buffer position reliably, send buffer depth from receiver to host.

Host can delay start until receivers have enough buffer.

### Stage 5: User-Facing Quality

Expose simple status:

- `Preparing...`
- `Ready`
- `Syncing`
- `Network slow`

Keep messages short and human-readable.

## Safety Rules

- Do not replace the LAN HTTP streaming system.
- Do not remove the existing WebRTC data channel.
- Do not make the receiver seek repeatedly for small drift.
- Do not block the UI while waiting for scheduled start.
- Keep audio-only behavior working, since it is already good.

## Success Criteria

The implementation is successful when:

- Audio-only remains synced.
- Video+audio receiver starts at the same time as host.
- Receiver no longer stays consistently 30-50ms behind.
- Receiver audio remains audible and does not stutter from seek storms.
- End Session remains reachable on the host UI.
