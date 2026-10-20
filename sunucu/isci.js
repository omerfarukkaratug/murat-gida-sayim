// =====================================================================
//  İşçi: Code.gs burada, SIRAYLA (bir istek bitmeden diğeri başlamaz) çalışır.
//  Veri bellekte; her istekten sonra değişen satırlar ana iş parçacığına
//  "kaydet" ile gönderilir ve veritabanına YAZILMADAN cevap dönmez.
//  Dış işler (internet, veritabanı, e-posta, yedek) senkron köprüyle ana
//  iş parçacığına yaptırılır.
// =====================================================================
'use strict';
const { parentPort, workerData, receiveMessageOnPort } = require('worker_threads');
const { ortamOlustur } = require('./ortam');
const { derle } = require('./calistirici');

const port = workerData.port, sinyal = new Int32Array(workerData.sinyal);
function senkron(tur, veri) {
  Atomics.store(sinyal, 0, 0);
  port.postMessage({ tur, veri });
  while (Atomics.wait(sinyal, 0, 0, 600000) === 'timed-out') { /* uzun iş (ör. büyük yedek) — beklemeye devam */ }
  const m = receiveMessageOnPort(port);
  if (!m) throw new Error('Köprü cevabı alınamadı (' + tur + ')');
  if (m.message.hata) throw new Error(m.message.hata);
  return m.message.ok;
}

const io = {
  fetch: (url, o) => senkron('fetch', { url, o }),
  eposta: (m) => senkron('eposta', m),
  yedekListe: (k) => senkron('yedekListe', { klasor: k }),
  yedekAl: (ad, k) => senkron('yedekAl', { ad, klasor: k }),
  yedekSil: (id) => senkron('yedekSil', { id }),
  bakim: (yenile) => senkron('bakim', { yenile: !!yenile }),
  uyu: (ms) => { Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, Math.min(Number(ms) || 0, 30000)); }
};
// GÜVENLİK: veri veritabanından TAM yüklenmeden hiçbir istek çalışmaz (boş veriyle çalışıp
// veritabanındaki gerçek veriyi ezme ihtimali olmasın). Yükleme başarısızsa her istekte yeniden denenir.
let ortam = null, ornekYap = null, saglam = false;
function hazirla() {
  saglam = false;
  const yeni = ortamOlustur(io, { ad: workerData.defterAdi, adres: workerData.adres });
  yeni.yukle(senkron('yukle', {}));
  yeni.degisiklikleriAl(); // yüklemenin izleri
  ortam = yeni; saglam = true;
}
function sagla() {
  if (saglam) return;
  try { hazirla(); } catch (e) { throw new Error('Veritabanına ulaşılamıyor — birazdan tekrar dene. Kayıtların telefonda saklı. (' + e.message + ')'); }
}
ornekYap = derle(workerData.kodYolu);
try { hazirla(); } catch (e) { /* ilk istekte yeniden denenir */ }

// İstek sonu: değişenleri yaz. Yazılamazsa bellek veritabanından YENİDEN yüklenir (ikisi ayrışmasın).
function bitir() {
  const d = ortam.degisiklikleriAl();
  if (d.bos) return;
  try { senkron('kaydet', d); }
  catch (e) { saglam = false; try { hazirla(); } catch (e2) { /* sonraki istekte yeniden denenir */ } throw new Error('Veritabanına yazılamadı, işlem kaydedilmedi: ' + e.message); }
}
function cikti(o) {
  if (o && typeof o.getContent === 'function') return { govde: o.getContent(), tur: o.getMimeType ? o.getMimeType() : 'text/plain' };
  return { govde: o === undefined ? '' : String(o), tur: 'text/plain' };
}
function calistir(fn) {
  sagla();
  const bul = ornekYap(ortam.servisler);
  try { const r = fn(bul); bitir(); return r; }
  catch (e) { try { bitir(); } catch (e2) { /* asıl hata önemli */ } throw e; }
}

// Zamanlanmış işler (ScriptApp tetikleri): her dakika bakılır.
const SON = '__MK_TETIK_SON';
function tetikler(simdi) {
  const p = ortam.servisler.PropertiesService.getScriptProperties();
  let l = []; try { l = JSON.parse(p.getProperty(ortam.TETIK) || '[]'); } catch (e) { l = []; }
  if (!l.length) return [];
  let son = {}; try { son = JSON.parse(p.getProperty(SON) || '{}'); } catch (e) { son = {}; }
  const fmt = ortam.servisler.Utilities.formatDate, d = new Date(simdi), gun = fmt(d, 'Europe/Istanbul', 'yyyy-MM-dd'), saat = Number(fmt(d, 'Europe/Istanbul', 'HH'));
  const calisan = [];
  l.forEach((t) => {
    const s = son[t.id] || 0;
    let zamani = false;
    if (t.tur === 'gun') zamani = saat >= (t.saat || 0) && (!s || fmt(new Date(s), 'Europe/Istanbul', 'yyyy-MM-dd') !== gun);
    else if (t.tur === 'saat') zamani = simdi - s >= (t.n || 1) * 3600e3;
    else if (t.tur === 'dakika') zamani = simdi - s >= (t.n || 1) * 60e3;
    if (!zamani) return;
    son[t.id] = simdi; p.setProperty(SON, JSON.stringify(son));
    const bas = Date.now();
    try { calistir((bul) => bul(t.fn)()); calisan.push({ fn: t.fn, ms: Date.now() - bas }); }
    catch (e) { calisan.push({ fn: t.fn, hata: String(e && e.message || e) }); }
  });
  return calisan;
}

parentPort.on('message', (m) => {
  let cevap;
  try {
    if (m.tur === 'sekme' || m.tur === 'saat') sagla();
    if (m.tur === 'istek') {
      const r = calistir((bul) => (m.yontem === 'POST' ? bul('doPost') : bul('doGet'))(m.e));
      cevap = { ok: cikti(r) };
    } else if (m.tur === 'saat') cevap = { ok: tetikler(Date.now()) };
    else if (m.tur === 'islev') cevap = { ok: calistir((bul) => { const r = bul(m.ad).apply(null, m.args || []); return r === undefined ? null : JSON.parse(JSON.stringify(r)); }) };
    else if (m.tur === 'sekme') { const sh = ortam.defter.getSheetByName(m.ad); cevap = { ok: sh ? JSON.parse(JSON.stringify(sh.veri)) : null }; } // yalnız test modu
    else if (m.tur === 'yeniden') { ornekYap = derle(workerData.kodYolu); hazirla(); cevap = { ok: true }; }
    else cevap = { hata: 'bilinmeyen iş' };
  } catch (e) { cevap = { hata: String(e && e.stack || e) }; }
  parentPort.postMessage(Object.assign({ id: m.id }, cevap));
});
parentPort.postMessage({ hazir: true });
