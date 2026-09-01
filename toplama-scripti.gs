/**
 * MURAT GIDA - SAYIM TOPLAMA SERVİSİ
 * Bu dosyanın tamamını Apps Script'e yapıştırın (eski kodun üzerine, hiçbir
 * satır kalmayacak şekilde tamamen silip baştan yapıştırın).
 */

function doGet(e) {
  // ?action=katalog ile ürün kataloğunu döndürür.
  // ?callback=xxx varsa (uygulama içinden <script> etiketiyle çağrılır),
  // JSONP formatında sarıp döner — CORS kısıtlamasına hiç takılmadan çalışır.
  if (e.parameter && e.parameter.action === 'katalog') {
    return getKatalog(e.parameter.callback);
  }
  return ContentService
    .createTextOutput('Sayım toplama servisi çalışıyor ✅ (' + new Date().toISOString() + ')')
    .setMimeType(ContentService.MimeType.TEXT);
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

    var HEADERS = ['Tarih', 'Saat', 'Personel', 'Ürün Adı', 'Stok Kodu', 'Barkod', 'Birim', 'Eski Stok', 'Sayılan Adet', 'Fark', 'Oturum ID', 'Kayıt ID'];
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
      var rowData = [row.date, row.time, personnel, row.name, row.stockCode || '', row.barcode, row.unit || 'Adet', oldStock, row.qty, diff, sessionId, row.id || ''];
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
