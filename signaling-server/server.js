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
    gitCommit: process.env.COMMIT_SHA || 'local',
    buildTag: 'downloads-20260512-0130',
    extensionZip: artifact('synchronization-extension.zip'),
    androidApk: artifact('synchronization-app.apk'),
    androidApks: {
      arm64: artifact('synchronization-arm64.apk'),
      arm32: artifact('synchronization-arm32.apk'),
      x86_64: artifact('synchronization-x86_64.apk'),
    },
  });
});

// Health check endpoint — used by the self-ping keepalive below
// and available for external uptime monitors.
app.get('/health', (req, res) => {
  res.setHeader('Cache-Control', 'no-store');
  res.json({ status: 'ok', uptime: process.uptime(), sessions: activeSessions?.size ?? 0 });
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
  perMessageDeflate: true,
  httpCompression: true,
  cors: { 
    origin: "*",
    methods: ["GET", "POST"]
  } 
});

// ── Active session announcements ─────────────────────────────────────────────
// Map of sessionId → { label, socketId, announcedAt, lat, lng }
// Extensions call 'announce-session' when they start streaming.
// Mobile clients call 'get-active-sessions' with their GPS to get a
// proximity-filtered list (50-metre radius).
const activeSessions = new Map();
const SESSION_TTL_MS = 90000;

// ── Haversine distance (metres between two GPS coordinates) ──────────────────
function haversineMetres(lat1, lng1, lat2, lng2) {
  const R = 6_371_000; // Earth radius in metres
  const toRad = (deg) => (deg * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function broadcastActiveSessions() {
  // Broadcast is only used for general server-push (e.g. after a session ends).
  // Individual clients receive proximity-filtered lists via 'get-active-sessions'.
  pruneExpiredSessions();
  // We emit refresh-sessions-needed so any connected client can refresh 
  // by calling get-active-sessions to get their filtered view without wiping the UI.
  io.emit('refresh-sessions-needed');
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

  // ── Discovery: extension/host announces it is streaming ─────────────────
  // Now accepts optional lat/lng so the server stores the session's location.
  socket.on('announce-session', ({ sessionId, label, type, lat, lng }) => {
    if (!sessionId) return;
    const existing = activeSessions.get(sessionId);
    console.log(`Session announced: ${sessionId} (${label || 'Unnamed'}, type=${type || 'computer'}, lat=${lat ?? 'none'}, lng=${lng ?? 'none'})`);
    activeSessions.set(sessionId, {
      sessionId,
      label: label || 'Computer',
      type: type || 'computer',
      socketId: socket.id,
      announcedAt: existing?.announcedAt || Date.now(),
      lastSeen: Date.now(),
      lat: lat ?? null,
      lng: lng ?? null,
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

  // ── Discovery: mobile requests sessions within 50m of its GPS ───────────
  // The client sends { lat, lng } with the request.
  // The server runs Haversine and only returns sessions within 50 metres.
  socket.on('get-active-sessions', (data) => {
    const reqLat = data?.lat ?? null;
    const reqLng = data?.lng ?? null;

    pruneExpiredSessions();

    const list = Array.from(activeSessions.values())
      .filter(({ lat, lng }) => {
        // Both sides must have GPS for the proximity filter to work.
        // If either side is missing coordinates, exclude for safety.
        if (lat == null || lng == null || reqLat == null || reqLng == null) {
          return false;
        }
        const dist = haversineMetres(reqLat, reqLng, lat, lng);
        return dist <= 50; // 50-metre radius
      })
      .map(({ sessionId, label, type, announcedAt }) => ({
        sessionId,
        label,
        type: type || 'computer',
        announcedAt,
      }));

    console.log(`get-active-sessions from (${reqLat},${reqLng}) → ${list.length} session(s) within 50m`);
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
