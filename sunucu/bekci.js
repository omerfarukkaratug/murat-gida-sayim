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

  async function kontrol() {
    if (calisiyor) return son;
    calisiyor = true;
    try {
      const maddeler = [await alanAdiKontrol(), ...(await surelerKontrol()), diskKontrol(), yedekKontrol(), await erpKontrol()];
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

  let saat = null;
  return {
    baslat() { setTimeout(() => kontrol(), 60000); saat = setInterval(() => kontrol(), 3600000); },
    durdur() { if (saat) clearInterval(saat); },
    async durum(yenile) { if (yenile || !son) await kontrol(); return son; }
  };
}
module.exports = { bekciOlustur };
