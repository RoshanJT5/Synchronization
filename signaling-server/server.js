const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const path = require('path');

const app = express();
const server = http.createServer(app);
const webRoot = path.join(__dirname, '../web');
const downloadsRoot = path.join(webRoot, 'downloads');

app.get('/__version', (req, res) => {
  const artifact = (fileName) => {
    try {
      const stats = require('fs').statSync(path.join(downloadsRoot, fileName));
      return {
        bytes: stats.size,
        modifiedAt: stats.mtime.toISOString(),
      };
    } catch (error) {
      return null;
    }
  };

  res.setHeader('Cache-Control', 'no-store, max-age=0');
  res.json({
    gitCommit: process.env.RENDER_GIT_COMMIT || process.env.COMMIT_SHA || 'local',
    buildTag: 'downloads-20260509-0215',
    extensionZip: artifact('syncronization-extension.zip'),
    androidApk: artifact('syncronization-app.apk'),
  });
});

app.use('/downloads', express.static(downloadsRoot, {
  setHeaders: (res) => {
    res.setHeader('Cache-Control', 'no-store, max-age=0');
    res.setHeader('Content-Disposition', 'attachment');
  },
}));

// Serve the static website files from the 'web' directory
app.use(express.static(webRoot, {
  setHeaders: (res, filePath) => {
    if (filePath.includes(`${path.sep}downloads${path.sep}`)) {
      res.setHeader('Cache-Control', 'no-store, max-age=0');
      res.setHeader('Content-Disposition', 'attachment');
    }
  },
}));

// Handle the /connect redirect specifically to ensure it matches the old structure
app.get('/connect', (req, res) => {
  res.sendFile(path.join(webRoot, 'connect/index.html'));
});

// Short QR URL: /c/ABC123 is easier and faster for phone cameras to decode
// than the old /connect?id=ABC123 form. The connect page reads the ID from
// the path and opens the mobile app when installed.
app.get('/c/:sessionId', (req, res) => {
  res.sendFile(path.join(webRoot, 'connect/index.html'));
});

const io = new Server(server, {
  pingInterval: 10000,
  pingTimeout: 20000,
  cors: { 
    origin: "*",
    methods: ["GET", "POST"]
  } 
});

// ── Active session announcements ─────────────────────────────────────────────
// Map of sessionId → { label, socketId, announcedAt }
// Extensions call 'announce-session' when they start streaming.
// Mobile clients call 'get-active-sessions' to get the current list,
// and subscribe to 'active-sessions-updated' for live updates.
const activeSessions = new Map();
const SESSION_TTL_MS = 20000;

function broadcastActiveSessions() {
  pruneExpiredSessions();
  const list = Array.from(activeSessions.values()).map(({ sessionId, label, announcedAt }) => ({
    sessionId,
    label,
    announcedAt,
  }));
  io.emit('active-sessions-updated', { sessions: list });
}

function pruneExpiredSessions() {
  const now = Date.now();
  let changed = false;

  for (const [sessionId, info] of activeSessions.entries()) {
    if (now - (info.lastSeen || info.announcedAt || 0) > SESSION_TTL_MS) {
      activeSessions.delete(sessionId);
      changed = true;
      console.log(`Expired stale session ${sessionId}`);
    }
  }

  return changed;
}

setInterval(() => {
  if (pruneExpiredSessions()) {
    broadcastActiveSessions();
  }
}, 15000);
// ─────────────────────────────────────────────────────────────────────────────

io.on('connection', (socket) => {
  console.log('User connected:', socket.id);

  // ── Discovery: extension announces it is streaming ──────────────────────
  socket.on('announce-session', ({ sessionId, label }) => {
    if (!sessionId) return;
    const existing = activeSessions.get(sessionId);
    console.log(`Session announced: ${sessionId} (${label || 'Unnamed'})`);
    activeSessions.set(sessionId, {
      sessionId,
      label: label || 'Computer',
      socketId: socket.id,
      announcedAt: existing?.announcedAt || Date.now(),
      lastSeen: Date.now(),
    });
    broadcastActiveSessions();
  });

  socket.on('session-heartbeat', ({ sessionId }) => {
    const session = activeSessions.get(sessionId);
    if (!session) return;

    session.socketId = socket.id;
    session.lastSeen = Date.now();
  });

  // ── Discovery: extension signals it stopped streaming ───────────────────
  socket.on('end-session', ({ sessionId }) => {
    console.log(`Session ended: ${sessionId}`);
    activeSessions.delete(sessionId);
    broadcastActiveSessions();
  });

  // ── Discovery: mobile requests current list of active sessions ───────────
  socket.on('get-active-sessions', () => {
    pruneExpiredSessions();
    const list = Array.from(activeSessions.values()).map(({ sessionId, label, announcedAt }) => ({
      sessionId,
      label,
      announcedAt,
    }));
    socket.emit('active-sessions-updated', { sessions: list });
  });

  // ── Session join (WebRTC signaling room) ─────────────────────────────────
  socket.on('join-session', (sessionId) => {
    const existingPeers = Array.from(io.sockets.adapter.rooms.get(sessionId) || [])
      .filter((peerId) => peerId !== socket.id);

    socket.join(sessionId);
    console.log(`Socket ${socket.id} joined session ${sessionId}`);

    socket.emit('session-peers', { peers: existingPeers });
    
    // Notify others in the session that someone joined
    socket.to(sessionId).emit('peer-joined', { peerId: socket.id });
  });

  // ── WebRTC signal relay ──────────────────────────────────────────────────
  socket.on('signal', ({ sessionId, signal, to }) => {
    console.log(`Relaying signal from ${socket.id} to ${to || sessionId}`);
    if (to) {
      io.to(to).emit('signal', { from: socket.id, signal });
    } else {
      socket.to(sessionId).emit('signal', { from: socket.id, signal });
    }
  });

  socket.on('disconnect', () => {
    console.log('User disconnected:', socket.id);
    // Clean up any sessions this socket was announcing
    for (const [sessionId, info] of activeSessions.entries()) {
      if (info.socketId === socket.id) {
        activeSessions.delete(sessionId);
        console.log(`Auto-removed session ${sessionId} (owner disconnected)`);
      }
    }
    broadcastActiveSessions();
  });
});

const PORT = process.env.PORT || 3001;
server.listen(PORT, '0.0.0.0', () => {
  console.log(`Signaling server running on http://0.0.0.0:${PORT}`);
});
