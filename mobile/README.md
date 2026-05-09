# Synchronization — Mobile App

Flutter mobile app that receives browser audio streamed from the Synchronization Chrome extension and plays it as a wireless speaker.

## Features

- **QR Code Scanner** — Scan the QR code shown in the extension popup to connect instantly.
- **Manual Session ID** — Enter the 8-character session ID manually if QR scanning isn't available.
- **Deep Link Support** — The website automatically opens the app via `syncronization://connect?id=...&server=...`.
- **WebRTC Audio** — Receives the P2P audio stream with ultra-low latency over your local Wi-Fi.
- **Background Audio** — Audio keeps playing when the screen is off or the app is backgrounded.
- **Premium Dark UI** — Matches the extension and website aesthetic with animated waveform visualizer.

## Tech Stack

| Layer | Technology |
|---|---|
| Framework | Flutter 3.x (Dart) |
| WebRTC | `flutter_webrtc` |
| Signaling | `socket_io_client` |
| QR Scanner | `mobile_scanner` |
| Deep Links | `app_links` |
| Audio Session | `audio_session` |

## Getting Started

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) ≥ 3.0.0
- Android SDK (API 21+) or Xcode 14+ for iOS
- The [signaling server](../signaling-server/) running on your computer

### Run on Android

```bash
cd mobile
flutter pub get
flutter run
```

### Build APK

```bash
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

Copy the APK to `web/downloads/syncronization-app.apk` to make it available on the website.

### Run on iOS

```bash
cd mobile/ios
pod install
cd ..
flutter run
```

## Configuration

The signaling server URL defaults to `http://192.168.1.5:3001`. Update it in the app's server URL field to match your computer's LAN IP address. The app remembers the last used server URL.

## Deep Link Format

The extension QR code encodes a URL like:

```
https://synchronization.netlify.app/?id=ABC12345&server=http://192.168.1.5:3001
```

The website's `script.js` converts this to a deep link:

```
syncronization://connect?id=ABC12345&server=http://192.168.1.5:3001
```

Which opens the app and auto-connects to the session.

## Project Structure

```
mobile/
├── lib/
│   ├── main.dart                  # Entry point
│   ├── app.dart                   # MaterialApp setup
│   ├── theme/
│   │   └── app_theme.dart         # Colors, typography, component themes
│   ├── screens/
│   │   ├── home_screen.dart       # Main screen (idle/connecting/connected/error)
│   │   └── qr_scanner_screen.dart # Camera QR scanner
│   ├── services/
│   │   ├── webrtc_service.dart    # WebRTC + Socket.io connection logic
│   │   └── deep_link_service.dart # Deep link / URL scheme handling
│   └── widgets/
│       ├── waveform_visualizer.dart # Animated audio waveform
│       ├── status_indicator.dart    # Pulsing live indicator
│       └── gradient_button.dart     # Purple gradient CTA button
├── android/
│   └── app/src/main/
│       ├── AndroidManifest.xml    # Permissions + deep link intent filters
│       └── kotlin/.../MainActivity.kt
├── ios/
│   ├── Runner/Info.plist          # Permissions + URL scheme
│   └── Podfile
└── pubspec.yaml                   # Dependencies
```
