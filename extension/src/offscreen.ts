import { Buffer } from 'buffer';
import { io, Socket } from 'socket.io-client';

(window as any).Buffer = Buffer;
(window as any).global = window;
(window as any).process = (window as any).process || { env: {} };

const SIGNALING_SERVER = 'https://synchronization-807q.onrender.com';
const ICE_SERVERS: RTCIceServer[] = [
  { urls: 'stun:stun.l.google.com:19302' },
  { urls: 'stun:stun1.l.google.com:19302' },
  {
    urls: 'turn:openrelay.metered.ca:443?transport=udp',
    username: 'openrelayproject',
    credential: 'openrelayproject',
  },
  {
    urls: 'turn:openrelay.metered.ca:443?transport=tcp',
    username: 'openrelayproject',
    credential: 'openrelayproject',
  },
];

let socket: Socket | null = null;
let activeSessionId = '';
let capturedStream: MediaStream | null = null;
let audioContext: AudioContext | null = null;
let localGain: GainNode | null = null;
let peers = new Map<string, RTCPeerConnection>();

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
    audioContext = new AudioContext();
    const source = audioContext.createMediaStreamSource(capturedStream);
    localGain = audioContext.createGain();
    localGain.gain.value = 1;
    source.connect(localGain);
    localGain.connect(audioContext.destination);

    socket = io(SIGNALING_SERVER, {
      transports: ['websocket', 'polling'],
      reconnection: true,
      timeout: 60000,
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
    });

    socket.on('session-peers', ({ peers: peerIds }) => {
      for (const peerId of peerIds || []) {
        if (peerId !== socket?.id) createOffer(peerId);
      }
    });

    socket.on('peer-joined', ({ peerId }) => {
      if (peerId && peerId !== socket?.id) createOffer(peerId);
    });

    socket.on('answer', async (data) => {
      const peer = peers.get(data.fromId);
      if (peer) await peer.setRemoteDescription(new RTCSessionDescription(data.answer));
    });

    socket.on('signal', async (data) => {
      const peer = peers.get(data.from);
      if (!peer || !data.signal) return;
      if (data.signal.type === 'answer') {
        await peer.setRemoteDescription(
          new RTCSessionDescription({
            type: 'answer',
            sdp: data.signal.sdp,
          }),
        );
      } else if (data.signal.candidate) {
        await peer.addIceCandidate(new RTCIceCandidate(data.signal));
      }
    });

    socket.on('ice-candidate', async (data) => {
      const peer = peers.get(data.fromId);
      if (peer) await peer.addIceCandidate(new RTCIceCandidate(data.candidate));
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

  const pc = new RTCPeerConnection({ iceServers: ICE_SERVERS });
  peers.set(peerId, pc);
  notifyPeerCount();

  for (const track of capturedStream.getAudioTracks()) {
    pc.addTrack(track, capturedStream);
  }

  const syncChannel = pc.createDataChannel('sync', { ordered: true });
  syncChannel.onopen = () => {
    syncChannel.send(
      JSON.stringify({
        action: 'streamReady',
        positionMs: 0,
        sentAtMs: Date.now(),
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
    if (
      pc.connectionState === 'failed' ||
      pc.connectionState === 'closed' ||
      pc.connectionState === 'disconnected'
    ) {
      peers.delete(peerId);
      notifyPeerCount();
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

function stopHost() {
  for (const peer of peers.values()) peer.close();
  peers.clear();
  notifyPeerCount();

  capturedStream?.getTracks().forEach((track) => track.stop());
  capturedStream = null;

  audioContext?.close().catch(() => {});
  audioContext = null;
  localGain = null;

  if (socket?.connected && activeSessionId) {
    socket.emit('end-session', { sessionId: activeSessionId });
  }
  socket?.removeAllListeners();
  socket?.disconnect();
  socket = null;
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
