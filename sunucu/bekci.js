'use strict';
// =====================================================================
//  Bekçi: sunucunun ve süresi dolan işlerin günlük kontrolü.
//   • krtsaha.com alan adının bitiş tarihi (internetten, RDAP ile kendisi öğrenir)
//   • Yöneticinin panelden girdiği tarihler (kart son kullanma, Play yıllık güncelleme…)
//   • Disk doluluğu, gece veritabanı yedeği, ERP verisinin ne zaman geldiği
//  Sorun varsa günde bir kez (sabah 08:00'den sonra) uyarı e-postası gönderir.
//  Sonuç yönetici panelinde "Sunucu ve süreler" bölümünde görünür (köprü: 'bakim').
// =====================================================================
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

const GUN = 86400000;
function gunFarki(t) { return Math.ceil((new Date(t).getTime() - Date.now()) / GUN); }
function trTarih(t) { const d = new Date(t); return isNaN(d) ? String(t) : d.toLocaleDateString('tr-TR', { timeZone: 'Europe/Istanbul' }); }
function saatMetni(ms) { const s = Math.round(ms / 3600000); return s < 48 ? s + ' saat' : Math.round(s / 24) + ' gün'; }

function bekciOlustur({ ayar, depo, gunluk, epostaGonder, disIstek }) {
  const alanAdi = ayar.alanAdi || 'krtsaha.com';
  const alici = ayar.bekciAlici || 'muratgida_avm@hotmail.com';
  const pgYedek = ayar.pgYedekDizini || '/var/lib/krtsaha/pg';
  let son = null, calisiyor = false, alanOnbellek = null;

  async function ozellik(ad) {
    try { const r = await depo.havuz.query('select deger from mk.ozellik where anahtar = $1', [ad]); return r.rows.length ? r.rows[0].deger : null; } catch (e) { return null; }
  }
  async function kayitOku(ad) {
    await depo.havuz.query('create table if not exists mk.bekci (anahtar text primary key, deger text not null)');
    const r = await depo.havuz.query('select deger from mk.bekci where anahtar = $1', [ad]); return r.rows.length ? r.rows[0].deger : null;
  }
  async function kayitYaz(ad, d) {
    await depo.havuz.query('insert into mk.bekci (anahtar, deger) values ($1, $2) on conflict (anahtar) do update set deger = excluded.deger', [ad, String(d)]);
  }
  async function getir(url, govde, basliklar) {
    const ac = new AbortController(), t = setTimeout(() => ac.abort(), 20000);
    try {
      const r = await fetch(url, { method: govde ? 'POST' : 'GET', headers: Object.assign({ 'Content-Type': 'application/json', Accept: 'application/json, application/rdap+json' }, basliklar || {}), body: govde ? JSON.stringify(govde) : undefined, signal: ac.signal });
      if (!r.ok) throw new Error('HTTP ' + r.status);
      return await r.json();
    } finally { clearTimeout(t); }
  }
  function madde(ad, kalanGun, metin, sinirUyari, sinirAcil) {
    const durum = kalanGun === null ? 'bilinmiyor' : kalanGun <= sinirAcil ? 'acil' : kalanGun <= sinirUyari ? 'uyari' : 'ok';
    return { ad, durum, metin };
  }

  async function alanAdiKontrol() {
    // Günde bir kez sorulur (RDAP sunucusu yormasın).
    if (!alanOnbellek || Date.now() - alanOnbellek.zaman > 12 * 3600000) {
      try {
        const j = await getir('https://rdap.verisign.com/com/v1/domain/' + alanAdi);
        const e = (j.events || []).find((x) => x.eventAction === 'expiration');
        alanOnbellek = { zaman: Date.now(), bitis: e ? e.eventDate : null, hata: e ? '' : 'bitiş tarihi bulunamadı' };
      } catch (e) { alanOnbellek = { zaman: Date.now() - 11 * 3600000, bitis: alanOnbellek && alanOnbellek.bitis, hata: e.message }; }
    }
    if (!alanOnbellek.bitis) return { ad: 'Alan adı (' + alanAdi + ')', durum: 'bilinmiyor', metin: 'Bitiş tarihi öğrenilemedi: ' + alanOnbellek.hata };
    const k = gunFarki(alanOnbellek.bitis);
    return madde('Alan adı (' + alanAdi + ')', k, trTarih(alanOnbellek.bitis) + ' tarihinde bitiyor (' + k + ' gün kaldı). Natro\'dan yenile.', 30, 7);
  }

  async function surelerKontrol() {
    let liste = [];
    try { liste = JSON.parse((await ozellik('SURELER')) || '[]'); } catch (e) { liste = []; }
    return (Array.isArray(liste) ? liste : []).filter((x) => x && x.ad && x.tarih).map((x) => {
      const k = gunFarki(x.tarih);
      return madde(String(x.ad), isNaN(k) ? null : k, trTarih(x.tarih) + (k < 0 ? ' — ' + (-k) + ' gün GEÇTİ' : ' — ' + k + ' gün kaldı') + (x.not ? '. ' + x.not : ''), 30, 7);
    });
  }

  function diskKontrol() {
    try {
      const s = fs.statfsSync('/'), bos = s.bavail * s.bsize, top = s.blocks * s.bsize, oran = bos / top;
      const durum = oran < 0.07 ? 'acil' : oran < 0.15 ? 'uyari' : 'ok';
      return { ad: 'Sunucu diski', durum, metin: '%' + Math.round(oran * 100) + ' boş (' + (bos / 1e9).toFixed(1) + ' GB / ' + (top / 1e9).toFixed(1) + ' GB)' };
    } catch (e) { return { ad: 'Sunucu diski', durum: 'bilinmiyor', metin: e.message }; }
  }

  function yedekKontrol() {
    try {
      if (!fs.existsSync(pgYedek)) return { ad: 'Gece veritabanı yedeği', durum: 'bilinmiyor', metin: 'Yedek klasörü yok (' + pgYedek + ')' };
      const d = fs.readdirSync(pgYedek).filter((f) => /^mkerp-.*\.dump$/.test(f)).map((f) => ({ f, st: fs.statSync(path.join(pgYedek, f)) })).filter((x) => x.st.isFile()).sort((a, b) => b.st.mtimeMs - a.st.mtimeMs);
      if (!d.length) return { ad: 'Gece veritabanı yedeği', durum: 'acil', metin: 'Hiç yedek yok' };
      const yas = Date.now() - d[0].st.mtimeMs;
      return { ad: 'Gece veritabanı yedeği', durum: yas > 50 * 3600000 ? 'acil' : yas > 30 * 3600000 ? 'uyari' : 'ok',
        metin: 'Son yedek ' + saatMetni(yas) + ' önce (' + (d[0].st.size / 1e6).toFixed(1) + ' MB, ' + d.length + ' yedek saklı)' };
    } catch (e) { return { ad: 'Gece veritabanı yedeği', durum: 'bilinmiyor', metin: e.message }; }
  }

  async function erpKontrol() {
    const url = String((await ozellik('DB_URL')) || '').trim().replace(/\/+$/, ''), anahtar = String((await ozellik('DB_ANAHTAR')) || '').trim();
    if (!url || !anahtar) return { ad: 'ERP verisi', durum: 'bilinmiyor', metin: 'Veri tabanı ayarı yok' };
    try {
      // Sunucunun kendi dış istek yolu (ERP verisi yerel veritabanındaysa orada çalışır).
      const c = await disIstek(url + '/rest/v1/rpc/stok_hareket', { method: 'POST', headers: { 'Content-Type': 'application/json', apikey: anahtar },
        body: JSON.stringify({ p_stok_kodu: '', p_barkod: '__bekci__', p_gun: 1, p_limit: 1 }) });
      if (c.hata || c.kod >= 400) throw new Error(c.hata || ('HTTP ' + c.kod));
      const j = JSON.parse(c.govde || 'null');
      const m = /^(\d\d)\.(\d\d)\.(\d{4}) (\d\d):(\d\d)$/.exec(String(j && j.sonVeri || ''));
      if (!m) return { ad: 'ERP verisi', durum: 'bilinmiyor', metin: 'Son veri zamanı okunamadı' };
      const t = new Date(m[3] + '-' + m[2] + '-' + m[1] + 'T' + m[4] + ':' + m[5] + ':00+03:00'), yas = Date.now() - t.getTime();
      return { ad: 'ERP verisi', durum: yas > 72 * 3600000 ? 'acil' : yas > 26 * 3600000 ? 'uyari' : 'ok',
        metin: 'Son veri ' + saatMetni(yas) + ' önce geldi' + (yas > 26 * 3600000 ? ' — ERP bilgisayarı ya da gönderim görevi çalışmıyor olabilir' : '') };
    } catch (e) { return { ad: 'ERP verisi', durum: 'acil', metin: 'Veri tabanına ulaşılamadı: ' + e.message }; }
  }

  // ---- ERP veri tabanı (Supabase) fonksiyonu çağır ----
  async function dbRpc(fn, govde) {
    const url = String((await ozellik('DB_URL')) || '').trim().replace(/\/+$/, ''), anahtar = String((await ozellik('DB_ANAHTAR')) || '').trim();
    if (!url || !anahtar) throw new Error('Veri tabanı ayarı yok');
    const c = await disIstek(url + '/rest/v1/rpc/' + fn, { method: 'POST', headers: { 'Content-Type': 'application/json', apikey: anahtar }, body: JSON.stringify(govde || {}) });
    if (c.hata || c.kod >= 400) throw new Error(c.hata || ('HTTP ' + c.kod + ' ' + String(c.govde || '').slice(0, 160)));
    const j = JSON.parse(c.govde || 'null');
    if (!j || j.status !== 'ok') throw new Error((j && j.message) || 'boş cevap');
    return j;
  }

  // ---- Telefondan ERP'ye giden irsaliyeler: program çalışıyor mu, bekleyen / hatalı / değişen belge var mı ----
  // r: [batch, belge türü, cari, personel, ilk, durum, ERP belge no, mesaj, son değişiklikten dakika, satır, tip]
  let erpSon = null;
  async function erpAktarimOku() {
    try { erpSon = { zaman: Date.now(), veri: await dbRpc('erp_aktarim_durum', { p_gun: 3 }) }; }
    catch (e) { erpSon = { zaman: Date.now(), hata: e.message }; }
    erpSon.kuyruk = await kuyrukOku();
    return erpSon;
  }
  // Sunucu → bulut (veri tabanı) gönderim kuyruğu: en eski bekleyen kaydın yaşı. Takılırsa ERP programı yeni
  // belgeleri HİÇ göremez (bulutta yoklar) — bu yüzden ayrıca bakılır.
  async function kuyrukOku() {
    try {
      const r = await depo.havuz.query("select count(*)::int as n, min(deger->>1) as ilk from mk.satir where sekme = 'DbKuyruk' and satir > 0 and coalesce(deger->>0, '') <> ''");
      const n = r.rows[0].n, ilk = r.rows[0].ilk, t = ilk ? Date.parse(String(ilk).replace(' ', 'T') + '+03:00') : NaN;
      return { n, dk: isNaN(t) ? 0 : Math.max(0, Math.round((Date.now() - t) / 60000)), sonHata: (await ozellik('DB_SON_HATA')) || '' };
    } catch (e) { return null; }
  }
  function erpSorunlar(v) {
    const l = (v && v.belgeler) || [], n = v && v.nabiz, s = [];
    const k = erpSon && erpSon.kuyruk;
    if (k && k.n && k.dk >= 10) s.push({ anahtar: 'kuyruk:' + new Date().toISOString().slice(0, 13), durum: 'acil', metin: 'Sunucudan buluta gönderim TAKILDI: ' + k.n + ' kayıt ' + k.dk + ' dakikadır bekliyor. Telefondan kaydedilen mal / sayım buluta gitmediği için ERP programı yeni belgeleri göremez. Son hata: ' + (k.sonHata || '—') });
    const bekleyen = l.filter((r) => r[5] === 'bekliyor'), gec = bekleyen.filter((r) => Number(r[8]) >= 20);
    const saat = Number(new Date().toLocaleTimeString('en-GB', { timeZone: 'Europe/Istanbul', hour: '2-digit', hour12: false }));
    if (n && Number(n.dk) > 15 && bekleyen.length && saat >= 7 && saat < 22) s.push({ anahtar: 'nabiz:' + new Date().toISOString().slice(0, 13), durum: 'acil', metin: 'ERP aktarım programı ' + n.dk + ' dakikadır çalışmıyor, ' + bekleyen.length + ' belge bekliyor. ERP bilgisayarı açık mı, "MK Saha ERP Aktarim" görevi çalışıyor mu?' });
    else if (!n && bekleyen.length) s.push({ anahtar: 'nabiz:yok:' + new Date().toISOString().slice(0, 10), durum: 'uyari', metin: 'ERP aktarım programından hiç haber yok (siparis-aktar.ps1 yeni sürümü kurulu mu?), ' + bekleyen.length + ' belge bekliyor.' });
    else if (gec.length) s.push({ anahtar: 'gec:' + gec.map((r) => r[0]).join(',').slice(0, 200), durum: 'uyari', metin: gec.length + ' belge 20 dakikadan uzun süredir ERP\'ye gitmedi: ' + gec.slice(0, 5).map((r) => r[1] + ' / ' + r[2]).join('; ') });
    l.filter((r) => r[5] === 'hata').forEach((r) => s.push({ anahtar: 'hata:' + r[0] + ':' + String(r[7]).slice(0, 80), durum: 'acil', metin: 'ERP\'ye YAZILAMADI — ' + r[1] + ' / ' + r[2] + ' (' + r[3] + ', ' + r[4] + '): ' + r[7] }));
    l.filter((r) => r[5] === 'degisti' || r[5] === 'degisti_bildirildi').forEach((r) => s.push({ anahtar: 'degisti:' + r[0], durum: 'uyari', metin: 'ERP\'ye gittikten SONRA telefonda değiştirildi — ' + r[6] + ' (' + r[1] + ' / ' + r[2] + '). ERP\'deki belgeyi elle düzeltin.' }));
    return s;
  }
  function erpMadde() {
    if (!erpSon) return { ad: 'ERP\'ye irsaliye aktarımı', durum: 'bilinmiyor', metin: 'Henüz bakılmadı' };
    if (erpSon.hata) return { ad: 'ERP\'ye irsaliye aktarımı', durum: /does not exist|404|bulunamad/i.test(erpSon.hata) ? 'bilinmiyor' : 'uyari', metin: 'Durum okunamadı: ' + erpSon.hata + ' (026 SQL çalıştırıldı mı?)' };
    const v = erpSon.veri, o = v.ozet || {}, sorun = erpSorunlar(v), n = v.nabiz;
    const durum = sorun.some((x) => x.durum === 'acil') ? 'acil' : sorun.length ? 'uyari' : 'ok';
    return { ad: 'ERP\'ye irsaliye aktarımı', durum,
      metin: (sorun.length ? sorun.map((x) => x.metin).join(' · ') + ' — ' : '') + 'Son 3 gün: ' + (o.ok || 0) + ' aktarıldı, ' + (o.bekliyor || 0) + ' bekliyor, ' + (o.hata || 0) + ' hata' +
        (n ? ' · program son ' + n.dk + ' dk önce çalıştı' : ' · programdan haber yok') };
  }
  // ERP bilgisayarındaki SQL yedeği (erp-sql-yedek.ps1 her gece "OK: ..." ya da "HATA: ..." bildirir).
  function erpSqlYedekMadde() {
    const ad = 'ERP12 SQL yedeği (ERP bilgisayarı)';
    const y = erpSon && erpSon.veri && erpSon.veri.nabizlar && erpSon.veri.nabizlar.erp_sql_yedek;
    if (!y) return { ad, durum: 'uyari', metin: 'ERP bilgisayarından yedek bilgisi hiç gelmedi — erp-sql-yedek.ps1 kurulu mu? (ERP-YEDEK-GOREV.bat)' };
    const saat = Number(y.dk) / 60, hata = /^HATA/.test(String(y.mesaj));
    return { ad, durum: hata ? 'acil' : saat > 50 ? 'acil' : saat > 30 ? 'uyari' : 'ok', metin: 'Son çalışma ' + saatMetni(Number(y.dk) * 60000) + ' önce — ' + y.mesaj };
  }
  // Anlık uyarı: yeni bir hata / değişiklik / durma görülünce HEMEN e-posta (her konu bir kez).
  async function erpAnlik() {
    await erpAktarimOku();
    if (!ayar.smtp) return;
    const sorun = erpSorunlar(erpSon.veri || {});
    if (erpSon.hata && !/does not exist|404/i.test(erpSon.hata)) sorun.push({ anahtar: 'bulut:' + new Date().toISOString().slice(0, 13), durum: 'acil', metin: 'Bulut veri tabanına (ERP programının baktığı yer) ulaşılamıyor: ' + erpSon.hata });
    if (!sorun.length) return;
    let gonderilen = [];
    try { gonderilen = JSON.parse((await kayitOku('erp_uyari')) || '[]'); } catch (e) { gonderilen = []; }
    const yeni = sorun.filter((x) => gonderilen.indexOf(x.anahtar) === -1);
    if (!yeni.length) return;
    const acil = yeni.some((x) => x.durum === 'acil');
    await depo.epostaEkle({ alici, konu: (acil ? '🔴 ' : '🟡 ') + 'KRT Saha → ERP: ' + yeni.length + ' konu',
      metin: 'Merhaba,\n\nTelefondan ERP\'ye giden irsaliyelerde şunlar görüldü:\n\n' + yeni.map((x) => (x.durum === 'acil' ? '🔴 ' : '🟡 ') + x.metin).join('\n\n') +
        '\n\nTelefonda: Mal Giriş → 🧾 İrsaliyeler → "Uygulamadan gidenler" bölümünde her belgenin durumu görünür.\nAynı konu için tekrar e-posta gelmez.\n\nKRT Saha' });
    await kayitYaz('erp_uyari', JSON.stringify(gonderilen.concat(yeni.map((x) => x.anahtar)).slice(-400)));
    gunluk('[bekçi] ERP aktarım uyarısı kuyruğa alındı →', alici, '(' + yeni.length + ' konu)');
    if (epostaGonder) setImmediate(epostaGonder);
  }

  // ---- Yalnız ERP veri tabanında duran uygulama verisi (tedarikçi siparişleri, notlar, aktarım kayıtları): her gece yedek ----
  async function uygulamaYedekAl() {
    const bugun = new Date().toLocaleDateString('sv-SE', { timeZone: 'Europe/Istanbul' });
    const saat = Number(new Date().toLocaleTimeString('en-GB', { timeZone: 'Europe/Istanbul', hour: '2-digit', hour12: false }));
    if (saat < 3 || (await kayitOku('uygulama_yedek')) === bugun) return;
    try {
      const j = await dbRpc('uygulama_yedek', {});
      if (!fs.existsSync(pgYedek)) fs.mkdirSync(pgYedek, { recursive: true });
      const f = path.join(pgYedek, 'uygulama-' + bugun + '.json.gz');
      fs.writeFileSync(f + '.tmp', zlib.gzipSync(Buffer.from(JSON.stringify(j))));
      fs.renameSync(f + '.tmp', f);
      fs.readdirSync(pgYedek).filter((x) => /^uygulama-\d{4}-\d\d-\d\d\.json\.gz$/.test(x)).sort().reverse().slice(30).forEach((x) => { try { fs.unlinkSync(path.join(pgYedek, x)); } catch (e) {} });
      await kayitYaz('uygulama_yedek', bugun);
      gunluk('[bekçi] uygulama verisi yedeklendi →', f);
    } catch (e) { gunluk('[bekçi] uygulama yedeği alınamadı:', e.message); }
  }
  function uygulamaYedekMadde() {
    try {
      const d = fs.existsSync(pgYedek) ? fs.readdirSync(pgYedek).filter((x) => /^uygulama-.*\.json\.gz$/.test(x)).map((x) => ({ x, st: fs.statSync(path.join(pgYedek, x)) })).sort((a, b) => b.st.mtimeMs - a.st.mtimeMs) : [];
      if (!d.length) return { ad: 'Uygulama verisi yedeği (tedarikçi siparişleri, notlar)', durum: 'bilinmiyor', metin: 'Henüz yedek yok (gece 03:00\'ten sonra alınır)' };
      const yas = Date.now() - d[0].st.mtimeMs;
      return { ad: 'Uygulama verisi yedeği (tedarikçi siparişleri, notlar)', durum: yas > 50 * 3600000 ? 'acil' : yas > 30 * 3600000 ? 'uyari' : 'ok', metin: 'Son yedek ' + saatMetni(yas) + ' önce (' + d.length + ' gün saklı)' };
    } catch (e) { return { ad: 'Uygulama verisi yedeği', durum: 'bilinmiyor', metin: e.message }; }
  }

  async function kontrol() {
    if (calisiyor) return son;
    calisiyor = true;
    try {
      await uygulamaYedekAl();
      if (!erpSon || Date.now() - erpSon.zaman > 5 * 60000) await erpAktarimOku();
      const maddeler = [await alanAdiKontrol(), ...(await surelerKontrol()), diskKontrol(), yedekKontrol(), uygulamaYedekMadde(), await erpKontrol(), erpMadde(), erpSqlYedekMadde()];
      son = { zaman: new Date().toISOString(), alici, maddeler };
      await epostaGerekirse();
      return son;
    } catch (e) { gunluk('[bekçi] hata', e.message); return son; } finally { calisiyor = false; }
  }

  async function epostaGerekirse() {
    const sorun = son.maddeler.filter((m) => m.durum === 'uyari' || m.durum === 'acil');
    const bugun = new Date().toLocaleDateString('sv-SE', { timeZone: 'Europe/Istanbul' });
    const saat = Number(new Date().toLocaleTimeString('en-GB', { timeZone: 'Europe/Istanbul', hour: '2-digit', hour12: false }));
    if (!sorun.length || saat < 8 || !ayar.smtp) return;
    if ((await kayitOku('son_eposta')) === bugun) return;
    const acil = sorun.some((m) => m.durum === 'acil');
    const satir = sorun.map((m) => (m.durum === 'acil' ? '🔴 ' : '🟡 ') + m.ad + ': ' + m.metin);
    await depo.epostaEkle({ alici, konu: (acil ? '🔴 ACİL — ' : '🟡 ') + 'KRT Saha: ' + sorun.length + ' konu ilgilenmeni bekliyor',
      metin: 'Merhaba,\n\nKRT Saha sunucusunun günlük kontrolünde şunlar çıktı:\n\n' + satir.join('\n') +
        '\n\nTüm liste: uygulamada Yönetici Paneli → Sunucu ve süreler.\nBu e-posta, sorun sürdükçe her sabah bir kez gelir.\n\nKRT Saha' });
    await kayitYaz('son_eposta', bugun);
    gunluk('[bekçi] uyarı e-postası kuyruğa alındı →', alici, '(' + sorun.length + ' konu)');
    if (epostaGonder) setImmediate(epostaGonder);
  }

  let saat = null, erpSaat = null;
  return {
    baslat() {
      setTimeout(() => kontrol(), 60000); saat = setInterval(() => kontrol(), 3600000);
      // ERP aktarımı 5 dakikada bir izlenir; yeni sorun görülünce hemen e-posta.
      erpSaat = setInterval(() => { erpAnlik().catch((e) => gunluk('[bekçi] ERP izleme hatası', e.message)); }, 5 * 60000);
    },
    durdur() { if (saat) clearInterval(saat); if (erpSaat) clearInterval(erpSaat); },
    async durum(yenile) { if (yenile || !son) await kontrol(); return son; }
  };
}
module.exports = { bekciOlustur };
