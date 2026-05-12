// src/background.ts

import { io, Socket } from 'socket.io-client';

const SIGNALING_SERVER = 'https://synchronization-807q.onrender.com';
const STATE_STORAGE_KEY = 'syncronization.currentState';

let offscreenReady = false;
let pendingInit: any = null;
let lobbySocket: Socket | null = null;
let readyPeerIds = new Set<string>();

let currentState = {
  isActive: false,
  mode: 'SEND',
  sessionId: '',
  sourceMuted: false,
  status: 'IDLE',
  readyPeers: 0
};
const stateReady = restoreState();

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message.type === 'GET_STATE') {
    stateReady.then(() => sendResponse(currentState));
    return true;
  } else if (message.type === 'PREPARE_SEND_SESSION') {
    prepareSendSession(message.sessionId);
  } else if (message.type === 'RESET_IDLE_SESSION') {
    stopLobby();
    currentState.isActive = false;
    currentState.mode = 'SEND';
    currentState.sessionId = '';
    currentState.status = 'IDLE';
    currentState.readyPeers = 0;
    readyPeerIds.clear();
    persistState();
  } else if (message.type === 'START_CAPTURE') {
    stopLobby();
    currentState.isActive = true;
    currentState.mode = 'SEND';
    currentState.sessionId = message.sessionId;
    currentState.status = 'CONNECTING';
    persistState();
    startOffscreen('SEND', message.sessionId, message.streamId).catch((error) => {
      currentState.isActive = false;
      currentState.status = 'ERROR';
      persistState();
      chrome.runtime.sendMessage({
        type: 'CONNECTION_ERROR',
        error: error?.message || 'Could not start the audio worker.'
      });
    });
  } else if (message.type === 'START_RECEIVE') {
    currentState.isActive = true;
    currentState.mode = 'RECEIVE';
    currentState.sessionId = message.sessionId;
    currentState.status = 'CONNECTING';
    persistState();
    startOffscreen('RECEIVE', message.sessionId).catch((error) => {
      currentState.isActive = false;
      currentState.status = 'ERROR';
      persistState();
      chrome.runtime.sendMessage({
        type: 'CONNECTION_ERROR',
        error: error?.message || 'Could not start the audio worker.'
      });
    });
  } else if (message.type === 'SET_SOURCE_MUTE') {
    currentState.sourceMuted = message.muted;
    persistState();
    // Forward mute toggle directly to the offscreen document
    chrome.runtime.sendMessage({ type: 'SET_SOURCE_MUTE', muted: message.muted });
  } else if (message.type === 'STOP_CAPTURE') {
    stopLobby();
    currentState.isActive = false;
    currentState.status = 'IDLE';
    currentState.sessionId = '';
    currentState.readyPeers = 0;
    readyPeerIds.clear();
    persistState();
    // Close the offscreen document entirely to clean up audio/sockets instantly
    chrome.offscreen.closeDocument().catch(() => {});
    offscreenReady = false;
  } else if (message.type === 'CONNECTION_SUCCESS') {
    currentState.status = currentState.mode === 'SEND' ? 'CAPTURING' : 'LISTENING';
    persistState();
  } else if (message.type === 'CONNECTION_ERROR') {
    currentState.isActive = false;
    currentState.status = 'ERROR';
    persistState();
  } else if (message.type === 'OFFSCREEN_READY') {
    offscreenReady = true;
    if (pendingInit) {
      chrome.runtime.sendMessage(pendingInit);
      pendingInit = null;
    }
  }
});

function prepareSendSession(sessionId: string) {
  if (!sessionId || currentState.status !== 'IDLE') return;
  if (lobbySocket?.connected && currentState.sessionId === sessionId) return;

  stopLobby();

  currentState.isActive = false;
  currentState.mode = 'SEND';
  currentState.sessionId = sessionId;
  currentState.status = 'IDLE';
  currentState.readyPeers = 0;
  readyPeerIds.clear();
  persistState();

  lobbySocket = io(SIGNALING_SERVER, {
    transports: ['websocket', 'polling'],
    reconnection: true,
    reconnectionAttempts: Infinity,
    reconnectionDelay: 1000,
    reconnectionDelayMax: 5000,
    timeout: 60000
  });

  let announceInterval: any;
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
    announceInterval = setInterval(announce, 5000);
  });

  lobbySocket.on('disconnect', () => {
    clearInterval(announceInterval);
  });

  lobbySocket.on('peer-joined', ({ peerId }) => {
    if (!peerId || peerId === lobbySocket?.id) return;
    readyPeerIds.add(peerId);
    currentState.readyPeers = readyPeerIds.size;
    persistState();
    notifyPopupState();
  });

  lobbySocket.on('session-peers', ({ peers }) => {
    readyPeerIds = new Set((peers || []).filter((peerId: string) => peerId !== lobbySocket?.id));
    currentState.readyPeers = readyPeerIds.size;
    persistState();
    notifyPopupState();
  });
}

function stopLobby() {
  if (!lobbySocket) return;
  lobbySocket.removeAllListeners();
  lobbySocket.disconnect();
  lobbySocket = null;
}

function notifyPopupState() {
  try {
    chrome.runtime.sendMessage({
      type: 'STATE_UPDATED',
      state: currentState
    });
  } catch (_) {}
}

async function restoreState() {
  const stored = await chrome.storage.local.get(STATE_STORAGE_KEY);
  const restored = stored[STATE_STORAGE_KEY];
  if (!restored) return;

  currentState = {
    ...currentState,
    ...restored,
    readyPeers: restored.readyPeers || 0
  };

  if (currentState.status !== 'IDLE') {
    const existingContexts = await chrome.runtime.getContexts({
      contextTypes: ['OFFSCREEN_DOCUMENT' as chrome.runtime.ContextType]
    });

    if (existingContexts.length === 0) {
      currentState = {
        isActive: false,
        mode: 'SEND',
        sessionId: '',
        sourceMuted: false,
        status: 'IDLE',
        readyPeers: 0
      };
      persistState();
    }
  }
}

function persistState() {
  chrome.storage.local.set({
    [STATE_STORAGE_KEY]: currentState
  });
}

async function startOffscreen(mode: 'SEND' | 'RECEIVE', sessionId: string, streamId?: string) {
  const existingContexts = await chrome.runtime.getContexts({
    contextTypes: ['OFFSCREEN_DOCUMENT' as chrome.runtime.ContextType]
  });

  const initMessage = {
    target: 'offscreen',
    type: 'INIT_OFFSCREEN',
    mode,
    sessionId,
    streamId
  };

  if (existingContexts.length > 0) {
    chrome.runtime.sendMessage(initMessage);
    return;
  }

  pendingInit = initMessage;
  offscreenReady = false;

  await chrome.offscreen.createDocument({
    url: 'offscreen.html',
    reasons: ['USER_MEDIA' as chrome.offscreen.Reason],
    justification: 'Capturing or playing audio for remote synchronization.'
  });
}
