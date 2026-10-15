// =====================================================================
//  MK Sunucu — ana süreç
//  • /exec        : Apps Script ile AYNI adres biçimi (GET JSONP + POST). Telefonlar ve
//                   ERP bilgisayarı yalnızca adresi değiştirerek buraya geçer.
//  • /saglik      : sunucu ayakta mı (izleme için)
//  • /            : (isteğe bağlı) uygulamanın kendisi — kendi web sitemizden yayın
//  Ayarlar: sunucu/ayar.json (örnek: ayar.ornek.json) ya da ortam değişkenleri.
// =====================================================================
'use strict';
const http = require('http');
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');
const { Worker, MessageChannel } = require('worker_threads');
const { depoOlustur } = require('./depo');

const KOK = __dirname;
function ayarOku() {
  let a = {};
  const yol = process.env.MK_AYAR || path.join(KOK, 'ayar.json');
  if (fs.existsSync(yol)) a = JSON.parse(fs.readFileSync(yol, 'utf8').replace(/^\uFEFF/, '')); // PowerShell UTF-8 BOM yazar
  return {
    port: Number(process.env.MK_PORT || a.port || 8080),
    veritabani: process.env.MK_VERITABANI || a.veritabani || 'postgres://mk:mk@localhost:5432/mkerp',
    kod: path.resolve(KOK, process.env.MK_KOD || a.kod || '../Code.gs'),
    statik: a.statik === false ? null : path.resolve(KOK, process.env.MK_STATIK || a.statik || '..'),
    yedekDizini: path.resolve(KOK, process.env.MK_YEDEK || a.yedekDizini || './yedekler'),
    adres: process.env.MK_ADRES || a.adres || '',
    smtp: a.smtp || null,
    // ERP verisi (Supabase fonksiyonları) kendi veritabanımızda: DB_URL bu önekle başlarsa RPC yerelde çalışır.
    yerelRpc: a.yerelRpc || null, // { onEk: 'http://yerel', veritabani: 'postgres://…' }
    defterAdi: a.defterAdi || 'MK ERP'
  };
}

function baslat(ayar) {
  ayar = ayar || ayarOku();
  const depo = depoOlustur(ayar.veritabani);
  const gunluk = (...x) => console.log(new Date().toISOString(), ...x);
  let isci = null, hazir = false, sira = 0;
  const bekleyen = new Map();

  // ---------------- köprü: işçinin senkron istekleri ----------------
  async function kopruIsle(m) {
    const v = m.veri;
    switch (m.tur) {
      case 'yukle': return depo.yukle();
      case 'kaydet': return depo.kaydet(v);
      case 'fetch': return disIstek(v.url, v.o);
      case 'eposta': await depo.epostaEkle(v); setImmediate(epostaGonder); return true;
      case 'yedekListe': return yedekListe(v.klasor);
      case 'yedekAl': return yedekAl(v.ad, v.klasor);
      case 'yedekSil': fs.rmSync(v.id, { force: true }); return true;
      default: throw new Error('bilinmeyen köprü işi: ' + m.tur);
    }
  }
  let rpcDepo = null;
  async function disIstek(url, o) {
    const y = ayar.yerelRpc, m = y && url.startsWith(y.onEk) ? /\/rest\/v1\/rpc\/(\w+)$/.exec(url) : null;
    if (m) {
      try {
        if (!rpcDepo) rpcDepo = y.veritabani ? depoOlustur(y.veritabani) : depo;
        const r = await rpcDepo.rpc(m[1], JSON.parse(o.body || '{}'));
        return { kod: 200, govde: JSON.stringify(r), basliklar: { 'content-type': 'application/json' } };
      } catch (e) { return { kod: 400, govde: JSON.stringify({ message: e.message, code: e.code }), basliklar: {} }; }
    }
    const ac = new AbortController(), t = setTimeout(() => ac.abort(), 60000);
    try {
      const r = await fetch(url, { method: o.method || 'GET', headers: o.headers || {}, body: o.method === 'GET' ? undefined : o.body, redirect: 'follow', signal: ac.signal });
      const basliklar = {}; r.headers.forEach((d, k) => { basliklar[k] = d; });
      return { kod: r.status, govde: await r.text(), basliklar };
    } catch (e) { return { hata: String(e && e.message || e) }; }
    finally { clearTimeout(t); }
  }

  // ---------------- yedek: veritabanının tam kopyası (sıkıştırılmış JSON) ----------------
  function klasorYolu(k) { const d = path.join(ayar.yedekDizini, String(k || 'Yedekler').replace(/[^\w .-]/g, '_')); fs.mkdirSync(d, { recursive: true }); return d; }
  function yedekListe(k) {
    const d = klasorYolu(k);
    return fs.readdirSync(d).filter((f) => f.endsWith('.json.gz')).map((f) => {
      const yol = path.join(d, f), st = fs.statSync(yol), m = /\.(\d{13})\.json\.gz$/.exec(f);
      return { id: yol, ad: f.replace(/\.\d{13}\.json\.gz$/, '').replace(/\.json\.gz$/, ''), zaman: m ? Number(m[1]) : st.mtimeMs, boyut: st.size };
    });
  }
  async function yedekAl(ad, k) {
    const veri = await depo.yukle();
    const yol = path.join(klasorYolu(k), String(ad).replace(/[\\/:*?"<>|]/g, '_') + '.' + Date.now() + '.json.gz');
    fs.writeFileSync(yol + '.tmp', zlib.gzipSync(JSON.stringify({ surum: 1, zaman: new Date().toISOString(), ...veri })));
    fs.renameSync(yol + '.tmp', yol); // yarım dosya kalmasın
    return true;
  }

  // ---------------- e-posta kuyruğu ----------------
  let epostaCalisiyor = false;
  async function epostaGonder() {
    if (epostaCalisiyor || !ayar.smtp) return;
    epostaCalisiyor = true;
    try {
      let nodemailer; try { nodemailer = require('nodemailer'); } catch (e) { gunluk('[e-posta] nodemailer kurulu değil'); return; }
      const tasiyici = nodemailer.createTransport(ayar.smtp);
      const r = await depo.havuz.query("select * from mk.eposta where durum = 'bekliyor' and deneme < 5 order by id limit 20");
      for (const m of r.rows) {
        try {
          await tasiyici.sendMail({ from: ayar.smtp.gonderen || ayar.smtp.auth && ayar.smtp.auth.user, to: m.alici, subject: m.konu, text: m.metin, html: m.html || undefined,
            attachments: (m.ekler || []).map((x) => ({ filename: x.ad, contentType: x.tur, content: Buffer.from(x.b64, 'base64') })) });
          await depo.havuz.query("update mk.eposta set durum = 'gitti' where id = $1", [m.id]);
        } catch (e) { await depo.havuz.query('update mk.eposta set deneme = deneme + 1, hata = $2 where id = $1', [m.id, String(e.message).slice(0, 500)]); }
      }
    } finally { epostaCalisiyor = false; }
  }

  // ---------------- işçi ----------------
  function isciBaslat() {
    return new Promise((coz, red) => {
      const kanal = new MessageChannel(), sab = new SharedArrayBuffer(4), sinyal = new Int32Array(sab);
      kanal.port1.on('message', async (m) => {
        let c; try { c = { ok: await kopruIsle(m) }; } catch (e) { c = { hata: String(e && e.message || e) }; }
        kanal.port1.postMessage(c); Atomics.store(sinyal, 0, 1); Atomics.notify(sinyal, 0);
      });
      const w = new Worker(path.join(KOK, 'isci.js'), { workerData: { port: kanal.port2, sinyal: sab, kodYolu: ayar.kod, defterAdi: ayar.defterAdi, adres: ayar.adres }, transferList: [kanal.port2] });
      w.on('message', (m) => {
        if (m.hazir) { isci = w; hazir = true; gunluk('[işçi] hazır'); coz(); return; }
        const b = bekleyen.get(m.id); if (!b) return; bekleyen.delete(m.id);
        if (m.hata) b.red(new Error(m.hata)); else b.coz(m.ok);
      });
      w.on('error', (e) => { gunluk('[işçi] hata:', e && e.stack || e); });
      w.on('exit', (kod) => {
        hazir = false; isci = null;
        bekleyen.forEach((b) => b.red(new Error('Sunucu yeniden başlıyor'))); bekleyen.clear();
        if (kapaniyor) return;
        gunluk('[işçi] durdu (' + kod + '), 2 sn sonra yeniden başlatılıyor');
        if (!kapaniyor) setTimeout(() => isciBaslat().catch((e) => gunluk('[işçi] başlatılamadı:', e.message)), 2000);
        red(new Error('işçi durdu'));
      });
    });
  }
  function isciye(m) {
    if (!hazir) return Promise.reject(new Error('Sunucu hazırlanıyor, birazdan tekrar dene'));
    const id = ++sira;
    return new Promise((coz, red) => { bekleyen.set(id, { coz, red }); isci.postMessage(Object.assign({ id }, m)); });
  }

  // ---------------- HTTP ----------------
  const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Methods': 'GET, POST, OPTIONS', 'Access-Control-Allow-Headers': 'Content-Type' };
  const TURLER = { '.html': 'text/html; charset=utf-8', '.js': 'application/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8', '.json': 'application/json; charset=utf-8',
    '.webmanifest': 'application/manifest+json', '.png': 'image/png', '.jpg': 'image/jpeg', '.svg': 'image/svg+xml', '.ico': 'image/x-icon', '.woff2': 'font/woff2' };
  function parametreler(u) {
    const parameter = {}, parameters = {};
    u.searchParams.forEach((v, k) => { if (!(k in parameter)) parameter[k] = v; (parameters[k] = parameters[k] || []).push(v); });
    return { parameter, parameters, queryString: u.search.replace(/^\?/, ''), contextPath: '', contentLength: -1 };
  }
  function govdeOku(req, sinir) {
    return new Promise((coz, red) => {
      const p = []; let n = 0;
      req.on('data', (c) => { n += c.length; if (n > sinir) { red(new Error('İstek çok büyük')); req.destroy(); } else p.push(c); });
      req.on('end', () => coz(Buffer.concat(p).toString('utf8'))); req.on('error', red);
    });
  }
  async function exec(req, res, u) {
    const e = parametreler(u);
    let yontem = 'GET';
    if (req.method === 'POST') {
      yontem = 'POST';
      const govde = await govdeOku(req, 60 * 1024 * 1024);
      e.postData = { contents: govde, length: Buffer.byteLength(govde), type: req.headers['content-type'] || 'text/plain', name: 'postData' };
      e.contentLength = e.postData.length;
      // Apps Script gibi: form gövdesindeki alanlar da parameter'a girer
      if (/application\/x-www-form-urlencoded/.test(e.postData.type)) new URLSearchParams(govde).forEach((v, k) => { if (!(k in e.parameter)) e.parameter[k] = v; });
    }
    const bas = Date.now();
    const r = await isciye({ tur: 'istek', yontem, e });
    const ms = Date.now() - bas;
    if (ms > 3000) gunluk('[yavaş]', yontem, e.parameter.action || e.parameter.type || '(post)', ms + ' ms');
    const tur = /javascript/.test(r.tur) ? 'application/javascript; charset=utf-8' : /json/.test(r.tur) ? 'application/json; charset=utf-8' : (r.tur || 'text/plain') + '; charset=utf-8';
    gonder(req, res, 200, Object.assign({ 'Content-Type': tur, 'Cache-Control': 'no-store' }, CORS), r.govde);
  }
  function gonder(req, res, kod, basliklar, govde) {
    let b = Buffer.isBuffer(govde) ? govde : Buffer.from(String(govde), 'utf8');
    if (b.length > 1024 && /\bgzip\b/.test(req.headers['accept-encoding'] || '')) { b = zlib.gzipSync(b); basliklar['Content-Encoding'] = 'gzip'; basliklar.Vary = 'Accept-Encoding'; }
    basliklar['Content-Length'] = b.length;
    res.writeHead(kod, basliklar); res.end(b);
  }
  function statik(req, res, u) {
    if (!ayar.statik) return gonder(req, res, 404, { 'Content-Type': 'text/plain; charset=utf-8' }, 'Bulunamadı');
    let yol = decodeURIComponent(u.pathname); if (yol.endsWith('/')) yol += 'index.html';
    const tam = path.resolve(ayar.statik, '.' + yol);
    const izinli = /\.(html|js|css|json|webmanifest|png|jpg|svg|ico|woff2)$/.test(tam) && !/[\\/](sunucu|erp|veritabani|node_modules|\.git)[\\/]/.test(tam.slice(ayar.statik.length)) && !/Code\.gs$/.test(tam);
    if (!tam.startsWith(ayar.statik + path.sep) || !izinli || !fs.existsSync(tam) || !fs.statSync(tam).isFile()) return gonder(req, res, 404, { 'Content-Type': 'text/plain; charset=utf-8' }, 'Bulunamadı');
    const ext = path.extname(tam);
    gonder(req, res, 200, { 'Content-Type': TURLER[ext] || 'application/octet-stream', 'Cache-Control': /sw\.js$|index\.html$/.test(tam) ? 'no-cache' : 'public, max-age=300' }, fs.readFileSync(tam));
  }
  const sunucu = http.createServer(async (req, res) => {
    let u; try { u = new URL(req.url, 'http://yerel'); } catch (e) { res.writeHead(400); return res.end(); }
    try {
      if (req.method === 'OPTIONS') { res.writeHead(204, CORS); return res.end(); }
      if (u.pathname === '/exec' || /\/macros\/s\/[^/]+\/exec$/.test(u.pathname)) return await exec(req, res, u);
      if (u.pathname === '/__yonetim/yeniden' && req.method === 'POST') {
        const yerel = ['127.0.0.1', '::1', '::ffff:127.0.0.1'].includes(req.socket.remoteAddress);
        if (!yerel) { res.writeHead(403); return res.end(); }
        await isciye({ tur: 'yeniden' }); return gonder(req, res, 200, { 'Content-Type': 'application/json' }, '{"status":"ok"}');
      }
      if (u.pathname === '/__yonetim/islev' && req.method === 'POST') {
        const yerel = ['127.0.0.1', '::1', '::ffff:127.0.0.1'].includes(req.socket.remoteAddress);
        if (!yerel) { res.writeHead(403); return res.end(); }
        const g = JSON.parse(await govdeOku(req, 1e6)); const r = await isciye({ tur: 'islev', ad: g.ad, args: g.args || [] });
        return gonder(req, res, 200, { 'Content-Type': 'application/json' }, JSON.stringify({ status: 'ok', sonuc: r }));
      }
      if (process.env.MK_TEST === '1' && (u.pathname === '/__durum' || u.pathname === '/__mal')) { // test araçları (gerçek kurulumda kapalı)
        const sk = async (ad) => (await isciye({ tur: 'sekme', ad })) || [];
        const g = u.pathname === '/__mal' ? (await sk('MalHareket')).slice(1) : { postSay: 0, belge: await sk('PlasiyerBelge'), tahsilat: await sk('PlasiyerTahsilat') };
        return gonder(req, res, 200, { 'Content-Type': 'application/json' }, JSON.stringify(g));
      }
      if (u.pathname === '/saglik') return gonder(req, res, hazir ? 200 : 503, Object.assign({ 'Content-Type': 'application/json' }, CORS), JSON.stringify({ durum: hazir ? 'ok' : 'hazirlaniyor', zaman: new Date().toISOString() }));
      if (req.method === 'GET') return statik(req, res, u);
      res.writeHead(405); res.end();
    } catch (e) {
      gunluk('[hata]', req.method, u.pathname, e && e.message);
      const cb = u.searchParams.get('callback'), m = JSON.stringify({ status: 'error', message: 'Sunucu hatası: ' + String(e && e.message || e).split('\n')[0] });
      if (!res.headersSent) gonder(req, res, cb ? 200 : 500, Object.assign({ 'Content-Type': cb ? 'application/javascript; charset=utf-8' : 'application/json; charset=utf-8' }, CORS), cb && /^[\w.$]+$/.test(cb) ? cb + '(' + m + ')' : m);
    }
  });

  let saat = null, kapaniyor = false;
  async function ac() {
    await new Promise((coz) => sunucu.listen(ayar.port, coz));
    gunluk('[sunucu] dinliyor: ' + ayar.port + (ayar.statik ? ' (uygulama: ' + ayar.statik + ')' : ''));
    // Bilgisayar açılırken veritabanı servisi bizden geç başlayabilir: hazır olana kadar 5 sn'de bir dene.
    for (let deneme = 1; !kapaniyor; deneme++) {
      try { await depo.kur(); break; }
      catch (e) { if (deneme === 1 || deneme % 12 === 0) gunluk('[veritabanı] bağlanılamadı, bekleniyor: ' + e.message); await new Promise((c) => setTimeout(c, 5000)); }
    }
    await isciBaslat();
    saat = setInterval(() => { if (hazir) isciye({ tur: 'saat' }).then((l) => l.forEach((x) => gunluk('[zamanlı]', x.fn, x.hata ? 'HATA: ' + x.hata : x.ms + ' ms'))).catch(() => {}); epostaGonder(); }, 30000);
    return { port: sunucu.address().port };
  }
  async function kapat() {
    kapaniyor = true; clearInterval(saat);
    await new Promise((coz) => sunucu.close(() => coz()));
    if (isci) await isci.terminate();
    await depo.kapat(); if (rpcDepo && rpcDepo !== depo) await rpcDepo.kapat();
  }
  return { ac, kapat, isciye, depo, ayar };
}

module.exports = { baslat, ayarOku };
if (require.main === module) {
  const s = baslat();
  s.ac().catch((e) => { console.error('Sunucu açılamadı:', e); process.exit(1); });
  const dur = () => s.kapat().then(() => process.exit(0), () => process.exit(1));
  process.on('SIGINT', dur); process.on('SIGTERM', dur);
}
