# Syncronization: Setup & Usage Guide

You now have a complete P2P audio synchronization system! Follow these steps to get it running.

## 1. Signaling Server
This server handles the connection handshake between your PC and mobile devices.
- **Location**: `signaling-server/`
- **Run**: 
  ```bash
  cd signaling-server
  npm install
  npm start
  ```
- **Note**: The server runs on port `3001` by default.

## 2. Browser Extension
Captures your tab audio and streams it.
- **Location**: `extension/`
- **Build**:
  ```bash
  cd extension
  npm install
  npm run build
  ```
- **Install in Chrome**:
  1. Open `chrome://extensions/`
  2. Enable "Developer mode" (top right).
  3. Click "Load unpacked".
  4. Select the `extension/dist` folder.

## 3. Mobile App
Receives the audio stream and plays it.
- **Location**: `mobile/`
- **Important**: Update `SIGNALING_SERVER` in `App.tsx` with your computer's local IP address (e.g., `http://192.168.1.5:3001`).
- **Run**:
  ```bash
  cd mobile
  npm install
  npx react-native run-android # Or run-ios
  ```

## 📱 Usage
1. Start the **Signaling Server**.
2. Open a tab with audio (e.g., YouTube) and click the **Syncronization Extension**.
3. Click **"Start Sync"** in the extension popup.
4. Open the **Mobile App** and click **"Scan QR Code"**.
5. Scan the QR code displayed in the extension.
6. Enjoy synchronized audio on your phone!

---
> [!TIP]
> You can connect multiple phones to the same session ID to create a multi-speaker system!
