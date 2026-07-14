#!/usr/bin/env node
/**
 * Synchronization — Configuration Updater
 * =========================================
 * Reads config.json and patches every file in the project that contains a
 * hardcoded server URL or frontend domain.
 *
 * Usage:
 *   node update-config.js        ← normal run
 *   npm run configure             ← via npm script alias
 *
 * Files patched:
 *   1. web/connect/index.html                        (backend_url fallback)
 *   2. mobile/lib/config/server_config.dart          (backend_url)
 *   3. mobile/android/app/src/main/AndroidManifest.xml  (frontend_domain deep-link hosts)
 *   4. extension/src/serverConfig.ts                 (backend_url + frontend_domain)
 *   5. extension/public/manifest.json                (backend_url in host_permissions & CSP)
 *
 * NOTE: cloudflare-proxy/wrangler.toml is NOT auto-patched.
 *       VM_URL must be edited manually (it's the raw VM IP, not the proxy URL).
 */

'use strict';

const fs   = require('fs');
const path = require('path');

// ── Resolve paths relative to this script's location ──────────────────────────
const ROOT = __dirname;

function p(...parts) {
  return path.join(ROOT, ...parts);
}

// ── Load config ────────────────────────────────────────────────────────────────
const configPath = p('config.json');
if (!fs.existsSync(configPath)) {
  console.error('❌  config.json not found at project root. Aborting.');
  process.exit(1);
}

let config;
try {
  config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
} catch (e) {
  console.error('❌  Failed to parse config.json:', e.message);
  process.exit(1);
}

const { frontend_domain, backend_url } = config;

if (!frontend_domain || !backend_url) {
  console.error('❌  config.json must contain both "frontend_domain" and "backend_url".');
  process.exit(1);
}

// Derive helper values
const backendHost = backend_url.replace(/^https?:\/\//, '').replace(/\/.*$/, ''); // e.g. 34.68.33.91:3001
const backendScheme = backend_url.startsWith('https') ? 'https' : 'http';
const backendWsScheme = backendScheme === 'https' ? 'wss' : 'ws';

console.log('');
console.log('⚙️   Synchronization Config Updater');
console.log('────────────────────────────────────────');
console.log(`    frontend_domain : ${frontend_domain}`);
console.log(`    backend_url     : ${backend_url}`);
console.log('');

// ── Utility helpers ────────────────────────────────────────────────────────────

/**
 * Read a file, apply a transform function, write it back.
 * Prints a one-line status. Never throws — errors are caught and reported.
 */
function patchFile(relPath, transformFn) {
  const absPath = p(relPath);
  if (!fs.existsSync(absPath)) {
    console.warn(`⚠️   Skipped (not found): ${relPath}`);
    return;
  }
  try {
    const original = fs.readFileSync(absPath, 'utf8');
    const updated  = transformFn(original);
    if (updated === original) {
      console.log(`✅  No change needed : ${relPath}`);
    } else {
      fs.writeFileSync(absPath, updated, 'utf8');
      console.log(`✏️   Updated          : ${relPath}`);
    }
  } catch (e) {
    console.error(`❌  Error patching ${relPath}: ${e.message}`);
    process.exit(1);
  }
}

// ── 1. web/connect/index.html ─────────────────────────────────────────────────
// Targets the JS fallback line:
//   const server = params.get('server') || 'http://34.68.33.91:3001';
patchFile(
  'web/connect/index.html',
  (src) => src.replace(
    /(const server\s*=\s*params\.get\('server'\)\s*\|\|\s*')([^']+)(')/,
    `$1${backend_url}$3`
  )
);

// ── 2. mobile/lib/config/server_config.dart ───────────────────────────────────
// Targets:
//   static const String primaryServer = 'http://34.68.33.91:3001';
patchFile(
  'mobile/lib/config/server_config.dart',
  (src) => src.replace(
    /(static const String primaryServer\s*=\s*')([^']+)(')/,
    `$1${backend_url}$3`
  )
);

// ── 3. mobile/android/app/src/main/AndroidManifest.xml ───────────────────────
// Reads the current frontend_domain already in the file and replaces it with
// the new one from config.json. Works for any domain format.
patchFile(
  'mobile/android/app/src/main/AndroidManifest.xml',
  (src) => {
    // Find the current host value in use by looking at the first android:host
    // that is NOT "connect" (which is the custom-scheme host, not the web host).
    // Then do a global replace of that value with the new frontend_domain.
    const match = src.match(/android:host="([^"]+\.[^"]+)"/);
    if (!match) {
      console.warn('⚠️   AndroidManifest: could not detect current frontend host — skipping.');
      return src;
    }
    const currentHost = match[1];
    if (currentHost === frontend_domain) {
      return src; // already up to date
    }
    // Replace every occurrence of the old host inside android:host="..."
    return src.split(`android:host="${currentHost}"`).join(`android:host="${frontend_domain}"`);
  }
);

// ── 4. extension/src/serverConfig.ts ─────────────────────────────────────────
// Targets:
//   export const PRIMARY_SERVER = 'http://34.68.33.91:3001';
//   export const CONNECT_PAGE_URL = 'https://synchronization.labs5.workers.dev/c';
patchFile(
  'extension/src/serverConfig.ts',
  (src) => {
    // Patch backend URL
    let out = src.replace(
      /(export const PRIMARY_SERVER\s*=\s*')([^']+)(')/,
      `$1${backend_url}$3`
    );
    // Patch connect page URL (keep the /c path suffix)
    out = out.replace(
      /(export const CONNECT_PAGE_URL\s*=\s*')(https?:\/\/[^/']+)(\/[^']*)(')/,
      `$1https://${frontend_domain}$3$4`
    );
    return out;
  }
);

// ── 5. extension/public/manifest.json ────────────────────────────────────────
// Targets host_permissions entries and the CSP connect-src directive.
patchFile(
  'extension/public/manifest.json',
  (src) => {
    let manifest;
    try {
      manifest = JSON.parse(src);
    } catch (e) {
      console.error('❌  manifest.json is not valid JSON:', e.message);
      process.exit(1);
    }

    // Rebuild host_permissions — replace any http/ws entry with the new backend.
    // We strip the old URL entirely and rebuild from scratch using the new host.
    if (Array.isArray(manifest.host_permissions)) {
      manifest.host_permissions = manifest.host_permissions.map((perm) => {
        if (/^https?:\/\//.test(perm)) {
          // Extract path suffix after host (e.g. "/*")
          const pathSuffix = perm.replace(/^https?:\/\/[^/]+/, '') || '/*';
          return `${backendScheme}://${backendHost}${pathSuffix}`;
        }
        if (/^wss?:\/\//.test(perm)) {
          const pathSuffix = perm.replace(/^wss?:\/\/[^/]+/, '') || '/*';
          return `${backendWsScheme}://${backendHost}${pathSuffix}`;
        }
        return perm; // leave non-URL permissions untouched
      });
    }

    // Rebuild CSP connect-src — replace old host with new backend host
    if (
      manifest.content_security_policy &&
      manifest.content_security_policy.extension_pages
    ) {
      const oldCsp = manifest.content_security_policy.extension_pages;
      // Replace any http(s)://host:port or ws(s)://host:port in connect-src
      const newCsp = oldCsp
        .replace(/https?:\/\/[^\s;]+/g, `${backendScheme}://${backendHost}`)
        .replace(/wss?:\/\/[^\s;]+/g,   `${backendWsScheme}://${backendHost}`);
      manifest.content_security_policy.extension_pages = newCsp;
    }

    // Write back with 2-space indent to match original formatting
    return JSON.stringify(manifest, null, 2) + '\n';
  }
);

// ── 6. cloudflare-proxy/wrangler.toml ────────────────────────────────────────
// NOTE: wrangler.toml is intentionally NOT auto-patched.
// VM_URL must always point to the RAW GCP VM address (e.g. http://34.68.33.91:3001),
// NOT the proxy URL (backend_url). If we overwrote VM_URL with backend_url,
// the Worker would health-check itself → infinite loop → total failure.
// Edit VM_URL manually in wrangler.toml when the VM IP changes, then redeploy.

// ── Done ───────────────────────────────────────────────────────────────────────
console.log('');
console.log('🎉  All files updated. You are ready to build!');
console.log('');
console.log('Next steps:');
console.log('  • Cloudflare proxy:  cd cloudflare-proxy && npx wrangler deploy  (first-time only)');
console.log('  • Flutter (Android): cd mobile && flutter build apk --release');
console.log('  • Extension:         cd extension && npm run build');
console.log('  • Signaling server:  already live on VM — no rebuild needed');
console.log('');
