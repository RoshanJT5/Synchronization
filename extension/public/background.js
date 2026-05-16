chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message.type === 'GET_STATE') {
    sendResponse({
      isActive: false,
      mode: 'INFO',
      sessionId: '',
      status: 'IDLE',
      readyPeers: 0,
    });
    return true;
  }
  return false;
});
