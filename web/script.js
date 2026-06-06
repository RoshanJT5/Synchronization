const params = new URLSearchParams(window.location.search);
const sessionId = params.get('id') || '';
const serverUrl = params.get('server') || '';
const sessionLabel = document.querySelector('#session-id');
const openButton = document.querySelector('#open-app');
const apkDownload = document.querySelector('#apk-download');
const apkStatus = document.querySelector('#apk-status');
const apkOptions = Array.from(document.querySelectorAll('.apk-option'));

const APK_LABELS = {
  arm64: 'ARM64',
  arm32: 'ARMv7 / 32-bit',
  x86_64: 'x86_64',
};

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

function detectPreferredAndroidArch() {
  const ua = navigator.userAgent.toLowerCase();
  const platform = (navigator.platform || '').toLowerCase();

  if (ua.includes('x86_64') || ua.includes('x64') || ua.includes('wow64') || ua.includes('win64')) {
    return 'x86_64';
  }

  if (ua.includes('i686') || ua.includes('x86')) {
    return 'x86_64';
  }

  if (ua.includes('armv7') || ua.includes('armeabi') || ua.includes('android 4') || ua.includes('android 5')) {
    return 'arm32';
  }

  if (ua.includes('android')) {
    return 'arm64';
  }

  if (platform.includes('arm')) {
    return 'arm64';
  }

  return 'arm64';
}

async function detectHighEntropyArch(fallback) {
  const uaData = navigator.userAgentData;
  if (!uaData?.getHighEntropyValues) return fallback;

  try {
    const values = await uaData.getHighEntropyValues(['architecture', 'bitness', 'platform']);
    const architecture = `${values.architecture || ''}`.toLowerCase();
    const bitness = `${values.bitness || ''}`.toLowerCase();
    const platform = `${values.platform || ''}`.toLowerCase();

    if (architecture.includes('x86') && bitness === '64') return 'x86_64';
    if (architecture.includes('arm') && bitness === '64') return 'arm64';
    if (architecture.includes('arm')) return 'arm32';
    if (platform.includes('android')) return fallback;
  } catch {
    return fallback;
  }

  return fallback;
}

async function apkExists(option) {
  try {
    const response = await fetch(option.getAttribute('href'), {
      method: 'HEAD',
      cache: 'no-store',
    });
    return response.ok;
  } catch {
    return false;
  }
}

function setRecommended(option) {
  apkOptions.forEach((item) => item.classList.remove('is-recommended'));
  option.classList.add('is-recommended');

  const arch = option.dataset.arch;
  apkDownload.href = option.href;
  apkDownload.setAttribute('download', option.getAttribute('download'));
  apkDownload.classList.remove('is-disabled');
  apkDownload.textContent = `Download Android APK (${APK_LABELS[arch] || arch})`;
}

async function setupApkDownloads() {
  if (!apkDownload || !apkStatus || apkOptions.length === 0) return;

  apkDownload.classList.add('is-disabled');
  apkStatus.textContent = 'Checking Android APK downloads...';

  const initialArch = detectPreferredAndroidArch();
  const preferredArch = await detectHighEntropyArch(initialArch);
  const availability = new Map();

  await Promise.all(
    apkOptions.map(async (option) => {
      const available = await apkExists(option);
      availability.set(option.dataset.arch, available);
      option.classList.toggle('is-disabled', !available);
      option.querySelector('.apk-state').textContent = available ? 'Available' : 'Not uploaded yet';
      if (!available) {
        option.removeAttribute('download');
        option.setAttribute('aria-disabled', 'true');
      }
    }),
  );

  const recommended =
    apkOptions.find((option) => option.dataset.arch === preferredArch && availability.get(option.dataset.arch)) ||
    apkOptions.find((option) => option.dataset.arch === 'arm64' && availability.get(option.dataset.arch)) ||
    apkOptions.find((option) => availability.get(option.dataset.arch));

  if (!recommended) {
    apkDownload.removeAttribute('download');
    apkDownload.setAttribute('href', '#setup');
    apkDownload.textContent = 'Android APKs not uploaded yet';
    apkStatus.textContent = 'Build split APKs and copy them into web/downloads using the three architecture filenames.';
    return;
  }

  setRecommended(recommended);
  const label = APK_LABELS[recommended.dataset.arch] || recommended.dataset.arch;
  const reason = navigator.userAgent.toLowerCase().includes('android')
    ? 'Recommended for this Android device.'
    : 'Recommended guess. If you are downloading on PC, choose the APK for the target phone below.';
  apkStatus.textContent = `${label} selected. ${reason}`;
}

setupApkDownloads();
