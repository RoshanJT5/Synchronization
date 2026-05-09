# Synchronization: Remote Browser Speaker

Synchronization is a tool that allows you to use your mobile device (or multiple devices) as external speakers for any audio playing in your browser (Netflix, YouTube, Prime, etc.).

## 🚀 Concept
- **Browser Extension**: Captures audio and generates a QR code.
- **Mobile App**: Scans the QR code and plays the audio with low latency.
- **Multi-Device Support**: Connect multiple phones to create a unified audio system.

## 🛠️ Tech Stack
- **Protocol**: WebRTC (Peer-to-Peer) for ultra-low latency.
- **Signaling Server**: Node.js + Socket.io for initial handshake.
- **Browser Extension**: Manifest V3, Chrome `tabCapture` API, React, TypeScript.
- **Mobile App**: Flutter 3.x (Dart) — `flutter_webrtc` for P2P audio, `socket_io_client` for signaling, `mobile_scanner` for QR codes, `app_links` for deep link handling.

## 📋 Requirements
### Functional
- Capture high-quality audio from browser tabs.
- One-click connection via QR code.
- Support for multiple receivers simultaneously.
- Real-time synchronization (< 50ms latency).

### Aesthetics
- **Extension**: Sleek dark mode UI with a glowing QR code and connection status animations.
- **Mobile App**: Premium minimalist design with wave-form audio visualizations.

## 📅 Implementation Plan
1. **Phase 1: Signaling Infrastructure**
   - Setup Node.js server to exchange WebRTC signals.
2. **Phase 2: Extension Development**
   - Implement `chrome.tabCapture`.
   - Build QR code generation UI.
   - Establish WebRTC Peer connection.
3. **Phase 3: Mobile App Development**
   - Build QR scanner.
   - Implement WebRTC MediaStream playback.
   - Optimize for background audio playback.
4. **Phase 4: Multi-Device Sync**
   - Enable signaling to multiple peers.
   - Implement clock synchronization if needed for multi-device lag.

---
> [!IMPORTANT]
> The full implementation plan has been saved to [docs/plans/2026-04-29-synchronization.md](file:///c:/Users/Roshan%20Talreja/Desktop/MY%20PROJECTS/Synchronization/docs/plans/2026-04-29-synchronization.md).
