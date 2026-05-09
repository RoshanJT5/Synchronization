import { Buffer } from 'buffer';
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
let socket: import('socket.io-client').Socket | null = null;
type PeerState = {
  pc: RTCPeerConnection;
  targetId: string;
};
const peers = new Map<string, PeerState>();
let audioPlayer: HTMLAudioElement | null = null;
let activeSessionId = '';
let networkingReady: Promise<void> | null = null;
let announceTimer: number | null = null;

// ── Source audio passthrough (keeps laptop speakers alive while streaming) ──
let audioCtx: AudioContext | null = null;
let sourceNode: MediaStreamAudioSourceNode | null = null;
let localGain: GainNode | null = null;       // controls local playback volume
let localDest: MediaStreamAudioDestinationNode | null = null; // feeds local <audio>
let localAudioEl: HTMLAudioElement | null = null;
let sourceMuted = false;  // tracks current mute state
let capturedStream: MediaStream | null = null; // Store to release tracks

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
        },
        optional: [
          { googAutoGainControl: false },
          { googNoiseSuppression: false },
          { googHighpassFilter: false },
          { googAudioMirroring: false },
          { echoCancellation: false },
          { latency: 0 }
        ]
      },
      video: false
    });

    capturedStream = rawStream;

    // ── Audio graph ──────────────────────────────────────────────────────
    // rawStream → sourceNode ─┬─ localGain → localDest → <audio> (laptop speakers)
    //                         └─ (stream passed directly to WebRTC peers)
    //
    // The WebRTC peer uses rawStream directly so remote devices always get
    // full-volume audio regardless of the local mute toggle.
    // ─────────────────────────────────────────────────────────────────────
    audioCtx = new AudioContext({ latencyHint: 'interactive' });
    sourceNode = audioCtx.createMediaStreamSource(rawStream);
    
    // Add a precise delay to the laptop's speakers to perfectly match
    // the ~40ms network/WebRTC latency of the mobile device.
    const delayNode = audioCtx.createDelay(1.0);
    delayNode.delayTime.value = 0.04; // 40 milliseconds

    localGain = audioCtx.createGain();
    localDest = audioCtx.createMediaStreamDestination();

    // Start unmuted — laptop keeps playing by default
    localGain.gain.value = sourceMuted ? 0 : 1;

    // Route: source -> delay -> gain -> laptop speakers
    sourceNode.connect(delayNode);
    delayNode.connect(localGain);
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

    const announce = () => {
      console.log('Announcing session:', sessionId);
      socket?.emit('announce-session', {
        sessionId,
        label: 'This Computer',
      });
    };

    socket?.on('connect', announce);
    socket?.emit('join-session', sessionId);
    announce(); // Initial announce
    startSessionHeartbeat(sessionId, announce);

    socket?.on('peer-joined', ({ peerId }) => {
      if (activeSessionId !== sessionId) return;
      if (peerId === socket?.id) return;
      console.log('Receiver joined session:', peerId);
      setupPeer(sessionId, true, stream, peerId);
    });

    socket?.on('session-peers', ({ peers }) => {
      if (activeSessionId !== sessionId) return;
      for (const peerId of peers || []) {
        if (peerId === socket?.id) continue;
        console.log('Found receiver already in session:', peerId);
        setupPeer(sessionId, true, stream, peerId);
      }
    });

    socket?.on('signal', ({ from, signal }) => {
      if (activeSessionId !== sessionId) return;
      const peer = peers.get(from);
      if (peer) {
        handlePeerSignal(peer, signal);
      }
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
      handlePeerSignal(peer, signal);
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
  const existingPeer = peers.get(targetId);
  if (existingPeer && existingPeer.pc.connectionState !== 'closed') {
    console.log('Peer already exists, keeping current connection:', targetId);
    return existingPeer;
  }

  destroyPeer(targetId);

  const pc = new RTCPeerConnection({ iceServers: ICE_SERVERS });
  const peer: PeerState = { pc, targetId };

  peers.set(targetId, peer);

  stream?.getTracks().forEach((track) => {
    pc.addTrack(track, stream);
  });

  // ── Clock-sync data channel ──────────────────────────────────────────────
  // Sender opens a data channel and sends { t: performance.now() } every 500ms.
  // Receiver replies with { t: senderT, r: performance.now() }.
  // This lets the mobile compute: offset = (r - t) / 2  (half-RTT estimate)
  // and drift-correct its audio scheduling.
  let clockChannel: RTCDataChannel | null = null;
  let clockTimer: number | null = null;

  if (initiator) {
    clockChannel = pc.createDataChannel('clock-sync', {
      ordered: false,
      maxRetransmits: 0,
    });

    clockChannel.onopen = () => {
      clockTimer = window.setInterval(() => {
        if (clockChannel?.readyState === 'open') {
          clockChannel.send(JSON.stringify({ t: performance.now() }));
        }
      }, 500);
    };

    clockChannel.onmessage = (e) => {
      // Receiver echoed back { t: senderT, r: receiverT }
      // We can compute RTT = performance.now() - senderT
      try {
        const msg = JSON.parse(e.data);
        const rtt = performance.now() - msg.t;
        console.log(`[ClockSync] RTT=${rtt.toFixed(1)}ms`);
      } catch (_) {}
    };

    clockChannel.onclose = () => {
      if (clockTimer !== null) { window.clearInterval(clockTimer); clockTimer = null; }
    };
  } else {
    pc.ondatachannel = (e) => {
      if (e.channel.label === 'clock-sync') {
        e.channel.onmessage = (msg) => {
          try {
            const data = JSON.parse(msg.data);
            // Echo back with our receive timestamp
            if (e.channel.readyState === 'open') {
              e.channel.send(JSON.stringify({ t: data.t, r: performance.now() }));
            }
          } catch (_) {}
        };
      }
    };
  }
  // ─────────────────────────────────────────────────────────────────────────

  pc.onicecandidate = (event) => {
    if (event.candidate) {
      socket?.emit('signal', {
        sessionId,
        signal: event.candidate.toJSON(),
        to: targetId
      });
    }
  };

  pc.ontrack = (event) => {
    const [remoteStream] = event.streams;
    if (remoteStream) {
      console.log('WebRTC Stream Received!');
      playStream(remoteStream);
    }
  };

  pc.onconnectionstatechange = () => {
    console.log('WebRTC connection state:', pc.connectionState);
    if (pc.connectionState === 'connected') {
      chrome.runtime.sendMessage({ type: 'CONNECTION_SUCCESS' });
    } else if (pc.connectionState === 'failed') {
      if (clockTimer !== null) { window.clearInterval(clockTimer); clockTimer = null; }
      peers.delete(targetId);
      chrome.runtime.sendMessage({
        type: 'CONNECTION_ERROR',
        error: 'WebRTC connection failed before audio could start.'
      });
    } else if (pc.connectionState === 'closed') {
      if (clockTimer !== null) { window.clearInterval(clockTimer); clockTimer = null; }
      peers.delete(targetId);
    }
  };

  pc.oniceconnectionstatechange = () => {
    console.log('WebRTC ICE state:', pc.iceConnectionState);
  };

  if (initiator) {
    createAndSendOffer(peer, sessionId).catch((error) => {
      console.error('Offer creation failed:', error);
      chrome.runtime.sendMessage({
        type: 'CONNECTION_ERROR',
        error: error?.message || 'Could not create WebRTC offer.'
      });
    });
  }

  return peer;
}

async function createAndSendOffer(peer: PeerState, sessionId: string) {
  const offer = await peer.pc.createOffer({
    offerToReceiveAudio: false,
    offerToReceiveVideo: false
  });

  // ── Patch SDP for minimum latency ────────────────────────────────────────
  // 1. Force Opus codec with lowest possible ptime (10ms frames vs default 20ms)
  // 2. Set maxplaybackrate to 48000 (full fidelity)
  // 3. Disable DTX (discontinuous transmission) — prevents silence gaps
  // 4. Set stereo=1 for music quality
  let sdp = offer.sdp || '';
  sdp = sdp.replace(
    /a=fmtp:(\d+) (.*opus.*)/gi,
    (match, pt, params) => {
      const existing = new Map(
        params.split(';').map((p: string) => {
          const [k, v] = p.trim().split('=');
          return [k.trim(), v?.trim() ?? '1'];
        })
      );
      existing.set('ptime', '10');
      existing.set('maxptime', '10');
      existing.set('useinbandfec', '1');
      existing.set('usedtx', '0');
      existing.set('stereo', '1');
      existing.set('maxplaybackrate', '48000');
      existing.set('sprop-maxcapturerate', '48000');
      return `a=fmtp:${pt} ${Array.from(existing.entries()).map(([k, v]) => `${k}=${v}`).join(';')}`;
    }
  );
  // ─────────────────────────────────────────────────────────────────────────

  await peer.pc.setLocalDescription(new RTCSessionDescription({ type: 'offer', sdp }));
  socket?.emit('signal', {
    sessionId,
    signal: {
      type: 'offer',
      sdp
    },
    to: peer.targetId
  });
}

async function handlePeerSignal(peer: PeerState, signal: any) {
  if (!signal || peer.pc.connectionState === 'closed') return;

  if (signal.type === 'offer' || signal.type === 'answer') {
    await peer.pc.setRemoteDescription(new RTCSessionDescription(signal));

    if (signal.type === 'offer') {
      const answer = await peer.pc.createAnswer();
      await peer.pc.setLocalDescription(answer);
      socket?.emit('signal', {
        sessionId: activeSessionId,
        signal: {
          type: answer.type,
          sdp: answer.sdp
        },
        to: peer.targetId
      });
    }
    return;
  }

  if (signal.candidate) {
    await peer.pc.addIceCandidate(new RTCIceCandidate(signal));
  }
}

function resetSessionState() {
  // End the announced session so it disappears from mobile discovery
  if (activeSessionId && socket?.connected) {
    socket.emit('end-session', { sessionId: activeSessionId });
  }

  stopSessionHeartbeat();
  socket?.off('peer-joined');
  socket?.off('session-peers');
  socket?.off('signal');
  socket?.off('connect');
  destroyAllPeers();

  // Tear down local audio passthrough
  if (capturedStream) {
    capturedStream.getTracks().forEach(t => { try { t.stop(); } catch (_) {} });
    capturedStream = null;
  }
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
    try { peer.pc.close(); } catch (e) { }
    peers.delete(peerId);
  }
}

function destroyAllPeers() {
  for (const peerId of peers.keys()) {
    destroyPeer(peerId);
  }
}

function startSessionHeartbeat(sessionId: string, announce: () => void) {
  stopSessionHeartbeat();
  announceTimer = window.setInterval(() => {
    if (activeSessionId !== sessionId) return;

    if (socket?.connected) {
      socket.emit('session-heartbeat', { sessionId });
      socket.emit('announce-session', {
        sessionId,
        label: 'This Computer',
      });
    } else {
      socket?.connect();
    }
  }, 7000);

  // Re-announce occasionally so a restarted signaling server can rebuild its
  // discovery list without needing the user to restart capture.
  window.setTimeout(() => {
    if (activeSessionId === sessionId && socket?.connected) {
      announce();
    }
  }, 1000);
}

function stopSessionHeartbeat() {
  if (announceTimer !== null) {
    window.clearInterval(announceTimer);
    announceTimer = null;
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
    import('socket.io-client')
  ]).then(([socketModule]) => {
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
