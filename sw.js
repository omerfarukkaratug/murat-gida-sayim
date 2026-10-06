const CACHE = 'sayim-v153';
// Barkod/QR kütüphaneleri sürüm numaralı adreslerden gelir ve hiç değişmez;
// uygulama güncellense de silinmesinler diye AYRI ve kalıcı bir önbellekte durur.
const KUTUPHANE_CACHE = 'sayim-kutuphane-v1';
const KUTUPHANE_HOST = 'cdn.jsdelivr.net';

// ZORUNLU dosyalar: bunlar inmeden kurulum tamamlanmış sayılmaz — uygulama
// internetsiz açılabilsin diye ana sayfalar da burada.
const CEKIRDEK = ['./', './index.html', './mesai.html', './etiket.html', './manifest.json'];
// İSTEĞE BAĞLI dosyalar: biri inemezse (örn. tek bir ikon) kurulum BOZULMAZ.
const ISTEGE_BAGLI = ['./icon.svg', './icon-192.png', './icon-512.png', './icon-512-maskable.png', './logo-header.png', './yerli-uretim.png'];
// Kamera kütüphaneleri: internet varken şimdiden indirilir, böylece sayım
// sırasında internet kesilse de (özellikle iPhone'da) barkod okuma çalışır.
const KUTUPHANELER = [
  'https://cdn.jsdelivr.net/npm/@undecaf/zbar-wasm@0.9.15/dist/index.js',
  'https://cdn.jsdelivr.net/npm/@undecaf/barcode-detector-polyfill@0.9.23/dist/index.js',
  'https://cdn.jsdelivr.net/npm/@zxing/library@0.20.0/umd/index.min.js',
  'https://cdn.jsdelivr.net/npm/qrcode-generator@1.4.4/qrcode.js'
];

function sakla(cacheAdi, istek, yanit) {
  // Sadece sağlam yanıtlar önbelleğe girer (hata sayfası kalıcı olmasın).
  if (!yanit || !(yanit.ok || yanit.type === 'opaque')) return;
  const kopya = yanit.clone();
  caches.open(cacheAdi).then((c) => c.put(istek, kopya)).catch(() => {});
}

self.addEventListener('install', (e) => {
  e.waitUntil((async () => {
    const c = await caches.open(CACHE);
    // cache:'reload' → tarayıcının eski HTTP önbelleğinden değil, sunucudan taze kopya.
    await c.addAll(CEKIRDEK.map((u) => new Request(u, { cache: 'reload' })));
    await Promise.all(ISTEGE_BAGLI.map((u) => c.add(u).catch(() => {})));
    const k = await caches.open(KUTUPHANE_CACHE);
    await Promise.all(KUTUPHANELER.map(async (u) => {
      try { if (!(await k.match(u))) await k.add(new Request(u, { mode: 'cors' })); } catch (err) { /* sonra, ilk kullanımda denenir */ }
    }));
  })());
  // DİKKAT: burada skipWaiting YOK. Eskiden yeni sürüm gelir gelmez devreye
  // girip sayfayı kendiliğinden yeniliyordu — sayımın ortasında ekran aniden
  // tazeleniyordu. Artık yeni sürüm BEKLER; uygulama "güncelleme hazır" der,
  // kullanıcı uygun anda "Güncelle"ye basınca (ya da uygulama tamamen kapanıp
  // açılınca) devreye girer.
});

// CACHE adındaki numara index.html'deki "build" numarasıyla AYNI tutulur:
// sayfa, bekleyen sürümün kendisiyle aynı olup olmadığını buradan öğrenir.
self.addEventListener('message', (e) => {
  if (e.data === 'SKIP_WAITING' || (e.data && e.data.type === 'SKIP_WAITING')) self.skipWaiting();
  if (e.data && e.data.type === 'SURUM' && e.ports && e.ports[0]) e.ports[0].postMessage(CACHE);
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys().then((keys) => Promise.all(keys.filter(k => k !== CACHE && k !== KUTUPHANE_CACHE).map(k => caches.delete(k))))
  );
  self.clients.claim();
});

// index.html (ve sayfa navigasyonları) için: ÖNCE İNTERNETTEN DENE (her zaman
// en güncel sürüm), sadece internet yoksa önbellekten aç. Diğer statik
// dosyalar (icon, manifest) nadiren değiştiği için önbellek-öncelikli kalır.
//
// ÖNEMLİ: Kendi sitemiz (aynı origin) ve kamera kütüphanelerinin adresi
// DIŞINDAKİ istekleri HİÇ yakalamıyoruz. Özellikle script.google.com (Apps
// Script) isteklerine dokunulmaz: Google bu isteklerde 302 ile başka bir
// adrese (googleusercontent.com) yönlendirme yapıyor; service worker bu tür
// cross-origin + redirect isteklerini respondWith içinde ele almaya çalışırsa
// istek askıda kalıp zaman aşımına uğrayabiliyor. Bu yüzden o istekler
// tamamen tarayıcının normal (service worker'sız) ağ katmanına bırakılır.
self.addEventListener('fetch', (e) => {
  if (e.request.method !== 'GET') return;
  const url = new URL(e.request.url);

  // Kamera/QR kütüphaneleri: önce önbellek, yoksa indir ve kalıcı sakla.
  if (url.hostname === KUTUPHANE_HOST) {
    e.respondWith(
      caches.open(KUTUPHANE_CACHE).then((k) => k.match(e.request.url).then((cached) => cached || fetch(e.request).then((res) => {
        sakla(KUTUPHANE_CACHE, e.request.url, res);
        return res;
      })))
    );
    return;
  }

  if (url.origin !== self.location.origin) return; // başka siteye karışma

  const isHTML = e.request.mode === 'navigate' || url.pathname.endsWith('.html') || url.pathname.endsWith('/');

  if (isHTML) {
    e.respondWith(
      fetch(e.request).then((res) => {
        sakla(CACHE, e.request, res);
        return res;
      }).catch(() => caches.match(e.request, { ignoreSearch: true }).then((c) => c || (e.request.mode === 'navigate' ? caches.match('./index.html') : undefined)))
    );
    return;
  }

  e.respondWith(
    caches.match(e.request).then((cached) => cached || fetch(e.request).then((res) => {
      sakla(CACHE, e.request, res);
      return res;
    }).catch(() => cached))
  );
});
