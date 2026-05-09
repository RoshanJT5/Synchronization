const params = new URLSearchParams(window.location.search);
const sessionId = params.get('id') || '';
const serverUrl = params.get('server') || '';
const sessionLabel = document.querySelector('#session-id');
const openButton = document.querySelector('#open-app');
const apkDownload = document.querySelector('#apk-download');
const apkStatus = document.querySelector('#apk-status');

function appUrl() {
  const deepLink = new URL('synchronization://connect');
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

if (apkDownload && apkStatus) {
  fetch(apkDownload.getAttribute('href'), { method: 'HEAD' })
    .then((response) => {
      if (!response.ok) throw new Error('missing');
      apkStatus.textContent = 'Android APK is available for direct download.';
    })
    .catch(() => {
      apkDownload.removeAttribute('download');
      apkDownload.setAttribute('href', '#setup');
      apkDownload.textContent = 'APK not uploaded yet';
      apkDownload.classList.add('is-disabled');
      apkStatus.textContent = 'Build the Android APK and upload it as web/downloads/synchronization-app.apk before deploying.';
    });
}
