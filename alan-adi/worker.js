// KRT Saha — Cloudflare Worker yönlendiricisi
//   krtsaha.com / www.krtsaha.com → tanıtım sitesi ve gizlilik politikası (depodaki /site klasörü)
//   app.krtsaha.com               → uygulama
// Dosyalar GitHub Pages'te durur; bu kod isteği oraya iletir.
const KAYNAK = 'https://omerfarukkaratug.github.io/murat-gida-sayim';

export default {
  async fetch(istek) {
    const u = new URL(istek.url);
    if (u.hostname === 'www.krtsaha.com') return Response.redirect('https://krtsaha.com' + u.pathname + u.search, 301);
    const site = u.hostname === 'krtsaha.com';
    if (!site && (u.pathname === '/murat-gida-sayim' || u.pathname.startsWith('/murat-gida-sayim/'))) {
      return Response.redirect(u.origin + (u.pathname.slice(17) || '/') + u.search, 301);
    }
    const kok = site ? KAYNAK + '/site' : KAYNAK;
    const hedef = kok + (u.pathname === '/' ? '/' : u.pathname) + u.search;
    const cevap = await fetch(hedef, { method: istek.method, headers: istek.headers, redirect: 'manual', cf: { cacheTtl: 0 } });
    const yeni = new Response(cevap.body, cevap);
    const yer = yeni.headers.get('Location');
    if (yer && yer.startsWith(kok)) yeni.headers.set('Location', u.origin + (yer.slice(kok.length) || '/'));
    return yeni;
  }
};
