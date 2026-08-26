const CACHE = 'sayim-v34';
const FILES = ['./manifest.json', './icon.svg', './icon-192.png', './icon-512.png', './icon-512-maskable.png', './logo-header.png'];

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(FILES)));
  self.skipWaiting();
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys().then((keys) => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k))))
  );
  self.clients.claim();
});

// index.html (ve sayfa navigasyonları) için: ÖNCE İNTERNETTEN DENE (her zaman
// en güncel sürüm), sadece internet yoksa önbellekten aç. Diğer statik
// dosyalar (icon, manifest) nadiren değiştiği için önbellek-öncelikli kalır.
self.addEventListener('fetch', (e) => {
  const isHTML = e.request.mode === 'navigate' || e.request.url.endsWith('/index.html') || e.request.url.endsWith('/');

  if (isHTML) {
    e.respondWith(
      fetch(e.request).then((res) => {
        const copy = res.clone();
        caches.open(CACHE).then((c) => c.put(e.request, copy));
        return res;
      }).catch(() => caches.match(e.request))
    );
    return;
  }

  e.respondWith(
    caches.match(e.request).then((cached) => cached || fetch(e.request).then((res) => {
      const copy = res.clone();
      caches.open(CACHE).then((c) => c.put(e.request, copy));
      return res;
    }).catch(() => cached))
  );
});
