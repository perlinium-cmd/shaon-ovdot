// Keeps the app on the device so it opens with no signal (after a reboot, in a basement, abroad…).
// The data itself is kept by Firestore's own offline cache; this only makes sure the app can start.
//   - our files: network first (deploys show up at once), the saved copy when there's no network
//   - Firebase SDK, fonts, Excel library: versioned URLs, so the saved copy is used first
const CACHE = 'shaon-v3'; // bump when app files change together, so a device never mixes old and new files
const SDK = 'https://www.gstatic.com/firebasejs/12.19.0';
const SHELL = [
  './', 'app.js', 'data.js', 'pay.js', 'phone.js', 'firebase-config.js', 'styles.css', 'manifest.webmanifest',
  'icon.svg', 'icon-192.png', 'icon-512.png', 'apple-touch-icon.png',
];
const SDK_FILES = ['firebase-app.js', 'firebase-auth.js', 'firebase-firestore.js'].map((f) => `${SDK}/${f}`);
const PINNED_HOSTS = ['www.gstatic.com', 'fonts.googleapis.com', 'fonts.gstatic.com', 'cdnjs.cloudflare.com'];

self.addEventListener('install', (e) => {
  e.waitUntil((async () => {
    const c = await caches.open(CACHE);
    await c.addAll(SHELL);
    await Promise.all(SDK_FILES.map(async (url) => {
      try { await c.put(url, await fetch(url, { mode: 'cors' })); } catch { /* cached on first use instead */ }
    }));
    await self.skipWaiting();
  })());
});

self.addEventListener('activate', (e) => {
  e.waitUntil((async () => {
    for (const k of await caches.keys()) if (k !== CACHE) await caches.delete(k);
    await self.clients.claim();
  })());
});

/** Network, but give up after a few seconds on a bad connection and use the saved copy. */
async function networkFirst(req, cacheKey) {
  const c = await caches.open(CACHE);
  try {
    const res = await Promise.race([
      fetch(req),
      new Promise((_, rej) => setTimeout(() => rej(new Error('timeout')), 4000)),
    ]);
    if (res.ok && !res.redirected) c.put(cacheKey, res.clone());
    return res;
  } catch (err) {
    const hit = await c.match(cacheKey, { ignoreSearch: true });
    if (hit) return hit;
    throw err;
  }
}

async function cacheFirst(req) {
  const c = await caches.open(CACHE);
  const hit = await c.match(req);
  if (hit) return hit;
  const res = await fetch(req);
  if (res.ok || res.type === 'opaque') c.put(req, res.clone());
  return res;
}

self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.origin === self.location.origin) {
    if (url.pathname.startsWith('/__/')) return; // Firebase sign-in handler and config
    if (url.pathname.startsWith('/android/')) return; // phone app download: never cached, never served as the app
    if (req.mode === 'navigate') { e.respondWith(networkFirst(req, './')); return; }
    e.respondWith(networkFirst(req, url.pathname === '/' ? './' : req));
    return;
  }
  const pinned = PINNED_HOSTS.includes(url.hostname) && (url.hostname !== 'www.gstatic.com' || url.pathname.startsWith('/firebasejs/'));
  if (pinned) e.respondWith(cacheFirst(req));
  // everything else (Firestore, Google sign-in) goes straight to the network
});
