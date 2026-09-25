// Offline copy of the page, so it installs as an app (PWA). index.html registers sw.js?v=N with its
// cache buster: a new N installs a new worker, which caches that version's files and drops the old
// cache. The page itself comes from the network when there is one (it names the version).
const V = self.location.search, C = 'yaif' + V;
const FILES = ['./', 'manifest.webmanifest', 'icons/192.png', 'icons/512.png', 'icons/maskable.png',
  'fonts/atkinson.woff2', 'fonts/atkinson-mono.woff2', 'fonts/bricolage.woff2',
  'samples/photo.yaif', 'samples/screenshot.yaif', 'samples/animation.yaif',
  ...['yaif_decode.js', 'heif_meta.js', 'meta_strip.js', 'worker.js', 'enc_worker.js', 'yaif_enc.js', 'yaif_enc.wasm'].map(f => f + V)];
self.oninstall = e => e.waitUntil(caches.open(C).then(c => c.addAll(FILES)).then(() => self.skipWaiting()));
self.onactivate = e => e.waitUntil(caches.keys()
  .then(ks => Promise.all(ks.filter(k => k !== C).map(k => caches.delete(k))))
  .then(() => self.clients.claim()));
self.onfetch = e => {
  const r = e.request;
  if (r.method !== 'GET' || new URL(r.url).origin !== location.origin) return;
  if (r.mode === 'navigate') {
    e.respondWith(fetch(r).then(res => {
      const copy = res.clone();
      if (res.ok) caches.open(C).then(c => c.put('./', copy));
      return res;
    }).catch(() => caches.match('./')));
  } else e.respondWith(caches.match(r).then(m => m || fetch(r)));
};
