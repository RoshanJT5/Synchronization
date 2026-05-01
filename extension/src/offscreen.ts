import { Buffer } from 'buffer';
(window as any).Buffer = Buffer;
(window as any).global = window;
(window as any).process = (window as any).process || { env: {} };

const SIGNALING_SERVER = 'https://syncronization-server.onrender.com';
let Peer: typeof import('simple-peer').default;
let socket: import('socket.io-client').Socket | null = null;
const peers = new Map<string, any>();
let audioPlayer: HTMLAudioElement | null = null;
let activeSessionId = '';
let networkingReady: Promise<void> | null = null;

// ── Source audio passthrough (keeps laptop speakers alive while streaming) ──
let audioCtx: AudioContext | null = null;
let sourceNode: MediaStreamAudioSourceNode | null = null;
let localGain: GainNode | null = null;       // controls local playback volume
let localDest: MediaStreamAudioDestinationNode | null = null; // feeds local <audio>
let localAudioEl: HTMLAudioElement | null = null;
let sourceMuted = false;  // tracks current mute state

console.log('Offscreen document initialized');

// Signal to background that we are ready to receive INIT
chrome.runtime.sendMessage({ type: 'OFFSCREEN_READY' });

chrome.runtime.onMessage.addListener((message) => {
  if (message.type === 'INIT_OFFSCREEN') {
    console.log('Received INIT_OFFSCREEN:', message);
    if (message.mode === 'SEND') {
      startSendMode(message.sessionId, message.streamId);
    } else {
      startReceiveMode(message.sessionId);
    }
  }

  // Toggle local (source) audio on/off while streaming
  if (message.type === 'SET_SOURCE_MUTE') {
    sourceMuted = message.muted;
    if (localGain) {
      // Smooth ramp to avoid clicks
      localGain.gain.setTargetAtTime(sourceMuted ? 0 : 1, audioCtx!.currentTime, 0.05);
    }
    console.log('Source audio muted:', sourceMuted);
  }
});

async function startSendMode(sessionId: string, streamId: string) {
  try {
    await ensureNetworkingReady();
    resetSessionState();
    activeSessionId = sessionId;

    const rawStream = await navigator.mediaDevices.getUserMedia({
      audio: {
        // @ts-ignore
        mandatory: {
          chromeMediaSource: 'tab',
          chromeMediaSourceId: streamId
        }
      },
      video: false
    });

    // ── Audio graph ──────────────────────────────────────────────────────
    // rawStream → sourceNode ─┬─ localGain → localDest → <audio> (laptop speakers)
    //                         └─ (stream passed directly to WebRTC peers)
    //
    // The WebRTC peer uses rawStream directly so remote devices always get
    // full-volume audio regardless of the local mute toggle.
    // ─────────────────────────────────────────────────────────────────────
    audioCtx = new AudioContext();
    sourceNode = audioCtx.createMediaStreamSource(rawStream);
    localGain = audioCtx.createGain();
    localDest = audioCtx.createMediaStreamDestination();

    // Start unmuted — laptop keeps playing by default
    localGain.gain.value = sourceMuted ? 0 : 1;

    sourceNode.connect(localGain);
    localGain.connect(localDest);

    // Play the local passthrough so the tab audio comes out of the laptop
    localAudioEl = document.createElement('audio');
    localAudioEl.srcObject = localDest.stream;
    localAudioEl.autoplay = true;
    document.body.appendChild(localAudioEl);
    localAudioEl.play().catch(err => console.warn('Local passthrough play failed:', err));

    // rawStream is what we send to peers — untouched, always full volume
    const stream = rawStream;

    await ensureSignalingConnected(sessionId);

    socket?.on('peer-joined', ({ peerId }) => {
      if (activeSessionId !== sessionId) return;
      console.log('Receiver joined session:', peerId);
      setupPeer(sessionId, true, stream, peerId);
    });

    socket?.on('session-peers', ({ peers }) => {
      if (activeSessionId !== sessionId) return;
      for (const peerId of peers || []) {
        console.log('Found receiver already in session:', peerId);
        setupPeer(sessionId, true, stream, peerId);
      }
    });

    socket?.on('signal', ({ from, signal }) => {
      if (activeSessionId !== sessionId) return;
      const peer = peers.get(from);
      if (peer) {
        peer.signal(signal);
      }
    });

    socket?.emit('join-session', sessionId);

    // Announce this session so mobile clients can auto-discover it
    socket?.emit('announce-session', {
      sessionId,
      label: 'This Computer',
    });

    chrome.runtime.sendMessage({ type: 'CONNECTION_SUCCESS' });
  } catch (error: any) {
    console.error('SEND error:', error);
    chrome.runtime.sendMessage({ type: 'CONNECTION_ERROR', error: error.message });
  }
}

async function startReceiveMode(sessionId: string) {
  console.log('Starting RECEIVE mode for session:', sessionId);

  try {
    await ensureNetworkingReady();
    resetSessionState();
    activeSessionId = sessionId;

    await ensureSignalingConnected(sessionId);

    socket?.on('signal', ({ from, signal }) => {
      if (activeSessionId !== sessionId) return;
      let peer = peers.get(from);
      if (!peer) {
        console.log('First signal from sender received, setting up peer');
        peer = setupPeer(sessionId, false, null, from);
      }
      peer.signal(signal);
    });

    socket?.emit('join-session', sessionId);

    // Notify UI that the signaling room is joined. WebRTC stream follows when the sender offers.
    chrome.runtime.sendMessage({ type: 'CONNECTION_SUCCESS' });
  } catch (error: any) {
    console.error('RECEIVE error:', error);
    chrome.runtime.sendMessage({ type: 'CONNECTION_ERROR', error: error.message });
  }
}

function setupPeer(sessionId: string, initiator: boolean, stream: MediaStream | null, targetId: string) {
  destroyPeer(targetId);

  const peer = new Peer({
    initiator: initiator,
    trickle: true, // Switched to trickle for faster handshake
    stream: stream || undefined,
    config: { iceServers: [{ urls: 'stun:stun.l.google.com:19302' }] }
  });

  peer.peerId = targetId;
  peers.set(targetId, peer);

  peer.on('signal', (data: any) => {
    socket.emit('signal', { sessionId, signal: data, to: targetId });
  });

  peer.on('stream', (remoteStream: MediaStream) => {
    console.log('WebRTC Stream Received!');
    playStream(remoteStream);
  });

  peer.on('connect', () => {
    console.log('WebRTC P2P Connection established!');
    chrome.runtime.sendMessage({ type: 'CONNECTION_SUCCESS' });
  });

  peer.on('close', () => {
    peers.delete(targetId);
  });

  peer.on('error', (err: any) => {
    console.error('Peer error:', err);
    peers.delete(targetId);
    chrome.runtime.sendMessage({ type: 'CONNECTION_ERROR', error: 'WebRTC Peer Error' });
  });

  return peer;
}

function resetSessionState() {
  // End the announced session so it disappears from mobile discovery
  if (activeSessionId && socket?.connected) {
    socket.emit('end-session', { sessionId: activeSessionId });
  }

  socket?.off('peer-joined');
  socket?.off('session-peers');
  socket?.off('signal');
  destroyAllPeers();

  // Tear down local audio passthrough
  if (localAudioEl) {
    localAudioEl.srcObject = null;
    localAudioEl.remove();
    localAudioEl = null;
  }
  if (sourceNode) { try { sourceNode.disconnect(); } catch (_) {} sourceNode = null; }
  if (localGain)  { try { localGain.disconnect();  } catch (_) {} localGain = null; }
  if (localDest)  { try { localDest.disconnect();  } catch (_) {} localDest = null; }
  if (audioCtx && audioCtx.state !== 'closed') {
    audioCtx.close().catch(() => {});
    audioCtx = null;
  }
}

function destroyPeer(peerId: string) {
  const peer = peers.get(peerId);
  if (peer) {
    try { peer.destroy(); } catch (e) { }
    peers.delete(peerId);
  }
}

function destroyAllPeers() {
  for (const peerId of peers.keys()) {
    destroyPeer(peerId);
  }
}

function ensureSignalingConnected(sessionId: string) {
  return new Promise<void>((resolve, reject) => {
    if (!socket) {
      reject(new Error('Signaling client is not ready.'));
      return;
    }

    if (socket.connected) {
      resolve();
      return;
    }

    const timeout = window.setTimeout(() => {
      cleanup();
      reject(new Error(`Could not connect to signaling server at ${SIGNALING_SERVER}. Is it running?`));
    }, 10000);

    const cleanup = () => {
      window.clearTimeout(timeout);
      socket.off('connect', onConnect);
      socket.off('connect_error', onConnectError);
    };

    const onConnect = () => {
      cleanup();
      console.log('Connected to signaling server for session:', sessionId);
      resolve();
    };

    const onConnectError = (error: Error) => {
      cleanup();
      reject(new Error(error.message || `Could not connect to ${SIGNALING_SERVER}`));
    };

    socket.once('connect', onConnect);
    socket.once('connect_error', onConnectError);
    socket.connect();
  });
}

function playStream(stream: MediaStream) {
  if (!audioPlayer) {
    audioPlayer = document.createElement('audio');
    audioPlayer.autoplay = true;
    document.body.appendChild(audioPlayer);
  }
  audioPlayer.srcObject = stream;
  audioPlayer.play().catch(err => console.error('Audio play failed:', err));
}

function ensureNetworkingReady() {
  if (networkingReady) {
    return networkingReady;
  }

  networkingReady = Promise.all([
    import('simple-peer'),
    import('socket.io-client')
  ]).then(([peerModule, socketModule]) => {
    Peer = peerModule.default;
    socket = socketModule.io(SIGNALING_SERVER, {
      autoConnect: false,
      reconnection: true,
      reconnectionAttempts: Infinity,
      reconnectionDelay: 1000,
      reconnectionDelayMax: 5000,
      timeout: 20000,
      transports: ['websocket', 'polling']
    });
  });

  return networkingReady;
}
