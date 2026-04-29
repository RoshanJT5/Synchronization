const params = new URLSearchParams(window.location.search);
const sessionId = params.get('id') || '';
const serverUrl = params.get('server') || '';
const sessionLabel = document.querySelector('#session-id');
const openButton = document.querySelector('#open-app');

function appUrl() {
  const deepLink = new URL('syncronization://connect');
  if (sessionId) deepLink.searchParams.set('id', sessionId);
  if (serverUrl) deepLink.searchParams.set('server', serverUrl);
  return deepLink.toString();
}

function openApp() {
  if (!sessionId) return;
  window.location.href = appUrl();
}

if (sessionId) {
  sessionLabel.textContent = sessionId.toUpperCase();
  openButton.disabled = false;

  window.setTimeout(openApp, 500);
} else {
  openButton.disabled = true;
}

openButton.addEventListener('click', openApp);
