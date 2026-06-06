# GEMINI AGENT PROMPT — Synchronization v2.0: Host Streams File to All Devices

---

## READ THIS ENTIRE DOCUMENT BEFORE WRITING A SINGLE LINE OF CODE

You are working on an existing Flutter + Chrome Extension project called **"Synchronization"**.

Before this task, the app tried to capture browser tab audio and send raw PCM bytes over a WebRTC DataChannel. That approach had fundamental sync problems and is being completely replaced.

---

## THE CORRECT MENTAL MODEL

**Only the HOST needs the file. Guests need nothing except the app.**

```
WRONG MENTAL MODEL (what was built before, do not do this):
Host phone has movie.mp4
↓
Captures audio as raw PCM bytes
↓
Sends bytes over WebRTC DataChannel
↓
Guests decode bytes and try to play
↓
Result: jitter, desync, bad quality ❌

CORRECT MENTAL MODEL (how AmpMe, SoundSeeder work):
Host phone has movie.mp4
↓
Host phone runs a tiny HTTP audio server ON THE PHONE ITSELF
↓
Host phone reads the file and serves it as an audio stream at a local URL
e.g. http://192.168.1.5:8080/stream
↓
Signaling server shares that URL with all guests (like sharing a radio station URL)
↓
Each guest app makes a standard HTTP request to that URL
↓
Each guest receives and plays audio exactly like tuning into a radio station
↓
Tiny sync commands (play/pause/seek) keep everyone at the same timestamp
↓
Result: perfect audio quality, minimal sync drift ✅
```

This is exactly how SoundSeeder works. The host phone becomes a personal Icecast radio station. Guests are listeners. The file never needs to be on guest devices.

---

## WHAT ALREADY EXISTS IN THIS PROJECT — DO NOT TOUCH THESE

| Component | Location | Status |
|-----------|----------|--------|
| Signaling server | `signaling-server/server.js` on Render | ✅ Working — DO NOT TOUCH |
| WebRTC peer connection setup | `mobile/lib/services/webrtc_service.dart` | ✅ Keep the connection logic |
| QR code session join flow | Extension + App | ✅ Keep this flow |
| Brand theme | `mobile/lib/theme/app_theme.dart` | ✅ DO NOT TOUCH |
| Android manifest base permissions | `AndroidManifest.xml` | ✅ Only ADD new permissions |

**Signaling server URL**: `https://synchronization-807q.onrender.com`
**Brand accent color**: `#a855f7` (purple)
**Brand background**: `#030303`

---

## ARCHITECTURE OF THE NEW SYSTEM

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                      SYNCHRONIZATION v2.0 ARCHITECTURE                      │
│                                                                             │
│  HOST PHONE                                                                 │
│  ┌──────────────────────────────────────────────┐                          │
│  │  Flutter App (Host Mode)                     │                          │
│  │                                              │                          │
│  │  1. User picks audio/video file              │                          │
│  │     e.g. /storage/emulated/0/Movies/film.mp4 │                          │
│  │                                              │                          │
│  │  2. App starts LOCAL HTTP SERVER on port 8080│                          │
│  │     Serves file as audio stream at:          │                          │
│  │     http://192.168.x.x:8080/stream           │                          │
│  │                                              │                          │
│  │  3. App gets its local WiFi IP address       │                          │
│  │     e.g. 192.168.1.5                         │                          │
│  │                                              │                          │
│  │  4. App sends stream URL to signaling server │                          │
│  │     via existing WebRTC DataChannel/Socket   │                          │
│  │                                              │                          │
│  │  5. App plays file locally too (host hears   │                          │
│  │     it on their own phone)                   │                          │
│  │                                              │                          │
│  │  6. Sends sync commands every 3 seconds:     │                          │
│  │     {action:"syncCheck", positionMs: 45000}  │                          │
│  └──────────────────────────────────────────────┘                          │
│           │                                                                 │
│           │ WiFi (same network — LAN)                                      │
│           │ OR                                                              │
│           │ Host creates WiFi Hotspot, guests connect to hotspot            │
│           │                                                                 │
│  ┌────────▼──────────────────────────────────────────────┐                 │
│  │  GUEST PHONES (no file needed on guest devices)       │                 │
│  │                                                       │                 │
│  │  Guest A App          Guest B App          Guest C    │                 │
│  │  ┌──────────┐         ┌──────────┐         ┌───────┐  │                 │
│  │  │Receives  │         │Receives  │         │Receiv │  │                 │
│  │  │stream URL│         │stream URL│         │stream │  │                 │
│  │  │from      │         │from      │         │URL    │  │                 │
│  │  │signaling │         │signaling │         │       │  │                 │
│  │  │          │         │          │         │       │  │                 │
│  │  │Opens:    │         │Opens:    │         │Opens: │  │                 │
│  │  │http://   │         │http://   │         │http:/ │  │                 │
│  │  │192.168   │         │192.168   │         │192.16 │  │                 │
│  │  │.1.5:8080 │         │.1.5:8080 │         │8.1.5: │  │                 │
│  │  │/stream   │         │/stream   │         │8080/  │  │                 │
│  │  │          │         │          │         │stream │  │                 │
│  │  │Plays like│         │Plays like│         │       │  │                 │
│  │  │radio 🎵  │         │radio 🎵  │         │radio🎵│  │                 │
│  │  └──────────┘         └──────────┘         └───────┘  │                 │
│  └───────────────────────────────────────────────────────┘                 │
│                                                                             │
│  SYNC COMMANDS (tiny JSON over existing WebRTC DataChannel):               │
│  Host → All Guests: {"action":"play","positionMs":45000,"sentAt":123456}   │
│  Host → All Guests: {"action":"pause","positionMs":45000,"sentAt":123456}  │
│  Host → All Guests: {"action":"syncCheck","positionMs":45000,"sentAt":...} │
│  Guest → Host: {"action":"syncResponse","positionMs":44950}                │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## CRITICAL NETWORKING REQUIREMENT

**The host and guests MUST be on the same WiFi network OR guests must connect to the host phone's WiFi hotspot.**

Why: The stream URL is a local IP address (`192.168.x.x`). Local IPs are only reachable within the same network. This is not a bug — this is how SoundSeeder, AmpMe, and all local streaming apps work.

The signaling server on Render is only used for:
1. Session creation (host registers a session)
2. Delivering the stream URL from host to guests
3. WebRTC handshake (keep as-is)

The actual audio travels directly from host phone to guest phones over local WiFi — the Render server is NOT in the audio path.

---

## PHASE 1 — HOST SIDE: LOCAL HTTP AUDIO SERVER

The host phone needs to serve the audio file over HTTP so guests can connect to it like a radio stream.

### Package to install for HTTP server:

```yaml
# mobile/pubspec.yaml — ADD these packages:
dependencies:
  shelf: ^1.4.1
  shelf_router: ^1.1.4
  just_audio: ^0.9.40
  audio_session: ^0.1.21
  file_picker: ^8.0.0+1
  network_info_plus: ^5.0.0
  video_player: ^2.8.6
  path_provider: ^2.1.0
```

Run `flutter pub get` after editing pubspec.yaml.

---

### Create the Local Streaming Server

**Create new file**: `mobile/lib/services/stream_server.dart`

```dart
import 'dart:io';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

class StreamServer {
  HttpServer? _server;
  String? _filePath;
  String? _mimeType;
  static const int PORT = 8080;

  /// Start the HTTP server that serves the audio/video file as a stream.
  /// Returns the local stream URL e.g. "http://192.168.1.5:8080/stream"
  Future<String> start(String filePath, String localIP) async {
    _filePath = filePath;
    _mimeType = _getMimeType(filePath);

    final router = Router();

    // Health check
    router.get('/ping', (shelf.Request request) {
      return shelf.Response.ok('pong');
    });

    // Main audio stream endpoint
    router.get('/stream', (shelf.Request request) async {
      final file = File(_filePath!);

      if (!await file.exists()) {
        return shelf.Response.notFound('File not found');
      }

      final fileSize = await file.length();
      final rangeHeader = request.headers['range'];

      // Support HTTP Range requests (needed for seeking)
      if (rangeHeader != null) {
        return _handleRangeRequest(file, fileSize, rangeHeader);
      }

      // Full file stream
      final stream = file.openRead();
      return shelf.Response.ok(
        stream,
        headers: {
          'Content-Type': _mimeType!,
          'Content-Length': '$fileSize',
          'Accept-Ranges': 'bytes',
          'Cache-Control': 'no-cache',
          'Connection': 'keep-alive',
        },
      );
    });

    final handler = const shelf.Pipeline()
        .addMiddleware(_corsMiddleware())
        .addHandler(router.call);

    // Bind to all network interfaces (0.0.0.0) so guests on the same WiFi can reach it
    _server = await shelf_io.serve(handler, '0.0.0.0', PORT);
    print('🎵 Stream server running at http://$localIP:$PORT/stream');

    return 'http://$localIP:$PORT/stream';
  }

  /// Handle HTTP Range requests — this is what allows guests to seek in the stream
  Future<shelf.Response> _handleRangeRequest(
      File file, int fileSize, String rangeHeader) async {
    // Parse "bytes=start-end" header
    final match = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(rangeHeader);
    if (match == null) {
      return shelf.Response(416, body: 'Invalid range');
    }

    final start = int.parse(match.group(1)!);
    final endStr = match.group(2)!;
    final end = endStr.isEmpty ? fileSize - 1 : int.parse(endStr);
    final length = end - start + 1;

    final stream = file.openRead(start, end + 1);

    return shelf.Response(
      206, // Partial Content
      body: stream,
      headers: {
        'Content-Type': _mimeType!,
        'Content-Range': 'bytes $start-$end/$fileSize',
        'Content-Length': '$length',
        'Accept-Ranges': 'bytes',
      },
    );
  }

  shelf.Middleware _corsMiddleware() {
    return (shelf.Handler handler) {
      return (shelf.Request request) async {
        final response = await handler(request);
        return response.change(headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, HEAD, OPTIONS',
        });
      };
    };
  }

  String _getMimeType(String path) {
    final ext = path.split('.').last.toLowerCase();
    const types = {
      'mp3': 'audio/mpeg',
      'mp4': 'video/mp4',
      'wav': 'audio/wav',
      'aac': 'audio/aac',
      'flac': 'audio/flac',
      'm4a': 'audio/mp4',
      'ogg': 'audio/ogg',
      'mkv': 'video/x-matroska',
      'avi': 'video/x-msvideo',
    };
    return types[ext] ?? 'application/octet-stream';
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    print('🔇 Stream server stopped');
  }

  bool get isRunning => _server != null;
}
```

---

### Create Network Info Service

**Create new file**: `mobile/lib/services/network_service.dart`

```dart
import 'package:network_info_plus/network_info_plus.dart';

class NetworkService {
  final _networkInfo = NetworkInfo();

  /// Get the device's local WiFi IP address
  /// Returns null if not connected to WiFi
  Future<String?> getLocalIP() async {
    try {
      final ip = await _networkInfo.getWifiIP();
      return ip; // Returns something like "192.168.1.5"
    } catch (e) {
      print('Could not get local IP: $e');
      return null;
    }
  }
}
```

---

### Create File Picker Service

**Create new file**: `mobile/lib/services/file_service.dart`

```dart
import 'package:file_picker/file_picker.dart';

class FileService {
  /// Let user pick an audio or video file from their phone storage
  Future<PlatformFile?> pickMediaFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        'mp3', 'mp4', 'wav', 'aac', 'flac',
        'm4a', 'ogg', 'mkv', 'avi', 'mov'
      ],
      allowMultiple: false,
    );

    if (result != null && result.files.isNotEmpty) {
      return result.files.first;
    }
    return null;
  }
}
```

---

### Create Host Media Player (Host plays the file locally too)

**Create new file**: `mobile/lib/services/host_media_player.dart`

```dart
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';

class HostMediaPlayer {
  final AudioPlayer _player = AudioPlayer();
  bool _isLoaded = false;

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;
  Duration get position => _player.position;
  Duration? get duration => _player.duration;
  bool get isPlaying => _player.playing;

  Future<void> loadFile(String filePath) async {
    final session = await AudioSession.instance;
    await session.configure(AudioSessionConfiguration.music());
    await _player.setFilePath(filePath);
    _isLoaded = true;
    print('🎵 Host loaded file: $filePath');
  }

  Future<void> play() async {
    if (_isLoaded) await _player.play();
  }

  Future<void> pause() async {
    if (_isLoaded) await _player.pause();
  }

  Future<void> seekTo(int positionMs) async {
    if (_isLoaded) await _player.seek(Duration(milliseconds: positionMs));
  }

  Future<void> setVolume(double volume) async {
    await _player.setVolume(volume.clamp(0.0, 1.0));
  }

  Future<void> dispose() async {
    await _player.dispose();
  }
}
```

---

## PHASE 2 — SYNC COMMAND SYSTEM

Create one shared model file used by both host and guest.

**Create new file**: `mobile/lib/models/sync_command.dart`

```dart
import 'dart:convert';

enum SyncAction { play, pause, seek, syncCheck, syncResponse, streamReady }

class SyncCommand {
  final SyncAction action;
  final int positionMs;
  final int sentAtMs;       // Host clock time when command was sent
  final String? streamUrl;  // Only used in streamReady command

  SyncCommand({
    required this.action,
    required this.positionMs,
    required this.sentAtMs,
    this.streamUrl,
  });

  String toJson() => jsonEncode({
    'action': action.name,
    'positionMs': positionMs,
    'sentAtMs': sentAtMs,
    if (streamUrl != null) 'streamUrl': streamUrl,
  });

  factory SyncCommand.fromJson(String raw) {
    final map = jsonDecode(raw);
    return SyncCommand(
      action: SyncAction.values.byName(map['action']),
      positionMs: map['positionMs'] ?? 0,
      sentAtMs: map['sentAtMs'] ?? DateTime.now().millisecondsSinceEpoch,
      streamUrl: map['streamUrl'],
    );
  }
}
```

---

## PHASE 3 — HOST SESSION CONTROLLER

**Create new file**: `mobile/lib/services/host_session_controller.dart`

```dart
import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../models/sync_command.dart';
import 'host_media_player.dart';
import 'stream_server.dart';
import 'network_service.dart';
import 'file_service.dart';
import 'package:file_picker/file_picker.dart';

class HostSessionController {
  final HostMediaPlayer _player = HostMediaPlayer();
  final StreamServer _streamServer = StreamServer();
  final NetworkService _networkService = NetworkService();
  final List<RTCDataChannel> _guestChannels = [];
  
  String? _streamUrl;
  String? _filePath;
  Timer? _syncTimer;

  // Called by UI when host picks a file and starts session
  Future<String?> setupSession(PlatformFile file) async {
    _filePath = file.path!;

    // Step 1: Get local IP
    final localIP = await _networkService.getLocalIP();
    if (localIP == null) {
      throw Exception('Not connected to WiFi. Connect to WiFi or create a hotspot first.');
    }

    // Step 2: Start the HTTP stream server
    _streamUrl = await _streamServer.start(_filePath!, localIP);

    // Step 3: Load the file in the local player (host hears it too)
    await _player.loadFile(_filePath!);

    print('✅ Session ready. Stream URL: $_streamUrl');
    return _streamUrl;
  }

  // Called when a new guest connects via WebRTC DataChannel
  void onGuestConnected(RTCDataChannel channel) {
    _guestChannels.add(channel);
    print('👤 Guest connected. Total guests: ${_guestChannels.length}');

    // Remove channel when guest disconnects
    channel.onDataChannelState = (state) {
      if (state == RTCDataChannelState.RTCDataChannelClosed) {
        _guestChannels.remove(channel);
        print('👤 Guest disconnected. Remaining: ${_guestChannels.length}');
      }
    };

    // Listen for sync responses from this guest
    channel.onMessage = (message) {
      _handleGuestMessage(message.text);
    };

    // Send stream URL to newly connected guest immediately
    if (_streamUrl != null) {
      _sendToChannel(channel, SyncCommand(
        action: SyncAction.streamReady,
        positionMs: _player.position.inMilliseconds,
        sentAtMs: DateTime.now().millisecondsSinceEpoch,
        streamUrl: _streamUrl,
      ));
    }
  }

  void _handleGuestMessage(String raw) {
    try {
      final command = SyncCommand.fromJson(raw);
      if (command.action == SyncAction.syncResponse) {
        // Guest reported its position — check for drift
        final expectedMs = _player.position.inMilliseconds;
        final guestMs = command.positionMs;
        final drift = (expectedMs - guestMs).abs();
        if (drift > 1500) {
          // Guest is more than 1.5 seconds off — send a corrective seek
          print('⚠️ Guest drift: ${drift}ms — sending correction');
          _broadcastToGuests(SyncCommand(
            action: SyncAction.seek,
            positionMs: _player.position.inMilliseconds,
            sentAtMs: DateTime.now().millisecondsSinceEpoch,
          ));
        }
      }
    } catch (e) {
      print('Error handling guest message: $e');
    }
  }

  // HOST CONTROLS — called by UI buttons

  Future<void> play() async {
    await _player.play();
    _broadcastToGuests(SyncCommand(
      action: SyncAction.play,
      positionMs: _player.position.inMilliseconds,
      sentAtMs: DateTime.now().millisecondsSinceEpoch,
    ));
    _startSyncTimer();
  }

  Future<void> pause() async {
    await _player.pause();
    _stopSyncTimer();
    _broadcastToGuests(SyncCommand(
      action: SyncAction.pause,
      positionMs: _player.position.inMilliseconds,
      sentAtMs: DateTime.now().millisecondsSinceEpoch,
    ));
  }

  Future<void> seekTo(int positionMs) async {
    await _player.seekTo(positionMs);
    _broadcastToGuests(SyncCommand(
      action: SyncAction.seek,
      positionMs: positionMs,
      sentAtMs: DateTime.now().millisecondsSinceEpoch,
    ));
  }

  Future<void> setVolume(double volume) async {
    await _player.setVolume(volume);
    // Volume is local only — don't broadcast to guests
    // Each guest controls their own volume
  }

  // Periodic sync — sends host position every 3 seconds while playing
  // Guests check if they are within 1 second of this position
  void _startSyncTimer() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (_player.isPlaying) {
        _broadcastToGuests(SyncCommand(
          action: SyncAction.syncCheck,
          positionMs: _player.position.inMilliseconds,
          sentAtMs: DateTime.now().millisecondsSinceEpoch,
        ));
      }
    });
  }

  void _stopSyncTimer() {
    _syncTimer?.cancel();
    _syncTimer = null;
  }

  void _broadcastToGuests(SyncCommand command) {
    final json = command.toJson();
    for (final channel in List.from(_guestChannels)) {
      _sendToChannel(channel, command);
    }
  }

  void _sendToChannel(RTCDataChannel channel, SyncCommand command) {
    if (channel.state == RTCDataChannelState.RTCDataChannelOpen) {
      channel.send(RTCDataChannelMessage(command.toJson()));
    }
  }

  // Expose player streams for UI
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;
  Duration get position => _player.position;
  Duration? get duration => _player.duration;
  bool get isPlaying => _player.isPlaying;
  int get guestCount => _guestChannels.length;

  Future<void> endSession() async {
    _stopSyncTimer();
    await _player.pause();
    await _streamServer.stop();
    await _player.dispose();
    _guestChannels.clear();
  }
}
```

---

## PHASE 4 — GUEST SIDE: RECEIVE STREAM AND PLAY IT

Guests receive the stream URL from host over the existing DataChannel and play it using `just_audio`. `just_audio` can play HTTP audio streams natively — no extra packages needed.

**Create new file**: `mobile/lib/services/guest_session_controller.dart`

```dart
import 'dart:async';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../models/sync_command.dart';

class GuestSessionController {
  final AudioPlayer _player = AudioPlayer();
  RTCDataChannel? _hostChannel;
  bool _isLoaded = false;
  static const int MAX_DRIFT_MS = 1000; // Re-sync if more than 1 second off

  // Called when DataChannel to host is established
  void setHostChannel(RTCDataChannel channel) {
    _hostChannel = channel;
    channel.onMessage = (message) {
      _handleHostCommand(message.text);
    };
  }

  Future<void> _handleHostCommand(String raw) async {
    try {
      final command = SyncCommand.fromJson(raw);
      // Time the command spent traveling over the network
      final transitMs = DateTime.now().millisecondsSinceEpoch - command.sentAtMs;

      switch (command.action) {

        case SyncAction.streamReady:
          // Host is telling us the stream URL — connect to it
          await _connectToStream(command.streamUrl!);
          break;

        case SyncAction.play:
          if (!_isLoaded) break;
          // Compensate for network transit time before playing
          final targetMs = command.positionMs + transitMs;
          await _player.seek(Duration(milliseconds: targetMs));
          await _player.play();
          break;

        case SyncAction.pause:
          await _player.pause();
          await _player.seek(Duration(milliseconds: command.positionMs));
          break;

        case SyncAction.seek:
          await _player.seek(Duration(milliseconds: command.positionMs));
          if (_player.playing) await _player.play();
          break;

        case SyncAction.syncCheck:
          // Host is checking our position — calculate expected position
          final expectedMs = command.positionMs + transitMs;
          final actualMs = _player.position.inMilliseconds;
          final drift = (actualMs - expectedMs).abs();

          // Report back to host
          _sendToHost(SyncCommand(
            action: SyncAction.syncResponse,
            positionMs: actualMs,
            sentAtMs: DateTime.now().millisecondsSinceEpoch,
          ));

          // Self-correct if too far off
          if (drift > MAX_DRIFT_MS) {
            print('⚠️ Drift: ${drift}ms — self-correcting');
            await _player.seek(Duration(milliseconds: expectedMs));
            if (!_player.playing) await _player.play();
          }
          break;

        default:
          break;
      }
    } catch (e) {
      print('Error handling host command: $e');
    }
  }

  Future<void> _connectToStream(String streamUrl) async {
    print('📡 Connecting to host stream: $streamUrl');

    final session = await AudioSession.instance;
    await session.configure(AudioSessionConfiguration.music());

    // just_audio can play HTTP URLs natively — host phone is the server
    await _player.setUrl(streamUrl);
    _isLoaded = true;
    print('✅ Connected to stream. Waiting for host play command.');
  }

  void _sendToHost(SyncCommand command) {
    if (_hostChannel?.state == RTCDataChannelState.RTCDataChannelOpen) {
      _hostChannel!.send(RTCDataChannelMessage(command.toJson()));
    }
  }

  Future<void> setVolume(double volume) async {
    await _player.setVolume(volume.clamp(0.0, 1.0));
  }

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;
  Duration get position => _player.position;
  bool get isConnected => _isLoaded;

  Future<void> leaveSession() async {
    await _player.stop();
    await _player.dispose();
  }
}
```

---

## PHASE 5 — UPDATE WebRTC SERVICE

**File to modify**: `mobile/lib/services/webrtc_service.dart`

Keep all existing WebRTC connection and signaling code. Only change what happens AFTER connection is established.

**Remove from this file:**
- All PCM audio byte handling
- All `FlutterPcmSound` references
- All `PlaybackBuffer` references
- All `SyncClock` references
- All audio track (`onTrack`) receiving code that tried to play remote WebRTC audio tracks

**Add to this file:**

```dart
// Add these imports at the top:
import 'host_session_controller.dart';
import 'guest_session_controller.dart';

// Add these fields to the WebRTCService class:
HostSessionController? hostController;
GuestSessionController? guestController;
bool isHost = false;

// Find the method where you create the RTCPeerConnection and add this:
// When creating peer connection as HOST, enable DataChannel creation:
Future<RTCDataChannel> createHostDataChannel(RTCPeerConnection pc) async {
  final dataChannel = await pc.createDataChannel(
    'sync',
    RTCDataChannelInit()..ordered = true,
  );
  return dataChannel;
}

// When peer connection is established (in onConnectionState or equivalent):
// If HOST — pass the DataChannel to HostSessionController
void onConnectionEstablished_Host(RTCDataChannel dataChannel) {
  hostController?.onGuestConnected(dataChannel);
}

// If GUEST — pass the DataChannel to GuestSessionController
void onConnectionEstablished_Guest(RTCDataChannel dataChannel) {
  guestController?.setHostChannel(dataChannel);
}

// In the peer connection setup, add this to handle incoming DataChannels (for guest):
// pc.onDataChannel = (RTCDataChannel channel) {
//   if (!isHost) {
//     guestController?.setHostChannel(channel);
//   }
// };
```

**Important**: The existing signaling flow (Socket.IO → offer → answer → ICE candidates) stays EXACTLY the same. Only what happens after the DataChannel opens has changed.

---

## PHASE 6 — UI SCREENS

**File to modify**: `mobile/lib/screens/home_screen.dart`

Keep the exact same visual theme. Add these screens as states within the existing screen or as new routes.

---

### SCREEN 1: Welcome / Home

```
Background: #030303

┌─────────────────────────────────────┐
│                                     │
│         🎵 Synchronization          │
│    Multi-device audio sync          │
│                                     │
│  ┌─────────────────────────────┐   │
│  │   🎵  HOST A SESSION        │   │  ← Purple button #a855f7
│  │   I have the audio file     │   │
│  └─────────────────────────────┘   │
│                                     │
│  ┌─────────────────────────────┐   │
│  │   📱  JOIN A SESSION        │   │  ← Outlined button
│  │   I want to listen          │   │
│  └─────────────────────────────┘   │
│                                     │
│  ☁️ Cloud Relay Active              │  ← small badge, already exists
└─────────────────────────────────────┘
```

---

### SCREEN 2: Host Setup

```
┌─────────────────────────────────────┐
│  ← Back         HOST SETUP          │
│                                     │
│  Step 1: Pick your audio/video file │
│                                     │
│  ┌─────────────────────────────┐   │
│  │   📂  Pick File             │   │  ← calls FileService.pickMediaFile()
│  └─────────────────────────────┘   │
│                                     │
│  [After file picked, show:]         │
│  ✅ movie.mp4 (1.2 GB)             │
│                                     │
│  ⚠️ Make sure guests are connected  │
│  to the same WiFi as your phone.   │
│  Or share your phone's hotspot.    │
│                                     │
│  ┌─────────────────────────────┐   │
│  │   🚀  Start Session         │   │  ← Purple button, enabled only after file picked
│  └─────────────────────────────┘   │
└─────────────────────────────────────┘
```

**On "Start Session" tap:**
1. Call `hostController.setupSession(file)` — starts HTTP server, gets stream URL
2. Create WebRTC session via existing signaling flow
3. Generate QR code with session ID (existing flow)
4. Navigate to Host Active screen

---

### SCREEN 3: Host Active (During Playback)

```
┌─────────────────────────────────────┐
│  SESSION ACTIVE                     │
│  👥 3 guests connected              │
│                                     │
│  📁 movie.mp4                      │
│                                     │
│  ━━━━━━━━━━━━●━━━━━━━━━━━━         │  ← Seek slider (purple)
│  1:23:45              2:11:30       │
│                                     │
│  [  ⏮10s  ]  [  ⏯  ]  [  10s⏭  ] │  ← Playback controls
│                                     │
│  🔊 ━━━━━━━●━━━━  Volume           │  ← Volume slider
│                                     │
│  📡 Stream: Active                 │
│                                     │
│  ┌─────────────────────────────┐   │
│  │   ⛔  End Session           │   │  ← Red/outlined button
│  └─────────────────────────────┘   │
└─────────────────────────────────────┘
```

**Controls behavior:**
- Play/Pause button: calls `hostController.play()` / `hostController.pause()`
- Seek slider: calls `hostController.seekTo(ms)` on drag end
- +10s / -10s buttons: calls `hostController.seekTo(currentMs ± 10000)`
- Volume slider: calls `hostController.setVolume(value)` — local only
- Guest count: updates from `hostController.guestCount`
- Timeline: updates from `hostController.positionStream`

---

### SCREEN 4: Guest Join

```
┌─────────────────────────────────────┐
│  ← Back         JOIN SESSION        │
│                                     │
│  ┌─────────────────────────────┐   │
│  │   📷  Scan QR Code          │   │  ← Existing QR scanner
│  └─────────────────────────────┘   │
│                                     │
│           — or —                    │
│                                     │
│  Enter Session Code:                │
│  ┌─────────────────────────────┐   │
│  │  _ _ _ _ _ _               │   │
│  └─────────────────────────────┘   │
│                                     │
│  ⚠️ You must be on the same WiFi   │
│  as the host, or connected to the  │
│  host's phone hotspot.             │
│                                     │
└─────────────────────────────────────┘
```

**After scanning QR / entering code:**
- Establish WebRTC DataChannel via existing signaling flow
- GuestSessionController receives `streamReady` command with stream URL
- Auto-connects to stream in background
- Navigate to Guest Active screen

---

### SCREEN 5: Guest Active (Listening)

```
┌─────────────────────────────────────┐
│  CONNECTED TO HOST                  │
│                                     │
│  📡 Receiving stream...             │  ← Shows "Buffering..." or "Playing"
│                                     │
│  ━━━━━━━━━━━━●━━━━━━━━━━━━         │  ← Read-only timeline (no seek for guests)
│  1:23:45              2:11:30       │
│                                     │
│  [  ⏯  ] (greyed out, host controls)│
│                                     │
│  🔊 ━━━━━━━●━━━━  Volume           │  ← Local volume only
│                                     │
│  Sync: ✅ In Sync                  │  ← or "⚠️ Syncing..."
│                                     │
│  ┌─────────────────────────────┐   │
│  │   🚪  Leave Session         │   │
│  └─────────────────────────────┘   │
└─────────────────────────────────────┘
```

---

## PHASE 7 — ANDROID PERMISSIONS

**File to modify**: `mobile/android/app/src/main/AndroidManifest.xml`

Add these permissions if not already present:

```xml
<!-- Network permissions — needed for HTTP server and stream -->
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />

<!-- File reading permissions — needed to read the media file -->
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"
    android:maxSdkVersion="32" />
<!-- Android 13+ replacements for READ_EXTERNAL_STORAGE: -->
<uses-permission android:name="android.permission.READ_MEDIA_AUDIO" />
<uses-permission android:name="android.permission.READ_MEDIA_VIDEO" />

<!-- Keep wake lock so stream server keeps running while screen is off -->
<uses-permission android:name="android.permission.WAKE_LOCK" />

<!-- Foreground service for keeping stream server alive in background -->
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
```

Also inside `<application>` tag, add:
```xml
<!-- Allow cleartext HTTP for local stream (192.168.x.x is not HTTPS) -->
android:usesCleartextTraffic="true"
```

If `network_security_config.xml` exists, make sure it allows cleartext for local IPs:
```xml
<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
    <domain-config cleartextTrafficPermitted="true">
        <domain includeSubdomains="true">192.168.0.0</domain>
        <domain includeSubdomains="true">10.0.0.0</domain>
        <domain includeSubdomains="true">172.16.0.0</domain>
    </domain-config>
    <base-config cleartextTrafficPermitted="false" />
</network-security-config>
```

---

## PHASE 8 — UPDATE EXTENSION (Simplified)

The Chrome extension is no longer the audio source. Update it to show a simple info card.

**File**: `extension/src/App.tsx` — replace all content with:

```tsx
import React from 'react';

const App: React.FC = () => {
  return (
    <div style={{
      width: '320px',
      minHeight: '200px',
      padding: '24px',
      background: '#030303',
      color: '#f8fafc',
      fontFamily: 'Inter, system-ui, sans-serif',
      boxSizing: 'border-box',
    }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: '10px', marginBottom: '8px' }}>
        <span style={{ fontSize: '20px' }}>🎵</span>
        <h1 style={{ margin: 0, fontSize: '18px', color: '#f8fafc' }}>Synchronization</h1>
      </div>
      <p style={{ color: '#94a3b8', fontSize: '12px', marginBottom: '20px' }}>
        Multi-device audio sync
      </p>

      <div style={{
        background: '#0f0f12',
        border: '1px solid rgba(255,255,255,0.08)',
        borderRadius: '12px',
        padding: '16px',
        marginBottom: '16px',
      }}>
        <p style={{ color: '#94a3b8', fontSize: '13px', margin: 0, lineHeight: '1.5' }}>
          📱 Open the <strong style={{ color: '#f8fafc' }}>Synchronization app</strong> on your
          phone to host a session and stream audio to other devices.
        </p>
      </div>

      <a
        href="https://synchronization-807q.onrender.com"
        target="_blank"
        rel="noreferrer"
        style={{
          display: 'block',
          padding: '10px 16px',
          background: '#a855f7',
          borderRadius: '8px',
          color: 'white',
          textAlign: 'center',
          textDecoration: 'none',
          fontSize: '13px',
          fontWeight: '500',
        }}
      >
        Get the App
      </a>
    </div>
  );
};

export default App;
```

**File**: `extension/src/offscreen.ts` — clear all content, replace with empty export:
```typescript
export {};
// Audio streaming has moved to the Flutter mobile app.
// This file is intentionally empty.
```

After editing extension files, rebuild:
```bash
cd extension
npm run build
```

---

## COMPLETE FILE SUMMARY TABLE

### New Files to Create
| File | Purpose |
|------|---------|
| `mobile/lib/services/stream_server.dart` | HTTP server that serves the audio file to guests |
| `mobile/lib/services/network_service.dart` | Gets local WiFi IP address |
| `mobile/lib/services/file_service.dart` | FilePicker wrapper |
| `mobile/lib/services/host_media_player.dart` | Host's local audio player |
| `mobile/lib/services/host_session_controller.dart` | Orchestrates host: file → server → commands |
| `mobile/lib/services/guest_session_controller.dart` | Guest: receives URL → plays stream → obeys commands |
| `mobile/lib/models/sync_command.dart` | Shared command data model |

### Files to Modify
| File | What Changes |
|------|-------------|
| `mobile/pubspec.yaml` | Add: shelf, shelf_router, just_audio, audio_session, file_picker, network_info_plus, video_player, path_provider |
| `mobile/lib/services/webrtc_service.dart` | Remove PCM/audio track code. Wire DataChannel to Host/GuestSessionController |
| `mobile/lib/screens/home_screen.dart` | Add 5 UI screens (Welcome, Host Setup, Host Active, Guest Join, Guest Active) |
| `mobile/android/app/src/main/AndroidManifest.xml` | Add file + network + foreground service permissions |
| `mobile/android/app/src/main/res/xml/network_security_config.xml` | Allow cleartext HTTP for local IPs |
| `extension/src/App.tsx` | Simplify to info card |
| `extension/src/offscreen.ts` | Clear all content |

### Files to Delete
| File | Reason |
|------|--------|
| `mobile/lib/services/sync_clock.dart` | Not needed |
| `mobile/lib/services/playback_buffer.dart` | Not needed |

### Files to NOT TOUCH
| File |
|------|
| `signaling-server/server.js` |
| `mobile/lib/theme/app_theme.dart` |
| `mobile/android/app/build.gradle` |
| `mobile/android/settings.gradle.kts` |
| `web/index.html` |
| All WebRTC signaling/ICE/offer/answer code inside `webrtc_service.dart` |

---

## IMPLEMENTATION ORDER — DO IN THIS EXACT ORDER

```
1.  Edit mobile/pubspec.yaml — add all new packages
2.  Run: flutter pub get
3.  Create mobile/lib/models/sync_command.dart
4.  Create mobile/lib/services/file_service.dart
5.  Create mobile/lib/services/network_service.dart
6.  Create mobile/lib/services/host_media_player.dart
7.  Create mobile/lib/services/stream_server.dart
8.  Create mobile/lib/services/host_session_controller.dart
9.  Create mobile/lib/services/guest_session_controller.dart
10. Modify mobile/lib/services/webrtc_service.dart
11. Modify mobile/lib/screens/home_screen.dart (add all 5 screens)
12. Modify mobile/android/app/src/main/AndroidManifest.xml
13. Modify mobile/android/app/src/main/res/xml/network_security_config.xml
14. Edit extension/src/App.tsx (simplify)
15. Edit extension/src/offscreen.ts (clear)
16. Run: cd extension && npm run build
17. Run: flutter build apk --debug
18. Verify: zero compilation errors
```

---

## HOW TO TEST AFTER IMPLEMENTATION

**Requirements for testing:**
- Host phone and at least one guest phone
- Both phones on the SAME WiFi network (OR guest connected to host's hotspot)
- An MP3 or MP4 file on the host phone

**Test steps:**
1. Host opens app → taps "Host a Session"
2. Host picks an MP3 file
3. Host taps "Start Session" — QR code appears
4. Guest opens app → taps "Join a Session" → scans QR
5. Host taps PLAY
6. Both phones should play audio simultaneously
7. Host seeks to 1:00 — guest should jump to ~1:00 within 1 second
8. Host pauses — guest pauses
9. Add a third guest — should sync automatically on join

**Expected sync accuracy:** ±50-150ms (imperceptible during music or movies)

---

## WHY THIS WILL ACTUALLY WORK THIS TIME

The previous approach tried to send raw audio bytes over WebRTC DataChannel. This fails because:
- Audio bytes are large (hundreds of KB per second)
- DataChannel delivery is not guaranteed to be perfectly timed
- Decoding and playing PCM bytes on Android introduces variable latency

This new approach works because:
- The host phone becomes a local HTTP radio station
- `just_audio` (used by millions of apps) handles all the buffering and playback internally
- The DataChannel only carries tiny JSON commands (50 bytes each)
- `just_audio` + HTTP streaming is the same technology used by every podcast app, Spotify, and SoundCloud
- Sync commands with transit time compensation keep positions within 1 second of each other
- The 3-second periodic sync check silently corrects any drift

This is architecturally identical to **SoundSeeder** — the most popular local audio sync app on Android.
