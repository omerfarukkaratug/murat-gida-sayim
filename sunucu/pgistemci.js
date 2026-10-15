// =====================================================================
//  Küçük PostgreSQL istemcisi — HİÇBİR ek paket gerektirmez (sunucuya
//  "npm install" yapmak gerekmesin). PostgreSQL ağ protokolü v3:
//  • kimlik: parolasız (trust), düz parola, MD5, SCRAM-SHA-256 (PG 10+ varsayılanı)
//  • parametreli sorgu ($1, $2 …) — değerler metin olarak gider, SQL'e karışmaz
//  • basit havuz: pool.query(), pool.connect() → { query, release }, pool.end()
//  Dönen tipler: int2/4/8, float, numeric → sayı; bool; json/jsonb → nesne; diğerleri metin.
// =====================================================================
'use strict';
const net = require('net');
const crypto = require('crypto');
const { EventEmitter } = require('events');

function adresCoz(b) {
  if (typeof b !== 'string') return Object.assign({ host: 'localhost', port: 5432, user: 'postgres', database: 'postgres', password: '' }, b);
  const u = new URL(b.replace(/^(postgres(?:ql)?:\/\/[^/]*@)\//, '$1localhost/').replace(/^(postgres(?:ql)?:\/\/)\//, '$1localhost/'));
  const o = { host: decodeURIComponent(u.hostname) || 'localhost', port: Number(u.port) || 5432, user: decodeURIComponent(u.username) || 'postgres',
    password: decodeURIComponent(u.password || ''), database: decodeURIComponent(u.pathname.replace(/^\//, '')) || 'postgres' };
  const h = u.searchParams.get('host'); if (h) o.host = h; // postgres://u@/db?host=/var/run/postgresql
  const pt = u.searchParams.get('port'); if (pt) o.port = Number(pt);
  return o;
}

const OID_SAYI = new Set([20, 21, 23, 26, 700, 701, 1700]), OID_JSON = new Set([114, 3802]), OID_BOOL = 16;
function degerCoz(oid, metin) {
  if (metin === null) return null;
  if (OID_SAYI.has(oid)) { const n = Number(metin); return isFinite(n) ? n : metin; }
  if (OID_JSON.has(oid)) return JSON.parse(metin);
  if (oid === OID_BOOL) return metin === 't';
  return metin;
}
function paramMetin(v) {
  if (v === null || v === undefined) return null;
  if (v instanceof Date) return v.toISOString();
  if (typeof v === 'boolean') return v ? 'true' : 'false';
  if (typeof v === 'object') return JSON.stringify(v);
  return String(v);
}

class Baglanti extends EventEmitter {
  constructor(ayar) { super(); this.ayar = ayar; this.tampon = Buffer.alloc(0); this.sira = []; this.hazir = false; this.kapali = false; }
  ac() {
    return new Promise((coz, red) => {
      const a = this.ayar;
      const yol = a.host && a.host.startsWith('/') ? require('path').join(a.host, '.s.PGSQL.' + a.port) : null;
      this.soket = yol ? net.connect({ path: yol }) : net.connect({ host: a.host, port: a.port });
      this.soket.setNoDelay(true);
      this.acilis = { coz, red };
      this.soket.on('connect', () => this.baslangic());
      this.soket.on('data', (d) => this.veri(d));
      this.soket.on('error', (e) => this.hata(e));
      this.soket.on('close', () => this.hata(new Error('Veritabanı bağlantısı kapandı')));
    });
  }
  hata(e) {
    if (this.kapali) return; this.kapali = true;
    if (this.acilis) { const r = this.acilis.red; this.acilis = null; r(e); return; }
    const s = this.sira; this.sira = []; s.forEach((x) => x.red(e));
    if (this.listenerCount('error')) this.emit('error', e);
  }
  yaz(tur, govde) {
    const b = Buffer.alloc(5); b.write(tur, 0, 'latin1'); b.writeInt32BE(4 + govde.length, 1);
    this.soket.write(Buffer.concat([b, govde]));
  }
  baslangic() {
    const a = this.ayar, parcalar = ['user', a.user, 'database', a.database, 'client_encoding', 'UTF8', 'application_name', 'mk-sunucu'];
    const govde = Buffer.from(parcalar.join('\0') + '\0\0', 'utf8'), b = Buffer.alloc(8);
    b.writeInt32BE(8 + govde.length, 0); b.writeInt32BE(196608, 4);
    this.soket.write(Buffer.concat([b, govde]));
  }
  veri(d) {
    this.tampon = this.tampon.length ? Buffer.concat([this.tampon, d]) : d;
    while (this.tampon.length >= 5) {
      const uz = this.tampon.readInt32BE(1);
      if (this.tampon.length < 1 + uz) break;
      const tur = String.fromCharCode(this.tampon[0]), govde = this.tampon.subarray(5, 1 + uz);
      this.tampon = this.tampon.subarray(1 + uz);
      try { this.mesaj(tur, govde); } catch (e) { this.hata(e); return; }
    }
  }
  kimlik(govde) {
    const kod = govde.readInt32BE(0), a = this.ayar;
    if (kod === 0) return;
    if (kod === 3) return this.yaz('p', Buffer.from(String(a.password) + '\0', 'utf8'));
    if (kod === 5) {
      const tuz = govde.subarray(4, 8), ic = crypto.createHash('md5').update(String(a.password) + a.user).digest('hex');
      return this.yaz('p', Buffer.from('md5' + crypto.createHash('md5').update(Buffer.concat([Buffer.from(ic), tuz])).digest('hex') + '\0'));
    }
    if (kod === 10) {
      if (!govde.subarray(4).toString().split('\0').includes('SCRAM-SHA-256')) throw new Error('Desteklenmeyen kimlik yöntemi');
      this.scram = { nonce: crypto.randomBytes(18).toString('base64') };
      this.scram.ilk = 'n=*,r=' + this.scram.nonce;
      const ilk = Buffer.from('n,,' + this.scram.ilk), mek = Buffer.from('SCRAM-SHA-256\0'), u = Buffer.alloc(4); u.writeInt32BE(ilk.length);
      return this.yaz('p', Buffer.concat([mek, u, ilk]));
    }
    if (kod === 11) {
      const sunucuIlk = govde.subarray(4).toString(), p = {};
      sunucuIlk.split(',').forEach((x) => { p[x[0]] = x.slice(2); });
      if (!p.r || !p.r.startsWith(this.scram.nonce)) throw new Error('SCRAM: sunucu cevabı geçersiz');
      const tuzlu = crypto.pbkdf2Sync(String(a.password).normalize('NFKC'), Buffer.from(p.s, 'base64'), Number(p.i), 32, 'sha256');
      const istemciAnahtar = crypto.createHmac('sha256', tuzlu).update('Client Key').digest();
      const saklanan = crypto.createHash('sha256').update(istemciAnahtar).digest();
      const sonsuz = 'c=biws,r=' + p.r, mesaj = this.scram.ilk + ',' + sunucuIlk + ',' + sonsuz;
      const imza = crypto.createHmac('sha256', saklanan).update(mesaj).digest();
      const kanit = Buffer.from(istemciAnahtar.map((b, i) => b ^ imza[i]));
      const sunucuAnahtar = crypto.createHmac('sha256', tuzlu).update('Server Key').digest();
      this.scram.bekSunucuImza = crypto.createHmac('sha256', sunucuAnahtar).update(mesaj).digest('base64');
      return this.yaz('p', Buffer.from(sonsuz + ',p=' + kanit.toString('base64')));
    }
    if (kod === 12) {
      const v = /v=([^,]+)/.exec(govde.subarray(4).toString());
      if (!v || v[1] !== this.scram.bekSunucuImza) throw new Error('SCRAM: sunucu doğrulanamadı');
      return;
    }
    throw new Error('Desteklenmeyen kimlik doğrulama (' + kod + ')');
  }
  mesaj(tur, g) {
    const is = this.sira[0];
    switch (tur) {
      case 'R': return this.kimlik(g);
      case 'S': case 'K': case 'N': case 't': case '1': case '2': case 'n': case 's': return;
      case 'Z':
        if (this.acilis) { const c = this.acilis.coz; this.acilis = null; this.hazir = true; return c(this); }
        if (is) { this.sira.shift(); if (is.hataNesne) is.red(is.hataNesne); else is.coz({ rows: is.satirlar, rowCount: is.adet, command: is.komut }); }
        return;
      case 'T': {
        const n = g.readInt16BE(0); let o = 2; is.alanlar = [];
        for (let i = 0; i < n; i++) { const son = g.indexOf(0, o); const ad = g.toString('utf8', o, son); o = son + 1; const oid = g.readInt32BE(o + 6); o += 18; is.alanlar.push({ ad, oid }); }
        return;
      }
      case 'D': {
        const n = g.readInt16BE(0); let o = 2; const satir = {};
        for (let i = 0; i < n; i++) {
          const uz = g.readInt32BE(o); o += 4;
          const m = uz < 0 ? null : g.toString('utf8', o, o + uz); if (uz > 0) o += uz;
          const al = is.alanlar[i]; satir[al.ad] = degerCoz(al.oid, m);
        }
        is.satirlar.push(satir); return;
      }
      case 'C': { const k = g.toString('utf8', 0, g.length - 1); is.komut = k.split(' ')[0]; const n = Number(k.split(' ').pop()); is.adet = isFinite(n) ? n : 0; return; }
      case 'I': return;
      case 'E': {
        const alan = {}; let o = 0;
        while (o < g.length && g[o] !== 0) { const t = String.fromCharCode(g[o]); const son = g.indexOf(0, o + 1); alan[t] = g.toString('utf8', o + 1, son); o = son + 1; }
        const e = new Error(alan.M || 'Veritabanı hatası'); e.code = alan.C; e.detail = alan.D; e.position = alan.P;
        if (this.acilis) { const r = this.acilis.red; this.acilis = null; r(e); return; }
        if (is) is.hataNesne = is.hataNesne || e;
        return;
      }
      default: return;
    }
  }
  query(metin, params) {
    if (this.kapali) return Promise.reject(new Error('Veritabanı bağlantısı kapalı'));
    return new Promise((coz, red) => {
      this.sira.push({ coz, red, satirlar: [], alanlar: [], adet: 0 });
      // Parametresiz: basit sorgu (birden çok komut ; ile ayrılabilir — şema kurulumu gibi)
      if (params === undefined) { this.yaz('Q', Buffer.from(metin + '\0', 'utf8')); return; }
      const p = params.map(paramMetin);
      const parca = [];
      const q = Buffer.from('\0' + metin + '\0', 'utf8'), sifir = Buffer.alloc(2);
      parca.push(['P', Buffer.concat([q, sifir])]);
      const bb = [Buffer.from('\0\0'), Buffer.from([0, 0])], n = Buffer.alloc(2); n.writeInt16BE(p.length); bb.push(n);
      p.forEach((v) => { const u = Buffer.alloc(4); if (v === null) { u.writeInt32BE(-1); bb.push(u); } else { const vb = Buffer.from(v, 'utf8'); u.writeInt32BE(vb.length); bb.push(u, vb); } });
      bb.push(Buffer.from([0, 0]));
      parca.push(['B', Buffer.concat(bb)], ['D', Buffer.from('P\0')], ['E', Buffer.from([0, 0, 0, 0, 0])], ['S', Buffer.alloc(0)]);
      parca.forEach(([t, g]) => this.yaz(t, g));
    });
  }
  kapat() { if (!this.kapali) { this.kapali = true; try { this.yaz('X', Buffer.alloc(0)); this.soket.end(); } catch (e) { /* yok */ } } }
}

class Pool extends EventEmitter {
  constructor(ayar) { super(); this.ayar = adresCoz(ayar.connectionString || ayar); this.max = (ayar && ayar.max) || 4; this.bos = []; this.tum = new Set(); this.bekleyen = []; this.bitti = false; }
  async connect() {
    if (this.bitti) throw new Error('Havuz kapatıldı');
    let b = this.bos.pop();
    while (b && b.kapali) b = this.bos.pop();
    if (!b) {
      if (this.tum.size >= this.max) return new Promise((coz, red) => this.bekleyen.push({ coz, red }));
      b = new Baglanti(this.ayar);
      b.on('error', (e) => { this.tum.delete(b); this.bos = this.bos.filter((x) => x !== b); if (this.listenerCount('error')) this.emit('error', e); });
      this.tum.add(b);
      try { await b.ac(); } catch (e) { this.tum.delete(b); throw e; }
    }
    return this.istemci(b);
  }
  istemci(b) {
    let birakildi = false;
    return { query: (m, p) => b.query(m, p), release: () => {
      if (birakildi) return; birakildi = true;
      const w = this.bekleyen.shift();
      if (w) { if (b.kapali) this.connect().then(w.coz, w.red); else w.coz(this.istemci(b)); return; }
      if (!b.kapali) this.bos.push(b);
    } };
  }
  async query(m, p) { const c = await this.connect(); try { return await c.query(m, p); } finally { c.release(); } }
  async end() { this.bitti = true; this.tum.forEach((b) => b.kapat()); this.tum.clear(); this.bos = []; }
}
module.exports = { Pool, adresCoz };
