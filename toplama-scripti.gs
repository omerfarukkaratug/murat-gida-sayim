/**
 * MURAT GIDA - SAYIM TOPLAMA SERVİSİ
 * Bu dosyanın tamamını Apps Script'e yapıştırın (eski kodun üzerine, hiçbir
 * satır kalmayacak şekilde tamamen silip baştan yapıştırın).
 */

function doGet(e) {
  // ?action=katalog ile ürün kataloğunu döndürür.
  // ?action=ilerleme ile ekip genelinde sayım ilerlemesini (%) döndürür.
  // ?callback=xxx varsa (uygulama içinden <script> etiketiyle çağrılır),
  // JSONP formatında sarıp döner — CORS kısıtlamasına hiç takılmadan çalışır.
  if (e.parameter && e.parameter.action === 'katalog') {
    return getKatalog(e.parameter.callback);
  }
  if (e.parameter && e.parameter.action === 'ilerleme') {
    return getIlerleme(e.parameter.callback);
  }
  // ---- Yönetici işlemleri (PIN korumalı) ----
  if (e.parameter && e.parameter.action === 'resetcheck') {
    return outJson({
      resetToken: PropertiesService.getScriptProperties().getProperty('RESET_TOKEN') || '',
      defaultWakeLock: PropertiesService.getScriptProperties().getProperty('DEFAULT_WAKE_LOCK') || 'true'
    }, e.parameter.callback);
  }
  if (e.parameter && e.parameter.action === 'temizle') {
    return handleTemizle(e.parameter.pin, e.parameter.callback);
  }
  if (e.parameter && e.parameter.action === 'finalize') {
    return handleFinalize(e.parameter.pin, e.parameter.callback);
  }
  if (e.parameter && e.parameter.action === 'kullanicilar') {
    return getKullanicilar(e.parameter.callback);
  }
  if (e.parameter && e.parameter.action === 'kullanicilar_kaydet') {
    return handleKullanicilarKaydet(e.parameter.pin, e.parameter.data, e.parameter.callback);
  }
  if (e.parameter && e.parameter.action === 'ayar_kaydet') {
    return handleAyarKaydet(e.parameter.pin, e.parameter.wakelock, e.parameter.callback);
  }
  return ContentService
    .createTextOutput('Sayım toplama servisi çalışıyor ✅ (' + new Date().toISOString() + ')')
    .setMimeType(ContentService.MimeType.TEXT);
}

// ---- Yardımcılar ----
function outJson(obj, callback) {
  var json = JSON.stringify(obj);
  if (callback) {
    return ContentService.createTextOutput(callback + '(' + json + ')').setMimeType(ContentService.MimeType.JAVASCRIPT);
  }
  return ContentService.createTextOutput(json).setMimeType(ContentService.MimeType.JSON);
}

// Yönetici PIN'i Apps Script > Proje Ayarları > Script Özellikleri'nden
// ADMIN_PIN adıyla değiştirilebilir. Hiç ayarlanmazsa varsayılan '2026' kullanılır.
function checkPin(pin) {
  var real = PropertiesService.getScriptProperties().getProperty('ADMIN_PIN') || '2026';
  return !!pin && String(pin) === String(real);
}

function getKatalog(callback) {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sheet = ss.getSheetByName('Katalog');
  var entries = [];
  if (sheet && sheet.getLastRow() >= 2) {
    var values = sheet.getRange(2, 1, sheet.getLastRow() - 1, 4).getValues();
    entries = values
      .filter(function (r) { return r[0] && r[1]; })
      .map(function (r) {
        return { name: String(r[0]), barcode: String(r[1]), stockCode: String(r[2] || ''), oldStock: String(r[3] || '') };
      });
  }
  var json = JSON.stringify({ entries: entries });
  if (callback) {
    return ContentService
      .createTextOutput(callback + '(' + json + ')')
      .setMimeType(ContentService.MimeType.JAVASCRIPT);
  }
  return ContentService.createTextOutput(json).setMimeType(ContentService.MimeType.JSON);
}

// Ekip genelinde sayım ilerlemesi: 'Sayim' tablosundaki TÜM telefonlardan
// gelmiş farklı barkod sayısı ÷ 'Katalog' tablosundaki toplam farklı barkod
// sayısı. Tek bir telefonun kendi verisiyle değil, sunucudaki ortak veriyle
// hesaplanır — bu yüzden gerçek ekip ilerlemesini yansıtır.
function getIlerleme(callback) {
  var ss = SpreadsheetApp.getActiveSpreadsheet();

  var katalogSheet = ss.getSheetByName('Katalog');
  var totalCatalog = 0;
  if (katalogSheet && katalogSheet.getLastRow() >= 2) {
    var katalogBarcodes = katalogSheet.getRange(2, 2, katalogSheet.getLastRow() - 1, 1).getValues();
    var catalogSeen = {};
    katalogBarcodes.forEach(function (r) {
      var b = String(r[0] || '').trim();
      if (b) catalogSeen[b] = true;
    });
    totalCatalog = Object.keys(catalogSeen).length;
  }

  var sayimSheet = ss.getSheetByName('Sayim');
  var countedSeen = {};
  var byReyon = {}; // reyon -> { barkod -> true }
  if (sayimSheet && sayimSheet.getLastRow() >= 2) {
    var HEADERS = ['Tarih', 'Saat', 'Personel', 'Ürün Adı', 'Stok Kodu', 'Barkod', 'Birim', 'Eski Stok', 'Sayılan Adet', 'Fark', 'Oturum ID', 'Kayıt ID', 'Reyon'];
    var barcodeCol = HEADERS.indexOf('Barkod');
    var reyonCol = HEADERS.indexOf('Reyon');
    var sayimValues = sayimSheet.getRange(2, 1, sayimSheet.getLastRow() - 1, HEADERS.length).getValues();
    sayimValues.forEach(function (r) {
      var b = String(r[barcodeCol] || '').trim();
      if (b) countedSeen[b] = true;
      var reyon = String(r[reyonCol] || '').trim();
      if (reyon && b) {
        if (!byReyon[reyon]) byReyon[reyon] = {};
        byReyon[reyon][b] = true;
      }
    });
  }

  var countedTotal = Object.keys(countedSeen).length;
  var byReyonCounts = {};
  Object.keys(byReyon).forEach(function (r) { byReyonCounts[r] = Object.keys(byReyon[r]).length; });

  var result = {
    totalCatalog: totalCatalog,
    countedTotal: countedTotal,
    percent: totalCatalog > 0 ? Math.round((countedTotal / totalCatalog) * 1000) / 10 : 0,
    byReyon: byReyonCounts
  };
  var json = JSON.stringify(result);
  if (callback) {
    return ContentService
      .createTextOutput(callback + '(' + json + ')')
      .setMimeType(ContentService.MimeType.JAVASCRIPT);
  }
  return ContentService.createTextOutput(json).setMimeType(ContentService.MimeType.JSON);
}

function doPost(e) {
  // 10+ telefon aynı anda veri gönderebildiği için, sayfaya yazma işlemini
  // KİLİTLİYORUZ. Kilit olmadan iki telefonun isteği aynı anda işlenirse,
  // ikisi de "son satır şurada" bilgisini eski haliyle okuyup üzerine
  // yazabilir — bu veri kaybına yol açar. LockService bunu engeller: bir
  // istek yazarken diğerleri kısa süre (en fazla 30 sn) sırada bekler.
  var lock = LockService.getScriptLock();
  try {
    lock.waitLock(30000);
  } catch (lockErr) {
    // 30 saniyede kilit açılmadıysa (aşırı yoğunluk) hatayı bildir —
    // uygulama tarafı bunu ağ hatası gibi algılayıp veriyi kuyrukta tutar,
    // hiçbir kayıt silinmez, birazdan otomatik tekrar dener.
    return ContentService
      .createTextOutput(JSON.stringify({ status: 'error', message: 'Sunucu yoğun, kilit alınamadı — tekrar denenecek' }))
      .setMimeType(ContentService.MimeType.JSON);
  }

  try {
    var data = JSON.parse(e.postData.contents);

    if (data.type === 'katalog_bulk') {
      return saveKatalogBulk(data.entries || []);
    }
    if (data.type === 'katalog_item') {
      return saveKatalogItem(data.entry || {});
    }

    // ---- Normal sayım verisi ----
    var ss = SpreadsheetApp.getActiveSpreadsheet();
    var sheet = ss.getSheetByName('Sayim') || ss.getActiveSheet();

    var HEADERS = ['Tarih', 'Saat', 'Personel', 'Ürün Adı', 'Stok Kodu', 'Barkod', 'Birim', 'Eski Stok', 'Sayılan Adet', 'Fark', 'Oturum ID', 'Kayıt ID', 'Reyon'];
    if (sheet.getLastRow() === 0) {
      sheet.appendRow(HEADERS);
    }
    var idCol = HEADERS.indexOf('Kayıt ID');

    var personnel = data.personnel || '';
    var sessionId = data.sessionId || '';
    var rows = data.rows || [];

    var lastRow = sheet.getLastRow();
    var existing = {};
    if (lastRow > 1) {
      var values = sheet.getRange(2, 1, lastRow - 1, HEADERS.length).getValues();
      for (var i = 0; i < values.length; i++) {
        var key = values[i][idCol];
        if (key) existing[key] = i + 2;
      }
    }

    // Güncellenecek (mevcut) satırları ve yeni eklenecek satırları ayır.
    // Yeni satırları TEK seferde toplu ekliyoruz (appendRow'u döngüde tekrar
    // tekrar çağırmak yerine) — hem çok daha hızlı hem de sayfa büyüdükçe
    // (binlerce satır, 72 saatlik sayım) performansı korur.
    var newRows = [];
    rows.forEach(function (row) {
      var oldStock = (row.oldStock !== '' && row.oldStock !== undefined && !isNaN(Number(row.oldStock))) ? Number(row.oldStock) : '';
      var diff = oldStock !== '' ? (row.qty - oldStock) : '';
      var rowData = [row.date, row.time, personnel, row.name, row.stockCode || '', row.barcode, row.unit || 'Adet', oldStock, row.qty, diff, sessionId, row.id || '', row.reyon || ''];
      if (row.id && existing[row.id]) {
        sheet.getRange(existing[row.id], 1, 1, HEADERS.length).setValues([rowData]);
      } else {
        newRows.push(rowData);
      }
    });
    if (newRows.length > 0) {
      sheet.getRange(sheet.getLastRow() + 1, 1, newRows.length, HEADERS.length).setValues(newRows);
    }

    return ContentService
      .createTextOutput(JSON.stringify({ status: 'ok', processed: rows.length }))
      .setMimeType(ContentService.MimeType.JSON);

  } catch (err) {
    return ContentService
      .createTextOutput(JSON.stringify({ status: 'error', message: err.toString() }))
      .setMimeType(ContentService.MimeType.JSON);
  } finally {
    lock.releaseLock();
  }
}

function saveKatalogBulk(entries) {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sheet = ss.getSheetByName('Katalog');
  if (!sheet) sheet = ss.insertSheet('Katalog');
  sheet.clear();
  sheet.appendRow(['Ürün Adı', 'Barkod', 'Stok Kodu', 'Eski Stok']);
  if (entries.length > 0) {
    var rows = entries.map(function (e) {
      return [e.name || '', e.barcode || '', e.stockCode || '', e.oldStock || ''];
    });
    sheet.getRange(2, 1, rows.length, 4).setValues(rows);
  }
  return ContentService
    .createTextOutput(JSON.stringify({ status: 'ok', saved: entries.length }))
    .setMimeType(ContentService.MimeType.JSON);
}

function saveKatalogItem(entry) {
  if (!entry.barcode || !entry.name) {
    return ContentService.createTextOutput(JSON.stringify({ status: 'error', message: 'eksik veri' }))
      .setMimeType(ContentService.MimeType.JSON);
  }
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sheet = ss.getSheetByName('Katalog');
  if (!sheet) {
    sheet = ss.insertSheet('Katalog');
    sheet.appendRow(['Ürün Adı', 'Barkod', 'Stok Kodu', 'Eski Stok']);
  }
  var lastRow = sheet.getLastRow();
  var rowData = [entry.name, entry.barcode, entry.stockCode || '', entry.oldStock || ''];
  if (lastRow >= 2) {
    var barcodes = sheet.getRange(2, 2, lastRow - 1, 1).getValues();
    for (var i = 0; i < barcodes.length; i++) {
      if (String(barcodes[i][0]) === String(entry.barcode)) {
        sheet.getRange(i + 2, 1, 1, 4).setValues([rowData]);
        return ContentService.createTextOutput(JSON.stringify({ status: 'ok', updated: true }))
          .setMimeType(ContentService.MimeType.JSON);
      }
    }
  }
  sheet.appendRow(rowData);
  return ContentService
    .createTextOutput(JSON.stringify({ status: 'ok', added: true }))
    .setMimeType(ContentService.MimeType.JSON);
}

// ============================================================
// YÖNETİCİ: DOSYA TEMİZLEME
// 'Sayim' sekmesini önce 'Arsiv_TARİH' adıyla kopyalar (veri kaybolmaz),
// sonra boşaltır ve yeni bir RESET_TOKEN üretir. Telefonlar bu token'ı
// açılışta/online olduklarında kontrol edip değiştiğini görünce kendi
// yerel kuyruklarını (henüz gönderilmemiş / eski test taramaları) otomatik
// sıfırlar — "temizlendi ama eski taramalar geri geldi" sorunu budur.
// ============================================================
function handleTemizle(pin, callback) {
  if (!checkPin(pin)) return outJson({ status: 'error', message: 'Yanlış PIN' }, callback);
  var lock = LockService.getScriptLock();
  try { lock.waitLock(30000); } catch (e) { return outJson({ status: 'error', message: 'Sunucu meşgul, birazdan tekrar dene' }, callback); }
  try {
    var ss = SpreadsheetApp.getActiveSpreadsheet();
    var sheet = ss.getSheetByName('Sayim');
    var archivedName = '(arşivlenecek veri yoktu)';
    if (sheet && sheet.getLastRow() > 1) {
      archivedName = 'Arsiv_' + Utilities.formatDate(new Date(), Session.getScriptTimeZone() || 'GMT+3', 'yyyyMMdd_HHmm');
      var copy = sheet.copyTo(ss);
      copy.setName(archivedName);
    }
    if (sheet && sheet.getLastRow() > 1) {
      sheet.getRange(2, 1, sheet.getLastRow() - 1, sheet.getLastColumn()).clearContent();
    }
    var token = new Date().toISOString();
    PropertiesService.getScriptProperties().setProperty('RESET_TOKEN', token);
    return outJson({ status: 'ok', resetToken: token, archivedSheet: archivedName }, callback);
  } catch (err) {
    return outJson({ status: 'error', message: err.toString() }, callback);
  } finally {
    lock.releaseLock();
  }
}

// ============================================================
// YÖNETİCİ: SAYIMI SONLANDIR VE RAPOR OLUŞTUR
// - Aynı Stok Kodu (yoksa Barkod) altındaki tüm okutmaları TEK satıra
//   birleştirir; en son okutulan değeri "final" sayım olarak alır.
// - Ürün adını Katalog sekmesindeki kanonik isimle değiştirir (isim
//   düzeltme burada otomatik olur — ham 'Sayim' verisi hiç bozulmaz).
// - 'Son Stok Sayimi' sekmesine yazar.
// - 'Yönetici Raporu' sekmesine: ürün çeşidi, toplam adet, ortalama
//   doğruluk, personel bazlı hız, dikkat çeken farklar yazar ve bu
//   sekmeyi gizler (hideSheet) — sıradan kullanıcı sekme listesinde
//   görmez. NOT: Sheets'te gerçek "sadece yönetici görsün" ancak ayrı
//   bir dosyada / paylaşım kısıtlamasıyla garanti edilir; hideSheet
//   sadece kazara görülmeyi engeller, sıkı gizlilik değildir.
// - ANTHROPIC_API_KEY script özelliği ayarlıysa, dikkat çeken farklar
//   için kısa bir yapay zeka değerlendirmesi ister.
// ============================================================
function handleFinalize(pin, callback) {
  if (!checkPin(pin)) return outJson({ status: 'error', message: 'Yanlış PIN' }, callback);
  var lock = LockService.getScriptLock();
  try { lock.waitLock(30000); } catch (e) { return outJson({ status: 'error', message: 'Sunucu meşgul, birazdan tekrar dene' }, callback); }
  try {
    var ss = SpreadsheetApp.getActiveSpreadsheet();
    var HEADERS = ['Tarih', 'Saat', 'Personel', 'Ürün Adı', 'Stok Kodu', 'Barkod', 'Birim', 'Eski Stok', 'Sayılan Adet', 'Fark', 'Oturum ID', 'Kayıt ID', 'Reyon'];
    var sayimSheet = ss.getSheetByName('Sayim');
    var rows = [];
    if (sayimSheet && sayimSheet.getLastRow() > 1) {
      rows = sayimSheet.getRange(2, 1, sayimSheet.getLastRow() - 1, HEADERS.length).getValues();
    }
    if (rows.length === 0) return outJson({ status: 'error', message: 'Sayım tablosunda veri yok' }, callback);

    var idx = {}; HEADERS.forEach(function (h, i) { idx[h] = i; });

    // Katalog'dan kanonik isim eşlemesi (Stok Kodu öncelikli, yoksa Barkod)
    var canonByStock = {}, canonByBarcode = {};
    var katalogSheet = ss.getSheetByName('Katalog');
    if (katalogSheet && katalogSheet.getLastRow() >= 2) {
      var kv = katalogSheet.getRange(2, 1, katalogSheet.getLastRow() - 1, 4).getValues();
      kv.forEach(function (r) {
        var name = String(r[0] || '').trim(), barcode = String(r[1] || '').trim(), stock = String(r[2] || '').trim();
        if (stock && name && !canonByStock[stock]) canonByStock[stock] = name;
        if (barcode && name && !canonByBarcode[barcode]) canonByBarcode[barcode] = name;
      });
    }

    var groups = {};
    rows.forEach(function (r) {
      var stockCode = String(r[idx['Stok Kodu']] || '').trim();
      var barcode = String(r[idx['Barkod']] || '').trim();
      var key = stockCode || ('B:' + barcode);
      if (key === 'B:' || !key) return;
      var ts = String(r[idx['Tarih']]) + ' ' + String(r[idx['Saat']]);
      if (!groups[key]) {
        groups[key] = {
          stockCode: stockCode, barcode: barcode, name: String(r[idx['Ürün Adı']] || ''),
          unit: String(r[idx['Birim']] || 'Adet'), oldStock: r[idx['Eski Stok']],
          finalQty: Number(r[idx['Sayılan Adet']]) || 0, lastPersonnel: String(r[idx['Personel']] || ''),
          lastTs: ts, scanCount: 0
        };
      }
      groups[key].scanCount++;
      if (ts >= groups[key].lastTs) {
        groups[key].lastTs = ts;
        groups[key].finalQty = Number(r[idx['Sayılan Adet']]) || 0;
        groups[key].lastPersonnel = String(r[idx['Personel']] || '');
        if (r[idx['Eski Stok']] !== '' && r[idx['Eski Stok']] !== undefined) groups[key].oldStock = r[idx['Eski Stok']];
      }
    });

    var finalRows = [];
    var toplamAdet = 0, dogrulukToplam = 0, dogrulukSayisi = 0;
    var anomaliler = [];
    Object.keys(groups).forEach(function (key) {
      var g = groups[key];
      var canonName = (g.stockCode && canonByStock[g.stockCode]) || canonByBarcode[g.barcode] || g.name;
      var oldStockNum = (g.oldStock !== '' && g.oldStock !== undefined && !isNaN(Number(g.oldStock))) ? Number(g.oldStock) : null;
      var fark = oldStockNum !== null ? (g.finalQty - oldStockNum) : '';
      toplamAdet += g.finalQty;
      if (oldStockNum !== null && oldStockNum > 0) {
        var dogruluk = Math.max(0, 1 - Math.min(1, Math.abs(fark) / oldStockNum));
        dogrulukToplam += dogruluk; dogrulukSayisi++;
        if (Math.abs(fark) / oldStockNum > 0.3) {
          anomaliler.push(canonName + ' (Stok Kodu: ' + (g.stockCode || '-') + '): eski ' + oldStockNum + ', sayılan ' + g.finalQty + ', fark ' + fark);
        }
      }
      finalRows.push([g.stockCode, canonName, g.barcode, g.unit, oldStockNum === null ? '' : oldStockNum, g.finalQty, fark, g.lastPersonnel, g.lastTs, g.scanCount]);
    });

    var sonSheet = ss.getSheetByName('Son Stok Sayimi');
    if (!sonSheet) sonSheet = ss.insertSheet('Son Stok Sayimi'); else sonSheet.clear();
    sonSheet.appendRow(['Stok Kodu', 'Ürün Adı', 'Barkod', 'Birim', 'Eski Stok', 'Final Adet', 'Fark', 'Son Sayan', 'Son Zaman', 'Kaç Kez Okutuldu']);
    if (finalRows.length > 0) sonSheet.getRange(2, 1, finalRows.length, finalRows[0].length).setValues(finalRows);

    var personelStats = {};
    rows.forEach(function (r) {
      var p = String(r[idx['Personel']] || '—');
      var ts = String(r[idx['Tarih']]) + ' ' + String(r[idx['Saat']]);
      if (!personelStats[p]) personelStats[p] = { satir: 0, ilkTs: ts, sonTs: ts, urunler: {} };
      personelStats[p].satir++;
      if (ts < personelStats[p].ilkTs) personelStats[p].ilkTs = ts;
      if (ts > personelStats[p].sonTs) personelStats[p].sonTs = ts;
      var stockKey = String(r[idx['Stok Kodu']] || '') || ('B:' + String(r[idx['Barkod']] || ''));
      personelStats[p].urunler[stockKey] = true;
    });

    var raporSheet = ss.getSheetByName('Yönetici Raporu');
    if (!raporSheet) raporSheet = ss.insertSheet('Yönetici Raporu'); else raporSheet.clear();
    var ortalamaDogruluk = dogrulukSayisi > 0 ? Math.round((dogrulukToplam / dogrulukSayisi) * 1000) / 10 : null;

    raporSheet.appendRow(['MURAT GIDA — SAYIM YÖNETİCİ RAPORU', Utilities.formatDate(new Date(), Session.getScriptTimeZone() || 'GMT+3', 'yyyy-MM-dd HH:mm')]);
    raporSheet.appendRow([]);
    raporSheet.appendRow(['Toplam farklı ürün çeşidi', Object.keys(groups).length]);
    raporSheet.appendRow(['Toplam sayılan adet (final, birleştirilmiş)', toplamAdet]);
    raporSheet.appendRow(['Toplam okutma (ham satır) sayısı', rows.length]);
    raporSheet.appendRow(['Ortalama doğruluk (eski stoğa göre)', ortalamaDogruluk !== null ? ('%' + ortalamaDogruluk) : '—']);
    raporSheet.appendRow([]);
    raporSheet.appendRow(['PERSONEL BAZLI']);
    raporSheet.appendRow(['Personel', 'Okutma Sayısı', 'Farklı Ürün', 'İlk Kayıt', 'Son Kayıt', 'Süre (saat)', 'Hız (okutma/saat)']);
    Object.keys(personelStats).forEach(function (p) {
      var s = personelStats[p];
      var sureSaat = Math.max((new Date(s.sonTs) - new Date(s.ilkTs)) / 3600000, 0.05);
      var hiz = Math.round((s.satir / sureSaat) * 10) / 10;
      raporSheet.appendRow([p, s.satir, Object.keys(s.urunler).length, s.ilkTs, s.sonTs, Math.round(sureSaat * 10) / 10, hiz]);
    });
    raporSheet.appendRow([]);
    raporSheet.appendRow(['DİKKAT ÇEKEN FARKLAR (eski stoğa göre %30+ sapma)']);
    if (anomaliler.length === 0) raporSheet.appendRow(['(yok)']);
    anomaliler.forEach(function (a) { raporSheet.appendRow([a]); });

    var aiYorum = '';
    var apiKey = PropertiesService.getScriptProperties().getProperty('ANTHROPIC_API_KEY');
    if (apiKey && anomaliler.length > 0) {
      try {
        aiYorum = getAiYorum(apiKey, anomaliler, Object.keys(groups).length, toplamAdet, ortalamaDogruluk);
        if (aiYorum) {
          raporSheet.appendRow([]);
          raporSheet.appendRow(['YAPAY ZEKA DEĞERLENDİRMESİ']);
          raporSheet.appendRow([aiYorum]);
        }
      } catch (aiErr) {
        raporSheet.appendRow(['YAPAY ZEKA DEĞERLENDİRMESİ (çalışmadı: ' + aiErr + ')']);
      }
    }

    try { raporSheet.hideSheet(); } catch (hideErr) { /* önemli değil */ }

    return outJson({
      status: 'ok',
      toplamCesit: Object.keys(groups).length,
      toplamAdet: toplamAdet,
      ortalamaDogruluk: ortalamaDogruluk !== null ? ortalamaDogruluk : '—',
      anomaliSayisi: anomaliler.length,
      aiYorum: aiYorum
    }, callback);
  } catch (err) {
    return outJson({ status: 'error', message: err.toString() }, callback);
  } finally {
    lock.releaseLock();
  }
}

// Dikkat çeken farkları kısaca Türkçe yorumlatmak için Anthropic API'ye
// istek atar. ANTHROPIC_API_KEY ayarlı değilse handleFinalize bu fonksiyonu
// hiç çağırmaz — anahtar yoksa rapor, yapay zeka bölümü olmadan üretilir.
function getAiYorum(apiKey, anomaliler, cesit, adet, dogruluk) {
  var prompt = 'Bir market sayım raporunu değerlendiriyorsun. Toplam ürün çeşidi: ' + cesit +
    ', toplam sayılan adet: ' + adet + ', ortalama doğruluk: %' + dogruluk + '.\n' +
    'Dikkat çeken farklar:\n' + anomaliler.slice(0, 30).join('\n') + '\n\n' +
    'Bu verilere bakarak yöneticiye 3-4 cümlelik, Türkçe, aksiyon odaklı kısa bir değerlendirme yaz ' +
    '(hangi ürünlere öncelikle bakılmalı, olası sayım hatası mı yoksa gerçek stok kaybı mı olabilir).';
  var res = UrlFetchApp.fetch('https://api.anthropic.com/v1/messages', {
    method: 'post',
    contentType: 'application/json',
    headers: { 'x-api-key': apiKey, 'anthropic-version': '2023-06-01' },
    payload: JSON.stringify({ model: 'claude-sonnet-5', max_tokens: 400, messages: [{ role: 'user', content: prompt }] }),
    muteHttpExceptions: true
  });
  var body = JSON.parse(res.getContentText());
  if (body.content && body.content[0] && body.content[0].text) return body.content[0].text.trim();
  return '';
}

// ============================================================
// KULLANICI YÖNETİMİ — hangi personel "kullanıcı", hangisi "yönetici"
// Yönetici Paneli'ndeki PIN gerçek yetki kontrolüdür; buradaki rol bilgisi
// sadece kimin "⚙ Yönetici Paneli" bağlantısını görüp göremeyeceğini
// belirler (kazara tıklamayı önler) — PIN olmadan hiçbir işlem yapılamaz.
// ============================================================
function getKullanicilar(callback) {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sheet = ss.getSheetByName('Kullanicilar');
  var users = [];
  if (sheet && sheet.getLastRow() >= 2) {
    var values = sheet.getRange(2, 1, sheet.getLastRow() - 1, 3).getValues();
    users = values.filter(function (r) { return r[0]; }).map(function (r) {
      return {
        name: String(r[0]).trim(),
        role: String(r[1] || 'kullanici').trim().toLowerCase() === 'yonetici' ? 'yonetici' : 'kullanici',
        active: String(r[2] || 'evet').trim().toLowerCase() !== 'hayir'
      };
    });
  }
  return outJson({ users: users }, callback);
}

// data: "Ad;Rol" formatında, her satırda bir kullanıcı (Rol: "yonetici" ya
// da boş/"kullanici"). Tüm listeyi tek seferde değiştirir (Katalog yükleme
// mantığıyla aynı — admin panelinde tek bir metin kutusuna yapıştırılır).
function handleKullanicilarKaydet(pin, data, callback) {
  if (!checkPin(pin)) return outJson({ status: 'error', message: 'Yanlış PIN' }, callback);
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sheet = ss.getSheetByName('Kullanicilar');
  if (!sheet) sheet = ss.insertSheet('Kullanicilar');
  sheet.clear();
  sheet.appendRow(['Ad', 'Rol', 'Aktif']);
  var lines = String(data || '').split('\n');
  var rows = [];
  lines.forEach(function (line) {
    line = line.trim();
    if (!line) return;
    var parts = line.split(';');
    var name = (parts[0] || '').trim();
    if (!name) return;
    var role = (parts[1] || 'kullanici').trim().toLowerCase();
    if (role !== 'yonetici') role = 'kullanici';
    rows.push([name, role, 'evet']);
  });
  if (rows.length > 0) sheet.getRange(2, 1, rows.length, 3).setValues(rows);
  return outJson({ status: 'ok', saved: rows.length }, callback);
}

// ============================================================
// AYARLAR — şimdilik tek ayar: sayım sırasında telefon ekranının açık
// kalıp kalmayacağı (varsayılan). Her telefon kendi ekranında bunu elle
// de değiştirebilir; buradaki değer sadece yeni açılan / hiç
// değiştirilmemiş telefonlar için varsayılanı belirler.
// ============================================================
function handleAyarKaydet(pin, wakelock, callback) {
  if (!checkPin(pin)) return outJson({ status: 'error', message: 'Yanlış PIN' }, callback);
  PropertiesService.getScriptProperties().setProperty('DEFAULT_WAKE_LOCK', wakelock === 'false' ? 'false' : 'true');
  return outJson({ status: 'ok' }, callback);
}
