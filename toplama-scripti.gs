function doGet(e) {
  return ContentService
    .createTextOutput('Sayım toplama servisi çalışıyor ✅ (' + new Date().toISOString() + ')')
    .setMimeType(ContentService.MimeType.TEXT);
}

function doPost(e) {
  try {
    var data = JSON.parse(e.postData.contents);
    var ss = SpreadsheetApp.getActiveSpreadsheet();
    var sheet = ss.getSheetByName('Sayim') || ss.getActiveSheet();

    var HEADERS = ['Tarih', 'Saat', 'Personel', 'Ürün Adı', 'Stok Kodu', 'Barkod', 'Birim', 'Eski Stok', 'Sayılan Adet', 'Fark', 'Oturum ID', 'Kayıt ID'];
    if (sheet.getLastRow() === 0) {
      sheet.appendRow(HEADERS);
    }
    var idCol = HEADERS.indexOf('Kayıt ID'); // 0-index

    var personnel = data.personnel || '';
    var sessionId = data.sessionId || '';
    var rows = data.rows || [];

    // Her okutma kendi EŞSİZ KAYIT ID'si ile tek satır olarak kalır — aynı
    // ürün/barkod tekrar okutulsa bile birleştirilmez, yeni satır olur.
    // Sadece aynı kayıt (id) tekrar gönderilirse (elle düzeltme sonrası),
    // o satır güncellenir; kopya oluşmaz.
    var lastRow = sheet.getLastRow();
    var existing = {};
    if (lastRow > 1) {
      var values = sheet.getRange(2, 1, lastRow - 1, HEADERS.length).getValues();
      for (var i = 0; i < values.length; i++) {
        var key = values[i][idCol];
        if (key) existing[key] = i + 2; // gerçek sayfa satır numarası
      }
    }

    rows.forEach(function (row) {
      var oldStock = (row.oldStock !== '' && row.oldStock !== undefined && !isNaN(Number(row.oldStock))) ? Number(row.oldStock) : '';
      var diff = oldStock !== '' ? (row.qty - oldStock) : '';
      var rowData = [row.date, row.time, personnel, row.name, row.stockCode || '', row.barcode, row.unit || 'Adet', oldStock, row.qty, diff, sessionId, row.id || ''];
      if (row.id && existing[row.id]) {
        sheet.getRange(existing[row.id], 1, 1, HEADERS.length).setValues([rowData]); // düzelt
      } else {
        sheet.appendRow(rowData); // yeni, ayrı satır
        if (row.id) existing[row.id] = sheet.getLastRow();
      }
    });

    return ContentService
      .createTextOutput(JSON.stringify({ status: 'ok', processed: rows.length }))
      .setMimeType(ContentService.MimeType.JSON);

  } catch (err) {
    return ContentService
      .createTextOutput(JSON.stringify({ status: 'error', message: err.toString() }))
      .setMimeType(ContentService.MimeType.JSON);
  }
}
