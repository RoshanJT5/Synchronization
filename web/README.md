# Synchronization

Stream browser audio to your Android phone with ultra-low latency.

## What it does & Purpose
Synchronization bridges the audio gap between your desktop browser and your mobile device. Whether your headphone jack is broken, your Bluetooth headphones are paired to your phone, or you just want to listen to a movie playing on your laptop while walking around the house, Synchronization streams the audio tab directly to your Android device using WebRTC P2P technology for zero-latency playback.

## Installation Guide
1. **Chrome Extension**: Download `synchronization-extension.zip`. Unzip it. Go to `chrome://extensions`, enable "Developer mode", and click "Load unpacked" to select the extracted folder.
2. **Android App**: Download `synchronization-app.apk` and install it on your Android device.

## Usage
1. Open a tab with audio in Chrome.
2. Click the Synchronization extension icon and press **Start Streaming**. A QR code will appear.
3. Open the Synchronization Android app, tap **Scan QR Code**, and scan the screen. Audio will start streaming immediately.

## Privacy Policy
Synchronization operates on a purely peer-to-peer (P2P) basis. We do not collect, store, or transmit your audio data, personal information, or browsing history to any external servers. The signaling server is only used momentarily to establish a direct connection between your devices.

## Terms and Conditions
By using Synchronization, you agree that the software is provided "as is" without warranty of any kind. You are responsible for the content you stream and must comply with all applicable local laws.

---

## Deploy
Upload the `web/` folder to Render or any static host.

## Downloads
Put release artifacts here before deployment:
- `web/downloads/synchronization-app.apk`
- `web/downloads/synchronization-extension.zip`

## QR / Deep Link Flow
The extension QR points to:
`https://synchronization-807q.onrender.com/connect?id=SESSION&server=https://synchronization-807q.onrender.com`

The website opens:
`synchronization://connect?id=SESSION&server=https://synchronization-807q.onrender.com`

If the app is installed, it opens and connects. If it is not installed, the user stays on the website and can download the app.
