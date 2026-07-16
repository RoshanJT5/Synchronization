/**
 * Synchronization — Smart Signaling Proxy (Cloudflare Worker)
 * ============================================================
 * This Worker sits in front of the signaling server and provides automatic
 * failover between the primary GCP VM and the Render free-tier fallback.
 *
 * Flow for every request:
 *   1. Fire a lightweight GET /health to the VM (2-second timeout).
 *   2. If VM responds HTTP 200 → proxy the real request to the VM.
 *   3. If VM is offline / times out → proxy to Render instead.
 *
 * Result: The app and extension always talk to ONE stable URL (this Worker).
 * Switching between VM and Render is fully automatic — zero rebuilds needed.
 *
 * Deploy command (run from THIS directory):
 *   npx wrangler deploy
 *
 * Environment variables — set in wrangler.toml [vars] or Cloudflare dashboard:
 *   VM_URL     → GCP VM signaling server  (e.g. http://34.68.33.91:3001)
 *   RENDER_URL → Render fallback server   (e.g. https://synchronization-807q.onrender.com)
 */

'use strict';

// ── Tuning constants ──────────────────────────────────────────────────────────

/** Max ms to wait for the VM /health probe before declaring the VM down. */
const HEALTH_CHECK_TIMEOUT_MS = 2000;

/**
 * How long (ms) to trust a cached health result before re-probing.
 * 30 seconds keeps per-request overhead near zero while still detecting
 * failures quickly.
 */
const HEALTH_CACHE_TTL_MS = 30_000;

// ── In-isolate health cache ───────────────────────────────────────────────────
// Cloudflare reuses V8 isolates between requests on the same edge node, so this
// module-level variable effectively caches the health status for up to TTL ms
// without needing KV or Durable Objects.
let _cache = { isUp: null, checkedAt: 0 };

// ── Health check ──────────────────────────────────────────────────────────────

async function isVmUp(vmUrl) {
  const now = Date.now();

  // Return cached result if still fresh
  if (_cache.isUp !== null && (now - _cache.checkedAt) < HEALTH_CACHE_TTL_MS) {
    return _cache.isUp;
  }

  try {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), HEALTH_CHECK_TIMEOUT_MS);
    const res   = await fetch(`${vmUrl}/health`, { signal: controller.signal });
    clearTimeout(timer);

    const up = res.status === 200;
    _cache = { isUp: up, checkedAt: Date.now() };
    return up;
  } catch (_) {
    // Timeout, connection refused, DNS failure — VM is down
    _cache = { isUp: false, checkedAt: Date.now() };
    return false;
  }
}

// ── HTTP proxy ────────────────────────────────────────────────────────────────

async function proxyHttp(request, backendUrl) {
  const url       = new URL(request.url);
  const targetUrl = new URL(url.pathname + url.search, backendUrl);

  const headers = new Headers(request.headers);
  headers.delete('host');
  headers.set('X-Forwarded-Host', url.hostname);
  const clientIp = request.headers.get('CF-Connecting-IP');
  if (clientIp) headers.set('X-Forwarded-For', clientIp);

  const noBody = ['GET', 'HEAD', 'OPTIONS'].includes(request.method.toUpperCase());

  const backendRes = await fetch(targetUrl.toString(), {
    method:  request.method,
    headers: headers,
    body:    noBody ? null : request.body,
    redirect: 'follow',
  });

  const resHeaders = new Headers(backendRes.headers);
  resHeaders.set('Access-Control-Allow-Origin',  '*');
  resHeaders.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  resHeaders.set('Access-Control-Allow-Headers', 'Content-Type');

  return new Response(backendRes.body, {
    status:  backendRes.status,
    headers: resHeaders,
  });
}

// ── WebSocket proxy ───────────────────────────────────────────────────────────

async function proxyWebSocket(request, backendUrl) {
  const url = new URL(request.url);

  // Convert http(s) to ws(s) for the backend
  const wsBase    = backendUrl.replace(/^http(s?):\/\//, (_, s) => `ws${s}://`);
  const targetWsUrl = new URL(url.pathname + url.search, wsBase);

  // Create a client-facing WebSocket pair
  const { 0: clientWs, 1: serverWs } = new WebSocketPair();
  serverWs.accept();

  // Open backend connection
  const backendWs = new WebSocket(targetWsUrl.toString());

  // ── Bridge: client → backend ──
  serverWs.addEventListener('message', (e) => {
    if (backendWs.readyState === WebSocket.OPEN) backendWs.send(e.data);
  });
  serverWs.addEventListener('close', (e) => backendWs.close(e.code, e.reason));
  serverWs.addEventListener('error', ()  => backendWs.close(1011, 'Client error'));

  // ── Bridge: backend → client ──
  backendWs.addEventListener('message', (e) => {
    if (serverWs.readyState === WebSocket.OPEN) serverWs.send(e.data);
  });
  backendWs.addEventListener('close', (e) => serverWs.close(e.code, e.reason));
  backendWs.addEventListener('error', ()  => serverWs.close(1011, 'Backend unavailable'));

  return new Response(null, { status: 101, webSocket: clientWs });
}

// ── Worker entry point ────────────────────────────────────────────────────────

export default {
  async fetch(request, env) {
    const vmUrl     = env.VM_URL;
    const renderUrl = env.RENDER_URL;

    if (!vmUrl || !renderUrl) {
      return new Response(
        JSON.stringify({ error: 'Proxy misconfigured: VM_URL or RENDER_URL env vars not set.' }),
        { status: 500, headers: { 'Content-Type': 'application/json' } }
      );
    }

    // CORS preflight
    if (request.method === 'OPTIONS') {
      return new Response(null, {
        status: 204,
        headers: {
          'Access-Control-Allow-Origin':  '*',
          'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
          'Access-Control-Allow-Headers': 'Content-Type',
          'Access-Control-Max-Age':       '86400',
        },
      });
    }

    // Decide which backend is alive (cached for 30 s)
    const vmHealthy  = await isVmUp(vmUrl);
    const backendUrl = vmHealthy ? vmUrl : renderUrl;

    // Block robots/crawlers on the sync subdomain by responding with a plain text Robots.txt or blocking headers
    const url = new URL(request.url);
    if (url.pathname === "/robots.txt") {
      return new Response("User-agent: *\nDisallow: /", {
        status: 200,
        headers: { "Content-Type": "text/plain" }
      });
    }

    // WebSocket upgrade (Socket.IO WS transport)
    if (request.headers.get('Upgrade')?.toLowerCase() === 'websocket') {
      return proxyWebSocket(request, backendUrl);
    }

    // Ordinary HTTP (Socket.IO polling transport + /health + etc.)
    const response = await proxyHttp(request, backendUrl);
    
    // Add X-Robots-Tag to prevent indexation of any api/signaling responses
    const headers = new Headers(response.headers);
    headers.set("X-Robots-Tag", "noindex, nofollow, noarchive, nosnippet");
    
    return new Response(response.body, {
      status: response.status,
      headers: headers
    });
  },
};
