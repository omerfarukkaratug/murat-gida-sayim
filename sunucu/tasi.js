// =====================================================================
//  TAŞIMA: Google Tablo + Apps Script → kendi sunucumuz (PostgreSQL)
//  Kullanım (sunucuda, MK Sunucu klasöründe):
//    node tasi.js --kaynak "https://script.google.com/macros/s/…/exec" --kullanici admin --sifre "…" --adres "https://erp.ornek.com" [--deneme]
//  --deneme : Google'ı kilitlemeden / yönlendirmeden yalnızca KOPYALAR (provası). Telefonlar Google'da kalır.
//  Sıra: kilit (Google yazmayı durdurur) → tüm sekmeler + ayarlar okunur → veritabanına tek işlemde yazılır →
//  okunan ile yazılan sayılır/karşılaştırılır → Google, istekleri bize aktarmaya başlar. Hata olursa kilit kalkar.
// =====================================================================
'use strict';
const crypto = require('crypto');
const { depoOlustur } = require('./depo');
const { ayarOku } = require('./ana');

function arg(ad, vars) { const i = process.argv.indexOf('--' + ad); return i < 0 ? vars : (process.argv[i + 1] && !process.argv[i + 1].startsWith('--') ? process.argv[i + 1] : true); }
const KAYNAK = arg('kaynak'), KUL = arg('kullanici'), SIFRE = arg('sifre'), ADRES = String(arg('adres', '') || '').replace(/\/+$/, ''), DENEME = !!arg('deneme', false);
const yaz = (...x) => console.log(...x);
if (!KAYNAK || !KUL || !SIFRE || (!DENEME && !/^https:\/\//.test(ADRES))) {
  yaz('Kullanım: node tasi.js --kaynak <Apps Script /exec adresi> --kullanici <yönetici> --sifre <şifre> --adres <https://yeni-sunucu> [--deneme]'); process.exit(2);
}
async function iste(p) {
  const u = new URL(KAYNAK); Object.entries(Object.assign({ action: 'tasima', user: KUL, pass: SIFRE }, p)).forEach(([k, v]) => u.searchParams.set(k, v));
  for (let deneme = 1; ; deneme++) {
    try {
      const r = await fetch(u, { redirect: 'follow' }); const m = await r.text();
      let j; try { j = JSON.parse(m); } catch (e) { throw new Error('Cevap okunamadı (Code.gs build189 kurulu mu?): ' + m.slice(0, 200)); }
      if (j.status !== 'ok') throw Object.assign(new Error(j.message || 'hata'), { kalici: true });
      return j;
    } catch (e) { if (e.kalici || deneme >= 4) throw e; yaz('  … tekrar deneniyor (' + e.message + ')'); await new Promise((c) => setTimeout(c, 3000 * deneme)); }
  }
}
const ozet = (satirlar) => crypto.createHash('sha256').update(JSON.stringify(satirlar)).digest('hex').slice(0, 16);
const sonBos = (r) => { const x = r.slice(); while (x.length && (x[x.length - 1] === '' || x[x.length - 1] === null)) x.pop(); return x; };

(async () => {
  const ayar = ayarOku(), depo = depoOlustur(ayar.veritabani);
  await depo.kur();
  let kilitli = false;
  try {
    let l = await iste({ ne: 'liste' });
    yaz('Kaynak: Code.gs ' + l.surum + ', ' + l.sekmeler.length + ' sekme');
    if (l.yeni) throw new Error('Bu Google sunucusu zaten ' + l.yeni + ' adresine taşınmış. Geri almak için: ne=geri');
    const mevcut = await depo.yukle();
    if (mevcut.sekmeler.length) {
      const yol = require('path').join(ayar.yedekDizini, 'tasima-oncesi-' + Date.now() + '.json.gz');
      require('fs').mkdirSync(ayar.yedekDizini, { recursive: true });
      require('fs').writeFileSync(yol, require('zlib').gzipSync(JSON.stringify(mevcut)));
      yaz('Veritabanında önceki veri vardı → yedeklendi: ' + yol);
    }
    if (!DENEME) { await iste({ ne: 'kilit', deger: '1' }); kilitli = true; yaz('Google sunucusu kilitlendi (yazma durdu). 20 sn bekleniyor (yarım kalan istekler bitsin)…'); await new Promise((c) => setTimeout(c, 20000)); l = await iste({ ne: 'liste' }); }
    const veri = { sekmeler: [], ozellikler: {} };
    for (const s of l.sekmeler) {
      const satirlar = [];
      for (let bas = 1; bas <= s.satir; bas += 3000) { const p = await iste({ ne: 'sekme', ad: s.ad, bas, adet: 3000 }); p.satirlar.forEach((r) => satirlar.push(sonBos(r))); }
      veri.sekmeler.push({ ad: s.ad, sira: s.sira, gizli: s.gizli, donmus: s.donmus, maxSatir: s.maxSatir, maxSutun: s.maxSutun, satirlar });
      yaz('  ' + s.ad.padEnd(34) + String(satirlar.length).padStart(7) + ' satır');
    }
    Object.entries(l.ozellikler).forEach(([k, v]) => { if (!/^(YENI_SUNUCU|TASIMA_KILIDI|SUNUCU_ADRESI)$/.test(k)) veri.ozellikler[k] = v; });
    if (ADRES) veri.ozellikler.SUNUCU_ADRESI = ADRES + '/exec';
    yaz(Object.keys(veri.ozellikler).length + ' ayar (kullanıcı şifreleri özet hâlinde sekmede, oturum sırrı ve ERP anahtarı ayarlarda)');
    await depo.tamYaz(veri);
    // Doğrulama: yazılanı geri oku, her sekmeyi karşılaştır
    const geri = await depo.yukle(); const gh = {}; geri.sekmeler.forEach((s) => { gh[s.ad] = s; });
    let fark = 0;
    veri.sekmeler.forEach((s) => { const g = gh[s.ad]; if (!g || g.satirlar.length !== s.satirlar.length || ozet(g.satirlar.map(sonBos)) !== ozet(s.satirlar)) { fark++; yaz('  ✗ FARK: ' + s.ad); } });
    if (fark || Object.keys(geri.ozellikler).length !== Object.keys(veri.ozellikler).length) throw new Error(fark + ' sekmede fark var — taşıma tamamlanmadı');
    yaz('✓ Doğrulandı: tüm sekmeler birebir aynı');
    try { const r = await fetch('http://127.0.0.1:' + ayar.port + '/__yonetim/yeniden', { method: 'POST' }); if (r.ok) yaz('✓ Çalışan sunucu yeni veriyi yükledi'); } catch (e) { yaz('(Sunucu şu an çalışmıyor — başlatınca yeni veriyle açılır)'); }
    if (!DENEME) { await iste({ ne: 'bitir', adres: ADRES }); kilitli = false; yaz('✓ TAŞINDI. Google sunucusu artık tüm istekleri ' + ADRES + ' adresine aktarıyor; telefonlar kendiliğinden geçecek.'); }
    else yaz('(Deneme: Google kilitlenmedi ve yönlendirilmedi — gerçek taşıma için --deneme olmadan çalıştır)');
  } catch (e) {
    yaz('✗ HATA: ' + e.message);
    if (kilitli) { try { await iste({ ne: 'kilit', deger: '0' }); yaz('Google sunucusunun kilidi kaldırıldı — eskisi gibi çalışıyor.'); } catch (e2) { yaz('!! Kilit kaldırılamadı: ' + e2.message + ' — elle: ?action=tasima&ne=kilit&deger=0'); } }
    process.exitCode = 1;
  } finally { await depo.kapat(); }
})();
