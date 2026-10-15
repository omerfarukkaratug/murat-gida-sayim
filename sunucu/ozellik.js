// Bir sunucu ayarını (Script Properties karşılığı) değiştirir: node ozellik.js AD "DEĞER"   (silmek için: node ozellik.js AD --sil)
// Örn. geri dönüşte telefonları Google'a yönlendirmek: node ozellik.js SUNUCU_ADRESI "https://script.google.com/macros/s/…/exec"
'use strict';
const { depoOlustur } = require('./depo');
const { ayarOku } = require('./ana');
const [ad, deger] = process.argv.slice(2);
if (!ad || deger === undefined) { console.log('Kullanım: node ozellik.js AD "DEĞER"  |  node ozellik.js AD --sil'); process.exit(2); }
(async () => {
  const ayar = ayarOku(), depo = depoOlustur(ayar.veritabani);
  try {
    if (deger === '--sil') await depo.kaydet({ ozellikler: { [ad]: null } }); else await depo.kaydet({ ozellikler: { [ad]: deger } });
    console.log('✓ ' + ad + (deger === '--sil' ? ' silindi' : ' = ' + deger));
    try { const r = await fetch('http://127.0.0.1:' + ayar.port + '/__yonetim/yeniden', { method: 'POST' }); if (r.ok) console.log('✓ Çalışan sunucu yeni ayarı aldı'); } catch (e) { /* sunucu kapalı */ }
  } finally { await depo.kapat(); }
})().catch((e) => { console.error('✗ ' + e.message); process.exit(1); });
