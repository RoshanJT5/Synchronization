// src/background.ts

let offscreenReady = false;
let pendingInit: any = null;

let currentState = {
  isActive: false,
  mode: 'SEND',
  sessionId: '',
  sourceMuted: false,
  status: 'IDLE'
};

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message.type === 'GET_STATE') {
    sendResponse(currentState);
    return true;
  } else if (message.type === 'START_CAPTURE') {
    currentState.isActive = true;
    currentState.mode = 'SEND';
    currentState.sessionId = message.sessionId;
    currentState.status = 'CONNECTING';
    startOffscreen('SEND', message.sessionId, message.streamId).catch((error) => {
      currentState.isActive = false;
      currentState.status = 'ERROR';
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
    startOffscreen('RECEIVE', message.sessionId).catch((error) => {
      currentState.isActive = false;
      currentState.status = 'ERROR';
      chrome.runtime.sendMessage({
        type: 'CONNECTION_ERROR',
        error: error?.message || 'Could not start the audio worker.'
      });
    });
  } else if (message.type === 'SET_SOURCE_MUTE') {
    currentState.sourceMuted = message.muted;
    // Forward mute toggle directly to the offscreen document
    chrome.runtime.sendMessage({ type: 'SET_SOURCE_MUTE', muted: message.muted });
  } else if (message.type === 'STOP_CAPTURE') {
    currentState.isActive = false;
    currentState.status = 'IDLE';
    currentState.sessionId = '';
    // Close the offscreen document entirely to clean up audio/sockets instantly
    chrome.offscreen.closeDocument().catch(() => {});
    offscreenReady = false;
  } else if (message.type === 'CONNECTION_SUCCESS') {
    currentState.status = currentState.mode === 'SEND' ? 'CAPTURING' : 'LISTENING';
  } else if (message.type === 'CONNECTION_ERROR') {
    currentState.isActive = false;
    currentState.status = 'ERROR';
  } else if (message.type === 'OFFSCREEN_READY') {
    offscreenReady = true;
    if (pendingInit) {
      chrome.runtime.sendMessage(pendingInit);
      pendingInit = null;
    }
  }
});

async function startOffscreen(mode: 'SEND' | 'RECEIVE', sessionId: string, streamId?: string) {
  const existingContexts = await chrome.runtime.getContexts({
    contextTypes: ['OFFSCREEN_DOCUMENT' as chrome.runtime.ContextType]
  });

  const initMessage = {
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
