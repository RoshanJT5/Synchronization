# Synchronization: Setup & Usage Guide

You now have a premium P2P audio synchronization system! This project allows you to stream your browser tab audio to any Android device with ultra-low latency.

## 🚀 Deployment Status
- **Website**: [https://synchronization.pages.dev](https://synchronization.pages.dev)
- **Signaling Server**: Cloud-hosted Node.js (Automatic Relay)

---

## 💻 1. Browser Extension
The extension captures your tab audio and creates a P2P bridge.

1. **Build**:
   ```powershell
   cd extension
   npm install
   npm run build
   ```
2. **Install in Chrome**:
   - Open `chrome://extensions/`
   - Enable **Developer mode**.
   - Click **Load unpacked**.
   - Select the `extension/dist` folder.

---

## 📱 2. Mobile App (Android)
The mobile app receives and plays the stream.

1. **Setup Flutter**: Ensure you have Flutter installed.
2. **Run**:
   ```powershell
   cd mobile
   flutter pub get
   flutter run
   ```
3. **Build APK**:
   ```powershell
   flutter build apk --split-per-abi
   ```

---

## 🛠️ 3. Signaling Server (Advanced)
By default, the app uses the cloud relay at `synchronization.pages.dev`. To run your own:
1. **Run**:
   ```powershell
   cd signaling-server
   npm install
   npm start
   ```
2. **Note**: Update the `SIGNALING_SERVER` constant in `extension/src/App.tsx` and `offscreen.ts` to point to your new server.

---

## 📱 Usage
1. Open a tab with audio (YouTube, Spotify, etc.) and click the **Synchronization Extension** icon.
2. Click **Start Streaming** in the extension popup. A QR code will appear.
3. Open the **Synchronization App** on your Android phone.
4. Click **Scan QR Code** and point your camera at your computer screen.
5. The connection will establish in ~2 seconds. Audio will now play on your phone!

---

## ✨ Features
- **Cloud Relay**: No firewall configuration or IP typing required.
- **Volume Control**: Adjust output level directly from the mobile app.
- **Signal Indicator**: Real-time monitoring of connection quality.
- **Source Toggle**: Choose whether to keep laptop speakers on or mute them.

---
> [!TIP]
> **Multi-Device Support**: Scan the same QR code on multiple phones to create a surround sound experience!
