// KRT Saha — app.krtsaha.com yönlendiricisi (Cloudflare Worker)
// Uygulama GitHub Pages'te durur; bu kod app.krtsaha.com'a gelen isteği oraya iletir.
const KAYNAK = 'https://omerfarukkaratug.github.io/murat-gida-sayim';

export default {
  async fetch(istek) {
    const u = new URL(istek.url);
    if (u.pathname === '/murat-gida-sayim' || u.pathname.startsWith('/murat-gida-sayim/')) {
      return Response.redirect(u.origin + (u.pathname.slice(17) || '/') + u.search, 301);
    }
    const hedef = KAYNAK + (u.pathname === '/' ? '/' : u.pathname) + u.search;
    const cevap = await fetch(hedef, {
      method: istek.method,
      headers: istek.headers,
      redirect: 'manual',
      cf: { cacheTtl: 0 }
    });
    const yeni = new Response(cevap.body, cevap);
    const yer = yeni.headers.get('Location');
    if (yer && yer.startsWith(KAYNAK)) yeni.headers.set('Location', u.origin + (yer.slice(KAYNAK.length) || '/'));
    return yeni;
  }
};
