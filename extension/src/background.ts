import { io, Socket } from 'socket.io-client';

const SIGNALING_SERVER = 'https://synchronization-807q.onrender.com';
const STATE_STORAGE_KEY = 'synchronization.extensionState';

type ExtensionState = {
  isActive: boolean;
  sessionId: string;
  status: 'IDLE' | 'READY' | 'CONNECTING' | 'STREAMING' | 'ERROR';
  readyPeers: number;
  sourceMuted: boolean;
  error?: string;
};

let state: ExtensionState = {
  isActive: false,
  sessionId: '',
  status: 'IDLE',
  readyPeers: 0,
  sourceMuted: false,
};

let lobbySocket: Socket | null = null;
let announceTimer: number | null = null;
let offscreenReady = false;
let pendingInit: unknown = null;
let readyPeerIds = new Set<string>();
const stateReady = restoreState();

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message.type === 'GET_STATE') {
    stateReady.then(() => sendResponse(state));
    return true;
  }

  if (message.type === 'PREPARE_EXTENSION_SESSION') {
    prepareSession(message.sessionId);
  }

  if (message.type === 'START_EXTENSION_HOST') {
    startExtensionHost(message.sessionId, message.streamId).catch((error) => {
      updateState({
        isActive: false,
        status: 'ERROR',
        error: error?.message || 'Could not start browser audio host.',
      });
    });
  }

  if (message.type === 'STOP_EXTENSION_HOST') {
    stopAll();
  }

  if (message.type === 'SET_SOURCE_MUTE') {
    updateState({ sourceMuted: Boolean(message.muted) });
    chrome.runtime.sendMessage({
      target: 'offscreen',
      type: 'SET_SOURCE_MUTE',
      muted: Boolean(message.muted),
    }).catch(() => {});
  }

  if (message.type === 'OFFSCREEN_READY') {
    offscreenReady = true;
    if (pendingInit) {
      chrome.runtime.sendMessage(pendingInit);
      pendingInit = null;
    }
  }

  if (message.type === 'EXTENSION_HOST_STARTED') {
    updateState({ isActive: true, status: 'STREAMING', error: undefined });
  }

  if (message.type === 'EXTENSION_HOST_ERROR') {
    updateState({
      isActive: false,
      status: 'ERROR',
      error: message.error || 'Browser audio host failed.',
    });
  }

  if (message.type === 'EXTENSION_PEER_COUNT') {
    updateState({ readyPeers: Number(message.count) || 0 });
  }

  return false;
});

function prepareSession(sessionId: string) {
  if (!sessionId) return;
  stopLobby();
  readyPeerIds.clear();
  updateState({
    isActive: false,
    sessionId,
    status: 'READY',
    readyPeers: 0,
    sourceMuted: state.sourceMuted,
    error: undefined,
  });

  lobbySocket = io(SIGNALING_SERVER, {
    transports: ['websocket', 'polling'],
    reconnection: true,
    reconnectionAttempts: Infinity,
    reconnectionDelay: 1000,
    reconnectionDelayMax: 5000,
    timeout: 60000,
  });

  lobbySocket.on('connect', () => {
    lobbySocket?.emit('join-session', sessionId);
    const announce = () => {
      lobbySocket?.emit('announce-session', {
        sessionId,
        label: 'Browser Extension',
        type: 'computer',
      });
    };
    announce();
    announceTimer = window.setInterval(announce, 5000);
  });

  lobbySocket.on('peer-joined', ({ peerId }) => {
    if (!peerId || peerId === lobbySocket?.id) return;
    readyPeerIds.add(peerId);
    updateState({ readyPeers: readyPeerIds.size });
  });

  lobbySocket.on('session-peers', ({ peers }) => {
    readyPeerIds = new Set(
      (peers || []).filter((peerId: string) => peerId !== lobbySocket?.id),
    );
    updateState({ readyPeers: readyPeerIds.size });
  });
}

async function startExtensionHost(sessionId: string, streamId: string) {
  stopLobby();
  updateState({
    isActive: true,
    sessionId,
    status: 'CONNECTING',
    error: undefined,
  });

  const initMessage = {
    target: 'offscreen',
    type: 'INIT_EXTENSION_HOST',
    sessionId,
    streamId,
  };

  const existingContexts = await chrome.runtime.getContexts({
    contextTypes: ['OFFSCREEN_DOCUMENT' as chrome.runtime.ContextType],
  });

  if (existingContexts.length > 0) {
    chrome.runtime.sendMessage(initMessage);
    return;
  }

  pendingInit = initMessage;
  offscreenReady = false;
  await chrome.offscreen.createDocument({
    url: 'offscreen.html',
    reasons: ['USER_MEDIA' as chrome.offscreen.Reason],
    justification: 'Capturing tab audio for Synchronization mobile receivers.',
  });
}

function stopAll() {
  stopLobby();
  chrome.runtime.sendMessage({ type: 'STOP_EXTENSION_HOST' }).catch(() => {});
  chrome.offscreen.closeDocument().catch(() => {});
  offscreenReady = false;
  pendingInit = null;
  readyPeerIds.clear();
  updateState({
    isActive: false,
    sessionId: '',
    status: 'IDLE',
    readyPeers: 0,
    sourceMuted: false,
    error: undefined,
  });
}

function stopLobby() {
  if (announceTimer != null) {
    window.clearInterval(announceTimer);
    announceTimer = null;
  }
  lobbySocket?.removeAllListeners();
  lobbySocket?.disconnect();
  lobbySocket = null;
}

function updateState(next: Partial<ExtensionState>) {
  state = { ...state, ...next };
  chrome.storage.local.set({ [STATE_STORAGE_KEY]: state });
  chrome.runtime.sendMessage({ type: 'STATE_UPDATED', state }).catch(() => {});
}

async function restoreState() {
  const stored = await chrome.storage.local.get(STATE_STORAGE_KEY);
  const restored = stored[STATE_STORAGE_KEY] as ExtensionState | undefined;
  if (!restored) return;

  state = {
    ...state,
    ...restored,
    sourceMuted: Boolean(restored.sourceMuted),
    readyPeers: restored.readyPeers || 0,
  };

  if (state.status === 'STREAMING' || state.status === 'CONNECTING') {
    const contexts = await chrome.runtime.getContexts({
      contextTypes: ['OFFSCREEN_DOCUMENT' as chrome.runtime.ContextType],
    });
    if (contexts.length === 0) {
      state = {
        isActive: false,
        sessionId: '',
        status: 'IDLE',
        readyPeers: 0,
        sourceMuted: false,
      };
      chrome.storage.local.set({ [STATE_STORAGE_KEY]: state });
    }
  }
}
