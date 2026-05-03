const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const path = require('path');

const app = express();
const server = http.createServer(app);

// Serve the static website files from the 'web' directory
app.use(express.static(path.join(__dirname, '../web')));

// Handle the /connect redirect specifically to ensure it matches the old structure
app.get('/connect', (req, res) => {
  res.sendFile(path.join(__dirname, '../web/connect/index.html'));
});

const io = new Server(server, { 
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

function broadcastActiveSessions() {
  const list = Array.from(activeSessions.values()).map(({ sessionId, label, announcedAt }) => ({
    sessionId,
    label,
    announcedAt,
  }));
  io.emit('active-sessions-updated', { sessions: list });
}
// ─────────────────────────────────────────────────────────────────────────────

io.on('connection', (socket) => {
  console.log('User connected:', socket.id);

  // ── Discovery: extension announces it is streaming ──────────────────────
  socket.on('announce-session', ({ sessionId, label }) => {
    console.log(`Session announced: ${sessionId} (${label || 'Unnamed'})`);
    activeSessions.set(sessionId, {
      sessionId,
      label: label || 'Computer',
      socketId: socket.id,
      announcedAt: Date.now(),
    });
    broadcastActiveSessions();
  });

  // ── Discovery: extension signals it stopped streaming ───────────────────
  socket.on('end-session', ({ sessionId }) => {
    console.log(`Session ended: ${sessionId}`);
    activeSessions.delete(sessionId);
    broadcastActiveSessions();
  });

  // ── Discovery: mobile requests current list of active sessions ───────────
  socket.on('get-active-sessions', () => {
    const list = Array.from(activeSessions.values()).map(({ sessionId, label, announcedAt }) => ({
      sessionId,
      label,
      announcedAt,
    }));
    socket.emit('active-sessions-updated', { sessions: list });
  });

  // ── Session join (WebRTC signaling room) ─────────────────────────────────
  socket.on('join-session', (sessionId) => {
    const existingPeers = Array.from(io.sockets.adapter.rooms.get(sessionId) || []);

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
