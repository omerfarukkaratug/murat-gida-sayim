// =====================================================================
//  YEDEKTEN GERİ YÜKLE: node geri-yukle.js "<yedek dosyası .json.gz>" --evet
//  Önce şu anki veri ayrıca yedeklenir (geri-yukleme-oncesi-….json.gz), sonra seçilen yedek
//  tek işlemde yazılır ve çalışan sunucu yeni veriyi yükler.
// =====================================================================
'use strict';
const fs = require('fs'), path = require('path'), zlib = require('zlib');
const { depoOlustur } = require('./depo');
const { ayarOku } = require('./ana');
const dosya = process.argv[2];
if (!dosya || !fs.existsSync(dosya)) { console.log('Kullanım: node geri-yukle.js "<yedek.json.gz>" --evet'); process.exit(2); }
(async () => {
  const veri = JSON.parse(zlib.gunzipSync(fs.readFileSync(dosya)).toString('utf8'));
  if (!Array.isArray(veri.sekmeler) || !veri.ozellikler) throw new Error('Bu bir MK Sunucu yedeği değil');
  console.log('Yedek: ' + (veri.zaman || '?') + ', ' + veri.sekmeler.length + ' sekme:');
  veri.sekmeler.forEach((s) => console.log('  ' + s.ad.padEnd(34) + String(s.satirlar.length).padStart(7) + ' satır'));
  if (!process.argv.includes('--evet')) { console.log('\nŞu anki veri BU YEDEKLE DEĞİŞECEK. Emin isen sonuna --evet ekleyip tekrar çalıştır.'); return; }
  const ayar = ayarOku(), depo = depoOlustur(ayar.veritabani);
  try {
    await depo.kur();
    const simdiki = await depo.yukle();
    fs.mkdirSync(ayar.yedekDizini, { recursive: true });
    const onceki = path.join(ayar.yedekDizini, 'geri-yukleme-oncesi-' + Date.now() + '.json.gz');
    fs.writeFileSync(onceki, zlib.gzipSync(JSON.stringify(Object.assign({ surum: 1, zaman: new Date().toISOString() }, simdiki))));
    console.log('Şu anki veri yedeklendi: ' + onceki);
    veri.sekmeler.forEach((s, i) => { if (s.sira === undefined) s.sira = i; s.satirlar = s.satirlar.map((r) => (Array.isArray(r) ? r : [])); });
    await depo.tamYaz(veri);
    console.log('✓ Geri yüklendi');
    try { const r = await fetch('http://127.0.0.1:' + ayar.port + '/__yonetim/yeniden', { method: 'POST' }); if (r.ok) console.log('✓ Çalışan sunucu yeni veriyi yükledi'); } catch (e) { console.log('(Sunucu çalışmıyor — başlatınca yedekteki veriyle açılır)'); }
  } finally { await depo.kapat(); }
})().catch((e) => { console.error('✗ ' + e.message); process.exit(1); });
