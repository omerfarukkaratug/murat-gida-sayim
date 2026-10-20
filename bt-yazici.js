/* KRT Saha — Bluetooth yazıcı (telefondan doğrudan termal yazıcıya baskı)
 *
 * Ne yapar: Ekranda hazırlanan baskı sayfalarını (etiket, fiş, liste) siyah-beyaz resme çevirir ve
 * Bluetooth (BLE) ile yazıcıya gönderir. Yazıcı dilleri:
 *   - ESC/POS  : 58 / 80 mm fiş yazıcıları (çoğu ucuz termal yazıcı)
 *   - TSPL     : etiket yazıcıları (TSC, Xprinter, Gprinter, HPRT, iDPRT…)
 *   - ZPL      : Zebra etiket yazıcıları (ZQ / ZD serisi)
 * Yalnızca Android'de Chrome (ve Play'deki KRT Saha) destekler; iPhone'da Bluetooth web'e kapalıdır,
 * orada "Yazdır" (AirPrint / WiFi) kullanılır.
 *
 * Kullanım:  BtYazici.yazdir({ sayfalar: [el1, el2…], etiket: { w: 80, h: 34 }, baslik: 'Etiket' })
 *            BtYazici.destekli()  → bu cihazda Bluetooth baskı var mı
 * Hiçbir kütüphane gerekmez; sayfa kendi içinde resme çevrilir (SVG foreignObject).
 */
(function () {
  'use strict';
  var AYAR_ANAHTAR = 'mkBtYazici_v1';
  // Termal yazıcıların bilinen BLE servisleri (Web Bluetooth yalnızca burada adı geçen servislere izin verir).
  var SERVISLER = [
    '000018f0-0000-1000-8000-00805f9b34fb', 'e7810a71-73ae-499d-8c15-faa9aef0c3f2', '49535343-fe7d-4ae5-8fa9-9fafd205e455',
    '0000ff00-0000-1000-8000-00805f9b34fb', '0000ffe0-0000-1000-8000-00805f9b34fb', '0000fff0-0000-1000-8000-00805f9b34fb',
    '0000ae30-0000-1000-8000-00805f9b34fb', '0000ae00-0000-1000-8000-00805f9b34fb', '0000fee7-0000-1000-8000-00805f9b34fb',
    '38eb4a80-c570-11e3-9507-0002a5d5c51b' /* Zebra */
  ];
  var ZEBRA_YAZ = '38eb4a82-c570-11e3-9507-0002a5d5c51b';
  var TURLER = {
    fis58: { ad: 'Fiş yazıcı 58 mm', dil: 'escpos', nokta: 384 },
    fis80: { ad: 'Fiş yazıcı 80 mm', dil: 'escpos', nokta: 576 },
    tspl:  { ad: 'Etiket yazıcı (TSPL — TSC, Xprinter…)', dil: 'tspl' },
    zpl:   { ad: 'Zebra etiket yazıcı (ZPL)', dil: 'zpl' }
  };

  function destekli() { return !!(navigator.bluetooth && navigator.bluetooth.requestDevice) && window.isSecureContext !== false; }
  function ayarOku() {
    var a = {}; try { a = JSON.parse(localStorage.getItem(AYAR_ANAHTAR) || '{}') || {}; } catch (e) { a = {}; }
    if (!TURLER[a.tur]) a.tur = 'fis58';
    a.dpi = a.dpi === 300 ? 300 : 203;
    a.w = Number(a.w) > 0 ? Number(a.w) : 0; a.h = Number(a.h) > 0 ? Number(a.h) : 0;
    a.bosluk = Number(a.bosluk) >= 0 && a.bosluk !== '' && a.bosluk !== undefined ? Number(a.bosluk) : 2;
    a.koyuluk = Number(a.koyuluk) >= 0 ? Number(a.koyuluk) : 0;  // −40…+40: eşik kayması (koyu baskı için +)
    a.ters = !!a.ters; a.kes = a.kes !== false;
    return a;
  }
  function ayarYaz(a) { try { localStorage.setItem(AYAR_ANAHTAR, JSON.stringify(a)); } catch (e) { /* önemli değil */ } }

  // ---------------- Bağlantı ----------------
  var bag = { cihaz: null, yaz: null, yanitsiz: false };
  function bagliMi() { return !!(bag.cihaz && bag.cihaz.gatt && bag.cihaz.gatt.connected && bag.yaz); }
  async function yazmaBul(sunucu) {
    var servisler = await sunucu.getPrimaryServices();
    var aday = null;
    for (var i = 0; i < servisler.length; i++) {
      var ozler; try { ozler = await servisler[i].getCharacteristics(); } catch (e) { continue; }
      for (var j = 0; j < ozler.length; j++) {
        var o = ozler[j], p = o.properties;
        if (o.uuid === ZEBRA_YAZ) return o;
        if ((p.writeWithoutResponse || p.write) && !aday) aday = o;
      }
    }
    return aday;
  }
  async function baglan(cihaz) {
    var sunucu = await cihaz.gatt.connect();
    var oz = await yazmaBul(sunucu);
    if (!oz) { try { cihaz.gatt.disconnect(); } catch (e) { /* */ } throw new Error('Bu cihazda yazma kanalı bulunamadı — bir yazıcı olduğundan emin ol'); }
    bag.cihaz = cihaz; bag.yaz = oz; bag.yanitsiz = !!oz.properties.writeWithoutResponse;
    cihaz.addEventListener('gattserverdisconnected', function () { bag.yaz = null; durumYaz(); });
    var a = ayarOku(); a.cihazAd = cihaz.name || 'Bluetooth yazıcı'; a.cihazId = cihaz.id; ayarYaz(a);
  }
  async function yaziciSec() {
    var cihaz = await navigator.bluetooth.requestDevice({ acceptAllDevices: true, optionalServices: SERVISLER });
    await baglan(cihaz);
  }
  // Daha önce izin verilen yazıcıya sormadan yeniden bağlan (tarayıcı destekliyorsa).
  async function eskiyeBaglan() {
    if (bagliMi()) return true;
    if (bag.cihaz) { try { await baglan(bag.cihaz); return true; } catch (e) { /* aşağıda dene */ } }
    if (!navigator.bluetooth.getDevices) return false;
    var a = ayarOku(); if (!a.cihazId) return false;
    try {
      var liste = await navigator.bluetooth.getDevices();
      var c = liste.filter(function (d) { return d.id === a.cihazId; })[0];
      if (!c) return false;
      await baglan(c); return true;
    } catch (e) { return false; }
  }
  function bekle(ms) { return new Promise(function (c) { setTimeout(c, ms); }); }
  async function gonder(bayt, ilerleme) {
    var parca = bag.yanitsiz ? 180 : 240, toplam = bayt.length;
    for (var i = 0; i < toplam; i += parca) {
      var p = bayt.subarray(i, Math.min(i + parca, toplam));
      if (bag.yanitsiz && bag.yaz.writeValueWithoutResponse) { await bag.yaz.writeValueWithoutResponse(p); if ((i / parca) % 8 === 7) await bekle(12); }
      else if (bag.yaz.writeValueWithResponse) await bag.yaz.writeValueWithResponse(p);
      else await bag.yaz.writeValue(p);
      if (ilerleme) ilerleme(Math.min(1, (i + parca) / toplam));
    }
  }

  // ---------------- Sayfayı resme çevirme ----------------
  var veriAdresi = {};
  function resimVeri(src) {
    if (!src || /^data:/.test(src)) return Promise.resolve(src);
    if (veriAdresi[src]) return Promise.resolve(veriAdresi[src]);
    return fetch(src).then(function (r) { return r.blob(); }).then(function (b) {
      return new Promise(function (coz) { var f = new FileReader(); f.onload = function () { veriAdresi[src] = f.result; coz(f.result); }; f.onerror = function () { coz(''); }; f.readAsDataURL(b); });
    }).catch(function () { return ''; });
  }
  // Bütün görünüş, öğenin üstüne satır içi yazılır (SVG resmin içinde sayfanın stil sayfaları çalışmaz).
  function stilKopyala(kaynak, hedef) {
    var cs = getComputedStyle(kaynak), s = '';
    for (var i = 0; i < cs.length; i++) { var ad = cs[i]; s += ad + ':' + cs.getPropertyValue(ad) + ';'; }
    hedef.setAttribute('style', s);
  }
  async function klonla(el) {
    var kopya = el.cloneNode(true), isler = [];
    var k1 = [el].concat(Array.prototype.slice.call(el.querySelectorAll('*')));
    var k2 = [kopya].concat(Array.prototype.slice.call(kopya.querySelectorAll('*')));
    for (var i = 0; i < k1.length; i++) {
      var a = k1[i], b = k2[i];
      if (!(a instanceof Element)) continue;
      stilKopyala(a, b);
      if (a.tagName === 'CANVAS') {
        var im = document.createElement('img'); im.setAttribute('style', b.getAttribute('style'));
        try { im.src = a.toDataURL('image/png'); } catch (e) { /* */ }
        b.parentNode.replaceChild(im, b); k2[i] = im;
      } else if (a.tagName === 'IMG') {
        (function (hedef, src) { isler.push(resimVeri(src).then(function (v) { hedef.setAttribute('src', v); })); })(b, a.currentSrc || a.src);
      } else if (a.tagName === 'INPUT' || a.tagName === 'TEXTAREA') {
        b.setAttribute('value', a.value);
      }
    }
    await Promise.all(isler);
    kopya.style.margin = '0'; kopya.style.transform = 'none'; kopya.style.position = 'static'; kopya.style.left = 'auto'; kopya.style.top = 'auto';
    return kopya;
  }
  async function resmeCevir(el, genislikNokta) {
    var r = el.getBoundingClientRect(), w = Math.max(1, Math.ceil(r.width || el.offsetWidth)), h = Math.max(1, Math.ceil(r.height || el.offsetHeight));
    var kopya = await klonla(el);
    if (getComputedStyle(el).display === 'block') { kopya.style.display = 'flow-root'; h = Math.max(h, el.scrollHeight); }
    var xml = new XMLSerializer().serializeToString(kopya);
    var svg = '<svg xmlns="http://www.w3.org/2000/svg" width="' + w + '" height="' + h + '"><foreignObject x="0" y="0" width="100%" height="100%">' +
      '<div xmlns="http://www.w3.org/1999/xhtml" style="width:' + w + 'px;height:' + h + 'px;background:#fff;">' + xml + '</div></foreignObject></svg>';
    var resim = await new Promise(function (coz, red) {
      var im = new Image(); im.onload = function () { coz(im); }; im.onerror = function () { red(new Error('Sayfa resme çevrilemedi')); };
      im.src = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(svg);
    });
    var olcek = genislikNokta / w, cw = Math.round(genislikNokta), ch = Math.max(1, Math.round(h * olcek));
    var tv = document.createElement('canvas'); tv.width = cw; tv.height = ch;
    var cx = tv.getContext('2d', { willReadFrequently: true });
    cx.fillStyle = '#fff'; cx.fillRect(0, 0, cw, ch);
    cx.imageSmoothingQuality = 'high';
    cx.drawImage(resim, 0, 0, cw, ch);
    return tv;
  }
  // Gri tonu siyah-beyaza: yazılar keskin kalsın diye eşik; fotoğraf/logo alanları için hafif titreşim (dither).
  function tekRenk(tv, koyuluk) {
    var w = tv.width, h = tv.height, d = tv.getContext('2d').getImageData(0, 0, w, h).data;
    var gri = new Float32Array(w * h);
    for (var i = 0, j = 0; i < gri.length; i++, j += 4) {
      var a = d[j + 3] / 255;
      gri[i] = 255 - a * (255 - (d[j] * 0.299 + d[j + 1] * 0.587 + d[j + 2] * 0.114));
    }
    var esik = 160 + (koyuluk || 0), bit = new Uint8Array(w * h);
    for (var y = 0; y < h; y++) for (var x = 0; x < w; x++) {
      var k = y * w + x, eski = gri[k], yeni = eski < esik ? 0 : 255, hata = eski - yeni;
      bit[k] = yeni === 0 ? 1 : 0;
      // Yalnızca ara tonlarda dağıt (düz siyah yazı ve beyaz zemin değişmesin).
      if (eski > 40 && eski < 215) {
        if (x + 1 < w) gri[k + 1] += hata * 7 / 16;
        if (y + 1 < h) { if (x > 0) gri[k + w - 1] += hata * 3 / 16; gri[k + w] += hata * 5 / 16; if (x + 1 < w) gri[k + w + 1] += hata / 16; }
      }
    }
    return { w: w, h: h, bit: bit };
  }
  function satirBaytlari(t, ters) {
    var wb = Math.ceil(t.w / 8), out = new Uint8Array(wb * t.h);
    for (var y = 0; y < t.h; y++) for (var x = 0; x < t.w; x++) {
      var siyah = t.bit[y * t.w + x] === 1;
      if (ters ? !siyah : siyah) out[y * wb + (x >> 3)] |= 0x80 >> (x & 7);
    }
    if (ters) for (var y2 = 0; y2 < t.h; y2++) for (var x2 = t.w; x2 < wb * 8; x2++) out[y2 * wb + (x2 >> 3)] |= 0x80 >> (x2 & 7); // kenar boşluğu beyaz
    return { wb: wb, veri: out };
  }
  function birlestir(parcalar) {
    var n = 0; parcalar.forEach(function (p) { n += p.length; });
    var o = new Uint8Array(n), i = 0; parcalar.forEach(function (p) { o.set(p, i); i += p.length; }); return o;
  }
  function metin(s) { return new TextEncoder().encode(s); }

  function escpos(resimler, a) {
    var p = [new Uint8Array([0x1b, 0x40])];
    resimler.forEach(function (t, sira) {
      var b = satirBaytlari(t, false);
      for (var y = 0; y < t.h; y += 128) {          // büyük resim parça parça (yazıcı tamponu taşmasın)
        var yk = Math.min(128, t.h - y);
        p.push(new Uint8Array([0x1d, 0x76, 0x30, 0x00, b.wb & 255, b.wb >> 8, yk & 255, yk >> 8]));
        p.push(b.veri.subarray(y * b.wb, (y + yk) * b.wb));
      }
      p.push(new Uint8Array([0x1b, 0x64, 0x04]));
      if (a.kes && sira === resimler.length - 1) p.push(new Uint8Array([0x1d, 0x56, 0x42, 0x00]));
    });
    return birlestir(p);
  }
  function tspl(resimler, a, wmm, hmm) {
    var p = [];
    resimler.forEach(function (t) {
      var b = satirBaytlari(t, !a.ters);              // TSPL'de 1 = beyaz (basılmaz)
      p.push(metin('SIZE ' + wmm + ' mm,' + hmm + ' mm\r\nGAP ' + a.bosluk + ' mm,0 mm\r\nDIRECTION 1\r\nCLS\r\nBITMAP 0,0,' + b.wb + ',' + t.h + ',0,'));
      p.push(b.veri);
      p.push(metin('\r\nPRINT 1,1\r\n'));
    });
    return birlestir(p);
  }
  function zpl(resimler, a) {
    var hex = '0123456789ABCDEF', p = [];
    resimler.forEach(function (t) {
      var b = satirBaytlari(t, a.ters), s = '';
      for (var i = 0; i < b.veri.length; i++) s += hex[b.veri[i] >> 4] + hex[b.veri[i] & 15];
      p.push(metin('^XA^PW' + t.w + '^LL' + t.h + '^FO0,0^GFA,' + b.veri.length + ',' + b.veri.length + ',' + b.wb + ',' + s + '^FS^XZ\r\n'));
    });
    return birlestir(p);
  }

  // ---------------- Ekran ----------------
  var kok = null, istek = null;
  function $(id) { return document.getElementById(id); }
  function esc(s) { return String(s == null ? '' : s).replace(/[&<>"]/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]; }); }
  function stilEkle() {
    if ($('btyStil')) return;
    var st = document.createElement('style'); st.id = 'btyStil';
    st.textContent = '#btyKok{position:fixed;inset:0;z-index:2147483000;background:rgba(10,10,20,.55);display:flex;align-items:flex-end;justify-content:center;font-family:-apple-system,"Segoe UI",Roboto,sans-serif;}' +
      '#btyKok .k{width:100%;max-width:520px;max-height:92vh;overflow:auto;background:#fff;color:#14162b;border-radius:22px 22px 0 0;padding:18px 16px calc(18px + env(safe-area-inset-bottom));box-shadow:0 -8px 30px rgba(0,0,0,.25);}' +
      '#btyKok h3{margin:0 0 4px;font-size:18px;} #btyKok .ip{font-size:12.5px;color:#5b6078;margin:2px 0 10px;line-height:1.4;}' +
      '#btyKok label{display:block;font-size:12px;font-weight:800;color:#5b6078;text-transform:uppercase;letter-spacing:.04em;margin:12px 0 5px;}' +
      '#btyKok select,#btyKok input{width:100%;box-sizing:border-box;font-size:16px;padding:10px;border-radius:11px;border:1.5px solid #dfe1ee;background:#f5f6fb;color:#14162b;}' +
      '#btyKok .sat{display:flex;gap:8px;} #btyKok .sat>*{flex:1;}' +
      '#btyKok button{font:inherit;font-size:15px;font-weight:800;border-radius:12px;padding:12px;border:1.5px solid #dfe1ee;background:#f5f6fb;color:#14162b;cursor:pointer;}' +
      '#btyKok button.ana{background:#5546ea;border-color:#5546ea;color:#fff;} #btyKok button:disabled{opacity:.45;}' +
      '#btyKok .durum{margin-top:12px;padding:10px 12px;border-radius:12px;background:#f5f6fb;font-size:14px;font-weight:700;}' +
      '#btyKok .onizleme{margin-top:12px;background:#eef0f7;border-radius:12px;padding:8px;text-align:center;max-height:220px;overflow:auto;}' +
      '#btyKok .onizleme canvas{max-width:100%;image-rendering:pixelated;background:#fff;box-shadow:0 1px 4px rgba(0,0,0,.2);}' +
      '#btyKok .cubuk{height:8px;border-radius:4px;background:#e3e4ee;overflow:hidden;margin-top:8px;} #btyKok .cubuk i{display:block;height:100%;width:0;background:#1fc777;}' +
      '@media (prefers-color-scheme:dark){#btyKok .k{background:#151936;color:#eceefd;} #btyKok select,#btyKok input,#btyKok button,#btyKok .durum{background:#1d2247;border-color:#2b3160;color:#eceefd;} #btyKok .ip,#btyKok label{color:#a3a8c8;} #btyKok .onizleme{background:#0c0f22;}}';
    document.head.appendChild(st);
  }
  function durumYaz(m, renk) {
    if (!kok) return;
    var a = ayarOku();
    $('btyDurum').innerHTML = m ? m : (bagliMi() ? '🟢 Bağlı: <b>' + esc(bag.cihaz.name || a.cihazAd || 'yazıcı') + '</b>' : (a.cihazAd ? '⚪ Son yazıcı: ' + esc(a.cihazAd) + ' (yazdırırken bağlanılır)' : '⚪ Yazıcı seçilmedi'));
    $('btyDurum').style.color = renk || '';
  }
  function alanlariGoster() {
    var t = TURLER[$('btyTur').value], etiket = t.dil !== 'escpos';
    $('btyEtiketAlan').style.display = etiket ? '' : 'none';
    $('btyTersAlan').style.display = etiket ? '' : 'none';
    $('btyKesAlan').style.display = etiket ? 'none' : '';
  }
  function ayarlariAl() {
    var a = ayarOku();
    a.tur = $('btyTur').value; a.dpi = Number($('btyDpi').value) === 300 ? 300 : 203;
    a.w = Number($('btyW').value) || 0; a.h = Number($('btyH').value) || 0; a.bosluk = Number($('btyGap').value) || 0;
    a.koyuluk = Number($('btyKoyu').value) || 0; a.ters = $('btyTers').checked; a.kes = $('btyKes').checked;
    ayarYaz(a); return a;
  }
  async function hazirla(a) {
    var t = TURLER[a.tur], resimler = [], wmm = 0, hmm = 0;
    var mm = a.dpi === 300 ? 11.81 : 8;
    for (var i = 0; i < istek.sayfalar.length; i++) {
      var el = istek.sayfalar[i], genislik;
      if (t.dil === 'escpos') genislik = t.nokta;
      else {
        wmm = a.w || (istek.etiket && istek.etiket.w) || 58; hmm = a.h || (istek.etiket && istek.etiket.h) || 40;
        genislik = Math.round(wmm * mm);
      }
      genislik = Math.floor(genislik / 8) * 8;
      var tv = await resmeCevir(el, genislik);
      if (t.dil !== 'escpos') {           // etiket: yükseklik etiket boyuna kırpılır / tamamlanır
        var hn = Math.round(hmm * mm);
        if (tv.height !== hn) { var t2 = document.createElement('canvas'); t2.width = tv.width; t2.height = hn; var c2 = t2.getContext('2d'); c2.fillStyle = '#fff'; c2.fillRect(0, 0, t2.width, hn); c2.drawImage(tv, 0, 0); tv = t2; }
      }
      resimler.push(tekRenk(tv, a.koyuluk));
      $('btyIlerleme').style.width = Math.round((i + 1) / istek.sayfalar.length * 30) + '%';
    }
    return { t: t, resimler: resimler, wmm: wmm, hmm: hmm };
  }
  function onizlemeCiz(r) {
    var t = r.resimler[0]; if (!t) return;
    var tv = document.createElement('canvas'); tv.width = t.w; tv.height = t.h;
    var cx = tv.getContext('2d'), im = cx.createImageData(t.w, t.h);
    for (var i = 0; i < t.bit.length; i++) { var v = t.bit[i] ? 0 : 255; im.data[i * 4] = im.data[i * 4 + 1] = im.data[i * 4 + 2] = v; im.data[i * 4 + 3] = 255; }
    cx.putImageData(im, 0, 0);
    var o = $('btyOnizleme'); o.innerHTML = ''; o.appendChild(tv);
    if (r.resimler.length > 1) { var y = document.createElement('div'); y.className = 'ip'; y.textContent = '1. sayfa gösteriliyor · toplam ' + r.resimler.length + ' sayfa'; o.appendChild(y); }
  }
  async function yazdirTikla() {
    var btn = $('btyYazdir'); btn.disabled = true;
    try {
      var a = ayarlariAl();
      durumYaz('⏳ Sayfa hazırlanıyor…');
      var r = await hazirla(a);
      onizlemeCiz(r);
      if (!(await eskiyeBaglan())) { durumYaz('⏳ Yazıcıyı seç…'); await yaziciSec(); }
      var bayt = r.t.dil === 'escpos' ? escpos(r.resimler, a) : r.t.dil === 'tspl' ? tspl(r.resimler, a, r.wmm, r.hmm) : zpl(r.resimler, a);
      durumYaz('⏳ Yazıcıya gönderiliyor…');
      await gonder(bayt, function (o) { $('btyIlerleme').style.width = Math.round(30 + o * 70) + '%'; });
      durumYaz('✅ Gönderildi (' + r.resimler.length + ' sayfa). Çıktı gelmediyse yazıcı türünü kontrol et.', '#1a9f5c');
      if (istek.bitti) try { istek.bitti(); } catch (e) { /* */ }
    } catch (e) {
      var m = String(e && e.message || e);
      if (/cancel|iptal|User cancelled|chooser/i.test(m)) durumYaz('Yazıcı seçilmedi.');
      else durumYaz('❌ ' + esc(m), '#d63a3a');
    } finally { btn.disabled = false; }
  }
  function kapat() { if (kok) { kok.remove(); kok = null; } istek = null; }
  function ac(secenek) {
    stilEkle(); kapat();
    istek = secenek || {};
    istek.sayfalar = Array.prototype.slice.call(istek.sayfalar || []).filter(Boolean);
    var a = ayarOku();
    if (istek.etiket && !a.w) { a.w = istek.etiket.w; a.h = istek.etiket.h; }
    if (istek.etiket && (a.tur === 'fis58' || a.tur === 'fis80') && !a.turSecildi) a.tur = 'tspl';
    kok = document.createElement('div'); kok.id = 'btyKok';
    kok.innerHTML = '<div class="k"><h3>🔵 Bluetooth yazıcıyla yazdır</h3>' +
      '<div class="ip">' + esc(istek.baslik || 'Baskı') + ' · ' + istek.sayfalar.length + ' sayfa. Yazıcıyı açık ve telefona yakın tut; telefonun Bluetooth\'u açık olsun.</div>' +
      '<label>Yazıcı türü</label><select id="btyTur">' + Object.keys(TURLER).map(function (k) { return '<option value="' + k + '"' + (a.tur === k ? ' selected' : '') + '>' + esc(TURLER[k].ad) + '</option>'; }).join('') + '</select>' +
      '<div id="btyEtiketAlan"><label>Etiket ölçüsü (mm)</label><div class="sat"><input id="btyW" type="number" inputmode="decimal" placeholder="genişlik" value="' + (a.w || '') + '"><input id="btyH" type="number" inputmode="decimal" placeholder="yükseklik" value="' + (a.h || '') + '"><input id="btyGap" type="number" inputmode="decimal" placeholder="boşluk" value="' + a.bosluk + '"></div>' +
      '<div class="ip">Genişlik × yükseklik × iki etiket arası boşluk.</div></div>' +
      '<div class="sat"><div><label>Çözünürlük</label><select id="btyDpi"><option value="203"' + (a.dpi === 203 ? ' selected' : '') + '>203 dpi (çoğu)</option><option value="300"' + (a.dpi === 300 ? ' selected' : '') + '>300 dpi</option></select></div>' +
      '<div><label>Koyuluk</label><select id="btyKoyu">' + [[-30, 'Açık'], [0, 'Normal'], [25, 'Koyu'], [45, 'Çok koyu']].map(function (x) { return '<option value="' + x[0] + '"' + (a.koyuluk === x[0] ? ' selected' : '') + '>' + x[1] + '</option>'; }).join('') + '</select></div></div>' +
      '<div id="btyTersAlan" class="ip" style="margin-top:10px;"><input type="checkbox" id="btyTers" style="width:auto;"' + (a.ters ? ' checked' : '') + '> Renkler ters çıkıyorsa (zemin siyah) işaretle</div>' +
      '<div id="btyKesAlan" class="ip" style="margin-top:10px;"><input type="checkbox" id="btyKes" style="width:auto;"' + (a.kes ? ' checked' : '') + '> Sonunda kâğıdı kes (kesicisi olan yazıcı)</div>' +
      '<div class="durum" id="btyDurum"></div><div class="cubuk"><i id="btyIlerleme"></i></div>' +
      '<div class="onizleme" id="btyOnizleme"><div class="ip">Önizleme yazdırırken görünür.</div></div>' +
      '<div class="sat" style="margin-top:12px;"><button type="button" id="btySec">🔍 Yazıcı seç</button><button type="button" class="ana" id="btyYazdir">🖨️ Yazdır</button></div>' +
      '<button type="button" id="btyKapat" style="width:100%;margin-top:8px;">Kapat</button></div>';
    document.body.appendChild(kok);
    alanlariGoster(); durumYaz();
    $('btyTur').addEventListener('change', function () { var x = ayarOku(); x.tur = this.value; x.turSecildi = true; ayarYaz(x); alanlariGoster(); });
    $('btySec').addEventListener('click', function () {
      yaziciSec().then(function () { durumYaz(); }).catch(function (e) { durumYaz(/cancel|chooser/i.test(String(e && e.message)) ? 'Yazıcı seçilmedi.' : '❌ ' + esc(e && e.message || e), '#d63a3a'); });
    });
    $('btyYazdir').addEventListener('click', yazdirTikla);
    $('btyKapat').addEventListener('click', kapat);
    kok.addEventListener('click', function (e) { if (e.target === kok) kapat(); });
  }

  function yazdir(secenek) {
    if (!destekli()) {
      alert('Bu cihazda Bluetooth ile yazdırma yok.\n\nAndroid telefonda Chrome ya da Play Store\'daki KRT Saha uygulamasıyla çalışır. iPhone\'da "Yazdır" düğmesiyle AirPrint / WiFi yazıcıya basabilirsin.');
      return;
    }
    ac(secenek);
  }
  // Yazdırma ekranına (#yazdir gibi: üstte .yazdirma düğmeleri, altında belge) "Bluetooth" düğmesi ekler.
  // Belgenin bütün parçaları tek bir kutuya toplanır ki tek resim olarak basılsın.
  function dugmeEkle(kap, baslik) {
    if (!kap || !destekli()) return;
    var cubuk = kap.querySelector('.yazdirma'); if (!cubuk || cubuk.querySelector('.btyDugme')) return;
    var d = document.createElement('button'); d.type = 'button'; d.className = 'btyDugme'; d.textContent = '🔵 Bluetooth';
    var once = cubuk.children[1]; cubuk.insertBefore(d, once || null);
    d.addEventListener('click', function () {
      var belge = kap.querySelector(':scope > .btyBelge');
      if (!belge) {
        belge = document.createElement('div'); belge.className = 'btyBelge'; belge.style.background = '#fff'; belge.style.color = '#000'; belge.style.display = 'flow-root';
        Array.prototype.slice.call(kap.childNodes).forEach(function (n) { if (n !== cubuk) belge.appendChild(n); });
        kap.appendChild(belge);
      }
      yazdir({ sayfalar: [belge], baslik: baslik || 'Belge' });
    });
  }
  window.BtYazici = { destekli: destekli, yazdir: yazdir, dugmeEkle: dugmeEkle, _ic: { resmeCevir: resmeCevir, tekRenk: tekRenk, escpos: escpos, tspl: tspl, zpl: zpl, ayarOku: ayarOku } };
})();
