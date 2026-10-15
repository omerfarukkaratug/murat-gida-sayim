// =====================================================================
//  MK Sunucu — Apps Script uyumlu çalışma ortamı
// ---------------------------------------------------------------------
//  Code.gs'i DEĞİŞTİRMEDEN kendi sunucumuzda çalıştırır. Code.gs'in kullandığı
//  Google servislerinin (SpreadsheetApp, PropertiesService, CacheService,
//  LockService, Utilities, ContentService, UrlFetchApp, MailApp, DriveApp,
//  ScriptApp, Session, Logger) aynı davranan karşılıklarını verir.
//
//  • Sekmeler bellekte durur (okuma çok hızlı); her istekte DEĞİŞEN satırlar
//    istek bitince tek işlemde (transaction) veritabanına yazılır → degisiklikleriAl().
//  • Dış dünya (internet, veritabanı, e-posta, yedek dosyaları) "io" ile verilir;
//    işçi (isci.js) bunları ana iş parçacığına senkron köprüyle yaptırır,
//    testler sahte io verir.
// =====================================================================
'use strict';
const crypto = require('crypto');
const zlib = require('zlib');

// ---------------------------------------------------------------------
//  Hücre değerleri: veritabanında JSON; tarih {"$d": ms} olarak saklanır.
// ---------------------------------------------------------------------
function hucreKodla(v) {
  if (v instanceof Date) return { $d: v.getTime() };
  if (v === undefined || v === null) return '';
  if (typeof v === 'number' && !isFinite(v)) return '';
  if (typeof v === 'object') return String(v);
  return v;
}
function hucreCoz(v) {
  if (v && typeof v === 'object' && '$d' in v) return new Date(v.$d);
  return v === undefined || v === null ? '' : v;
}
function hucreKopya(v) { return v instanceof Date ? new Date(v.getTime()) : (v === undefined || v === null ? '' : v); }
function bosMu(v) { return v === '' || v === undefined || v === null; }

// ---------------------------------------------------------------------
//  Tarih biçimi (Utilities.formatDate): yyyy yy MM dd HH mm ss; saat dilimi
//  'Europe/Istanbul' ya da 'GMT+3' / 'GMT+03:00' biçiminde.
// ---------------------------------------------------------------------
function tarihParcalari(d, tz) {
  tz = String(tz || 'Europe/Istanbul');
  const m = /^(?:GMT|UTC)\s*([+-])(\d{1,2})(?::?(\d{2}))?$/.exec(tz);
  if (m) {
    const ofs = (m[1] === '-' ? -1 : 1) * (Number(m[2]) * 60 + Number(m[3] || 0));
    const t = new Date(d.getTime() + ofs * 60000);
    return { y: t.getUTCFullYear(), M: t.getUTCMonth() + 1, d: t.getUTCDate(), H: t.getUTCHours(), m: t.getUTCMinutes(), s: t.getUTCSeconds() };
  }
  if (tz === 'GMT' || tz === 'UTC') tz = 'UTC';
  const p = {};
  new Intl.DateTimeFormat('en-GB', { timeZone: tz, year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', second: '2-digit', hourCycle: 'h23' })
    .formatToParts(d).forEach((x) => { p[x.type] = x.value; });
  return { y: +p.year, M: +p.month, d: +p.day, H: +p.hour, m: +p.minute, s: +p.second };
}
function formatDate(d, tz, desen) {
  if (!(d instanceof Date) || isNaN(d)) throw new Error('Utilities.formatDate: geçersiz tarih');
  const p = tarihParcalari(d, tz), iki = (n) => (n < 10 ? '0' : '') + n;
  return String(desen).replace(/yyyy|yy|MM|dd|HH|mm|ss/g, (t) => ({
    yyyy: String(p.y), yy: String(p.y).slice(2), MM: iki(p.M), dd: iki(p.d), HH: iki(p.H), mm: iki(p.m), ss: iki(p.s)
  })[t]);
}

// Byte dizisi: Apps Script işaretli bayt (-128..127) dizisi döndürür.
const isaretli = (buf) => Array.from(buf).map((b) => (b > 127 ? b - 256 : b));
const isaretsiz = (dizi) => Buffer.from(dizi.map((x) => (x + 256) % 256));
const metinYaDaBayt = (v) => (Array.isArray(v) ? isaretsiz(v) : Buffer.from(String(v), 'utf8'));

// ---------------------------------------------------------------------
//  Blob ve zip (Utilities.newBlob / Utilities.zip): e-posta ekleri için.
// ---------------------------------------------------------------------
function blobYap(veri, tur, ad) {
  let buf = Buffer.isBuffer(veri) ? veri : metinYaDaBayt(veri);
  const b = {
    _buf: () => buf,
    getBytes: () => isaretli(buf), getDataAsString: () => buf.toString('utf8'),
    getName: () => ad || null, setName(n) { ad = n; return b; },
    getContentType: () => tur || 'application/octet-stream', setContentType(t) { tur = t; return b; },
    copyBlob: () => blobYap(Buffer.from(buf), tur, ad), getBlob: () => b
  };
  return b;
}
const CRC_TABLO = (() => { const t = []; for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; t[n] = c >>> 0; } return t; })();
function crc32(buf) { let c = 0xffffffff; for (let i = 0; i < buf.length; i++) c = CRC_TABLO[(c ^ buf[i]) & 0xff] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0; }
function zipYap(bloblar, ad) {
  const yerel = [], merkez = []; let ofs = 0;
  bloblar.forEach((b) => {
    const isim = Buffer.from(b.getName() || 'dosya', 'utf8'), ham = b._buf(), sik = zlib.deflateRawSync(ham), crc = crc32(ham);
    const h = Buffer.alloc(30); h.writeUInt32LE(0x04034b50, 0); h.writeUInt16LE(20, 4); h.writeUInt16LE(0x0800, 6); h.writeUInt16LE(8, 8);
    h.writeUInt32LE(0, 10); h.writeUInt32LE(crc, 14); h.writeUInt32LE(sik.length, 18); h.writeUInt32LE(ham.length, 22); h.writeUInt16LE(isim.length, 26); h.writeUInt16LE(0, 28);
    yerel.push(h, isim, sik);
    const m = Buffer.alloc(46); m.writeUInt32LE(0x02014b50, 0); m.writeUInt16LE(20, 4); m.writeUInt16LE(20, 6); m.writeUInt16LE(0x0800, 8); m.writeUInt16LE(8, 10);
    m.writeUInt32LE(0, 12); m.writeUInt32LE(crc, 16); m.writeUInt32LE(sik.length, 20); m.writeUInt32LE(ham.length, 24); m.writeUInt16LE(isim.length, 28);
    m.writeUInt32LE(ofs, 42); merkez.push(m, isim);
    ofs += 30 + isim.length + sik.length;
  });
  const mBuf = Buffer.concat(merkez), son = Buffer.alloc(22);
  son.writeUInt32LE(0x06054b50, 0); son.writeUInt16LE(bloblar.length, 8); son.writeUInt16LE(bloblar.length, 10); son.writeUInt32LE(mBuf.length, 12); son.writeUInt32LE(ofs, 16);
  return blobYap(Buffer.concat(yerel.concat([mBuf, son])), 'application/zip', ad || 'dosya.zip');
}

// =====================================================================
//  SEKME (Sheet) — satırlar `veri` dizisinde (1. satır = veri[0]).
// =====================================================================
function sekmeYap(defter, ad) {
  const s = {
    ad, veri: [], gizli: false, donmus: 0, maxSatir: 1000, maxSutun: 26,
    _kirli: new Set(), _hepsi: true, _kayitliUzunluk: 0, _yeni: true,
    getName: () => s.ad, getSheetName: () => s.ad,
    setName(n) { if (defter._sekmeler[n] && defter._sekmeler[n] !== s) throw new Error('Bu adla bir sekme zaten var: ' + n); delete defter._sekmeler[s.ad]; defter._silinen.add(s.ad); s.ad = n; defter._sekmeler[n] = s; defter._silinen.delete(n); s._hepsi = true; return s; },
    getParent: () => defter,
    getLastRow() { for (let i = s.veri.length - 1; i >= 0; i--) { const r = s.veri[i]; if (r && r.some((v) => !bosMu(v))) return i + 1; } return 0; },
    getLastColumn() { let m = 0; for (const r of s.veri) { if (!r) continue; for (let j = r.length - 1; j >= m; j--) if (!bosMu(r[j])) { m = j + 1; break; } } return m; },
    getMaxRows: () => Math.max(s.maxSatir, s.veri.length), getMaxColumns: () => Math.max(s.maxSutun, s.getLastColumn()),
    insertRowsAfter(after, n) {
      n = Number(n) || 0; if (n <= 0) return s;
      if (after < s.veri.length) { const bos = []; for (let i = 0; i < n; i++) bos.push([]); s.veri.splice(after, 0, ...bos); s._hepsi = true; }
      s.maxSatir = s.getMaxRows() + n; s._yapiDegisti = true; return s;
    },
    insertRows(before, n) { return s.insertRowsAfter(before - 1, n || 1); },
    insertColumnsAfter(after, n) { n = Number(n) || 0; s.veri.forEach((r) => { if (r && r.length > after) r.splice(after, 0, ...new Array(n).fill('')); }); s.maxSutun = s.getMaxColumns() + n; s._hepsi = true; return s; },
    deleteRow(n) { return s.deleteRows(n, 1); },
    deleteRows(n, k) {
      k = k || 1;
      if (n < 1 || n + k - 1 > s.getMaxRows()) throw new Error('Satır aralığı sekmenin dışında');
      if (s.getMaxRows() - k < 1 + s.donmus || (s.getMaxRows() - k < 1)) throw new Error('Sekmedeki tüm donmamış satırlar silinemez');
      s.veri.splice(n - 1, k); s.maxSatir = Math.max(1, s.getMaxRows() - k); s._hepsi = true; return s;
    },
    appendRow(r) { const i = s.getLastRow(); s.veri[i] = r.map(hucreKopya); for (let j = 0; j < i; j++) if (!s.veri[j]) s.veri[j] = []; s._kirli.add(i); return s; },
    clear() { s.veri = []; s._hepsi = true; return s; },
    clearContents() { return s.clear(); },
    setFrozenRows(n) { s.donmus = Number(n) || 0; s._yapiDegisti = true; return s; },
    getFrozenRows: () => s.donmus,
    hideSheet() { s.gizli = true; s._yapiDegisti = true; return s; }, showSheet() { s.gizli = false; s._yapiDegisti = true; return s; },
    isSheetHidden: () => s.gizli,
    copyTo(hedef) {
      let ad2 = 'Copy of ' + s.ad, i = 2; while (hedef._sekmeler[ad2]) ad2 = 'Copy of ' + s.ad + ' ' + i++;
      const y = hedef.insertSheet(ad2); y.veri = s.veri.map((r) => (r ? r.map(hucreKopya) : [])); y.donmus = s.donmus; return y;
    },
    activate() { return s; },
    getDataRange() { return s.getRange(1, 1, Math.max(1, s.getLastRow()), Math.max(1, s.getLastColumn())); },
    getRange(r, c, nr, nc) {
      if (typeof r === 'string') return a1Aralik(s, r);
      r = Number(r); c = Number(c); nr = nr === undefined ? 1 : Number(nr); nc = nc === undefined ? 1 : Number(nc);
      if (!(r >= 1) || !(c >= 1)) throw new Error('Aralık başlangıcı geçersiz (' + r + ', ' + c + ')');
      if (!(nr >= 1) || !(nc >= 1)) throw new Error('Aralıktaki satır / sütun sayısı en az 1 olmalı');
      return aralikYap(s, r, c, nr, nc);
    },
    // Ortama özel: tüm satırlar yeniden yazılacak mı / hangi satırlar değişti
    _isaretle(i) { s._kirli.add(i); }
  };
  return s;
}
function a1Aralik(s, a1) {
  const m = /^\$?([A-Z]+)\$?(\d+)(?::\$?([A-Z]+)\$?(\d+))?$/i.exec(String(a1).trim());
  if (!m) throw new Error('Desteklenmeyen aralık: ' + a1);
  const sut = (h) => h.toUpperCase().split('').reduce((t, ch) => t * 26 + ch.charCodeAt(0) - 64, 0);
  const r1 = +m[2], c1 = sut(m[1]), r2 = m[4] ? +m[4] : r1, c2 = m[3] ? sut(m[3]) : c1;
  return aralikYap(s, Math.min(r1, r2), Math.min(c1, c2), Math.abs(r2 - r1) + 1, Math.abs(c2 - c1) + 1);
}
function aralikYap(s, r, c, nr, nc) {
  const rng = {
    getRow: () => r, getColumn: () => c, getNumRows: () => nr, getNumColumns: () => nc, getLastRow: () => r + nr - 1, getLastColumn: () => c + nc - 1,
    getSheet: () => s,
    getValues() {
      const out = new Array(nr);
      for (let i = 0; i < nr; i++) {
        const row = s.veri[r - 1 + i], o = new Array(nc);
        for (let j = 0; j < nc; j++) o[j] = row ? hucreKopya(row[c - 1 + j]) : '';
        out[i] = o;
      }
      return out;
    },
    getDisplayValues() { return rng.getValues().map((row) => row.map((v) => (v instanceof Date ? formatDate(v, 'Europe/Istanbul', 'dd.MM.yyyy HH:mm:ss') : String(v)))); },
    getValue() { const row = s.veri[r - 1]; return row ? hucreKopya(row[c - 1]) : ''; },
    setValues(v) {
      if (!Array.isArray(v) || v.length !== nr || v.some((x) => !Array.isArray(x) || x.length !== nc)) {
        throw new Error('Verilerdeki satır/sütun sayısı aralıkla uyuşmuyor: veri ' + (v && v.length) + 'x' + (v && v[0] && v[0].length) + ', aralık ' + nr + 'x' + nc);
      }
      for (let i = 0; i < nr; i++) {
        const ri = r - 1 + i;
        while (s.veri.length <= ri) s.veri.push([]);
        const row = s.veri[ri] || (s.veri[ri] = []);
        while (row.length < c - 1) row.push('');
        for (let j = 0; j < nc; j++) row[c - 1 + j] = hucreKopya(v[i][j]);
        s._kirli.add(ri);
      }
      if (r + nr - 1 > s.maxSatir) s.maxSatir = r + nr - 1;
      return rng;
    },
    setValue(v) { return rng.setValues([[v]]); },
    clearContent() {
      for (let i = 0; i < nr; i++) { const ri = r - 1 + i, row = s.veri[ri]; if (!row) continue; for (let j = 0; j < nc; j++) if (c - 1 + j < row.length) row[c - 1 + j] = ''; s._kirli.add(ri); }
      return rng;
    },
    clear() { return rng.clearContent(); },
    // Biçim: değerler JS türüyle saklandığı için biçim gerekmiyor (metin metin, sayı sayı kalır).
    setNumberFormat() { return rng; }, setNumberFormats() { return rng; }, getNumberFormat: () => 'General',
    setFontWeight() { return rng; }, setBackground() { return rng; }, setFontColor() { return rng; }, setHorizontalAlignment() { return rng; }, setWrap() { return rng; },
    sort(spec) {
      const sutun = typeof spec === 'number' ? spec : (spec && spec.column) || c, artan = !(spec && spec.ascending === false);
      const v = rng.getValues(), k = sutun - c;
      v.sort((a, b) => { const x = a[k], y = b[k]; const d = x < y ? -1 : x > y ? 1 : 0; return artan ? d : -d; });
      return rng.setValues(v);
    }
  };
  return rng;
}

// =====================================================================
//  DEFTER (Spreadsheet)
// =====================================================================
function defterYap(ad) {
  const d = {
    _sekmeler: {}, _sira: [], _silinen: new Set(), _ad: ad || 'MK ERP',
    getId: () => 'mk-sunucu', getName: () => d._ad, getUrl: () => '', rename(n) { d._ad = n; },
    getSheetByName: (n) => d._sekmeler[n] || null,
    getSheets: () => d._sira.map((n) => d._sekmeler[n]).filter(Boolean),
    insertSheet(n, index) {
      if (n === undefined || typeof n === 'number') { let i = 1; while (d._sekmeler['Sayfa' + i]) i++; n = 'Sayfa' + i; }
      if (d._sekmeler[n]) throw new Error('"' + n + '" adında bir sayfa zaten var. Lütfen başka bir ad girin.');
      const s = sekmeYap(d, n); d._sekmeler[n] = s; d._silinen.delete(n);
      if (typeof index === 'number') d._sira.splice(index, 0, n); else d._sira.push(n);
      return s;
    },
    deleteSheet(s) { delete d._sekmeler[s.ad]; d._sira = d._sira.filter((x) => x !== s.ad); d._silinen.add(s.ad); },
    getActiveSheet: () => d.getSheets()[0] || d.insertSheet(),
    setActiveSheet: (s) => s,
    toast() {}, flush() {}
  };
  // setName sonrası sıra listesini düzelt
  const ilkInsert = d.insertSheet;
  d.insertSheet = function (n, i) { const s = ilkInsert(n, i); const eskiSetName = s.setName; s.setName = function (yeni) { const eski = s.ad; eskiSetName(yeni); d._sira = d._sira.map((x) => (x === eski ? yeni : x)); return s; }; return s; };
  return d;
}

// =====================================================================
//  ORTAM — tüm servisler. io: { fetch(url, opts) -> {kod, govde, basliklar},
//  eposta(m), yedekListe(klasor), yedekAl(ad, klasor), yedekSil(id), simdi() }
// =====================================================================
function ortamOlustur(io, secenek) {
  secenek = secenek || {};
  const defter = defterYap(secenek.ad);
  const ozellik = {}; const degisenOzellik = new Map();
  const onbellek = new Map(); // anahtar -> { v, bitis }
  const durum = { genelKilitDolu: false };
  const simdi = () => (io && io.simdi ? io.simdi() : Date.now());

  const props = {
    getProperty: (k) => (Object.prototype.hasOwnProperty.call(ozellik, k) ? ozellik[k] : null),
    setProperty(k, v) { ozellik[k] = String(v); degisenOzellik.set(k, ozellik[k]); return props; },
    setProperties(o, sil) { if (sil) Object.keys(ozellik).forEach((k) => { if (!(k in o)) props.deleteProperty(k); }); Object.keys(o).forEach((k) => props.setProperty(k, o[k])); return props; },
    deleteProperty(k) { delete ozellik[k]; degisenOzellik.set(k, null); return props; },
    deleteAllProperties() { Object.keys(ozellik).forEach((k) => props.deleteProperty(k)); return props; },
    getProperties: () => Object.assign({}, ozellik), getKeys: () => Object.keys(ozellik)
  };
  const cache = {
    get(k) { const x = onbellek.get(k); if (!x) return null; if (x.bitis < simdi()) { onbellek.delete(k); return null; } return x.v; },
    put(k, v, sn) { onbellek.set(k, { v: String(v), bitis: simdi() + Math.min(Number(sn) || 600, 21600) * 1000 }); },
    getAll(ks) { const o = {}; ks.forEach((k) => { const v = cache.get(k); if (v !== null) o[k] = v; }); return o; },
    putAll(o, sn) { Object.keys(o).forEach((k) => cache.put(k, o[k], sn)); },
    remove(k) { onbellek.delete(k); }, removeAll(ks) { ks.forEach((k) => onbellek.delete(k)); }
  };
  // İstekler sırayla işlendiği için kilit hep alınır; testler "dolu kilit"i durum.genelKilitDolu ile dener.
  const kilit = (genel) => {
    let var_ = false;
    return {
      waitLock() { if (genel && durum.genelKilitDolu) throw new Error('Lock timeout: another process was holding the lock for too long.'); var_ = true; },
      tryLock() { if (genel && durum.genelKilitDolu) return false; var_ = true; return true; },
      releaseLock() { var_ = false; }, hasLock: () => var_
    };
  };
  const Utilities = {
    formatDate, getUuid: () => crypto.randomUUID(),
    DigestAlgorithm: { SHA_256: 'sha256', MD5: 'md5', SHA_1: 'sha1', SHA_512: 'sha512' }, Charset: { UTF_8: 'utf8' },
    MacAlgorithm: { HMAC_SHA_256: 'sha256' },
    computeDigest: (alg, v) => isaretli(crypto.createHash(alg || 'sha256').update(metinYaDaBayt(v)).digest()),
    computeHmacSha256Signature: (v, k) => isaretli(crypto.createHmac('sha256', metinYaDaBayt(k)).update(metinYaDaBayt(v)).digest()),
    computeHmacSignature: (alg, v, k) => isaretli(crypto.createHmac(alg, metinYaDaBayt(k)).update(metinYaDaBayt(v)).digest()),
    base64Encode: (b) => metinYaDaBayt(b).toString('base64'),
    base64EncodeWebSafe: (b) => metinYaDaBayt(b).toString('base64').replace(/\+/g, '-').replace(/\//g, '_'),
    base64Decode: (s) => isaretli(Buffer.from(String(s), 'base64')),
    base64DecodeWebSafe: (s) => isaretli(Buffer.from(String(s).replace(/-/g, '+').replace(/_/g, '/'), 'base64')),
    newBlob: (veri, tur, ad) => blobYap(veri, tur, ad),
    zip: (bloblar, ad) => zipYap(bloblar, ad),
    gzip: (b, ad) => blobYap(zlib.gzipSync(b._buf()), 'application/x-gzip', ad),
    ungzip: (b) => blobYap(zlib.gunzipSync(b._buf()), 'application/octet-stream'),
    parseCsv: (s, ayr) => String(s).split(/\r?\n/).filter((x) => x !== '').map((l) => l.split(ayr || ',')),
    sleep(ms) { if (io && io.uyu) io.uyu(ms); }
  };
  function cikti(metin) { let tur = 'text/plain'; const o = { _ciktiMi: true, getContent: () => metin, setContent(m) { metin = String(m); return o; }, append(m) { metin += String(m); return o; }, setMimeType(t) { tur = t; return o; }, getMimeType: () => tur }; return o; }
  const ContentService = { createTextOutput: (t) => cikti(t === undefined ? '' : String(t)), MimeType: { JSON: 'application/json', JAVASCRIPT: 'application/javascript', TEXT: 'text/plain', CSV: 'text/csv' } };
  const HtmlService = { createHtmlOutput: (t) => cikti(String(t || '')).setMimeType('text/html') };
  const UrlFetchApp = {
    fetch(url, o) {
      o = o || {};
      if (!io || !io.fetch) throw new Error('Bu ortamda dış istek yapılamaz');
      const govde = o.payload === undefined ? undefined : (typeof o.payload === 'string' ? o.payload : (o.payload && o.payload._buf ? o.payload._buf().toString('utf8') : JSON.stringify(o.payload)));
      const basliklar = Object.assign({}, o.headers || {});
      if (o.contentType) basliklar['Content-Type'] = o.contentType;
      const c = io.fetch(String(url), { method: String(o.method || (govde !== undefined ? 'post' : 'get')).toUpperCase(), headers: basliklar, body: govde });
      if (c.hata) throw new Error('Adres alınamadı: ' + url + ' — ' + c.hata);
      if (c.kod >= 400 && o.muteHttpExceptions !== true) throw new Error('İstek başarısız oldu: ' + url + ' — kod ' + c.kod + '. Yanıt: ' + String(c.govde).slice(0, 300));
      return { getResponseCode: () => c.kod, getContentText: () => c.govde, getHeaders: () => c.basliklar || {}, getBlob: () => blobYap(c.govde, (c.basliklar || {})['content-type']) };
    },
    fetchAll(istekler) { return istekler.map((x) => UrlFetchApp.fetch(x.url, x)); }
  };
  const MailApp = {
    sendEmail(a, konu, govde, sec) {
      let m = typeof a === 'object' ? Object.assign({}, a) : Object.assign({ to: a, subject: konu, body: govde }, sec || {});
      const ekler = (m.attachments || []).map((b) => ({ ad: b.getName ? b.getName() : 'ek', tur: b.getContentType ? b.getContentType() : 'application/octet-stream', b64: b._buf ? b._buf().toString('base64') : '' }));
      if (!io || !io.eposta) throw new Error('E-posta gönderilemiyor (sunucuda e-posta ayarı yok)');
      io.eposta({ alici: String(m.to || ''), konu: String(m.subject || ''), metin: String(m.body || ''), html: m.htmlBody ? String(m.htmlBody) : '', ad: m.name || '', ekler });
    },
    getRemainingDailyQuota: () => 100
  };
  // Yedek "Drive"ı: sunucunun diskindeki yedek klasörü (io). makeCopy = veritabanının o anki tam kopyası.
  const DriveApp = (() => {
    const dosya = (x) => ({ getName: () => x.ad, getId: () => x.id, getDateCreated: () => new Date(x.zaman), getSize: () => x.boyut || 0, setTrashed(v) { if (v) io.yedekSil(x.id); return this; } });
    const klasor = (ad) => ({ getName: () => ad, getId: () => ad,
      getFiles() { const l = io && io.yedekListe ? io.yedekListe(ad) : []; let i = 0; return { hasNext: () => i < l.length, next: () => dosya(l[i++]) }; } });
    return {
      getFoldersByName(ad) { let v = true; return { hasNext: () => v, next: () => { v = false; return klasor(ad); } }; },
      createFolder: (ad) => klasor(ad),
      getFileById() { return { makeCopy(ad, k) { if (!io || !io.yedekAl) throw new Error('Yedek alınamıyor'); io.yedekAl(ad, k ? k.getName() : 'Yedekler'); } }; }
    };
  })();
  // Zamanlanmış işler: özellik deposunda; sunucu her dakika tetikleriCalistir() ile bakar.
  const TETIK = '__MK_TETIKLER';
  const tetikler = () => { try { return JSON.parse(props.getProperty(TETIK) || '[]'); } catch (e) { return []; } };
  const ScriptApp = {
    getProjectTriggers: () => tetikler().map((t) => ({ getHandlerFunction: () => t.fn, getUniqueId: () => t.id, _t: t })),
    deleteTrigger(x) { props.setProperty(TETIK, JSON.stringify(tetikler().filter((t) => t.id !== (x._t ? x._t.id : x.getUniqueId())))); },
    newTrigger(fn) {
      const t = { id: crypto.randomUUID(), fn, tur: 'gun', saat: 0, dakika: 0 };
      const b = { timeBased: () => b, everyDays(n) { t.tur = 'gun'; t.n = n || 1; return b; }, everyHours(n) { t.tur = 'saat'; t.n = n || 1; return b; },
        everyMinutes(n) { t.tur = 'dakika'; t.n = n || 1; return b; }, atHour(h) { t.saat = Number(h) || 0; return b; }, nearMinute(m) { t.dakika = Number(m) || 0; return b; },
        inTimezone() { return b; },
        create() { const l = tetikler(); l.push(t); props.setProperty(TETIK, JSON.stringify(l)); return { getHandlerFunction: () => fn, getUniqueId: () => t.id, _t: t }; } };
      return b;
    },
    getService: () => ({ getUrl: () => (secenek.adres || '') })
  };
  const Session = { getScriptTimeZone: () => 'Europe/Istanbul', getActiveUser: () => ({ getEmail: () => '' }), getEffectiveUser: () => ({ getEmail: () => '' }) };
  const gunluk = [];
  const Logger = { log() { gunluk.push(Array.from(arguments).join(' ')); if (gunluk.length > 200) gunluk.shift(); } };

  const servisler = {
    SpreadsheetApp: { getActiveSpreadsheet: () => defter, getActive: () => defter, flush() {} },
    PropertiesService: { getScriptProperties: () => props, getDocumentProperties: () => props, getUserProperties: () => props },
    CacheService: { getScriptCache: () => cache, getDocumentCache: () => cache, getUserCache: () => cache },
    LockService: { getScriptLock: () => kilit(true), getDocumentLock: () => kilit(false), getUserLock: () => kilit(false) },
    Utilities, ContentService, HtmlService, UrlFetchApp, MailApp, DriveApp, ScriptApp, Session, Logger
  };

  // ---- Kalıcılık: yükle / değişiklikleri al ----
  function yukle(veri) {
    (veri.sekmeler || []).forEach((x) => {
      const s = defter.insertSheet(x.ad);
      s.veri = (x.satirlar || []).map((r) => (Array.isArray(r) ? r.map(hucreCoz) : []));
      s.gizli = !!x.gizli; s.donmus = Number(x.donmus) || 0; s.maxSatir = Math.max(Number(x.maxSatir) || 1000, s.veri.length); s.maxSutun = Number(x.maxSutun) || 26;
      s._kirli.clear(); s._hepsi = false; s._yeni = false; s._kayitliUzunluk = s.veri.length; s._yapiDegisti = false;
    });
    Object.keys(veri.ozellikler || {}).forEach((k) => { ozellik[k] = String(veri.ozellikler[k]); });
    defter._silinen.clear(); degisenOzellik.clear();
  }
  // İstek sonunda veritabanına yazılacaklar (ve izleri sıfırlar).
  function degisiklikleriAl() {
    const sekmeler = [];
    defter._sira.forEach((ad, sira) => {
      const s = defter._sekmeler[ad]; if (!s) return;
      if (!s._hepsi && !s._kirli.size && !s._yeni && !s._yapiDegisti && s._sira === sira) return;
      const k = { ad, sira, gizli: s.gizli, donmus: s.donmus, maxSatir: s.getMaxRows(), maxSutun: s.maxSutun, uzunluk: s.veri.length };
      if (s._hepsi || s._yeni) k.hepsi = s.veri.map((r) => (r || []).map(hucreKodla));
      else { k.satirlar = []; s._kirli.forEach((i) => { if (i < s.veri.length) k.satirlar.push([i, (s.veri[i] || []).map(hucreKodla)]); }); k.eskiUzunluk = s._kayitliUzunluk; }
      sekmeler.push(k);
      s._kirli.clear(); s._hepsi = false; s._yeni = false; s._yapiDegisti = false; s._kayitliUzunluk = s.veri.length; s._sira = sira;
    });
    const silinen = Array.from(defter._silinen); defter._silinen.clear();
    const oz = {}; degisenOzellik.forEach((v, k) => { oz[k] = v; }); degisenOzellik.clear();
    return { sekmeler, silinen, ozellikler: oz, bos: !sekmeler.length && !silinen.length && !Object.keys(oz).length };
  }
  function tamKopya() {
    return { sekmeler: defter.getSheets().map((s, i) => ({ ad: s.ad, sira: i, gizli: s.gizli, donmus: s.donmus, maxSatir: s.getMaxRows(), maxSutun: s.maxSutun, satirlar: s.veri.map((r) => (r || []).map(hucreKodla)) })), ozellikler: Object.assign({}, ozellik) };
  }
  return { servisler, defter, ozellik, onbellek, durum, gunluk, yukle, degisiklikleriAl, tamKopya, TETIK };
}

module.exports = { ortamOlustur, formatDate, hucreKodla, hucreCoz };
