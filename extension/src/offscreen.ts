import { Buffer } from 'buffer';
import { io, Socket } from 'socket.io-client';
(window as any).Buffer = Buffer;
(window as any).global = window;
(window as any).process = (window as any).process || { env: {} };

const SIGNALING_SERVER = 'https://synchronization-807q.onrender.com';
const ICE_SERVERS = [
  { urls: 'stun:stun.l.google.com:19302' },
  { urls: 'stun:stun1.l.google.com:19302' },
  { urls: 'stun:openrelay.metered.ca:80' },
  {
    urls: 'turn:openrelay.metered.ca:80',
    username: 'openrelayproject',
    credential: 'openrelayproject'
  },
  {
    urls: 'turn:openrelay.metered.ca:443',
    username: 'openrelayproject',
    credential: 'openrelayproject'
  },
  {
    urls: 'turn:openrelay.metered.ca:443?transport=tcp',
    username: 'openrelayproject',
    credential: 'openrelayproject'
  }
];
let socket: Socket | null = null;
type PeerState = {
  pc: RTCPeerConnection;
  targetId: string;
};
const peers = new Map<string, PeerState>();
let activeSessionId = '';
let networkingReady: Promise<void> | null = null;
let announceTimer: number | null = null;

// ── Receiver Mesh Sync Coordinator ──────────────────────────────────────────
interface ReceiverState {
  peerId: string;
  lastChunkId: number;
  lastReportTime: number;
  isWaiting: boolean;
}
const receiverStates = new Map<string, ReceiverState>();
let syncCoordinatorTimer: number | null = null;

// ── Global Playback State ────────────────────────────────────────────────────
let syncBufferMs = 700;
let chunkSequence = 0;
let audioCtx: AudioContext | null = null;
let sourceNode: MediaStreamAudioSourceNode | null = null;
let localDelay: DelayNode | null = null;
let localGain: GainNode | null = null;
let sourceMuted = false;
let capturedStream: MediaStream | null = null;

console.log('Offscreen document initialized');
chrome.runtime.sendMessage({ type: 'OFFSCREEN_READY' });

chrome.runtime.onMessage.addListener((message) => {
  if (message.type === 'INIT_OFFSCREEN') {
    if (message.mode === 'SEND') {
      startSendMode(message.sessionId, message.streamId);
    }
  }

  if (message.type === 'SET_SOURCE_MUTE' || message.type === 'MUTE_SOURCE') {
    sourceMuted = message.muted !== undefined ? message.muted : message.isMuted;
    if (localGain && audioCtx) {
      localGain.gain.setTargetAtTime(sourceMuted ? 0 : 1.0, audioCtx.currentTime, 0.1);
    }
    console.log('[Offscreen] Source mute toggled:', sourceMuted);
  }

  if (message.type === 'SET_SYNC_BUFFER') {
    syncBufferMs = message.bufferMs;
    console.log('[Offscreen] Setting sync buffer to:', syncBufferMs);
    if (localDelay && audioCtx) {
      localDelay.delayTime.linearRampToValueAtTime(syncBufferMs / 1000, audioCtx.currentTime + 0.5);
    }
    _broadcastSyncConfig();
  }
});

async function startSendMode(sessionId: string, streamId: string) {
  try {
    activeSessionId = sessionId;
    await ensureNetworkingReady();
    resetSessionState();

    capturedStream = await navigator.mediaDevices.getUserMedia({
      audio: {
        // @ts-ignore
        mandatory: {
          chromeMediaSource: 'tab',
          chromeMediaSourceId: streamId
        },
        optional: [
          { googAutoGainControl: false },
          { googNoiseSuppression: false },
          { googHighpassFilter: false },
          { echoCancellation: false }
        ]
      },
      video: false
    });

    // ── Audio Graph ──────────────────────────────────────────────────────
    // Capture at 48kHz to match receiver
    audioCtx = new AudioContext({ sampleRate: 48000, latencyHint: 'interactive' });
    sourceNode = audioCtx.createMediaStreamSource(capturedStream);
    
    localDelay = audioCtx.createDelay(2.0);
    localDelay.delayTime.value = syncBufferMs / 1000;
    
    localGain = audioCtx.createGain();
    localGain.gain.value = sourceMuted ? 0 : 1.0;

    sourceNode.connect(localDelay);
    localDelay.connect(localGain);
    localGain.connect(audioCtx.destination);

    // ── Audio Capture for DataChannel ─────────────────────────────────────
    const processor = audioCtx.createScriptProcessor(4096, 2, 2);
    sourceNode.connect(processor);
    processor.connect(audioCtx.destination);

    processor.onaudioprocess = (e) => {
      if (peers.size === 0) return;

      const left = e.inputBuffer.getChannelData(0);
      const right = e.inputBuffer.getChannelData(1);
      
      const interleaved = new Int16Array(left.length * 2);
      for (let i = 0; i < left.length; i++) {
        interleaved[i * 2]     = Math.max(-1, Math.min(1, left[i])) * 0x7FFF;
        interleaved[i * 2 + 1] = Math.max(-1, Math.min(1, right[i])) * 0x7FFF;
      }

      const syncPacket = {
        type: 'audio',
        chunkId: chunkSequence++,
        playbackTimestamp: Date.now() + syncBufferMs,
        audioData: Array.from(new Uint8Array(interleaved.buffer)) 
      };

      const packetJson = JSON.stringify(syncPacket);
      for (const peer of peers.values()) {
        const ch = (peer as any).__clockChannel as RTCDataChannel | undefined;
        if (ch && ch.readyState === 'open') {
          ch.send(packetJson);
        }
      }
    };
    (window as any).__audioProcessor = processor;

    startSyncCoordinator();
    chrome.runtime.sendMessage({ type: 'CONNECTION_SUCCESS' });
  } catch (error: any) {
    console.error('SEND error:', error);
  }
}

function _broadcastSyncConfig() {
  const msg = JSON.stringify({ type: 'sync-config', bufferMs: syncBufferMs });
  for (const peer of peers.values()) {
    const ch = (peer as any).__clockChannel as RTCDataChannel | undefined;
    if (ch && ch.readyState === 'open') {
      ch.send(msg);
    }
  }
}

function runSyncCoordinator() {
  if (receiverStates.size < 2) return;

  let minChunk = Infinity;
  for (const state of receiverStates.values()) {
    if (Date.now() - state.lastReportTime > 5000) continue;
    if (state.lastChunkId < minChunk) minChunk = state.lastChunkId;
  }

  if (minChunk === Infinity) return;
  const checkpoint = minChunk + 20;

  for (const state of receiverStates.values()) {
    if (state.lastChunkId > checkpoint + 10 && !state.isWaiting) {
      state.isWaiting = true;
      sendToReceiver(state.peerId, { type: 'wait_at_checkpoint', checkpoint });
    }
  }

  if (minChunk >= checkpoint - 2) {
    let released = false;
    for (const state of receiverStates.values()) {
      if (state.isWaiting) {
        state.isWaiting = false;
        released = true;
      }
    }
    if (released) {
      broadcastToAllReceivers({ type: 'resume' });
    }
  }
}

function sendToReceiver(peerId: string, msg: any) {
  const peer = peers.get(peerId);
  const ch = (peer as any)?.__clockChannel as RTCDataChannel | undefined;
  if (ch && ch.readyState === 'open') ch.send(JSON.stringify(msg));
}

function broadcastToAllReceivers(msg: any) {
  const json = JSON.stringify(msg);
  for (const peer of peers.values()) {
    const ch = (peer as any)?.__clockChannel as RTCDataChannel | undefined;
    if (ch && ch.readyState === 'open') ch.send(json);
  }
}

function startSyncCoordinator() {
  if (syncCoordinatorTimer) return;
  syncCoordinatorTimer = window.setInterval(runSyncCoordinator, 2000);
}

function stopSyncCoordinator() {
  if (syncCoordinatorTimer) {
    window.clearInterval(syncCoordinatorTimer);
    syncCoordinatorTimer = null;
  }
  receiverStates.clear();
}

function resetSessionState() {
  stopSyncCoordinator();
  if (audioCtx) {
    audioCtx.close().catch(() => {});
    audioCtx = null;
  }
  peers.forEach(peer => peer.pc.close());
  peers.clear();
  chunkSequence = 0;
}

async function ensureNetworkingReady() {
  if (networkingReady) return networkingReady;
  networkingReady = new Promise((resolve) => {
    socket = io(SIGNALING_SERVER, {
      transports: ['websocket'],
      reconnection: true,
      timeout: 60000
    });
    socket.on('connect', () => {
      console.log('[Offscreen] Connected. Joining session:', activeSessionId);
      if (activeSessionId) {
        socket?.emit('join-session', activeSessionId);
      }
      resolve();
    });
    socket.on('connect_error', (err) => {
      console.error('[Offscreen] Connection error:', err);
    });
    socket.on('session-peers', ({ peers: peerIds }: { peers: string[] }) => {
      console.log('[Offscreen] Received session peers:', peerIds);
      for (const peerId of peerIds) {
        if (peerId !== socket?.id && !peers.has(peerId)) {
          console.log('[Offscreen] Initiating offer to existing peer:', peerId);
          createOffer(peerId);
        }
      }
    });
    socket.on('peer-joined', ({ peerId }: { peerId: string }) => {
      if (peerId !== socket?.id) {
        console.log('Peer joined, creating offer for:', peerId);
        createOffer(peerId);
      }
    });
    socket.on('offer', async (data: any) => {
      await handleOffer(data.offer, data.fromId);
    });
    socket.on('answer', async (data: any) => {
      const peer = peers.get(data.fromId);
      if (peer) await peer.pc.setRemoteDescription(new RTCSessionDescription(data.answer));
    });
    socket.on('ice-candidate', async (data: any) => {
      const peer = peers.get(data.fromId);
      if (peer) await peer.pc.addIceCandidate(new RTCIceCandidate(data.candidate));
    });
  });
  return networkingReady;
}

async function createOffer(peerId: string) {
  const pc = new RTCPeerConnection({ iceServers: ICE_SERVERS });
  const clockChannel = pc.createDataChannel('clock-sync', { ordered: true });
  
  peers.set(peerId, { pc, targetId: peerId });
  (pc as any).__clockChannel = clockChannel;

  pc.onicecandidate = (event) => {
    if (event.candidate && socket) {
      socket.emit('ice-candidate', { candidate: event.candidate, toId: peerId });
    }
  };

  const offer = await pc.createOffer();
  await pc.setLocalDescription(offer);
  socket?.emit('offer', { offer, toId: peerId });
}

async function handleOffer(offer: RTCSessionDescriptionInit, fromId: string) {
  const pc = new RTCPeerConnection({ iceServers: ICE_SERVERS });
  peers.set(fromId, { pc, targetId: fromId });

  pc.onicecandidate = (event) => {
    if (event.candidate && socket) {
      socket.emit('ice-candidate', { candidate: event.candidate, toId: fromId });
    }
  };

  pc.ondatachannel = (event) => {
    const ch = event.channel;
    if (ch.label === 'clock-sync') {
      (pc as any).__clockChannel = ch;
      ch.onmessage = (e) => {
        const msg = JSON.parse(e.data);
        if (msg.t) {
          const rtt = performance.now() - msg.t;
          if (msg.type === 'position_report') {
            const state = receiverStates.get(fromId) || { peerId: fromId, lastChunkId: 0, lastReportTime: 0, isWaiting: false };
            state.lastChunkId = msg.currentChunkId;
            state.lastReportTime = Date.now();
            receiverStates.set(fromId, state);
            runSyncCoordinator();
          }
          // Echo pong
          if (ch.readyState === 'open') ch.send(JSON.stringify({ t: msg.t, r: performance.now() }));
        }
      };
    }
  };

  await pc.setRemoteDescription(new RTCSessionDescription(offer));
  const answer = await pc.createAnswer();
  await pc.setLocalDescription(answer);
  socket!.emit('answer', { answer, toId: fromId });
}
