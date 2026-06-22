import { Buffer } from 'buffer';
import { io, Socket } from 'socket.io-client';
import { SIGNALING_SERVER } from './serverConfig';

(window as any).Buffer = Buffer;
(window as any).global = window;
(window as any).process = (window as any).process || { env: {} };


const ICE_SERVERS: RTCIceServer[] = [
  // Always try Google STUN first (Fastest, uses 0MB)
  { urls: 'stun:stun.l.google.com:19302' },

  // ExpressTURN STUN Backup
  { urls: 'stun:free.expressturn.com:3478' },

  // ExpressTURN TURN (Try this first)
  {
    urls: 'turn:free.expressturn.com:3478',
    username: '000000002096352701',
    credential: 'I4PrWLgp6znLfV6BXYK7xQviwTw=',
  },

  // Metered private TURN servers (Fast, reliable)
  { urls: 'stun:stun.relay.metered.ca:80' },
  {
    urls: 'turn:global.relay.metered.ca:80',
    username: '3bc60cb6f671013bf50ac68c',
    credential: '6w0c+6c2jfIWt5v1',
  },
  {
    urls: 'turn:global.relay.metered.ca:80?transport=tcp',
    username: '3bc60cb6f671013bf50ac68c',
    credential: '6w0c+6c2jfIWt5v1',
  },
  {
    urls: 'turn:global.relay.metered.ca:443',
    username: '3bc60cb6f671013bf50ac68c',
    credential: '6w0c+6c2jfIWt5v1',
  },
  {
    urls: 'turns:global.relay.metered.ca:443?transport=tcp',
    username: '3bc60cb6f671013bf50ac68c',
    credential: '6w0c+6c2jfIWt5v1',
  },

  // Fallback: OpenRelay (free, overloaded but always available)
  {
    urls: 'turn:openrelay.metered.ca:443?transport=udp',
    username: 'openrelayproject',
    credential: 'openrelayproject',
  },
];
const MOBILE_SYNC_DELAY_SECONDS = 0.8;
const MOBILE_SYNC_DELAY_MS = MOBILE_SYNC_DELAY_SECONDS * 1000;

let socket: Socket | null = null;
let activeSessionId = '';
let capturedStream: MediaStream | null = null;
let audioContext: AudioContext | null = null;
let localGain: GainNode | null = null;
let phoneDelay: DelayNode | null = null;
let phoneDestination: MediaStreamAudioDestinationNode | null = null;
let peers = new Map<string, RTCPeerConnection>();
let pendingIceCandidates = new Map<string, RTCIceCandidateInit[]>();
let heartbeatTimer: ReturnType<typeof setInterval> | null = null;

chrome.runtime.sendMessage({ type: 'OFFSCREEN_READY' });

chrome.runtime.onMessage.addListener((message) => {
  if (message.type === 'INIT_EXTENSION_HOST') {
    startHost(message.sessionId, message.streamId);
  }

  if (message.type === 'STOP_EXTENSION_HOST') {
    stopHost();
  }

  if (message.type === 'SET_SOURCE_MUTE') {
    setSourceMuted(Boolean(message.muted));
  }
});

async function startHost(sessionId: string, streamId: string) {
  try {
    stopHost();
    activeSessionId = sessionId;
    capturedStream = await navigator.mediaDevices.getUserMedia({
      audio: {
        // @ts-expect-error Chrome extension tab capture constraint.
        mandatory: {
          chromeMediaSource: 'tab',
          chromeMediaSourceId: streamId,
        },
      },
      video: false,
    });

    // Keep local browser audio audible while the captured stream is active.
    // Use the captured stream's native sample rate to avoid resampling jitter,
    // and 'playback' latency hint for maximum audio stability.
    const nativeSampleRate = capturedStream.getAudioTracks()[0]?.getSettings()?.sampleRate;
    audioContext = new AudioContext({
      sampleRate: nativeSampleRate || 48000,
      latencyHint: 'playback',
    });
    const source = audioContext.createMediaStreamSource(capturedStream);

    localGain = audioContext.createGain();
    localGain.gain.value = 1;
    source.connect(localGain);
    localGain.connect(audioContext.destination);

    // Send one intentionally delayed timeline to every phone. The browser
    // stays live locally, while all receivers hear the same shared delayed feed.
    phoneDelay = audioContext.createDelay(2);
    phoneDelay.delayTime.value = MOBILE_SYNC_DELAY_SECONDS;
    phoneDestination = audioContext.createMediaStreamDestination();
    source.connect(phoneDelay);
    phoneDelay.connect(phoneDestination);

    socket = io(SIGNALING_SERVER, {
      transports: ['websocket', 'polling'],
      reconnection: true,
      timeout: 10000,
    });

    socket.on('connect', () => {
      socket?.emit('join-session', activeSessionId);
      socket?.emit('announce-session', {
        sessionId: activeSessionId,
        label: 'Browser Extension',
        type: 'computer',
      });
      chrome.runtime.sendMessage({ type: 'EXTENSION_HOST_STARTED' });
      notifyPeerCount();

      // Periodic heartbeat keeps the signalling server aware this session is
      // alive AND generates inbound traffic that prevents Render free tier
      // from sleeping after 15 minutes of "inactivity".
      if (heartbeatTimer) clearInterval(heartbeatTimer);
      heartbeatTimer = setInterval(() => {
        socket?.emit('session-heartbeat', { sessionId: activeSessionId });
        socket?.emit('announce-session', {
          sessionId: activeSessionId,
          label: 'Browser Extension',
          type: 'computer',
        });
      }, 30_000); // every 30 seconds
    });

    socket.on('session-peers', ({ peers: peerIds }) => {
      for (const peerId of peerIds || []) {
        if (peerId !== socket?.id) {
          createOffer(peerId).catch((error) => {
            console.warn('[Synchronization] Failed to create offer', error);
            cleanupPeer(peerId);
          });
        }
      }
    });

    socket.on('peer-joined', ({ peerId }) => {
      if (peerId && peerId !== socket?.id) {
        createOffer(peerId).catch((error) => {
          console.warn('[Synchronization] Failed to create offer', error);
          cleanupPeer(peerId);
        });
      }
    });

    socket.on('signal', async (data) => {
      try {
        await handleSignal(data);
      } catch (error) {
        console.warn('[Synchronization] Failed to handle signal', error);
      }
    });
  } catch (error: any) {
    chrome.runtime.sendMessage({
      type: 'EXTENSION_HOST_ERROR',
      error: error?.message || 'Could not capture tab audio.',
    });
  }
}

async function createOffer(peerId: string) {
  if (peers.has(peerId) || !capturedStream) return;

  const pc = new RTCPeerConnection({
    iceServers: ICE_SERVERS,
    iceCandidatePoolSize: 1,
  });
  peers.set(peerId, pc);
  notifyPeerCount();

  const outboundStream = phoneDestination?.stream ?? capturedStream;
  for (const track of outboundStream.getAudioTracks()) {
    pc.addTrack(track, outboundStream);
  }

  const syncChannel = pc.createDataChannel('sync', { ordered: true });
  syncChannel.onopen = () => {
    const now = Date.now();
    syncChannel.send(
      JSON.stringify({
        action: 'streamReady',
        positionMs: 0,
        sentAtMs: now,
        hostClockMs: now,
        startAtMs: now + 1000,
        sharedDelayMs: MOBILE_SYNC_DELAY_MS,
      }),
    );
  };

  pc.onicecandidate = (event) => {
    if (!event.candidate) return;
    socket?.emit('signal', {
      sessionId: activeSessionId,
      signal: {
        candidate: event.candidate.candidate,
        sdpMid: event.candidate.sdpMid,
        sdpMLineIndex: event.candidate.sdpMLineIndex,
      },
      to: peerId,
    });
  };

  pc.onconnectionstatechange = () => {
    if (pc.connectionState === 'connected') {
      notifyPeerCount();
    }
    // ICE restart: attempt to re-negotiate instead of silently dropping.
    if (pc.connectionState === 'disconnected' || pc.connectionState === 'failed') {
      (async () => {
        try {
          const restartOffer = await pc.createOffer({ iceRestart: true });
          await pc.setLocalDescription(restartOffer);
          socket?.emit('signal', {
            sessionId: activeSessionId,
            signal: { type: restartOffer.type, sdp: restartOffer.sdp },
            to: peerId,
          });
        } catch {
          // ICE restart failed — remove the peer as a last resort.
          cleanupPeer(peerId);
        }
      })();
    }
    if (pc.connectionState === 'closed') {
      cleanupPeer(peerId);
    }
  };

  const offer = await pc.createOffer({
    offerToReceiveAudio: false,
    offerToReceiveVideo: false,
  });
  await pc.setLocalDescription(offer);
  socket?.emit('signal', {
    sessionId: activeSessionId,
    signal: { type: offer.type, sdp: offer.sdp },
    to: peerId,
  });
}

async function handleSignal(data: any) {
  const peerId = data?.from;
  const signal = data?.signal;
  const peer = peers.get(peerId);
  if (!peer || !signal) return;

  if (signal.type === 'offer') {
    await peer.setRemoteDescription(
      new RTCSessionDescription({
        type: 'offer',
        sdp: signal.sdp,
      }),
    );
    const answer = await peer.createAnswer();
    await peer.setLocalDescription(answer);
    socket?.emit('signal', {
      sessionId: activeSessionId,
      signal: { type: answer.type, sdp: answer.sdp },
      to: peerId,
    });
    await flushPendingIceCandidates(peerId, peer);
    return;
  }

  if (signal.type === 'answer') {
    await peer.setRemoteDescription(
      new RTCSessionDescription({
        type: 'answer',
        sdp: signal.sdp,
      }),
    );
    await flushPendingIceCandidates(peerId, peer);
    return;
  }

  if (signal.candidate) {
    const candidate = {
      candidate: signal.candidate,
      sdpMid: signal.sdpMid,
      sdpMLineIndex: signal.sdpMLineIndex,
    };

    if (!peer.remoteDescription) {
      const pending = pendingIceCandidates.get(peerId) ?? [];
      pending.push(candidate);
      pendingIceCandidates.set(peerId, pending);
      return;
    }

    await peer.addIceCandidate(new RTCIceCandidate(candidate));
  }
}

async function flushPendingIceCandidates(peerId: string, peer: RTCPeerConnection) {
  const pending = pendingIceCandidates.get(peerId) ?? [];
  pendingIceCandidates.delete(peerId);

  for (const candidate of pending) {
    try {
      await peer.addIceCandidate(new RTCIceCandidate(candidate));
    } catch (error) {
      console.warn('[Synchronization] Ignored stale ICE candidate', error);
    }
  }
}

function stopHost() {
  for (const peer of peers.values()) peer.close();
  peers.clear();
  pendingIceCandidates.clear();
  notifyPeerCount();

  if (heartbeatTimer) {
    clearInterval(heartbeatTimer);
    heartbeatTimer = null;
  }

  capturedStream?.getTracks().forEach((track) => track.stop());
  capturedStream = null;

  audioContext?.close().catch(() => {});
  audioContext = null;
  localGain = null;
  phoneDelay = null;
  phoneDestination = null;

  if (socket?.connected && activeSessionId) {
    socket.emit('end-session', { sessionId: activeSessionId });
  }
  socket?.removeAllListeners();
  socket?.disconnect();
  socket = null;
}

function cleanupPeer(peerId: string) {
  pendingIceCandidates.delete(peerId);
  const peer = peers.get(peerId);
  if (peer && peer.connectionState !== 'closed') {
    peer.close();
  }
  peers.delete(peerId);
  notifyPeerCount();
}

function notifyPeerCount() {
  chrome.runtime.sendMessage({
    type: 'EXTENSION_PEER_COUNT',
    count: peers.size,
  }).catch(() => {});
}

function setSourceMuted(muted: boolean) {
  if (!audioContext || !localGain) return;
  localGain.gain.setTargetAtTime(muted ? 0 : 1, audioContext.currentTime, 0.05);
}
