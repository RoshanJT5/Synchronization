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

  // ── Desktop / x86 checks ──────────────────────────────────────────────────
  if (ua.includes('x86_64') || ua.includes('x64') || ua.includes('wow64') || ua.includes('win64')) {
    return 'x86_64';
  }
  if (ua.includes('i686') || (ua.includes('x86') && !ua.includes('android'))) {
    return 'x86_64';
  }

  // ── Explicit ABI strings that only appear on ARM32 devices ───────────────
  // Android WebView / Chrome on 32-bit devices often exposes these.
  if (
    ua.includes('armv7') ||
    ua.includes('armeabi-v7') ||
    ua.includes('armeabi') ||
    ua.includes('arm_32')
  ) {
    return 'arm32';
  }

  // ── Android version heuristic ─────────────────────────────────────────────
  // Extract Android version number from UA like "Android 8.1.0"
  if (ua.includes('android')) {
    const versionMatch = ua.match(/android\s+(\d+)\.?(\d*)/);
    const major = versionMatch ? parseInt(versionMatch[1], 10) : 0;
    const minor = versionMatch && versionMatch[2] ? parseInt(versionMatch[2], 10) : 0;

    // Android 4 and 5: virtually all devices are 32-bit ARMv7.
    if (major <= 5) return 'arm32';

    // Android 6: mostly 32-bit, some early arm64 (Nexus 6P etc.).
    // Defaulting to arm32 is safer for older phones.
    if (major === 6) return 'arm32';

    // Android 7: still a significant mix — lean arm32 as the safer default
    // for phones visiting download pages (newer phones use newer Android).
    if (major === 7) return 'arm32';

    // Android 8.x: many Snapdragon 4xx/6xx devices (e.g. SD625, SD430) are
    // ARMv7 even on Android 8. Without architecture hint, arm32 is safer.
    if (major === 8) return 'arm32';

    // Android 9 and above: the vast majority of devices are arm64.
    // (arm32 phones rarely received Android 9+ updates.)
    return 'arm64';
  }

  // ── Non-Android ARM (e.g. iOS browsing, rare) ─────────────────────────────
  if (platform.includes('arm')) {
    return 'arm64';
  }

  // ── Unknown — default to arm64 (most common architecture today) ───────────
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
  const ua = navigator.userAgent.toLowerCase();
  const isAndroid = ua.includes('android');
  const usedHighEntropy = preferredArch !== initialArch;
  const versionMatch = ua.match(/android\s+(\d+)/);
  const androidMajor = versionMatch ? parseInt(versionMatch[1], 10) : 0;

  let reason;
  if (!isAndroid) {
    reason = 'Recommended guess for PC download. Choose the APK that matches the target phone below.';
  } else if (usedHighEntropy) {
    reason = 'Detected from your browser\'s device architecture API. High confidence.';
  } else if (androidMajor > 0 && androidMajor <= 8) {
    reason = `Detected via Android ${androidMajor} version (older devices often use ARMv7). If your phone is 64-bit, try ARM64 below.`;
  } else {
    reason = 'Recommended for this Android device.';
  }
  apkStatus.textContent = `${label} selected. ${reason}`;
}

setupApkDownloads();


// Hero Scroll Canvas Animation
document.addEventListener('DOMContentLoaded', () => {
  const canvas = document.getElementById('hero-scroll-canvas');
  const container = document.querySelector('.hero-scroll-container');
  
  if (canvas && container) {
    const ctx = canvas.getContext('2d');
    const frameCount = 148;
    const spritesheets = [];
    const sheetCount = 5;
    const framesPerSheet = 30;
    const columns = 5;
    const frameWidth = 960;
    const frameHeight = 540;

    // We only need to load 5 spritesheets
    for (let i = 0; i < sheetCount; i++) {
      spritesheets.push(null);
    }

    // Lazy Loading Logic
    const initialLoadCount = 1; // Load just the first spritesheet immediately (contains first 30 frames)

    const loadImage = (i) => {
      return new Promise((resolve) => {
        const img = new Image();
        img.src = `assets/spritesheets/sheet_${i}.webp`;
        img.onload = () => {
          spritesheets[i] = img;
          if (i === 0) {
            canvas.width = frameWidth;
            canvas.height = frameHeight;
            // Draw first frame
            ctx.drawImage(
              img, 
              0, 0, frameWidth, frameHeight, // source
              0, 0, frameWidth, frameHeight  // destination
            );
          }
          resolve();
        };
        // Fallback if image fails
        img.onerror = resolve; 
      });
    };

    // 1. Load initial sheet
    const initialPromises = [];
    for (let i = 0; i < initialLoadCount && i < sheetCount; i++) {
      initialPromises.push(loadImage(i));
    }

    // 2. Load remaining sheets in background
    Promise.all(initialPromises).then(() => {
      const loadRemaining = async () => {
        for (let i = initialLoadCount; i < sheetCount; i++) {
          await loadImage(i);
        }
      };
      loadRemaining();
    });

    const updateCanvasProgress = () => {
      const rect = container.getBoundingClientRect();
      const stickyOffset = window.innerHeight * 0.15; // 15vh sticky top
      const maxScroll = container.offsetHeight - window.innerHeight;
      
      let progress = (stickyOffset - rect.top) / maxScroll;
      if (progress < 0) progress = 0;
      if (progress > 1) progress = 1;
      
      const frameIndex = Math.floor(progress * (frameCount - 1));
      
      const sheetIndex = Math.floor(frameIndex / framesPerSheet);
      const currentSheet = spritesheets[sheetIndex];
      
      // Ensure we don't draw if the sheet isn't loaded yet
      if (currentSheet && currentSheet.complete && currentSheet.naturalHeight !== 0) {
        if (canvas.width !== frameWidth) {
            canvas.width = frameWidth;
            canvas.height = frameHeight;
        }
        
        const localIndex = frameIndex % framesPerSheet;
        const col = localIndex % columns;
        const row = Math.floor(localIndex / columns);
        
        ctx.clearRect(0, 0, canvas.width, canvas.height);
        ctx.drawImage(
            currentSheet, 
            col * frameWidth, row * frameHeight, frameWidth, frameHeight, // source x,y,w,h
            0, 0, canvas.width, canvas.height // destination x,y,w,h
        );
      }
    };

    let isScrolling = false;
    window.addEventListener('scroll', () => {
      if (!isScrolling) {
        window.requestAnimationFrame(() => {
          updateCanvasProgress();
          isScrolling = false;
        });
        isScrolling = true;
      }
    }, { passive: true });
    
    // Initial draw (in case user refreshes partway down the page)
    updateCanvasProgress();

    // Setup Video Fallback logic
    const video = document.getElementById('hero-scroll-video');
    const savedScrollAnim = localStorage.getItem('bgScrollAnimEnabled');
    
    const applyScrollAnimState = (isScrollEnabled) => {
      if (isScrollEnabled) {
        canvas.style.display = 'block';
        if (video) video.style.display = 'none';
        container.classList.remove('no-scroll-anim');
      } else {
        canvas.style.display = 'none';
        if (video) video.style.display = 'block';
        container.classList.add('no-scroll-anim');
      }
    };

    // Apply initial state
    applyScrollAnimState(savedScrollAnim === 'true');

    // Listen for toggle changes from bg-animator.js
    document.addEventListener('scrollAnimToggled', (e) => {
      applyScrollAnimState(e.detail.enabled);
    });
  }
});
