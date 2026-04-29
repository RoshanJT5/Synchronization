const express = require('express');
const http = require('http');
const { Server } = require('socket.io');

const app = express();
const server = http.createServer(app);
const io = new Server(server, { 
  cors: { 
    origin: "*",
    methods: ["GET", "POST"]
  } 
});

// Store active sessions and their members
const sessions = new Map();

io.on('connection', (socket) => {
  console.log('User connected:', socket.id);

  // When a device (extension or mobile) joins a session
  socket.on('join-session', (sessionId) => {
    const existingPeers = Array.from(io.sockets.adapter.rooms.get(sessionId) || []);

    socket.join(sessionId);
    console.log(`Socket ${socket.id} joined session ${sessionId}`);

    socket.emit('session-peers', { peers: existingPeers });
    
    // Notify others in the session that someone joined
    socket.to(sessionId).emit('peer-joined', { peerId: socket.id });
  });

  // Relay WebRTC signals (offer, answer, ICE candidates)
  socket.on('signal', ({ sessionId, signal, to }) => {
    console.log(`Relaying signal from ${socket.id} to ${to || sessionId}`);
    if (to) {
      // Direct signal to a specific peer (useful for multi-device)
      io.to(to).emit('signal', { from: socket.id, signal });
    } else {
      // Broadcast to everyone else in the session
      socket.to(sessionId).emit('signal', { from: socket.id, signal });
    }
  });

  socket.on('disconnect', () => {
    console.log('User disconnected:', socket.id);
  });
});

const PORT = process.env.PORT || 3001;
server.listen(PORT, '0.0.0.0', () => {
  console.log(`Signaling server running on http://0.0.0.0:${PORT}`);
});
