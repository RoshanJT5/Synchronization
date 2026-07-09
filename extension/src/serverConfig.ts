/**
 * Central server configuration for the Synchronization extension.
 *
 * The extension connects to the Cloudflare signaling proxy, which
 * automatically routes to the GCP VM (primary) or Render (fallback).
 * Nothing else in the extension should hardcode a server URL.
 */

/** Cloudflare signaling proxy — smart router between VM and Render fallback. */
export const PRIMARY_SERVER = 'https://sync.synchronizationpro.app';

/** The active signaling server URL used by the entire extension. */
export const SIGNALING_SERVER = PRIMARY_SERVER;

/** The connect page base URL (for QR code generation). */
export const CONNECT_PAGE_URL = 'https://synchronizationpro.app/c';
