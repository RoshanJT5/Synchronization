import { Buffer } from 'buffer';
(window as any).Buffer = Buffer;
(window as any).global = window;
(window as any).process = (window as any).process || { env: {} };

const SIGNALING_SERVER = 'http://localhost:3001';
let Peer: typeof import('simple-peer').default;
let socket: import('socket.io-client').Socket | null = null;
const peers = new Map<string, any>();
let audioPlayer: HTMLAudioElement | null = null;
let activeSessionId = '';
let networkingReady: Promise<void> | null = null;

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
});

async function startSendMode(sessionId: string, streamId: string) {
  try {
    await ensureNetworkingReady();
    resetSessionState();
    activeSessionId = sessionId;

    const stream = await navigator.mediaDevices.getUserMedia({
      audio: {
        // @ts-ignore
        mandatory: {
          chromeMediaSource: 'tab',
          chromeMediaSourceId: streamId
        }
      },
      video: false
    });

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
  socket?.off('peer-joined');
  socket?.off('session-peers');
  socket?.off('signal');
  destroyAllPeers();
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
      transports: ['websocket', 'polling']
    });
  });

  return networkingReady;
}
