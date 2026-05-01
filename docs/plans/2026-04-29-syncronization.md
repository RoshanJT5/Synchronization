# Syncronization Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create a browser extension and mobile app that synchronizes browser audio to mobile devices via WebRTC for low-latency remote speaker functionality.

**Architecture:** Peer-to-Peer audio streaming using WebRTC. A Node.js signaling server facilitates the initial connection via QR code. The extension acts as the audio source (Peer A) and the mobile app as the receiver (Peer B).

**Tech Stack:** 
- **Extension**: Manifest V3, React, WebRTC, `chrome.tabCapture`
- **Mobile App**: React Native, `react-native-webrtc`, `react-native-vision-camera`
- **Signaling**: Node.js, Socket.io
- **Connection**: QR Code (Signaling ID)

---

### Task 1: Signaling Server Setup
**Files:**
- Create: `signaling-server/package.json`
- Create: `signaling-server/server.js`

**Step 1: Initialize signaling server project**
Run: `mkdir signaling-server && cd signaling-server && npm init -y`

**Step 2: Install dependencies**
Run: `npm install socket.io express cors`

**Step 3: Implement basic signaling logic**
```javascript
const express = require('express');
const http = require('http');
const { Server } = require('socket.io');

const app = express();
const server = http.createServer(app);
const io = new Server(server, { cors: { origin: "*" } });

io.on('connection', (socket) => {
  console.log('User connected:', socket.id);

  socket.on('join-session', (sessionId) => {
    socket.join(sessionId);
    console.log(`Socket ${socket.id} joined session ${sessionId}`);
  });

  socket.on('signal', ({ sessionId, signal }) => {
    socket.to(sessionId).emit('signal', { from: socket.id, signal });
  });

  socket.on('disconnect', () => {
    console.log('User disconnected:', socket.id);
  });
});

const PORT = process.env.PORT || 3001;
server.listen(PORT, () => console.log(`Signaling server running on port ${PORT}`));
```

**Step 4: Commit**
```bash
git add signaling-server/
git commit -m "feat: setup basic signaling server"
```

---

### Task 2: Browser Extension - Foundation
**Files:**
- Create: `extension/manifest.json`
- Create: `extension/popup.html`
- Create: `extension/popup.js`

**Step 1: Create Manifest V3**
```json
{
  "manifest_version": 3,
  "name": "Syncronization",
  "version": "1.0",
  "permissions": ["tabCapture", "activeTab", "storage"],
  "action": {
    "default_popup": "popup.html"
  },
  "background": {
    "service_worker": "background.js"
  }
}
```

**Step 2: Create simple popup with QR generation**
Install `qrcode` in extension folder first.
```html
<!DOCTYPE html>
<html>
<head>
  <title>Syncronization</title>
  <style>
    body { width: 300px; padding: 10px; text-align: center; }
    #qrcode { margin: 20px auto; }
  </style>
</head>
<body>
  <h1>Syncronization</h1>
  <div id="qrcode"></div>
  <p id="status">Connecting...</p>
  <script src="qrcode.min.js"></script>
  <script src="popup.js"></script>
</body>
</html>
```

**Step 3: Implement QR generation and signaling handshake**
(Logic to connect to Socket.io and display sessionId as QR)

**Step 4: Commit**
```bash
git add extension/
git commit -m "feat: extension skeleton and QR setup"
```

---

### Task 3: Browser Extension - Audio Capture
**Files:**
- Create: `extension/background.js`
- Modify: `extension/popup.js`

**Step 1: Implement chrome.tabCapture logic**
```javascript
// In background.js or triggered via popup
chrome.tabCapture.capture({ audio: true, video: false }, (stream) => {
  if (!stream) {
    console.error('Error capturing stream:', chrome.runtime.lastError);
    return;
  }
  // Setup WebRTC with this stream
});
```

**Step 2: Commit**
```bash
git commit -m "feat: audio capture logic in extension"
```

---

### Task 4: Mobile App Setup (React Native)
**Files:**
- Create: `mobile/App.tsx`

**Step 1: Initialize RN project**
Run: `npx react-native init SyncronizationApp --directory mobile`

**Step 2: Install WebRTC and Camera libs**
Run: `npm install react-native-webrtc react-native-vision-camera socket.io-client`

**Step 3: Implement QR Scanner and WebRTC Receiver**
(Logic to scan, join signaling session, and play incoming MediaStream)

**Step 4: Commit**
```bash
git add mobile/
git commit -m "feat: mobile app skeleton with WebRTC receiver"
```

---

### Task 5: Testing & Polishing
- Test latency.
- Implement "multiple devices" logic (Signaling server handles broadcasting to all joined sockets).
- UI/UX improvements (Aesthetics).
