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
  perMessageDeflate: false,
  httpCompression: false,
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
const SESSION_DISCOVERY_RADIUS_METRES = Number(
  process.env.SESSION_DISCOVERY_RADIUS_METRES || 50,
);
const DEBUG_SIGNALING = process.env.DEBUG_SIGNALING === 'true';
const MAX_SIGNAL_BYTES = 200_000;

function normalizeSessionId(value) {
  if (typeof value !== 'string') return null;
  const sessionId = value.trim().toUpperCase();
  return /^[A-Z0-9_-]{3,64}$/.test(sessionId) ? sessionId : null;
}

function normalizeCoordinate(value) {
  if (value == null || value === '') return null;
  const coordinate = Number(value);
  return Number.isFinite(coordinate) ? coordinate : null;
}

function hasValidCoordinates(lat, lng) {
  return (
    Number.isFinite(lat) &&
    Number.isFinite(lng) &&
    lat >= -90 &&
    lat <= 90 &&
    lng >= -180 &&
    lng <= 180
  );
}

function isSafeSignalPayload(signal) {
  if (!signal || typeof signal !== 'object') return false;
  try {
    return JSON.stringify(signal).length <= MAX_SIGNAL_BYTES;
  } catch {
    return false;
  }
}

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

function cleanIp(ip) {
  if (typeof ip !== 'string') return '';
  return ip.split(',')[0].trim().replace(/^::ffff:/, '');
}

io.on('connection', (socket) => {
  console.log('User connected:', socket.id);

  // Extract Cloudflare IP Geolocation and IP headers passed via query parameters
  const queryIp = socket.handshake.query.cf_ip;
  const forwardHeader = socket.handshake.headers['x-forwarded-for'];
  const rawIp = queryIp || forwardHeader || socket.handshake.address;
  socket.clientIp = cleanIp(rawIp);

  const cfLatRaw = socket.handshake.query.cf_lat;
  const cfLngRaw = socket.handshake.query.cf_lng;
  const cfLat = cfLatRaw ? Number(cfLatRaw) : null;
  const cfLng = cfLngRaw ? Number(cfLngRaw) : null;
  socket.cfLocation = (cfLat !== null && cfLng !== null && Number.isFinite(cfLat) && Number.isFinite(cfLng))
    ? { lat: cfLat, lng: cfLng }
    : null;

  // ── Discovery: extension/host announces it is streaming ─────────────────
  // Now accepts optional lat/lng so the server stores the session's location.
  socket.on('announce-session', ({ sessionId, label, type, lat, lng }) => {
    sessionId = normalizeSessionId(sessionId);
    if (!sessionId) return;
    const safeType = type === 'mobile-host' ? 'mobile-host' : 'computer';
    
    // Check GPS coordinates
    const safeLat = normalizeCoordinate(lat);
    const safeLng = normalizeCoordinate(lng);
    const hasGpsLocation = hasValidCoordinates(safeLat, safeLng);

    // Fallback to Cloudflare IP Geolocation for extension/computer if GPS is not supplied
    let finalLat = safeLat;
    let finalLng = safeLng;
    let locationSource = 'gps';

    if (!hasGpsLocation && safeType === 'computer' && socket.cfLocation) {
      finalLat = socket.cfLocation.lat;
      finalLng = socket.cfLocation.lng;
      locationSource = 'cloudflare_geo';
    }

    const finalHasLocation = hasValidCoordinates(finalLat, finalLng);
    const existing = activeSessions.get(sessionId);

    if (DEBUG_SIGNALING) {
      console.log(`Session announced: ${sessionId} (${label || 'Unnamed'}, type=${safeType}, lat=${finalHasLocation ? finalLat : 'none'}, lng=${finalHasLocation ? finalLng : 'none'}, source=${locationSource})`);
    }

    activeSessions.set(sessionId, {
      sessionId,
      label: label || 'Computer',
      type: safeType,
      socketId: socket.id,
      announcedAt: existing?.announcedAt || Date.now(),
      lastSeen: Date.now(),
      lat: finalHasLocation ? finalLat : null,
      lng: finalHasLocation ? finalLng : null,
      clientIp: socket.clientIp || null,
      locationSource: finalHasLocation ? locationSource : 'none',
    });
    broadcastActiveSessions();
  });

  socket.on('session-heartbeat', ({ sessionId }) => {
    sessionId = normalizeSessionId(sessionId);
    if (!sessionId) return;
    const session = activeSessions.get(sessionId);
    if (!session) return;

    session.socketId = socket.id;
    session.lastSeen = Date.now();
  });

  // ── Discovery: extension signals it stopped streaming ───────────────────
  socket.on('end-session', ({ sessionId }) => {
    sessionId = normalizeSessionId(sessionId);
    if (!sessionId) return;
    console.log(`Session ended: ${sessionId}`);
    activeSessions.delete(sessionId);
    broadcastActiveSessions();
  });

  // ── Discovery: mobile requests sessions within 50m of its GPS ───────────
  // The client sends { lat, lng } with the request.
  // The server runs Haversine and only returns sessions within 50 metres.
  socket.on('get-active-sessions', (data) => {
    const reqLat = normalizeCoordinate(data?.lat);
    const reqLng = normalizeCoordinate(data?.lng);
    const requesterHasLocation = hasValidCoordinates(reqLat, reqLng);

    // Extract mobile client's IP. Prefer the Cloudflare-injected cf_ip query
    // param (same source as used for the extension) to ensure consistent
    // IP matching on both sides of the same-Wi-Fi check.
    const mobileQueryIp = socket.handshake.query.cf_ip;
    const mobileForwardHeader = socket.handshake.headers['x-forwarded-for'];
    const mobileRawIp = mobileQueryIp || mobileForwardHeader || socket.handshake.address;
    const mobileIp = cleanIp(mobileRawIp);

    pruneExpiredSessions();

    const list = Array.from(activeSessions.values())
      .filter(({ type, lat, lng, clientIp, locationSource }) => {
        const isComputerSession = (type || 'computer') === 'computer';
        const sessionHasLocation = hasValidCoordinates(lat, lng);

        // 1. Local/dev fallback: If it's a computer session and has NO location info,
        // (meaning it did not come through Cloudflare proxy, e.g. localhost), show it by default.
        if (isComputerSession && !sessionHasLocation) {
          return true;
        }

        // 2. Same-Wi-Fi check (IP matching): If public IPs are identical, they are nearby (0m distance)
        if (clientIp && mobileIp && clientIp === mobileIp) {
          return true;
        }

        // Location is required for both if we are calculating distance
        if (!requesterHasLocation || !sessionHasLocation) {
          return false;
        }

        const dist = haversineMetres(reqLat, reqLng, lat, lng);

        // 3. Dynamic search threshold:
        // Use a 5km radius to compensate for IP location database offset,
        // or a precise 50m radius if using GPS-to-GPS.
        const allowedRadius = locationSource === 'cloudflare_geo' ? 5000 : SESSION_DISCOVERY_RADIUS_METRES;
        return dist <= allowedRadius;
      })
      .map(({ sessionId, label, type, announcedAt }) => ({
        sessionId,
        label,
        type: type || 'computer',
        announcedAt,
      }));

    if (DEBUG_SIGNALING) {
      console.log(`get-active-sessions from (${reqLat},${reqLng}) -> ${list.length} session(s)`);
    }
    socket.emit('active-sessions-updated', { sessions: list });
  });

  // ── Session join (WebRTC signaling room) ─────────────────────────────────
  socket.on('join-session', (sessionId) => {
    sessionId = normalizeSessionId(sessionId);
    if (!sessionId) return;
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
    sessionId = normalizeSessionId(sessionId);
    if (!sessionId || !isSafeSignalPayload(signal)) return;
    if (DEBUG_SIGNALING) {
      console.log(`Relaying signal from ${socket.id} to ${to || sessionId}`);
    }
    if (typeof to === 'string' && to.length <= 128) {
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
