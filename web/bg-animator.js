/**
 * Synchronization - Animated Background Animator & Preview Switcher
 * Handles procedural canvas-based Bokeh, Purple Glittering Snow, and Purple Flies simulations.
 */

(function () {
  // Configuration mapping internal keys to user-friendly metadata
  const ANIM_META = {
    'procedural_bokeh': {
      name: 'Purple Bubbles',
      desc: 'Procedural real-time floating purple bubbles with 3D highlights (Infinite)',
      aspect: 'Responsive'
    },
    'purple_flies': {
      name: 'Purple Flies',
      desc: 'Procedural glittering purple snow and edge vignettes (Infinite)',
      aspect: 'Responsive'
    },
    'purple_snow': {
      name: 'Purple Snow',
      desc: 'Procedural real-time glittering purple snow falling down (Infinite)',
      aspect: 'Responsive'
    }
  };

  // State Variables
  let activeKey = localStorage.getItem('bgActiveKey') || 'procedural_bokeh'; // default
  let densityScale = 1.0;
  let playbackSpeed = parseFloat(localStorage.getItem('bgPlaybackSpeed')) || 10; // fps target ~10 default
  let glitterModifier = 0.7;

  // New state variables for toggles
  let animDisabled = localStorage.getItem('bgAnimDisabled') === 'true';
  let allPagesAnim = localStorage.getItem('bgAllPagesAnim') === 'true';
  let spotlightGlow = localStorage.getItem('bgSpotlightGlow') !== 'false'; // Defaults to true
  let isHomePage = window.location.pathname.endsWith('index.html') || window.location.pathname === '/' || window.location.pathname.endsWith('.app/');

  let lastTimestamp = 0;
  let animationFrameId = null;

  // Procedural Bokeh State (Preserved user's custom bubble configurations)
  let bubbles = [];
  const BUBBLE_COUNT = 50; // User custom bubble count
  const BUBBLE_COLORS = [
    { r: 180, g: 40, b: 220 },
    { r: 160, g: 30, b: 200 },
    { r: 200, g: 60, b: 240 },
    { r: 140, g: 20, b: 180 },
    { r: 220, g: 80, b: 255 },
    { r: 120, g: 10, b: 160 }
  ];

  // Procedural Snow State
  let snowParticles = [];
  const SNOW_COUNT = 180;
  const SNOW_COLORS = [
    { r: 168, g: 85, b: 247 }, // #a855f7
    { r: 217, g: 70, b: 239 }, // #d946ef
    { r: 192, g: 38, b: 211 }, // violet
    { r: 139, g: 92, b: 246 }, // purple-blue
    { r: 243, g: 232, b: 255 }, // light violet/white glow
    { r: 255, g: 255, b: 255 }  // pure white sparkle
  ];

  // Procedural Flies State (Direct translation of user's provided Purple Glitter Snow)
  let fliesParticles = [];
  const FLIES_COUNT = 420;
  const FLIES_COLORS = [
    { r: 220, g: 80, b: 255 },
    { r: 200, g: 60, b: 240 },
    { r: 255, g: 140, b: 255 },
    { r: 180, g: 40, b: 220 },
    { r: 255, g: 200, b: 255 },
    { r: 160, g: 30, b: 200 },
    { r: 240, g: 100, b: 255 },
    { r: 255, g: 255, b: 255 }
  ];

  // DOM Elements
  let canvas = null;
  let ctx = null;

  // Bubble Class (User modified parameters are fully preserved)
  class Bubble {
    constructor(initOnScreen = false) {
      this.reset(initOnScreen);
    }

    reset(initOnScreen = false) {
      const w = window.innerWidth;
      const h = window.innerHeight;
      this.x = Math.random() * w;
      this.y = initOnScreen ? Math.random() * h : h + Math.random() * 20 + 20;
      this.baseR = 18 + Math.random() * 90;
      this.r = this.baseR;
      
      // User custom speeds
      this.vx = (Math.random() - 0.5) * 2;
      this.vy = -(0.6 + Math.random() * 0.6);
      
      this.c = BUBBLE_COLORS[Math.floor(Math.random() * BUBBLE_COLORS.length)];
      this.a = 0.12 + Math.random() * 0.38;
      
      // User custom pulsing rates
      this.ps = 0.03 + Math.random() * 0.05;
      this.pp = Math.random() * Math.PI * 2;
      this.life = 0;
      this.maxL = 1000 + Math.random() * 1600;
      
      // User custom fade in/out
      this.fi = 120;
      this.fo = 220;
      this.ca = 0;
    }

    update() {
      const w = window.innerWidth;
      const h = window.innerHeight;
      // Scale speed relative to default 10.0 (User manual configuration)
      const speedRatio = playbackSpeed / 10.0;

      this.x += this.vx * speedRatio;
      this.y += this.vy * speedRatio;
      this.life += speedRatio;

      this.x += Math.sin(this.life * 0.005 + this.pp) * 0.06 * speedRatio;
      // Pulse speed modulated by widget's glitter rate
      const p = 1 + Math.sin(this.life * this.ps * glitterModifier + this.pp) * 0.12;
      this.r = this.baseR * p;

      let o = this.a;
      if (this.life < this.fi) {
        o = this.a * (this.life / this.fi);
      } else if (this.life > this.maxL - this.fo) {
        o = this.a * Math.max(0, (this.maxL - this.life) / this.fo);
      }

      if (this.y + this.r < -20 || this.life >= this.maxL || this.x < -this.r - 40 || this.x > w + this.r + 40) {
        this.reset(false);
      }
      this.ca = o;
    }

    draw() {
      const a = this.ca;
      if (a <= 0) return;

      // Create shifted highlight center to simulate 3D refraction
      const shiftX = this.x + Math.cos(this.life * 0.015 + this.pp) * (this.r * 0.1);
      const shiftY = this.y + Math.sin(this.life * 0.015 + this.pp) * (this.r * 0.1);

      const g = ctx.createRadialGradient(shiftX, shiftY, 0, this.x, this.y, this.r);
      const { r, g: gg, b } = this.c;

      g.addColorStop(0, `rgba(${r},${gg},${b},${a * 0.95})`);
      g.addColorStop(0.35, `rgba(${r},${gg},${b},${a * 0.55})`);
      g.addColorStop(0.7, `rgba(${r},${gg},${b},${a * 0.18})`);
      g.addColorStop(1, `rgba(${r},${gg},${b},0)`);

      ctx.beginPath();
      ctx.arc(this.x, this.y, this.r, 0, Math.PI * 2);
      ctx.fillStyle = g;
      ctx.fill();

      // Shimmering outer border ring
      if (a > 0.08) {
        const ringShimmer = (0.15 + Math.sin(this.life * 0.02 + this.pp) * 0.07) * glitterModifier;
        ctx.beginPath();
        ctx.arc(this.x, this.y, this.r * 0.94, 0, Math.PI * 2);
        ctx.strokeStyle = `rgba(${Math.min(255, r + 45)},${Math.min(255, gg + 35)},${Math.min(255, b + 45)},${a * ringShimmer})`;
        ctx.lineWidth = 1.0;
        ctx.stroke();
      }
    }
  }

  // SnowParticle Class (Procedural purple snow falling with lens highlights & parallax layers)
  class SnowParticle {
    constructor(initOnScreen = false) {
      this.reset(initOnScreen);
    }

    reset(initOnScreen = false) {
      const w = window.innerWidth;
      const h = window.innerHeight;
      this.x = Math.random() * w;
      this.y = initOnScreen ? Math.random() * h : -20 - Math.random() * 50;

      // Parallax depth layering (0 is far/tiny, 1 is near/large)
      const depth = Math.random();
      this.depth = depth;

      this.size = 0.5 + depth * 2.8; // range: 0.5px to 3.3px
      this.vx = (Math.random() - 0.5) * 0.25;
      this.vy = 0.15 + depth * 0.45; // slower, gentler snow speed (range: 0.15px to 0.6px)

      this.c = SNOW_COLORS[Math.floor(Math.random() * SNOW_COLORS.length)];
      this.baseAlpha = 0.15 + Math.random() * 0.65;
      this.glitterSpeed = 0.02 + Math.random() * 0.06;
      this.phase = Math.random() * Math.PI * 2;
      this.life = Math.random() * 1000;

      this.swaySpeed = 0.005 + Math.random() * 0.01;
      this.swayAmt = 0.1 + Math.random() * 0.3;
      this.ca = 0;
    }

    update() {
      const w = window.innerWidth;
      const h = window.innerHeight;
      // Scale speed relative to default 25.0 f/s to keep base speed correct at startup
      const speedRatio = playbackSpeed / 25.0;

      this.y += this.vy * speedRatio;
      this.x += this.vx * speedRatio;
      this.life += speedRatio;

      // Gentle swaying drift
      this.x += Math.sin(this.life * this.swaySpeed + this.phase) * this.swayAmt * speedRatio;

      // Twinkling/Glittering alpha oscillation
      this.ca = this.baseAlpha * (0.2 + 0.8 * Math.abs(Math.sin(this.life * this.glitterSpeed * glitterModifier + this.phase)));

      // Occasional random flash highlight
      if (Math.random() < 0.0005) {
        this.ca = 0.95;
      }

      // Recycle if falling off-screen
      if (this.y > h + 10 || this.x < -10 || this.x > w + 10) {
        this.reset(false);
      }
    }

    draw() {
      const a = this.ca;
      if (a <= 0) return;

      const { r, g: gg, b } = this.c;

      // Draw particle halo for foreground particles (adds premium depth)
      if (this.depth > 0.6) {
        const glowRad = this.size * 3.5;
        const g = ctx.createRadialGradient(this.x, this.y, 0, this.x, this.y, glowRad);
        g.addColorStop(0, `rgba(${r},${gg},${b},${a * 0.35})`);
        g.addColorStop(0.5, `rgba(${r},${gg},${b},${a * 0.1})`);
        g.addColorStop(1, `rgba(${r},${gg},${b},0)`);
        ctx.beginPath();
        ctx.arc(this.x, this.y, glowRad, 0, Math.PI * 2);
        ctx.fillStyle = g;
        ctx.fill();
      }

      // Draw particle core
      ctx.beginPath();
      ctx.arc(this.x, this.y, this.size, 0, Math.PI * 2);
      ctx.fillStyle = `rgba(${r},${gg},${b},${a})`;
      ctx.fill();

      // If foreground particle is twinkling brightly, draw lens cross flares
      if (this.depth > 0.8 && a > 0.75) {
        ctx.strokeStyle = `rgba(255, 255, 255, ${a * 0.6})`;
        ctx.lineWidth = 0.6;
        ctx.beginPath();
        ctx.moveTo(this.x - this.size * 2, this.y);
        ctx.lineTo(this.x + this.size * 2, this.y);
        ctx.moveTo(this.x, this.y - this.size * 2);
        ctx.lineTo(this.x, this.y + this.size * 2);
        ctx.stroke();
      }
    }
  }

  // FliesParticle Class (Translates user's Purple Glitter Snow script)
  class FliesParticle {
    constructor(initOnScreen = false) {
      this.reset(initOnScreen);
    }

    reset(initOnScreen = false) {
      const w = window.innerWidth;
      const h = window.innerHeight;
      this.x = Math.random() * w;
      this.y = initOnScreen ? Math.random() * h : -Math.random() * 80;

      // Size spectrum: many tiny, fewer medium/bright
      const roll = Math.random();
      if (roll < 0.72) {
        this.baseSize = 0.6 + Math.random() * 1.4;
      } else if (roll < 0.92) {
        this.baseSize = 1.8 + Math.random() * 2.4;
      } else {
        this.baseSize = 3.2 + Math.random() * 3.5;
      }
      this.size = this.baseSize;
      
      this.vx = (Math.random() - 0.5) * 0.35;
      this.vy = 0.18 + Math.random() * 0.55; // gentle downward drift

      this.color = FLIES_COLORS[Math.floor(Math.random() * FLIES_COLORS.length)];
      this.alpha = 0.25 + Math.random() * 0.75;
      this.twinkleSpeed = 0.02 + Math.random() * 0.06;
      this.twinklePhase = Math.random() * Math.PI * 2;
      this.life = 0;
      this.maxLife = 700 + Math.random() * 1100;
      this.fadeIn = 40 + Math.random() * 50;
      this.fadeOut = 120 + Math.random() * 100;
      this.swayAmp = 0.15 + Math.random() * 0.4;
      this.swayFreq = 0.006 + Math.random() * 0.012;
      this.currentAlpha = 0;
    }

    update() {
      const w = window.innerWidth;
      const h = window.innerHeight;
      // Scale speed relative to default 25.0 f/s to keep base speed correct at startup
      const speedRatio = playbackSpeed / 25.0;

      this.x += (this.vx + Math.sin(this.life * this.swayFreq + this.twinklePhase) * this.swayAmp) * speedRatio;
      this.y += this.vy * speedRatio;
      this.life += speedRatio;

      // Twinkle size pulsing modulated by widgets' glitter Rate
      const tw = 0.7 + 0.3 * Math.sin(this.life * this.twinkleSpeed * glitterModifier + this.twinklePhase);
      this.size = this.baseSize * tw;

      let o = this.alpha;
      if (this.life < this.fadeIn) {
        o = this.alpha * (this.life / this.fadeIn);
      } else if (this.life > this.maxLife - this.fadeOut) {
        o = this.alpha * Math.max(0, (this.maxLife - this.life) / this.fadeOut);
      }

      // Twinkle brightness modulation
      o *= 0.55 + 0.45 * Math.sin(this.life * this.twinkleSpeed * 1.7 * glitterModifier + this.twinklePhase);
      this.currentAlpha = Math.max(0, Math.min(1, o));

      if (this.y > h + 20 || this.life >= this.maxLife || this.x < -20 || this.x > w + 20) {
        this.reset(false);
      }
    }

    draw() {
      const a = this.currentAlpha;
      if (a < 0.02) return;

      const { r, g, b } = this.color;

      // Soft glowing radial gradient core
      const grd = ctx.createRadialGradient(this.x, this.y, 0, this.x, this.y, this.size * 2.2);
      grd.addColorStop(0, `rgba(${r},${g},${b},${a * 0.95})`);
      grd.addColorStop(0.4, `rgba(${r},${g},${b},${a * 0.45})`);
      grd.addColorStop(1, `rgba(${r},${g},${b},0)`);

      ctx.beginPath();
      ctx.arc(this.x, this.y, this.size * 2.2, 0, Math.PI * 2);
      ctx.fillStyle = grd;
      ctx.fill();

      // Bright center spark for larger particles
      if (this.baseSize > 2.2) {
        ctx.beginPath();
        ctx.arc(this.x, this.y, this.size * 0.45, 0, Math.PI * 2);
        ctx.fillStyle = `rgba(255,240,255,${a * 0.9})`;
        ctx.fill();
      }
    }
  }

  // Initialize bubbles for procedural effect
  function initBubbles() {
    bubbles = [];
    const targetCount = Math.floor(BUBBLE_COUNT * densityScale);
    for (let i = 0; i < targetCount; i++) {
      bubbles.push(new Bubble(true));
    }
  }

  // Initialize snow particles for procedural effect
  function initSnow() {
    snowParticles = [];
    const targetCount = Math.floor(SNOW_COUNT * densityScale);
    for (let i = 0; i < targetCount; i++) {
      snowParticles.push(new SnowParticle(true));
    }
  }

  // Initialize flies particles (for Purple Flies effect)
  function initFlies() {
    fliesParticles = [];
    const targetCount = Math.floor(FLIES_COUNT * densityScale);
    for (let i = 0; i < targetCount; i++) {
      fliesParticles.push(new FliesParticle(true));
    }
  }

  // Dynamic particle count adjustment (triggered by density slider)
  function adjustParticleCounts() {
    if (activeKey === 'procedural_bokeh') {
      const targetCount = Math.floor(BUBBLE_COUNT * densityScale);
      while (bubbles.length < targetCount) {
        bubbles.push(new Bubble(false));
      }
      if (bubbles.length > targetCount) {
        bubbles.length = targetCount;
      }
    } else if (activeKey === 'purple_snow') {
      const targetCount = Math.floor(SNOW_COUNT * densityScale);
      while (snowParticles.length < targetCount) {
        snowParticles.push(new SnowParticle(false));
      }
      if (snowParticles.length > targetCount) {
        snowParticles.length = targetCount;
      }
    } else if (activeKey === 'purple_flies') {
      const targetCount = Math.floor(FLIES_COUNT * densityScale);
      while (fliesParticles.length < targetCount) {
        fliesParticles.push(new FliesParticle(false));
      }
      if (fliesParticles.length > targetCount) {
        fliesParticles.length = targetCount;
      }
    }
  }

  // Initialization
  function init() {
    // Apply spotlight glow preference immediately
    if (!spotlightGlow) {
      document.body.classList.add('no-spotlight');
    } else {
      document.body.classList.remove('no-spotlight');
    }

    // Canvas setup
    canvas = document.createElement('canvas');
    canvas.id = 'bg-canvas';
    document.body.insertBefore(canvas, document.body.firstChild);
    ctx = canvas.getContext('2d');

    // Make canvas responsive
    resizeCanvas();
    window.addEventListener('resize', resizeCanvas);

    // 2. Build Switcher Control Panel
    createSwitcherUI();

    // 3. Load initial animation and start loop
    loadActiveAnimation();
    lastTimestamp = performance.now();
    requestAnimationFrame(renderLoop);
  }

  // Handle Canvas Resizing (With High-DPR sharpness support)
  function resizeCanvas() {
    if (canvas) {
      const dpr = Math.min(window.devicePixelRatio || 1, 2);
      const layoutW = window.innerWidth;
      const layoutH = window.innerHeight;

      canvas.width = layoutW * dpr;
      canvas.height = layoutH * dpr;
      canvas.style.width = layoutW + 'px';
      canvas.style.height = layoutH + 'px';

      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);

      // Prevent clamping issues on resize
      bubbles.forEach(b => {
        if (b.x > layoutW + 50) b.x = Math.random() * layoutW;
        if (b.y > layoutH + 100) b.y = Math.random() * layoutH;
      });
      snowParticles.forEach(s => {
        if (s.x > layoutW + 50) s.x = Math.random() * layoutW;
        if (s.y > layoutH + 100) s.y = Math.random() * layoutH;
      });
      fliesParticles.forEach(p => {
        if (p.x > layoutW + 30) p.x = Math.random() * layoutW;
        if (p.y > layoutH + 40) p.y = Math.random() * layoutH;
      });
    }
  }

  // Initializer for the active animation key
  function loadActiveAnimation() {
    if (activeKey === 'procedural_bokeh') {
      initBubbles();
    } else if (activeKey === 'purple_snow') {
      initSnow();
    } else if (activeKey === 'purple_flies') {
      initFlies();
    }
  }

  // Draw Vignette for Purple Flies background
  function drawFliesVignette() {
    const w = window.innerWidth;
    const h = window.innerHeight;

    // Soft purple edge glow matching the video frames
    const v = ctx.createRadialGradient(
      w * 0.5, h * 0.5, Math.min(w, h) * 0.25,
      w * 0.5, h * 0.5, Math.max(w, h) * 0.72
    );
    v.addColorStop(0, "rgba(0,0,0,0)");
    v.addColorStop(0.55, "rgba(30,0,50,0.15)");
    v.addColorStop(0.85, "rgba(80,0,120,0.35)");
    v.addColorStop(1, "rgba(120,20,160,0.55)");
    ctx.fillStyle = v;
    ctx.fillRect(0, 0, w, h);
  }

  // Frame Render Loop (executes at maximum browser frame rate)
  function renderLoop(timestamp) {
    animationFrameId = requestAnimationFrame(renderLoop);

    if (animDisabled) return; // Skip rendering if animation is disabled
    if (!isHomePage && !allPagesAnim) return; // Skip rendering on non-home pages if global animation is off

    // Calculate delta time
    const dt = (timestamp - lastTimestamp) / 1000;
    lastTimestamp = timestamp;

    // 1. Draw solid dark background
    ctx.fillStyle = '#000000';
    ctx.fillRect(0, 0, window.innerWidth, window.innerHeight);

    // 2. Render specific procedural items
    if (activeKey === 'procedural_bokeh' || activeKey === 'purple_snow') {
      // Ambient glow (shared for bokeh and snow)
      const layoutW = window.innerWidth;
      const layoutH = window.innerHeight;
      const amb = ctx.createRadialGradient(layoutW * 0.5, layoutH * 0.45, 0, layoutW * 0.5, layoutH * 0.45, Math.max(layoutW, layoutH) * 0.7);
      amb.addColorStop(0, 'rgba(40, 0, 60, 0.22)');
      amb.addColorStop(0.5, 'rgba(20, 0, 35, 0.1)');
      amb.addColorStop(1, 'rgba(0, 0, 0, 0)');
      ctx.fillStyle = amb;
      ctx.fillRect(0, 0, layoutW, layoutH);

      if (activeKey === 'procedural_bokeh') {
        for (const b of bubbles) {
          b.update();
          b.draw();
        }
      } else {
        for (const s of snowParticles) {
          s.update();
          s.draw();
        }
      }
    } else if (activeKey === 'purple_flies') {
      // Haze background
      const w = window.innerWidth;
      const h = window.innerHeight;
      const haze = ctx.createLinearGradient(0, 0, 0, h * 0.55);
      haze.addColorStop(0, "rgba(90, 10, 130, 0.22)");
      haze.addColorStop(0.4, "rgba(40, 0, 60, 0.08)");
      haze.addColorStop(1, "rgba(0, 0, 0, 0)");
      ctx.fillStyle = haze;
      ctx.fillRect(0, 0, w, h);

      // Particles
      for (const p of fliesParticles) {
        p.update();
        p.draw();
      }

      // Vignette
      drawFliesVignette();
    }
  }

  // Create UI Widget
  function createSwitcherUI() {
    // Check if widget already exists, remove if so (for updates)
    const existingWidget = document.getElementById('bg-switcher-widget');
    if (existingWidget) existingWidget.remove();

    // Find trigger button in the navbar or page
    const trigger = document.getElementById('bg-switcher-trigger-btn');

    // Switcher Container
    const switcher = document.createElement('div');
    switcher.className = 'bg-switcher minimized';
    switcher.id = 'bg-switcher-widget';

    // Initial density values
    let densityDisplayVal = '';
    if (activeKey === 'procedural_bokeh') {
      densityDisplayVal = Math.floor(BUBBLE_COUNT * densityScale);
    } else if (activeKey === 'purple_snow') {
      densityDisplayVal = Math.floor(SNOW_COUNT * densityScale);
    } else if (activeKey === 'purple_flies') {
      densityDisplayVal = Math.floor(FLIES_COUNT * densityScale);
    } else {
      densityDisplayVal = densityScale.toFixed(1) + 'x';
    }

    // Switcher HTML Structure
    switcher.innerHTML = `
      <div class="bg-sw-header">
        <h3>Background Switcher</h3>
        <button id="bg-sw-minimize" title="Minimize Panel">
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <line x1="18" y1="6" x2="6" y2="18"></line>
            <line x1="6" y1="6" x2="18" y2="18"></line>
          </svg>
        </button>
      </div>
      
      <p class="bg-sw-intro">Play with our exclusive backgrounds. Use the sliders to customize speed, density, and shimmer rates.</p>

      <div class="bg-sw-list">
        ${Object.keys(ANIM_META).map((key) => {
          const m = ANIM_META[key];
          return `
            <button class="bg-sw-option ${key === activeKey ? 'active' : ''}" data-key="${key}">
              <div class="bg-opt-name">${m.name}</div>
              <div class="bg-opt-desc">${m.desc}</div>
              <div class="bg-opt-badge">${m.aspect} Fit</div>
            </button>
          `;
        }).join('')}
      </div>

      <div class="bg-sw-settings">
        <div class="bg-sw-row">
          <span>Speed / Rate</span>
          <div class="bg-sw-slider-group">
            <input type="range" id="bg-fps-slider" min="1" max="50" value="${playbackSpeed}" step="1">
            <strong id="bg-fps-val" style="width: 25px; text-align: right;">${Math.round(playbackSpeed)}</strong>
            <span style="color: var(--text-dim); font-size: 10px;">f/s</span>
          </div>
        </div>

        <div class="bg-sw-row">
          <span>Density / Amount</span>
          <div class="bg-sw-slider-group">
            <input type="range" id="bg-density-slider" min="0.2" max="2.0" value="${densityScale}" step="0.1">
            <strong id="bg-density-val" style="width: 35px; text-align: right;">${densityDisplayVal}</strong>
          </div>
        </div>

        <div class="bg-sw-row">
          <span>Glitter / Shimmer</span>
          <div class="bg-sw-slider-group">
            <input type="range" id="bg-glitter-slider" min="0.2" max="3.0" value="${glitterModifier}" step="0.1">
            <strong id="bg-glitter-val" style="width: 30px; text-align: right;">${glitterModifier.toFixed(1)}x</strong>
          </div>
        </div>

        <div class="bg-sw-row">
          <span>Spotlight Glow</span>
          <label class="bg-sw-switch">
            <input type="checkbox" id="bg-spotlight-toggle" ${spotlightGlow ? 'checked' : ''}>
            <span class="bg-sw-slider"></span>
          </label>
        </div>

        <div class="bg-sw-row">
          <span>Disable Animation</span>
          <label class="bg-sw-switch">
            <input type="checkbox" id="bg-disable-toggle" ${animDisabled ? 'checked' : ''}>
            <span class="bg-sw-slider"></span>
          </label>
        </div>

        <div class="bg-sw-row">
          <span>Global Animation</span>
          <label class="bg-sw-switch" id="bg-global-toggle-label" style="${animDisabled ? 'opacity: 0.4; cursor: not-allowed;' : ''}">
            <input type="checkbox" id="bg-global-toggle" ${allPagesAnim ? 'checked' : ''} ${animDisabled ? 'disabled' : ''}>
            <span class="bg-sw-slider"></span>
          </label>
        </div>
      </div>
    `;
    document.body.appendChild(switcher);

    // Apply Switcher Event Listeners
    setupUIListeners(switcher, trigger);
  }

  // Attach Event Listeners to widget controls
  function setupUIListeners(switcher, trigger) {
    // 1. Toggle Active background
    const options = switcher.querySelectorAll('.bg-sw-option');
    options.forEach(opt => {
      opt.addEventListener('click', () => {
        options.forEach(o => o.classList.remove('active'));
        opt.classList.add('active');

        const newKey = opt.dataset.key;
        const changed = (newKey !== activeKey);
        activeKey = newKey;
        localStorage.setItem('bgActiveKey', activeKey);
        loadActiveAnimation();

        // Apply default spotlight preference when switching backgrounds
        if (changed) {
          spotlightGlow = (activeKey !== 'purple_snow');
          localStorage.setItem('bgSpotlightGlow', spotlightGlow);
          
          const spotlightToggle = switcher.querySelector('#bg-spotlight-toggle');
          if (spotlightToggle) spotlightToggle.checked = spotlightGlow;
          
          if (spotlightGlow) {
            document.body.classList.remove('no-spotlight');
          } else {
            document.body.classList.add('no-spotlight');
          }
        }

        // Refresh density display text immediately when active background switches
        const densityVal = switcher.querySelector('#bg-density-val');
        if (densityVal) {
          if (activeKey === 'procedural_bokeh') {
            densityVal.textContent = Math.floor(BUBBLE_COUNT * densityScale);
          } else if (activeKey === 'purple_snow') {
            densityVal.textContent = Math.floor(SNOW_COUNT * densityScale);
          } else if (activeKey === 'purple_flies') {
            densityVal.textContent = Math.floor(FLIES_COUNT * densityScale);
          } else {
            densityVal.textContent = densityScale.toFixed(1) + 'x';
          }
        }
      });
    });

    // 2a. Adjust Playback Speed (Frames Per Second or Speed Multiplier)
    const fpsSlider = switcher.querySelector('#bg-fps-slider');
    const fpsVal = switcher.querySelector('#bg-fps-val');
    fpsSlider.addEventListener('input', (e) => {
      playbackSpeed = parseFloat(e.target.value);
      fpsVal.textContent = Math.round(playbackSpeed);
      localStorage.setItem('bgPlaybackSpeed', playbackSpeed);
    });

    // 2b. Adjust Density / Amount (Shows real counts: 10 to 100 for bubbles)
    const densitySlider = switcher.querySelector('#bg-density-slider');
    const densityVal = switcher.querySelector('#bg-density-val');
    densitySlider.addEventListener('input', (e) => {
      densityScale = parseFloat(e.target.value);
      if (activeKey === 'procedural_bokeh') {
        densityVal.textContent = Math.floor(BUBBLE_COUNT * densityScale);
      } else if (activeKey === 'purple_snow') {
        densityVal.textContent = Math.floor(SNOW_COUNT * densityScale);
      } else if (activeKey === 'purple_flies') {
        densityVal.textContent = Math.floor(FLIES_COUNT * densityScale);
      } else {
        densityVal.textContent = densityScale.toFixed(1) + 'x';
      }
      adjustParticleCounts();
    });

    // 2c. Adjust Glitter / Shimmer rate
    const glitterSlider = switcher.querySelector('#bg-glitter-slider');
    const glitterVal = switcher.querySelector('#bg-glitter-val');
    glitterSlider.addEventListener('input', (e) => {
      glitterModifier = parseFloat(e.target.value);
      glitterVal.textContent = glitterModifier.toFixed(1) + 'x';
    });

    // 4. Toggle Spotlight Overlay
    const spotlightToggle = switcher.querySelector('#bg-spotlight-toggle');
    if (spotlightToggle) {
      spotlightToggle.addEventListener('change', (e) => {
        spotlightGlow = e.target.checked;
        localStorage.setItem('bgSpotlightGlow', spotlightGlow);
        if (spotlightGlow) {
          document.body.classList.remove('no-spotlight');
        } else {
          document.body.classList.add('no-spotlight');
        }
      });
    }

    // 4. Disable Animation Toggle
    const disableToggle = switcher.querySelector('#bg-disable-toggle');
    const globalToggle = switcher.querySelector('#bg-global-toggle');
    const globalToggleLabel = switcher.querySelector('#bg-global-toggle-label');

    if (disableToggle) {
      disableToggle.addEventListener('change', (e) => {
        animDisabled = e.target.checked;
        localStorage.setItem('bgAnimDisabled', animDisabled);
        
        // Disable Global Animation toggle visually and functionally
        if (globalToggle && globalToggleLabel) {
          globalToggle.disabled = animDisabled;
          globalToggleLabel.style.opacity = animDisabled ? '0.4' : '1';
          globalToggleLabel.style.cursor = animDisabled ? 'not-allowed' : 'pointer';
        }

        if (animDisabled) {
          if (ctx && canvas) ctx.clearRect(0, 0, canvas.width, canvas.height);
          
          // Automatically turn off Global Animation if Disable Animation is checked
          if (allPagesAnim) {
            allPagesAnim = false;
            localStorage.setItem('bgAllPagesAnim', false);
            if (globalToggle) globalToggle.checked = false;
          }
        }
      });
    }

    // 5. Global Animation Toggle
    // globalToggle is already selected above
    if (globalToggle) {
      globalToggle.addEventListener('change', (e) => {
        allPagesAnim = e.target.checked;
        localStorage.setItem('bgAllPagesAnim', allPagesAnim);
        
        // If turned off on a non-home page, clear the canvas
        if (!isHomePage && !allPagesAnim && ctx && canvas) {
          ctx.clearRect(0, 0, canvas.width, canvas.height);
        }
      });
    }

    // 6. Minimize Widget
    const minimizeBtn = switcher.querySelector('#bg-sw-minimize');
    minimizeBtn.addEventListener('click', () => {
      switcher.classList.add('minimized');
      if (trigger) trigger.classList.remove('active');
    });

    // 6. Toggle Widget via Trigger Button
    if (trigger) {
      trigger.addEventListener('click', () => {
        if (switcher.classList.contains('minimized')) {
          switcher.classList.remove('minimized');
          trigger.classList.add('active');
        } else {
          switcher.classList.add('minimized');
          trigger.classList.remove('active');
        }
      });
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
