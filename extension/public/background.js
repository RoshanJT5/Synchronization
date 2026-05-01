// background.js

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message.type === 'START_CAPTURE') {
    startCapture(message.sessionId);
  }
});

async function startCapture(sessionId) {
  // Check if offscreen document already exists
  const existingContexts = await chrome.runtime.getContexts({
    contextTypes: ['OFFSCREEN_DOCUMENT']
  });

  if (existingContexts.length > 0) {
    return;
  }

  // Create offscreen document
  await chrome.offscreen.createDocument({
    url: 'offscreen.html',
    reasons: ['USER_MEDIA'],
    justification: 'Capturing audio to stream to mobile device via WebRTC.'
  });

  // Notify offscreen document to start
  chrome.runtime.sendMessage({
    type: 'INIT_OFFSCREEN',
    sessionId: sessionId
  });
}
