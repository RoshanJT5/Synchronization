/**
 * Central server configuration for the Synchronization extension.
 *
 * To switch servers, change USE_BACKUP:
 *   USE_BACKUP = false → uses the primary VM (http://34.68.33.91:3001)
 *   USE_BACKUP = true  → uses the Render backup (https://synchronization-807q.onrender.com)
 *
 * Nothing else in the extension should hardcode a server URL.
 */

/** Primary signaling server — GCP VM. */
export const PRIMARY_SERVER = 'http://34.68.33.91:3001';

/** Backup signaling server — Render cloud (used during VM maintenance). */
export const BACKUP_SERVER = 'https://synchronization-807q.onrender.com';

/** Set to true when the VM is down and Render should be used instead. */
export const USE_BACKUP = false;

/** The active signaling server URL used by the entire extension. */
export const SIGNALING_SERVER = USE_BACKUP ? BACKUP_SERVER : PRIMARY_SERVER;

/** The connect page base URL (for QR code generation). */
export const CONNECT_PAGE_URL = 'https://synchronization.labs5.workers.dev/c';
