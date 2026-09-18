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
  // ---- Giriş / yetkilendirme ----
  if (e.parameter && e.parameter.action === 'login') {
    return handleLogin(e.parameter.user, e.parameter.pass, e.parameter.callback);
  }
  if (e.parameter && e.parameter.action === 'resetcheck') {
    return outJson({
      resetToken: PropertiesService.getScriptProperties().getProperty('RESET_TOKEN') || '',
      defaultWakeLock: PropertiesService.getScriptProperties().getProperty('DEFAULT_WAKE_LOCK') || 'true',
      idleMinutes: PropertiesService.getScriptProperties().getProperty('DEFAULT_IDLE_MINUTES') || '0'
    }, e.parameter.callback);
  }
  if (e.parameter && e.parameter.action === 'temizle') {
    return handleTemizle(e.parameter.user, e.parameter.pass, e.parameter.callback);
  }
  if (e.parameter && e.parameter.action === 'finalize') {
    return handleFinalize(e.parameter.user, e.parameter.pass, e.parameter.callback);
  }
  if (e.parameter && e.parameter.action === 'kullanicilar') {
    return getKullanicilar(e.parameter.callback);
  }
  if (e.parameter && e.parameter.action === 'kullanicilar_detay') {
    return getKullanicilarDetay(e.parameter.user, e.parameter.pass, e.parameter.callback);
  }
  if (e.parameter && e.parameter.action === 'kullanicilar_kaydet') {
    return handleKullanicilarKaydet(e.parameter.user, e.parameter.pass, e.parameter.data, e.parameter.callback);
  }
  if (e.parameter && e.parameter.action === 'ayar_kaydet') {
    return handleAyarKaydet(e.parameter.user, e.parameter.pass, e.parameter.wakelock, e.parameter.idleMinutes, e.parameter.callback);
  }
  if (e.parameter && e.parameter.action === 'son_stok_getir') {
    return getSonStokGetir(e.parameter.user, e.parameter.pass, e.parameter.callback);
  }
  if (e.parameter && e.parameter.action === 'canli_durum') {
    return getCanliDurum(e.parameter.user, e.parameter.pass, e.parameter.callback);
  }
  if (e.parameter && e.parameter.action === 'sayim_ara') {
    return sayimAra(e.parameter.user, e.parameter.pass, e.parameter.q, e.parameter.callback);
  }
  if (e.parameter && e.parameter.action === 'sayim_guncelle') {
    return sayimGuncelle(e.parameter.user, e.parameter.pass, e.parameter.kayitId, e.parameter.adet, e.parameter.callback);
  }
  if (e.parameter && e.parameter.action === 'sayim_sil') {
    return sayimSil(e.parameter.user, e.parameter.pass, e.parameter.kayitId, e.parameter.callback);
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

// ============================================================
// GİRİŞ / YETKİLENDİRME
// 'Kullanicilar' sekmesi: Ad | Şifre | Rol | Yetkiler | Aktif
// Rol "yonetici" ise TÜM yetkiler otomatik verilir. Rol "kullanici" ise
// sadece Yetkiler sütununda yazılanlar (virgülle ayrılmış:
// rapor, temizle, kullanici_yonetimi, ayarlar) geçerlidir.
// "admin" / "admin", sekmede ADI "admin" olan bir satır TANIMLANMADIĞI
// SÜRECE her zaman yedek bir giriştir (sadece sekme boşken değil) —
// böylece daha önce başka isimlerle kullanıcı eklenmiş olsa bile ilk kurulum
// kilitlenmez. Bir kişi "admin" adıyla kaydedilip farklı bir şifre
// verildiğinde, o satır geçerli olur ve bu yedek devre dışı kalır. NOT:
// Şifreler düz metin olarak saklanır (Apps Script'in sunduğu basit bir
// koruma) — kurumsal güvenlik seviyesinde değildir, sadece ekip içi
// yetkilendirme için yeterlidir. Tabloyu düzenleme yetkisi olan herkes
// şifreleri görebilir.
// ============================================================
var ALL_PERMS = ['rapor', 'temizle', 'kullanici_yonetimi', 'ayarlar', 'canli_durum', 'duzelt'];

function authenticate(user, pass) {
  user = String(user || '').trim();
  pass = String(pass || '');
  if (!user) return { ok: false, message: 'Kullanıcı adı gir' };
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sheet = ss.getSheetByName('Kullanicilar');
  if (sheet && sheet.getLastRow() >= 2) {
    var values = sheet.getRange(2, 1, sheet.getLastRow() - 1, 5).getValues();
    for (var i = 0; i < values.length; i++) {
      var name = String(values[i][0] || '').trim();
      if (name.toLowerCase() !== user.toLowerCase()) continue;
      var pw = String(values[i][1] || '');
      var role = String(values[i][2] || 'kullanici').trim().toLowerCase() === 'yonetici' ? 'yonetici' : 'kullanici';
      var yetkiler = String(values[i][3] || '').split(',').map(function (s) { return s.trim(); }).filter(Boolean);
      var active = String(values[i][4] || 'evet').trim().toLowerCase() !== 'hayir';
      if (!active) return { ok: false, message: 'Bu kullanıcı pasif duruma alınmış' };
      if (pw !== pass) return { ok: false, message: 'Şifre yanlış' };
      return { ok: true, role: role, permissions: role === 'yonetici' ? ALL_PERMS : yetkiler };
    }
  }
  // Listede "admin" adında bir satır yok — yedek girişi dene.
  if (user.toLowerCase() === 'admin' && pass === 'admin') {
    return { ok: true, role: 'yonetici', permissions: ALL_PERMS, bootstrap: true };
  }
  return { ok: false, message: 'Kullanıcı bulunamadı' };
}

function requirePermission(user, pass, perm) {
  var auth = authenticate(user, pass);
  if (!auth.ok) return auth;
  if (auth.permissions.indexOf(perm) === -1) return { ok: false, message: 'Bu işlem için yetkin yok' };
  return auth;
}

function handleLogin(user, pass, callback) {
  var auth = authenticate(user, pass);
  if (!auth.ok) return outJson({ status: 'error', message: auth.message }, callback);
  // Yedek (bootstrap) admin/admin girişinde kalıcı bir "admin" satırı
  // oluştur ki Kullanıcı Yönetimi ekranında görünsün ve şifresi
  // değiştirilebilsin — sheet boş olsun ya da başka kullanıcılar zaten
  // tanımlanmış olsun fark etmez, authenticate() zaten "admin" adında bir
  // satır YOKSA bootstrap döndürür.
  if (auth.bootstrap) {
    try {
      var ss = SpreadsheetApp.getActiveSpreadsheet();
      var sheet = ss.getSheetByName('Kullanicilar');
      if (!sheet) sheet = ss.insertSheet('Kullanicilar');
      if (sheet.getLastRow() < 1) sheet.appendRow(['Ad', 'Şifre', 'Rol', 'Yetkiler', 'Aktif']);
      sheet.appendRow(['admin', 'admin', 'yonetici', '', 'evet']);
    } catch (e) { /* kritik değil, bir sonraki girişte tekrar denenir */ }
  }
  return outJson({ status: 'ok', role: auth.role, permissions: auth.permissions }, callback);
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
function handleTemizle(user, pass, callback) {
  var auth = requirePermission(user, pass, 'temizle');
  if (!auth.ok) return outJson({ status: 'error', message: auth.message }, callback);
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
function handleFinalize(user, pass, callback) {
  var auth = requirePermission(user, pass, 'rapor');
  if (!auth.ok) return outJson({ status: 'error', message: auth.message }, callback);
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
    var personelListesi = [];
    Object.keys(personelStats).forEach(function (p) {
      var s = personelStats[p];
      var sureSaat = Math.max((new Date(s.sonTs) - new Date(s.ilkTs)) / 3600000, 0.05);
      var hiz = Math.round((s.satir / sureSaat) * 10) / 10;
      raporSheet.appendRow([p, s.satir, Object.keys(s.urunler).length, s.ilkTs, s.sonTs, Math.round(sureSaat * 10) / 10, hiz]);
      personelListesi.push({ personel: p, okutma: s.satir, farkliUrun: Object.keys(s.urunler).length, hiz: hiz });
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
      anomaliler: anomaliler.slice(0, 40),
      personelListesi: personelListesi,
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
// KULLANICI YÖNETİMİ
// getKullanicilar: herkese açık, sadece isim + aktiflik döner (giriş
// ekranındaki kullanıcı adı otomatik tamamlama için) — şifre/rol/yetki
// İÇERMEZ, böylece her telefonun önbelleğinde başkalarının şifresi
// birikmez.
// getKullanicilarDetay: SADECE 'kullanici_yonetimi' yetkisi olan biri
// çağırabilir, tam listeyi (şifreler dahil) döner — Yönetici Paneli'nde
// listeyi düzenlerken mevcut hâlini göstermek için kullanılır.
// ============================================================
function getKullanicilar(callback) {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sheet = ss.getSheetByName('Kullanicilar');
  var users = [];
  if (sheet && sheet.getLastRow() >= 2) {
    var values = sheet.getRange(2, 1, sheet.getLastRow() - 1, 5).getValues();
    users = values.filter(function (r) { return r[0]; }).map(function (r) {
      return { name: String(r[0]).trim(), active: String(r[4] || 'evet').trim().toLowerCase() !== 'hayir' };
    });
  }
  return outJson({ users: users }, callback);
}

function getKullanicilarDetay(user, pass, callback) {
  var auth = requirePermission(user, pass, 'kullanici_yonetimi');
  if (!auth.ok) return outJson({ status: 'error', message: auth.message }, callback);
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sheet = ss.getSheetByName('Kullanicilar');
  var users = [];
  if (sheet && sheet.getLastRow() >= 2) {
    var values = sheet.getRange(2, 1, sheet.getLastRow() - 1, 5).getValues();
    users = values.filter(function (r) { return r[0]; }).map(function (r) {
      return {
        name: String(r[0]).trim(), pass: String(r[1] || ''),
        role: String(r[2] || 'kullanici').trim().toLowerCase() === 'yonetici' ? 'yonetici' : 'kullanici',
        yetkiler: String(r[3] || ''), active: String(r[4] || 'evet').trim().toLowerCase() !== 'hayir'
      };
    });
  }
  return outJson({ status: 'ok', users: users }, callback);
}

// data: "Ad;Şifre;Rol;Yetkiler;Aktif" formatında, her satırda bir kullanıcı.
// Rol "yonetici" ya da boş/"kullanici" olabilir; Yetkiler sadece rol
// "kullanici" iken anlamlıdır (rapor,temizle,kullanici_yonetimi,ayarlar,
// canli_durum,duzelt arasından virgülle ayrılmış bir alt küme). Aktif
// "evet"/"hayir" — boş bırakılırsa "evet" sayılır (geriye dönük uyumluluk).
// Tüm listeyi tek seferde değiştirir — düzenlerken önce getKullanicilarDetay
// ile mevcut hâli çekip üstüne yazman gerekir (Katalog yükleme mantığıyla
// aynı). LockService ile korunur: iki yönetici aynı anda kaydederse biri
// diğerini beklemeden ezmesin diye.
function handleKullanicilarKaydet(user, pass, data, callback) {
  var auth = requirePermission(user, pass, 'kullanici_yonetimi');
  if (!auth.ok) return outJson({ status: 'error', message: auth.message }, callback);
  var lock = LockService.getScriptLock();
  try { lock.waitLock(30000); } catch (e) { return outJson({ status: 'error', message: 'Sunucu meşgul, birazdan tekrar dene' }, callback); }
  try {
    var ss = SpreadsheetApp.getActiveSpreadsheet();
    var sheet = ss.getSheetByName('Kullanicilar');
    if (!sheet) sheet = ss.insertSheet('Kullanicilar');
    sheet.clear();
    sheet.appendRow(['Ad', 'Şifre', 'Rol', 'Yetkiler', 'Aktif']);
    var lines = String(data || '').split('\n');
    var rows = [];
    lines.forEach(function (line) {
      line = line.trim();
      if (!line) return;
      var parts = line.split(';');
      var name = (parts[0] || '').trim();
      if (!name) return;
      var passw = (parts[1] || '').trim();
      var role = (parts[2] || 'kullanici').trim().toLowerCase();
      if (role !== 'yonetici') role = 'kullanici';
      var yetkiler = (parts[3] || '').trim();
      var aktif = (parts[4] || 'evet').trim().toLowerCase();
      if (aktif !== 'hayir') aktif = 'evet';
      rows.push([name, passw, role, yetkiler, aktif]);
    });
    if (rows.length > 0) sheet.getRange(2, 1, rows.length, 5).setValues(rows);
    return outJson({ status: 'ok', saved: rows.length }, callback);
  } catch (err) {
    return outJson({ status: 'error', message: err.toString() }, callback);
  } finally {
    lock.releaseLock();
  }
}

// ============================================================
// AYARLAR
// - DEFAULT_WAKE_LOCK: sayım sırasında telefon ekranının açık kalıp
//   kalmayacağı (varsayılan).
// - DEFAULT_IDLE_MINUTES: kaç dakika hiç dokunulmazsa ekranın kendi
//   haline (kararmaya) bırakılacağı — 0 ise devre dışı, hiç kapanmaz.
// Her telefon kendi ekranında bunu elle de değiştirebilir; buradaki değer
// sadece yeni açılan / hiç değiştirilmemiş telefonlar için varsayılanı
// belirler.
// ============================================================
function handleAyarKaydet(user, pass, wakelock, idleMinutes, callback) {
  var auth = requirePermission(user, pass, 'ayarlar');
  if (!auth.ok) return outJson({ status: 'error', message: auth.message }, callback);
  var props = PropertiesService.getScriptProperties();
  props.setProperty('DEFAULT_WAKE_LOCK', wakelock === 'false' ? 'false' : 'true');
  var mins = parseInt(idleMinutes, 10);
  if (isNaN(mins) || mins < 0) mins = 0;
  props.setProperty('DEFAULT_IDLE_MINUTES', String(mins));
  return outJson({ status: 'ok' }, callback);
}

// ============================================================
// SON STOK SAYIMINI İNDİRME (CSV için veri kaynağı)
// "Sayımı Bitir ve Rapor Oluştur" ile üretilen 'Son Stok Sayimi' sekmesini
// JSON olarak döner — istemci bunu CSV'ye çevirip telefona indirir.
// ============================================================
function getSonStokGetir(user, pass, callback) {
  var auth = requirePermission(user, pass, 'rapor');
  if (!auth.ok) return outJson({ status: 'error', message: auth.message }, callback);
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sheet = ss.getSheetByName('Son Stok Sayimi');
  var headers = [];
  var rows = [];
  if (sheet && sheet.getLastRow() >= 1) {
    headers = sheet.getRange(1, 1, 1, sheet.getLastColumn()).getValues()[0].map(String);
    if (sheet.getLastRow() >= 2) {
      rows = sheet.getRange(2, 1, sheet.getLastRow() - 1, sheet.getLastColumn()).getValues();
    }
  }
  return outJson({ status: 'ok', headers: headers, rows: rows }, callback);
}

// ============================================================
// CANLI DURUM
// 'Sayim' sekmesindeki TÜM ham satırlardan, her personelin en son ne zaman
// okutma yaptığını ve o ana kadar kaç farklı ürün / toplam kaç okutma
// yaptığını çıkarır. Gerçek "şu an aktif mi" bilgisi yok (telefonlar
// heartbeat göndermiyor) — bunun yerine en son okutma zamanını "aktif/son
// görülme" göstergesi olarak sunuyoruz: 10 dakikadan yeniyse muhtemelen hâlâ
// sayıyor, değilse durmuş/molada demektir.
// ============================================================
function getCanliDurum(user, pass, callback) {
  var auth = requirePermission(user, pass, 'canli_durum');
  if (!auth.ok) return outJson({ status: 'error', message: auth.message }, callback);
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sheet = ss.getSheetByName('Sayim');
  var HEADERS = ['Tarih', 'Saat', 'Personel', 'Ürün Adı', 'Stok Kodu', 'Barkod', 'Birim', 'Eski Stok', 'Sayılan Adet', 'Fark', 'Oturum ID', 'Kayıt ID', 'Reyon'];
  var idx = {}; HEADERS.forEach(function (h, i) { idx[h] = i; });
  var stats = {};
  if (sheet && sheet.getLastRow() >= 2) {
    var values = sheet.getRange(2, 1, sheet.getLastRow() - 1, HEADERS.length).getValues();
    values.forEach(function (r) {
      var p = String(r[idx['Personel']] || '—');
      var tsStr = String(r[idx['Tarih']]) + 'T' + String(r[idx['Saat']]);
      var ts = new Date(tsStr).getTime();
      if (!stats[p]) stats[p] = { okutma: 0, urunler: {}, sonTs: 0, sonZaman: '', sonUrun: '', sonReyon: '' };
      stats[p].okutma++;
      var stockKey = String(r[idx['Stok Kodu']] || '') || ('B:' + String(r[idx['Barkod']] || ''));
      stats[p].urunler[stockKey] = true;
      if (!isNaN(ts) && ts >= stats[p].sonTs) {
        stats[p].sonTs = ts;
        stats[p].sonZaman = String(r[idx['Tarih']]) + ' ' + String(r[idx['Saat']]);
        stats[p].sonUrun = String(r[idx['Ürün Adı']] || '');
        stats[p].sonReyon = String(r[idx['Reyon']] || '');
      }
    });
  }
  var now = new Date().getTime();
  var personeller = Object.keys(stats).map(function (p) {
    var s = stats[p];
    var dakikaOnce = s.sonTs ? Math.round((now - s.sonTs) / 60000) : null;
    return {
      personel: p, okutma: s.okutma, farkliUrun: Object.keys(s.urunler).length,
      sonZaman: s.sonZaman, sonUrun: s.sonUrun, sonReyon: s.sonReyon,
      dakikaOnce: dakikaOnce, aktif: dakikaOnce !== null && dakikaOnce <= 10
    };
  }).sort(function (a, b) { return (a.dakikaOnce === null ? 999999 : a.dakikaOnce) - (b.dakikaOnce === null ? 999999 : b.dakikaOnce); });
  return outJson({ status: 'ok', personeller: personeller }, callback);
}

// ============================================================
// SAYIM KAYITLARINI DÜZELTME
// sayimAra: ürün adı / personel / barkod / stok koduna göre ham 'Sayim'
// satırlarını arar (q boşsa en son 50 kaydı döner). sayimGuncelle: bir
// kaydın adedini değiştirir (Farkı da yeniden hesaplar). sayimSil: bir
// kaydı tamamen siler. Hepsi 'Kayıt ID' üzerinden çalışır — bu kolon her
// satır için benzersizdir (doPost sırasında telefon tarafında üretilir).
// ============================================================
function sayimAra(user, pass, q, callback) {
  var auth = requirePermission(user, pass, 'duzelt');
  if (!auth.ok) return outJson({ status: 'error', message: auth.message }, callback);
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sheet = ss.getSheetByName('Sayim');
  var HEADERS = ['Tarih', 'Saat', 'Personel', 'Ürün Adı', 'Stok Kodu', 'Barkod', 'Birim', 'Eski Stok', 'Sayılan Adet', 'Fark', 'Oturum ID', 'Kayıt ID', 'Reyon'];
  var idx = {}; HEADERS.forEach(function (h, i) { idx[h] = i; });
  var sonuc = [];
  if (sheet && sheet.getLastRow() >= 2) {
    var values = sheet.getRange(2, 1, sheet.getLastRow() - 1, HEADERS.length).getValues();
    var kelimeler = String(q || '').trim().toLowerCase().split(/\s+/).filter(Boolean);
    for (var i = values.length - 1; i >= 0 && sonuc.length < 100; i--) {
      var r = values[i];
      if (kelimeler.length > 0) {
        var hedef = (String(r[idx['Ürün Adı']] || '') + ' ' + String(r[idx['Personel']] || '') + ' ' + String(r[idx['Barkod']] || '') + ' ' + String(r[idx['Stok Kodu']] || '')).toLowerCase();
        var hepsiVar = kelimeler.every(function (k) { return hedef.indexOf(k) !== -1; });
        if (!hepsiVar) continue;
      }
      sonuc.push({
        kayitId: String(r[idx['Kayıt ID']] || ''), tarih: String(r[idx['Tarih']] || ''), saat: String(r[idx['Saat']] || ''),
        personel: String(r[idx['Personel']] || ''), ad: String(r[idx['Ürün Adı']] || ''), stokKodu: String(r[idx['Stok Kodu']] || ''),
        barkod: String(r[idx['Barkod']] || ''), birim: String(r[idx['Birim']] || 'Adet'), eskiStok: r[idx['Eski Stok']],
        adet: r[idx['Sayılan Adet']], fark: r[idx['Fark']], reyon: String(r[idx['Reyon']] || '')
      });
      if (kelimeler.length === 0 && sonuc.length >= 50) break;
    }
  }
  return outJson({ status: 'ok', sonuclar: sonuc }, callback);
}

function sayimGuncelle(user, pass, kayitId, adet, callback) {
  var auth = requirePermission(user, pass, 'duzelt');
  if (!auth.ok) return outJson({ status: 'error', message: auth.message }, callback);
  if (!kayitId) return outJson({ status: 'error', message: 'Kayıt ID eksik' }, callback);
  var yeniAdet = parseFloat(adet);
  if (isNaN(yeniAdet) || yeniAdet < 0) return outJson({ status: 'error', message: 'Geçersiz adet' }, callback);
  var lock = LockService.getScriptLock();
  try { lock.waitLock(30000); } catch (e) { return outJson({ status: 'error', message: 'Sunucu meşgul, birazdan tekrar dene' }, callback); }
  try {
    var ss = SpreadsheetApp.getActiveSpreadsheet();
    var sheet = ss.getSheetByName('Sayim');
    var HEADERS = ['Tarih', 'Saat', 'Personel', 'Ürün Adı', 'Stok Kodu', 'Barkod', 'Birim', 'Eski Stok', 'Sayılan Adet', 'Fark', 'Oturum ID', 'Kayıt ID', 'Reyon'];
    var idx = {}; HEADERS.forEach(function (h, i) { idx[h] = i; });
    if (!sheet || sheet.getLastRow() < 2) return outJson({ status: 'error', message: 'Kayıt bulunamadı' }, callback);
    var values = sheet.getRange(2, 1, sheet.getLastRow() - 1, HEADERS.length).getValues();
    for (var i = 0; i < values.length; i++) {
      if (String(values[i][idx['Kayıt ID']]) === String(kayitId)) {
        var rowNum = i + 2;
        var eskiStok = values[i][idx['Eski Stok']];
        var fark = (eskiStok !== '' && eskiStok !== undefined && !isNaN(Number(eskiStok))) ? (yeniAdet - Number(eskiStok)) : '';
        sheet.getRange(rowNum, idx['Sayılan Adet'] + 1).setValue(yeniAdet);
        sheet.getRange(rowNum, idx['Fark'] + 1).setValue(fark);
        return outJson({ status: 'ok' }, callback);
      }
    }
    return outJson({ status: 'error', message: 'Kayıt bulunamadı (silinmiş olabilir)' }, callback);
  } catch (err) {
    return outJson({ status: 'error', message: err.toString() }, callback);
  } finally {
    lock.releaseLock();
  }
}

function sayimSil(user, pass, kayitId, callback) {
  var auth = requirePermission(user, pass, 'duzelt');
  if (!auth.ok) return outJson({ status: 'error', message: auth.message }, callback);
  if (!kayitId) return outJson({ status: 'error', message: 'Kayıt ID eksik' }, callback);
  var lock = LockService.getScriptLock();
  try { lock.waitLock(30000); } catch (e) { return outJson({ status: 'error', message: 'Sunucu meşgul, birazdan tekrar dene' }, callback); }
  try {
    var ss = SpreadsheetApp.getActiveSpreadsheet();
    var sheet = ss.getSheetByName('Sayim');
    var HEADERS = ['Tarih', 'Saat', 'Personel', 'Ürün Adı', 'Stok Kodu', 'Barkod', 'Birim', 'Eski Stok', 'Sayılan Adet', 'Fark', 'Oturum ID', 'Kayıt ID', 'Reyon'];
    var idx = {}; HEADERS.forEach(function (h, i) { idx[h] = i; });
    if (!sheet || sheet.getLastRow() < 2) return outJson({ status: 'error', message: 'Kayıt bulunamadı' }, callback);
    var values = sheet.getRange(2, 1, sheet.getLastRow() - 1, HEADERS.length).getValues();
    for (var i = 0; i < values.length; i++) {
      if (String(values[i][idx['Kayıt ID']]) === String(kayitId)) {
        sheet.deleteRow(i + 2);
        return outJson({ status: 'ok' }, callback);
      }
    }
    return outJson({ status: 'error', message: 'Kayıt bulunamadı (zaten silinmiş olabilir)' }, callback);
  } catch (err) {
    return outJson({ status: 'error', message: err.toString() }, callback);
  } finally {
    lock.releaseLock();
  }
}
