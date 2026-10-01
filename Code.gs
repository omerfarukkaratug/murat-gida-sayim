/**
 * MURAT GIDA - SAYIM TOPLAMA SERVİSİ
 * Bu dosyanın tamamını Apps Script'e yapıştırın (eski kodun üzerine, hiçbir
 * satır kalmayacak şekilde tamamen silip baştan yapıştırın).
 */

// KOD SÜRÜMÜ — dağıtımın güncel olup olmadığını kontrol etmek için. Yeni
// bir sürüm dağıttıktan sonra /exec adresini boş açtığında burada yazan
// numarayı görmelisin; index.html'in üstündeki "build" numarasıyla
// eşleşecek şekilde ben her ikisini birlikte güncelliyorum.
var GS_VERSION = 'build104';

// Sheets'te "Saat" sütunu zaman biçimli olarak algılanırsa, hücre değeri düz
// metin değil bir Date nesnesi olarak gelir ve String(...) çirkin bir çıktı
// üretir (örn. "Sat Dec 30 1899..."). Bu yardımcılar hem düz metni hem Date
// nesnesini düzgün biçimde okunabilir metne çevirir.
function formatTimeValue(v) {
  if (v instanceof Date) return Utilities.formatDate(v, Session.getScriptTimeZone() || 'GMT+3', 'HH:mm:ss');
  return String(v || '');
}
function formatDateValue(v) {
  if (v instanceof Date) return Utilities.formatDate(v, Session.getScriptTimeZone() || 'GMT+3', 'yyyy-MM-dd');
  return String(v || '');
}

function doGet(e) {
  // ?action=katalog ile ürün kataloğunu döndürür.
  // ?action=ilerleme ile ekip genelinde sayım ilerlemesini (%) döndürür.
  // ?callback=xxx varsa (uygulama içinden <script> etiketiyle çağrılır),
  // JSONP formatında sarıp döner — CORS kısıtlamasına hiç takılmadan çalışır.
  if (e.parameter && e.parameter.action === 'katalog') {
    return getKatalog(e.parameter.callback);
  }
  if (e.parameter && e.parameter.action === 'cari') {
    return getCari(e.parameter.callback);
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
      idleMinutes: PropertiesService.getScriptProperties().getProperty('DEFAULT_IDLE_MINUTES') || '0',
      katalogVersion: PropertiesService.getScriptProperties().getProperty('KATALOG_VERSION') || '',
      cariVersion: PropertiesService.getScriptProperties().getProperty('CARI_VERSION') || ''
    }, e.parameter.callback);
  }
  if (e.parameter && e.parameter.action === 'urun_hareket') {
    return urunHareket(e.parameter, e.parameter.callback);
  }
  if (e.parameter && e.parameter.action === 'temizle') {
    return handleTemizle(e.parameter.user, e.parameter.pass, e.parameter.callback);
  }
  if (e.parameter && e.parameter.action === 'finalize') {
    return handleFinalize(e.parameter.user, e.parameter.pass, e.parameter.force, e.parameter.haric, e.parameter.callback);
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
    return handleAyarKaydet(e.parameter.user, e.parameter.pass, e.parameter.wakelock, e.parameter.idleMinutes, e.parameter.backupEmail, e.parameter.malEmail, e.parameter.callback);
  }
  // ---- Mal Giriş / Mal Çıkış ----
  // mal_kontrol: telefon, kaydın sunucuya GERÇEKTEN yazıldığını doğrular.
  // mal_export / mal_export_onay: sunucudaki PowerShell script'i yeni
  // kayıtları masaüstüne CSV olarak indirir, sonra "indirildi" diye işaretler.
  if (e.parameter && e.parameter.action === 'mal_kontrol') {
    return malKontrol(e.parameter.batch, e.parameter.callback);
  }
  // sayim_kontrol: telefon, gönderdiği sayım kayıtlarının sunucuya hangi
  // SÜRÜMLE yazıldığını sorar. Telefon kuyruğundan sadece burada doğrulanan
  // kayıtları çıkarır (bkz. sayimKontrol).
  // Sistem Durumu ekranı: son gelen veriler, sayılar, günlük ve hatalar.
  // Şube konumları: telefonlar girişte konumlarını bunlarla karşılaştırır.
  if (e.parameter && e.parameter.action === 'subeler') {
    return outJson({ status: 'ok', subeler: subeleriOku() }, e.parameter.callback);
  }
  if (e.parameter && e.parameter.action === 'sube_kaydet') {
    return subeKaydet(e.parameter.user, e.parameter.pass, e.parameter.data, e.parameter.callback);
  }
  // Telefon girişte nerede olduğunu bildirir (Sistem Durumu günlüğüne yazılır).
  if (e.parameter && e.parameter.action === 'konum_bildir') {
    return konumBildir(e.parameter, e.parameter.callback);
  }
  if (e.parameter && e.parameter.action === 'sistem_durumu') {
    return sistemDurumu(e.parameter.user, e.parameter.pass, e.parameter.callback);
  }
  // Telefon, gönderemediği verinin hatasını bildirir (günlüğe yazılır).
  if (e.parameter && e.parameter.action === 'hata_bildir') {
    return hataBildir(e.parameter, e.parameter.callback);
  }
  if (e.parameter && e.parameter.action === 'sayim_kontrol') {
    return sayimKontrol(e.parameter.session, e.parameter.nonce, e.parameter.callback);
  }
  if (e.parameter && e.parameter.action === 'mal_export') {
    return malExport(e.parameter.user, e.parameter.pass, e.parameter.callback);
  }
  if (e.parameter && e.parameter.action === 'mal_export_onay') {
    return malExportOnay(e.parameter.user, e.parameter.pass, e.parameter.ids, e.parameter.callback);
  }
  if (e.parameter && e.parameter.action === 'ayar_getir') {
    return getAyarlar(e.parameter.user, e.parameter.pass, e.parameter.callback);
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
    .createTextOutput('Sayım toplama servisi çalışıyor ✅ kod sürümü: ' + GS_VERSION + ' (' + new Date().toISOString() + ')')
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
// Yedek "admin/admin" girişi KALDIRILDI: artık sadece 'Kullanicilar'
// sekmesinde tanımlı kullanıcılar giriş yapabilir. Sekmede hiç yönetici
// yoksa, tabloyu açıp elle bir satır ekleyin (örn: Ad | Şifre | yonetici |
// | evet). NOT:
// Şifreler düz metin olarak saklanır (Apps Script'in sunduğu basit bir
// koruma) — kurumsal güvenlik seviyesinde değildir, sadece ekip içi
// yetkilendirme için yeterlidir. Tabloyu düzenleme yetkisi olan herkes
// şifreleri görebilir.
// ============================================================
var ALL_PERMS = ['rapor', 'temizle', 'kullanici_yonetimi', 'ayarlar', 'canli_durum', 'duzelt', 'hareket'];

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
  return { ok: false, message: 'Kullanıcı bulunamadı' };
}

function requirePermission(user, pass, perm) {
  var auth = authenticate(user, pass);
  if (!auth.ok) {
    // Şifre ASLA günlüğe yazılmaz — sadece kullanıcı adı ve sebep.
    gunlukYaz('yetki', String(user || '(boş)'), 'Giriş reddedildi (' + perm + ' işlemi): ' + auth.message, true);
    return auth;
  }
  if (auth.permissions.indexOf(perm) === -1) {
    gunlukYaz('yetki', String(user || ''), '"' + perm + '" yetkisi yok, işlem reddedildi', true);
    return { ok: false, message: 'Bu işlem için yetkin yok' };
  }
  return auth;
}

function handleLogin(user, pass, callback) {
  var auth = authenticate(user, pass);
  if (!auth.ok) {
    gunlukYaz('yetki', String(user || '(boş)'), 'Uygulamaya giriş reddedildi: ' + auth.message, true);
    return outJson({ status: 'error', message: auth.message }, callback);
  }
  return outJson({ status: 'ok', role: auth.role, permissions: auth.permissions }, callback);
}

// Cari (tedarikçi/müşteri) listesi — Mal Giriş/Mal Çıkış ekranlarında
// seçilebilecek cari hesapları. Katalog ile aynı mantık: "Cari" sekiminden
// okunur, telefonlar otomatik senkronize eder (CARI_VERSION ile).
function getCari(callback) {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sheet = ss.getSheetByName('Cari');
  var entries = [];
  if (sheet && sheet.getLastRow() >= 2) {
    var values = sheet.getRange(2, 1, sheet.getLastRow() - 1, 3).getValues();
    entries = values
      .filter(function (r) { return r[0]; })
      .map(function (r) { return { name: String(r[0]), code: String(r[1] || ''), balance: String(r[2] || '') }; });
  }
  var json = JSON.stringify({ entries: entries });
  if (callback) {
    return ContentService.createTextOutput(callback + '(' + json + ')').setMimeType(ContentService.MimeType.JAVASCRIPT);
  }
  return ContentService.createTextOutput(json).setMimeType(ContentService.MimeType.JSON);
}

function saveCariBulk(entries) {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sheet = ss.getSheetByName('Cari');
  if (!sheet) sheet = ss.insertSheet('Cari');
  var props = PropertiesService.getScriptProperties();
  var ozet = listeOzeti(entries.map(function (e) { return [e.name || '', e.code || '', cleanNum(e.balance)]; }));
  if (entries.length > 0 && ozet === props.getProperty('CARI_OZET') && sheet.getLastRow() === entries.length + 1) {
    return ContentService.createTextOutput(JSON.stringify({ status: 'ok', saved: 0, degisiklikYok: true })).setMimeType(ContentService.MimeType.JSON);
  }
  sheet.clear();
  sheet.appendRow(['Cari Adı', 'Cari Kodu', 'Bakiye']);
  if (entries.length > 0) {
    var rows = entries.map(function (e) { return [e.name || '', e.code || '', cleanNum(e.balance)]; });
    sheet.getRange(2, 1, rows.length, 3).setValues(rows);
    sheet.getRange(2, 3, rows.length, 1).setNumberFormat('0.00');
  }
  props.setProperty('CARI_VERSION', new Date().toISOString());
  props.setProperty('CARI_OZET', ozet);
  return ContentService.createTextOutput(JSON.stringify({ status: 'ok', saved: entries.length })).setMimeType(ContentService.MimeType.JSON);
}

// ============================================================
// MAL GİRİŞ / MAL ÇIKIŞ
// Bir irsaliye/fiş altında okutulan ürünler "MalHareket" sekmesine yazılır
// (sayım verisiyle KARIŞMAZ). Her kayıt (batch) için:
//   1) Sekmeye satırlar eklenir — Kayıt ID ile tekrar gönderim güvenlidir
//      (telefon "emin olamadım" diye tekrar yollarsa çift satır oluşmaz).
//   2) "Mal Giriş/Çıkış E-postası" tanımlıysa CSV eki olarak mail gider.
//   3) Sunucudaki PowerShell script'i (mal-hareket-indir.ps1) kaydı
//      masaüstüne CSV olarak indirir ve "Aktarıldı" damgası basar.
// ============================================================
var MAL_HEADERS = ['Tarih', 'Saat', 'Tip', 'Cari', 'Fatura/İrsaliye No', 'Personel', 'Barkod', 'Ürün Adı', 'Stok Kodu', 'Miktar', 'Birim', 'Kayıt ID',
  'Belge Türü', 'Cari Kodu', 'Sebep', 'KDV %', 'Fiyat', 'Batch ID', 'Aktarıldı'];
var MAL_COL = { MIKTAR: 10, KAYIT_ID: 12, BATCH: 18, AKTARILDI: 19, SURUM: 20, ACIKLAMA: 21, KONUM: 22 };
// 20. sütun "Sürüm": MAL_HEADERS'a EKLENMEDİ — masaüstü aktarımı (malExport)
// ve mail eki ilk 19 sütunla aynen çalışmaya devam etsin diye ayrı tutulur.
var MAL_SURUM_BASLIK = 'Sürüm';
// 21. sütun: fatura/irsaliye altına yazılan serbest açıklama (her satırda aynı).
var MAL_ACIKLAMA_BASLIK = 'Açıklama';
// 22. sütun: kaydın yapıldığı şube (telefonun giriş konumuna göre).
var MAL_KONUM_BASLIK = 'Konum';
// Mail ekindeki yedek CSV, ERP12'nin resmi mal aktarım şablonuyla aynı sütun sırasında.
var MAL_CSV_HEADERS = ['BARKOD', 'Stok Kodu', 'Stok İsmi', 'MIKTAR', 'FIYAT', 'Kdv', 'ISKONTO', 'Tutar', 'birim', 'grup', 'SFİYAT'];

function ensureMalSheet() {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sheet = ss.getSheetByName('MalHareket');
  if (!sheet) sheet = ss.insertSheet('MalHareket');
  if (sheet.getMaxColumns() < MAL_COL.KONUM) {
    sheet.insertColumnsAfter(sheet.getMaxColumns(), MAL_COL.KONUM - sheet.getMaxColumns());
  }
  if (sheet.getLastRow() === 0) {
    sheet.getRange(1, 1, 1, MAL_HEADERS.length).setValues([MAL_HEADERS]);
  } else if (sheet.getLastColumn() < MAL_HEADERS.length) {
    // Eski (12 sütunlu) sekme: yeni sütunların başlıklarını sağa ekle, eski satırlara dokunma.
    sheet.getRange(1, 13, 1, MAL_HEADERS.length - 12).setValues([MAL_HEADERS.slice(12)]);
  }
  if (String(sheet.getRange(1, MAL_COL.SURUM).getValue()) !== MAL_SURUM_BASLIK) {
    sheet.getRange(1, MAL_COL.SURUM).setValue(MAL_SURUM_BASLIK);
  }
  if (String(sheet.getRange(1, MAL_COL.ACIKLAMA).getValue()) !== MAL_ACIKLAMA_BASLIK) {
    sheet.getRange(1, MAL_COL.ACIKLAMA).setValue(MAL_ACIKLAMA_BASLIK);
  }
  if (String(sheet.getRange(1, MAL_COL.KONUM).getValue()) !== MAL_KONUM_BASLIK) {
    sheet.getRange(1, MAL_COL.KONUM).setValue(MAL_KONUM_BASLIK);
  }
  return sheet;
}

// Kayıt (batch) yazma. Telefon her kalemi kimlik (kayitId) ve sürüm (v) ile
// gönderir; sürüm, kalemin miktarı her değiştiğinde artar.
//  - Yeni kalem: eklenir.
//  - Aynı batch'te zaten var, gelen sürüm daha yeni: satır güncellenir
//    (örn. onay alınamadı, kullanıcı miktarı düzeltip tekrar kaydetti).
//  - Aynı ya da eski sürüm: atlanır (tekrar gönderim güvenli, çift satır yok).
//  - Telefondaki listede artık olmayan kalem (tekrar kaydetmeden önce
//    silinmiş): sekmeden silinir.
//  - Masaüstüne aktarılmış ("Aktarıldı" dolu) satır DEĞİŞTİRİLMEZ ve
//    SİLİNMEZ — ERP'ye girmiş veri sessizce değişmesin. Telefon onayda bunu
//    görür ve kullanıcıyı uyarır.
function saveMalHareket(data) {
  var sheet = ensureMalSheet();
  var batchId = String(data.batchId || Utilities.getUuid());
  var hareket = data.tip === 'cikis' ? 'Çıkış' : 'Giriş';
  var W = MAL_COL.KONUM; // okunan/yazılan sütun genişliği (1..22)
  var konum = String(data.konum || '').substring(0, 120);
  var aciklama = String(data.aciklama || '').substring(0, 500);

  var existing = {}; // kayıtId -> { satir, batch, v, aktarildi }
  var last = sheet.getLastRow();
  if (last >= 2) {
    sheet.getRange(2, 1, last - 1, W).getValues().forEach(function (r, i) {
      var id = r[MAL_COL.KAYIT_ID - 1];
      if (!id) return;
      existing[String(id)] = { satir: i + 2, batch: String(r[MAL_COL.BATCH - 1] || ''), v: surumOku(r[MAL_COL.SURUM - 1]), aktarildi: !!r[MAL_COL.AKTARILDI - 1] };
    });
  }

  var satirYap = function (r, id, v) {
    return [
      r.tarih || '', r.saat || '', hareket,
      data.cari || '', data.faturaNo || '', data.personel || '',
      r.barkod || '', r.ad || '', r.stokKodu || '', cleanNum(r.miktar), r.birim || 'Adet', id,
      data.belgeTuru || '', data.cariKodu || '', data.sebep || '', cleanNum(r.kdv), cleanNum(r.fiyat), batchId, '', v, aciklama, konum
    ];
  };
  var metinSutunlari = function (ilk, adet) {
    // Tarih / Saat / Barkod / Stok Kodu / Cari Kodu METİN olarak yazılsın —
    // yoksa Sheets 13 haneli barkodu 8,69E+12 gibi bilimsel sayıya çevirir,
    // baştaki sıfırlar kaybolur, saat de zaman biçimine dönüşüp kayar.
    [1, 2, 7, 9, 14].forEach(function (c) { sheet.getRange(ilk, c, adet, 1).setNumberFormat('@'); });
  };

  var duplicate = 0, guncellenen = 0, kilitli = 0, silinen = 0;
  var gelenIdler = {};
  var rows = [];
  (data.rows || []).forEach(function (r) {
    var id = String(r.kayitId || Utilities.getUuid());
    var v = surumOku(r.v);
    gelenIdler[id] = true;
    var ex = existing[id];
    if (!ex) {
      existing[id] = { satir: -1, batch: batchId, v: v, aktarildi: false };
      rows.push(satirYap(r, id, v));
      return;
    }
    if (ex.satir !== -1 && ex.batch === batchId && v <= ex.v && !ex.aktarildi) {
      sheet.getRange(ex.satir, MAL_COL.ACIKLAMA).setValue(aciklama); // açıklama sonradan düzeltilmiş olabilir
    }
    if (ex.satir === -1 || ex.batch !== batchId || v <= ex.v) { duplicate++; return; }
    if (ex.aktarildi) { kilitli++; return; }
    metinSutunlari(ex.satir, 1);
    sheet.getRange(ex.satir, 1, 1, W).setValues([satirYap(r, id, v)]);
    ex.v = v;
    guncellenen++;
  });

  // Telefonda silinmiş kalemler: bu batch'te olup gönderilen listede olmayanlar.
  var silinecek = [];
  Object.keys(existing).forEach(function (id) {
    var ex = existing[id];
    if (ex.batch !== batchId || ex.satir === -1 || gelenIdler[id]) return;
    if (ex.aktarildi) { kilitli++; return; }
    silinecek.push(ex.satir);
  });
  silinecek.sort(function (a, b) { return b - a; }).forEach(function (n) { sheet.deleteRow(n); silinen++; });

  if (rows.length > 0) {
    var ilk = sheet.getLastRow() + 1;
    metinSutunlari(ilk, rows.length);
    sheet.getRange(ilk, 1, rows.length, W).setValues(rows);
  }

  // Mail: sadece bu çağrıda YENİ satır yazıldıysa gider — tekrar gönderimde ikinci mail çıkmaz.
  var mailGitti = false;
  if (rows.length > 0) {
    try { mailGitti = sendMalMail(malBatchFromRows(rows)); } catch (mailErr) { /* mail gitmese de kayıt güvende */ }
  }

  return ContentService
    .createTextOutput(JSON.stringify({ status: 'ok', saved: rows.length, duplicate: duplicate, guncellenen: guncellenen, silinen: silinen, kilitli: kilitli, batchId: batchId, mail: mailGitti }))
    .setMimeType(ContentService.MimeType.JSON);
}

// Telefon: "bu batch sunucuda nasıl yazıldı?" — kaydın gerçekten ve DOĞRU
// yazıldığının doğrulaması. Satır sayısının yanında her kalemin sürümünü,
// miktarını ve aktarılıp aktarılmadığını döndürür:
// rows: { kayıtId: [sürüm, miktar, aktarıldı(1/0)] }
function malKontrol(batch, callback) {
  var sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName('MalHareket');
  var count = 0;
  var rows = {};
  var hedef = String(batch || '');
  if (hedef && sheet && sheet.getLastRow() >= 2 && sheet.getLastColumn() >= MAL_COL.BATCH) {
    var genislik = Math.min(sheet.getMaxColumns(), MAL_COL.SURUM);
    sheet.getRange(2, 1, sheet.getLastRow() - 1, genislik).getValues().forEach(function (r) {
      if (String(r[MAL_COL.BATCH - 1]) !== hedef) return;
      count++;
      var id = r[MAL_COL.KAYIT_ID - 1];
      if (!id) return;
      var v = genislik >= MAL_COL.SURUM ? surumOku(r[MAL_COL.SURUM - 1]) : 1;
      rows[String(id)] = [v, r[MAL_COL.MIKTAR - 1], r[MAL_COL.AKTARILDI - 1] ? 1 : 0];
    });
  }
  return outJson({ status: 'ok', count: count, rows: rows }, callback);
}

// ---- CSV yardımcıları (mail ve masaüstü dosyası AYNI çıktıyı kullanır) ----
function csvAlan(v) {
  var s = (v === null || v === undefined) ? '' : String(v);
  if (s.indexOf(';') !== -1 || s.indexOf('"') !== -1 || s.indexOf('\n') !== -1) s = '"' + s.replace(/"/g, '""') + '"';
  return s;
}
function trSayi(v, ondalik) {
  if (v === '' || v === null || v === undefined || isNaN(Number(v))) return '';
  var n = Number(v);
  var t = (ondalik === undefined) ? String(Math.round(n * 1000) / 1000) : n.toFixed(ondalik);
  return t.replace('.', ',');
}
function asciiSlug(s, max) {
  var map = { 'ç': 'c', 'Ç': 'c', 'ğ': 'g', 'Ğ': 'g', 'ı': 'i', 'İ': 'i', 'ö': 'o', 'Ö': 'o', 'ş': 's', 'Ş': 's', 'ü': 'u', 'Ü': 'u' };
  var t = String(s || '').replace(/[çÇğĞıİöÖşŞüÜ]/g, function (ch) { return map[ch]; }).toLowerCase();
  t = t.replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '');
  return t.substring(0, max || 24);
}
// Barkod / stok kodu gibi rakamdan oluşan değerler için: Excel'e "bu bir metin,
// sayı değil" demenin yolu ="değer" formül biçimidir. Böylece mail ekindeki CSV
// çift tıklanıp açılınca 8.69E+12 gibi bilimsel gösterime dönmez.
function csvMetinZorla(v) {
  var s = (v === null || v === undefined) ? '' : String(v).replace(/"/g, '""');
  return '"=""' + s + '"""';
}
// KDV oranına göre ERP12'nin "grup" sütunu: %20 -> GENEL 20, %10 -> GENEL 10, %1 -> GENEL 1.
function kdvGrup(kdv) {
  if (kdv === '' || kdv === null || kdv === undefined) return '';
  return 'GENEL ' + Number(kdv);
}

// Sekmedeki satırlardan (MAL_HEADERS sırasında) bir batch nesnesi kurar.
// batch.items -> ERP12'nin resmi mal aktarım şablonuyla (BARKOD, Stok Kodu, Stok İsmi,
// MIKTAR, FIYAT, Kdv, ISKONTO, Tutar, birim, grup, SFİYAT) birebir eşleşecek şekilde;
// masaüstündeki PowerShell script'i bu listeden gerçek bir .xlsx üretir.
// batch.csv -> sadece mail ekinde okunabilir bir yedek kopya, aynı sütun sırasıyla.
function malBatchFromRows(rows) {
  var f = rows[0];
  var batch = {
    batchId: String(f[17]), hareket: String(f[2]), belgeTuru: String(f[12]), belgeNo: String(f[4]),
    cari: String(f[3]), cariKodu: String(f[13]), sebep: String(f[14]), personel: String(f[5]),
    tarih: formatDateValue(f[0]), saat: formatTimeValue(f[1]), kalemSayisi: rows.length, toplamMiktar: 0,
    aciklama: String(f[MAL_COL.ACIKLAMA - 1] || ''),
    items: []
  };
  var lines = [MAL_CSV_HEADERS.join(';')];
  rows.forEach(function (r) {
    var miktar = Number(r[9]) || 0;
    var fiyat = (r[16] === '' || r[16] === null || r[16] === undefined) ? '' : Number(r[16]);
    var kdv = (r[15] === '' || r[15] === null || r[15] === undefined) ? '' : Number(r[15]);
    var grup = kdvGrup(kdv);
    // Yeni (katalogda olmayan) ürünlerde fiyat bilinmediği için SFİYAT da boş kalır —
    // sadece barkod ve miktar zorunlu, geri kalanı ERP12'de elle tamamlanır.
    var sfiyat = (fiyat === '') ? '' : Math.round(fiyat * 1.45 * 100) / 100;
    batch.toplamMiktar += miktar;
    batch.items.push({
      barkod: String(r[6] || ''), stokKodu: String(r[8] || ''), urunAdi: String(r[7] || ''),
      miktar: miktar, birim: r[10] || 'Adet', fiyat: fiyat, kdv: kdv, grup: grup, sfiyat: sfiyat
    });
    lines.push([
      csvMetinZorla(r[6]), csvMetinZorla(r[8]), csvAlan(r[7]), csvAlan(trSayi(miktar)),
      csvAlan(fiyat === '' ? '' : trSayi(fiyat, 2)), csvAlan(kdv === '' ? '' : trSayi(kdv)), csvAlan('0'), csvAlan(''),
      csvAlan(r[10]), csvAlan(grup), csvAlan(sfiyat === '' ? '' : trSayi(sfiyat, 2))
    ].join(';'));
  });
  batch.csv = lines.join('\r\n');
  // Dosya adı: önce cari ismi, sonra belge no (belge no yoksa "belgesiz"),
  // sonrasında ayırt edici olsun diye tarih/saat ve kısa bir kod.
  batch.temelAd = asciiSlug(batch.cari, 30) + '_' + (batch.belgeNo ? asciiSlug(batch.belgeNo, 20) : 'belgesiz') + '_' +
    batch.tarih + '_' + String(batch.saat).substring(0, 5).replace(':', '') + '_' + batch.batchId.substring(0, 8);
  batch.dosyaAdi = batch.temelAd + '.csv';
  return batch;
}

// Yönetici Paneli'nde ayrıca bir şey yapılmasa bile mail hep bu adrese gitsin diye
// sabit bir varsayılan e-posta tanımlı. Panelden farklı bir adres girilip
// kaydedilirse (MAL_EMAIL script property'si) o adres bunun yerine geçer.
var VARSAYILAN_MAL_EMAIL = 'muratgida_avm@hotmail.com';

function sendMalMail(batch) {
  // Property hiç ayarlanmamışsa (null) sabit varsayılan adrese gider. Panelden
  // bilerek boş bırakılıp kaydedilmişse (boş metin, null değil) mail kapatılmış
  // demektir — o zaman gitmez.
  var raw = PropertiesService.getScriptProperties().getProperty('MAL_EMAIL');
  var to = (raw === null) ? VARSAYILAN_MAL_EMAIL : raw;
  if (!to) return false;
  var blob = Utilities.newBlob('\uFEFF' + batch.csv, 'text/csv', batch.dosyaAdi);
  MailApp.sendEmail({
    to: to,
    subject: 'Mal ' + batch.hareket + ' — ' + batch.belgeTuru + ' — ' + batch.cari + (batch.belgeNo ? (' — No ' + batch.belgeNo) : ''),
    body: 'Mal ' + batch.hareket.toLowerCase() + ' kaydı tamamlandı.\n\n' +
      'Belge: ' + batch.belgeTuru + (batch.belgeNo ? (' · No ' + batch.belgeNo) : '') + '\n' +
      'Cari: ' + batch.cari + (batch.cariKodu ? (' (' + batch.cariKodu + ')') : '') + '\n' +
      (batch.sebep ? ('Sebep: ' + batch.sebep + '\n') : '') +
      (batch.aciklama ? ('Açıklama: ' + batch.aciklama + '\n') : '') +
      'Kalem sayısı: ' + batch.kalemSayisi + ' · Toplam miktar: ' + trSayi(batch.toplamMiktar) + '\n' +
      'Kaydeden: ' + batch.personel + ' · ' + batch.tarih + ' ' + batch.saat + '\n\n' +
      'Ürün listesi ekte CSV olarak bulunuyor.',
    attachments: [blob]
  });
  return true;
}

// Sunucudaki PowerShell script'i: henüz masaüstüne indirilmemiş kayıtlar.
// Yetki: 'rapor'. En fazla 25 kayıt (batch) döner; indirilen kayıtlar
// mal_export_onay ile işaretlenince bir sonraki çağrıda gelmez.
function malExport(user, pass, callback) {
  var auth = requirePermission(user, pass, 'rapor');
  if (!auth.ok) return outJson({ status: 'error', message: auth.message }, callback);
  var lock = LockService.getScriptLock();
  try { lock.waitLock(20000); } catch (e) { return outJson({ status: 'error', message: 'Sunucu yoğun, tekrar denenecek' }, callback); }
  try {
    var sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName('MalHareket');
    if (!sheet || sheet.getLastRow() < 2 || sheet.getLastColumn() < MAL_HEADERS.length) return outJson({ status: 'ok', batches: [] }, callback);
    // Açıklama (21. sütun) da masaüstü programına gitsin; eski sekmede yoksa 19 sütun okunur.
    var values = sheet.getRange(2, 1, sheet.getLastRow() - 1, Math.min(sheet.getMaxColumns(), MAL_COL.ACIKLAMA)).getValues();
    var order = [];
    var groups = {};
    values.forEach(function (r) {
      var b = String(r[MAL_COL.BATCH - 1] || '');
      if (!b || r[MAL_COL.AKTARILDI - 1]) return; // batch kimliği yok (eski kayıt) ya da zaten indirilmiş
      if (!groups[b]) { groups[b] = []; order.push(b); }
      groups[b].push(r);
    });
    var batches = order.slice(0, 25).map(function (b) { return malBatchFromRows(groups[b]); });
    // PowerShell'in son bağlanma zamanı her seferinde, indirilecek kayıt
    // varsa ayrıca günlüğe yazılır (boş kontroller günlüğü doldurmasın).
    sonKaydet('masaustu_kontrol', String(user || ''), order.length + ' bekleyen kayıt', false);
    if (batches.length > 0) gunlukYaz('masaustu', String(user || ''), batches.length + ' mal kaydı masaüstüne gönderildi', false);
    return outJson({ status: 'ok', batches: batches, kalan: Math.max(order.length - batches.length, 0) }, callback);
  } catch (err) {
    return outJson({ status: 'error', message: err.toString() }, callback);
  } finally {
    lock.releaseLock();
  }
}

function malExportOnay(user, pass, ids, callback) {
  var auth = requirePermission(user, pass, 'rapor');
  if (!auth.ok) return outJson({ status: 'error', message: auth.message }, callback);
  var set = {};
  String(ids || '').split(',').forEach(function (x) { x = x.trim(); if (x) set[x] = true; });
  var lock = LockService.getScriptLock();
  try { lock.waitLock(20000); } catch (e) { return outJson({ status: 'error', message: 'Sunucu yoğun, tekrar denenecek' }, callback); }
  try {
    var sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName('MalHareket');
    var isaretlenen = 0;
    if (sheet && sheet.getLastRow() >= 2 && sheet.getLastColumn() >= MAL_COL.AKTARILDI) {
      var n = sheet.getLastRow() - 1;
      var vals = sheet.getRange(2, MAL_COL.BATCH, n, 2).getValues();
      var damga = Utilities.formatDate(new Date(), Session.getScriptTimeZone() || 'GMT+3', 'yyyy-MM-dd HH:mm:ss');
      var yaz = vals.map(function (v) {
        if (set[String(v[0])] && !v[1]) { isaretlenen++; return [damga]; }
        return [v[1]];
      });
      if (isaretlenen > 0) sheet.getRange(2, MAL_COL.AKTARILDI, n, 1).setValues(yaz);
    }
    if (isaretlenen > 0) gunlukYaz('masaustu', String(user || ''), isaretlenen + ' satır "Aktarıldı" olarak işaretlendi', false);
    return outJson({ status: 'ok', isaretlenen: isaretlenen }, callback);
  } catch (err) {
    return outJson({ status: 'error', message: err.toString() }, callback);
  } finally {
    lock.releaseLock();
  }
}

function numOrEmpty(v) {
  return (v === '' || v === null || v === undefined) ? '' : String(v);
}

function getKatalog(callback) {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sheet = ss.getSheetByName('Katalog');
  var entries = [];
  if (sheet && sheet.getLastRow() >= 2) {
    var values = sheet.getRange(2, 1, sheet.getLastRow() - 1, 6).getValues();
    entries = values
      .filter(function (r) { return r[0] && r[1]; })
      .map(function (r) {
        // ⚠️ "r[3] || ''" yazınca sayısal 0 değeri (stok 0, KDV %0) boş sayılıyordu:
        // sıfır stoklu ürün "stok bilgisi yok" gibi görünüyordu. Sadece gerçekten
        // boş hücreler boş kalır, 0 olduğu gibi gelir.
        return { name: String(r[0]), barcode: String(r[1]), stockCode: String(r[2] || ''), oldStock: numOrEmpty(r[3]), price: numOrEmpty(r[4]), kdv: numOrEmpty(r[5]) };
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

// ============================================================
// SAYIM SEKMESİ: SÜRÜM ve SİLİNDİ İŞARETİ
// 'Sayim' sekmesinin 14. sütunu "Sürüm"dür. Telefon her kaydı bir sürüm
// numarasıyla gönderir; sunucu daha yeni sürümü asla eskisiyle ezmez.
// 'SilinenKayitlar' sekmesi silinen kayıtların kimliklerini tutar — bir kayıt
// silindikten sonra eski bir gönderi onu tabloya geri ekleyemez.
// ============================================================
var SAYIM_HEADERS = ['Tarih', 'Saat', 'Personel', 'Ürün Adı', 'Stok Kodu', 'Barkod', 'Birim', 'Eski Stok', 'Sayılan Adet', 'Fark', 'Oturum ID', 'Kayıt ID', 'Reyon', 'Sürüm'];
var SAYIM_COL = { ADET: 9, FARK: 10, OTURUM: 11, KAYIT_ID: 12, SURUM: 14 };
var SILINEN_HEADERS = ['Kayıt ID', 'Oturum ID', 'Silinme Zamanı', 'Silen'];

// Başlık satırını ve "Sürüm" sütununu hazırlar. Eski (13 sütunlu) sekmede
// sadece 14. sütunun başlığı eklenir; mevcut satırlara dokunulmaz — sürümü
// boş olan eski satırlar 1 kabul edilir.
function ensureSayimColumns(sheet) {
  if (sheet.getMaxColumns() < SAYIM_HEADERS.length) {
    sheet.insertColumnsAfter(sheet.getMaxColumns(), SAYIM_HEADERS.length - sheet.getMaxColumns());
  }
  if (sheet.getLastRow() === 0) {
    sheet.getRange(1, 1, 1, SAYIM_HEADERS.length).setValues([SAYIM_HEADERS]);
  } else if (String(sheet.getRange(1, SAYIM_COL.SURUM).getValue()) !== 'Sürüm') {
    sheet.getRange(1, SAYIM_COL.SURUM).setValue('Sürüm');
  }
}

function surumOku(v) {
  var n = parseInt(v, 10);
  return (isNaN(n) || n < 1) ? 1 : n;
}

function silinenSheet(olustur) {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sheet = ss.getSheetByName('SilinenKayitlar');
  if (!sheet && olustur) {
    sheet = ss.insertSheet('SilinenKayitlar');
    sheet.getRange(1, 1, 1, SILINEN_HEADERS.length).setValues([SILINEN_HEADERS]);
    sheet.hideSheet(); // günlük kullanımda kafa karıştırmasın
  }
  return sheet;
}

// Silinen kayıtların kimliklerini { kayıtId: oturumId } olarak döndürür.
function readSilinenler() {
  var map = {};
  var sheet = silinenSheet(false);
  if (!sheet || sheet.getLastRow() < 2) return map;
  sheet.getRange(2, 1, sheet.getLastRow() - 1, 2).getValues().forEach(function (r) {
    if (r[0]) map[String(r[0])] = String(r[1] || '');
  });
  return map;
}

function addSilinenler(ids, sessionId, silen) {
  if (!ids || ids.length === 0) return;
  var sheet = silinenSheet(true);
  var zaman = Utilities.formatDate(new Date(), Session.getScriptTimeZone() || 'GMT+3', 'yyyy-MM-dd HH:mm:ss');
  var rows = ids.map(function (id) { return [String(id), String(sessionId || ''), zaman, String(silen || '')]; });
  var ilk = sheet.getLastRow() + 1;
  sheet.getRange(ilk, 1, rows.length, 2).setNumberFormat('@'); // kimlikler metin kalsın
  sheet.getRange(ilk, 1, rows.length, SILINEN_HEADERS.length).setValues(rows);
}

// Telefonun gönderim onayı: bir oturumun tablodaki kayıtlarını ('Sayim' ve
// 'GecGelenKayitlar' sekmelerinden) { kayıtId: [sürüm, adet] } ve o oturumda
// silinmiş kimlikleri döndürür.
// Telefon kuyruğundan SADECE burada doğrulanan kayıtları çıkarır:
//  - tablodaki sürüm >= telefondaki sürüm ise kayıt yazılmış demektir,
//  - silinen kimlik tabloda yoksa silme işlenmiş demektir.
// Kilit almadan okur; doPost yazarken okunsa bile en kötü ihtimalle telefon
// kaydı "henüz yazılmadı" sayıp bir sonraki turda tekrar gönderir.
function sayimKontrol(sessionId, nonce, callback) {
  var hedef = String(sessionId || '');
  if (!hedef) return outJson({ status: 'error', message: 'Oturum ID eksik' }, callback);
  if (nonce) {
    try {
      var hazir = CacheService.getScriptCache().get('ack_' + hedef + '_' + nonce);
      if (hazir) {
        var h = JSON.parse(hazir);
        return outJson({ status: 'ok', rows: h.rows || {}, deleted: h.deleted || [], kaynak: 'onbellek' }, callback);
      }
    } catch (ce) { /* önbellek okunamadı: tablo taranır */ }
  }
  var rows = {};
  sayimOturumSatirlari(SpreadsheetApp.getActiveSpreadsheet().getSheetByName('Sayim'), hedef, rows);
  sayimOturumSatirlari(gecGelenSheet(false), hedef, rows); // temizlikten sonra gelen eski kayıtlar
  var silinenler = readSilinenler();
  var deleted = Object.keys(silinenler).filter(function (id) { return silinenler[id] === hedef; });
  return outJson({ status: 'ok', rows: rows, deleted: deleted }, callback);
}

// Sayım satırlarını verilen sekmeye (Sayim ya da GecGelenKayitlar) sürüm
// kontrolüyle yazar. Dönen değer: atlanan (yazılmayan) satır sayısı.
//
// SÜRÜM KONTROLÜ: Her kayıt telefonda bir sürüm numarası (v) taşır; adet her
// değiştiğinde artar. Tablodaki sürüm gelen sürümden küçük değilse satır
// EZİLMEZ — böylece geç ulaşan eski bir gönderi, yeni düzeltmenin (telefondan
// ya da yöneticinin "Düzelt" ekranından) üzerine yazamaz. Sürümsüz gelen
// kayıt (eski uygulama sürümü) v=1 sayılır ve sadece tablodaki satır da hiç
// düzeltilmemişse (v<=1) üzerine yazılır.
function writeSayimRows(sheet, rows, personnel, sessionId, silinenler) {
  // ack: { kayıtId: [tablodaki sürüm, tablodaki adet] }; tablo: tüm kayıtların güncel sürüm/adedi
  var sonuc = { skipped: 0, ack: {}, tablo: { v: {}, q: {} } };
  if (!rows || rows.length === 0) return sonuc;
  ensureSayimColumns(sheet);
  var HEADERS = SAYIM_HEADERS;

  // PERFORMANS: büyük sayımda (18 saat) tablo 80 bin satıra çıkabilir. Her
  // gönderimde 14 sütunun hepsini okumak yerine SADECE gereken 3 sütunu
  // (Kayıt ID, Sürüm, Adet) okuyoruz — okunan hücre sayısı ~5 kat azalır.
  var lastRow = sheet.getLastRow();
  var existing = {};   // kayıtId -> satır numarası
  var existingV = {};  // kayıtId -> tablodaki sürüm
  var existingQ = {};  // kayıtId -> tablodaki adet
  if (lastRow > 1) {
    var n = lastRow - 1;
    var ids = sheet.getRange(2, SAYIM_COL.KAYIT_ID, n, 1).getValues();
    var surumler = sheet.getRange(2, SAYIM_COL.SURUM, n, 1).getValues();
    var adetler = sheet.getRange(2, SAYIM_COL.ADET, n, 1).getValues();
    for (var i = 0; i < n; i++) {
      var key = ids[i][0];
      if (key) {
        existing[key] = i + 2;
        existingV[key] = surumOku(surumler[i][0]);
        existingQ[key] = adetler[i][0];
      }
    }
  }

  // Yeni satırları TEK seferde toplu ekliyoruz (appendRow'u döngüde tekrar
  // tekrar çağırmak yerine) — hem çok daha hızlı hem de sayfa büyüdükçe
  // (binlerce satır, büyük sayım) performansı korur.
  //
  // SÜRÜM KONTROLÜ: Her kayıt telefonda bir sürüm numarası (v) taşır; adet her
  // değiştiğinde artar. Tablodaki sürüm gelen sürümden küçük değilse satır
  // EZİLMEZ — böylece geç ulaşan eski bir gönderi, yeni düzeltmenin (telefondan
  // ya da yöneticinin "Düzelt" ekranından) üzerine yazamaz. Sürümsüz gelen
  // kayıt (eski uygulama sürümü) v=1 sayılır ve sadece tablodaki satır da hiç
  // düzeltilmemişse (v<=1) üzerine yazılır.
  var newRows = [];
  rows.forEach(function (row) {
    var id = row.id ? String(row.id) : '';
    if (id && silinenler[id]) { sonuc.skipped++; return; }
    var surumVar = row.v !== undefined && row.v !== null && row.v !== '';
    var v = surumVar ? surumOku(row.v) : 1;
    var oldStock = (row.oldStock !== '' && row.oldStock !== undefined && !isNaN(Number(row.oldStock))) ? Number(row.oldStock) : '';
    var diff = oldStock !== '' ? (row.qty - oldStock) : '';
    var rowData = [row.date, row.time, personnel, row.name, row.stockCode || '', row.barcode, row.unit || 'Adet', oldStock, row.qty, diff, sessionId, row.id || '', row.reyon || '', v];
    if (id && existing[id] === -1) { sonuc.skipped++; return; } // aynı istekte zaten eklendi
    if (id && existing[id]) {
      var mevcutV = existingV[id];
      var yaz = surumVar ? (v > mevcutV) : (mevcutV <= 1);
      if (!yaz) { sonuc.skipped++; sonuc.ack[id] = [mevcutV, existingQ[id]]; return; }
      sheet.getRange(existing[id], 1, 1, HEADERS.length).setValues([rowData]);
      existingV[id] = v; existingQ[id] = row.qty;
      sonuc.ack[id] = [v, row.qty];
    } else {
      newRows.push(rowData);
      if (id) { existing[id] = -1; existingV[id] = v; existingQ[id] = row.qty; sonuc.ack[id] = [v, row.qty]; } // aynı istekte tekrar gelirse çift satır olmasın
    }
  });
  if (newRows.length > 0) {
    sheet.getRange(sheet.getLastRow() + 1, 1, newRows.length, HEADERS.length).setValues(newRows);
  }
  sonuc.tablo = { v: existingV, q: existingQ };
  return sonuc;
}

// Verilen kimlikleri sekmeden siler (sondan başa, satır numaraları kaymasın).
function deleteSayimIds(sheet, ids) {
  var last = sheet.getLastRow();
  if (!ids || ids.length === 0 || last < 2) return;
  var set = {};
  ids.forEach(function (d) { set[String(d)] = true; });
  var idColValues = sheet.getRange(2, SAYIM_COL.KAYIT_ID, last - 1, 1).getValues();
  var rowsToDelete = [];
  for (var j = 0; j < idColValues.length; j++) {
    var cellId = idColValues[j][0];
    if (cellId && set[String(cellId)]) rowsToDelete.push(j + 2);
  }
  rowsToDelete.sort(function (a, b) { return b - a; });
  rowsToDelete.forEach(function (rowNum) { sheet.deleteRow(rowNum); });
}

// Temizlikten önce okutulup temizlikten SONRA gelen kayıtların sekmesi.
// 'Sayim' ile aynı sütunlara sahiptir; rapora (finalize) dahil edilmez.
function gecGelenSheet(olustur) {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sheet = ss.getSheetByName('GecGelenKayitlar');
  if (!sheet && olustur) {
    sheet = ss.insertSheet('GecGelenKayitlar');
    ensureSayimColumns(sheet);
  }
  return sheet;
}

// Bir sekmedeki, verilen oturuma ait kayıtları { kayıtId: [sürüm, adet] }
// olarak "rows" nesnesine ekler (aynı kimlik iki sekmede varsa yüksek sürüm kalır).
function sayimOturumSatirlari(sheet, hedef, rows) {
  if (!sheet || sheet.getLastRow() < 2) return;
  // Sadece Adet (9) … Sürüm (14) aralığı okunur — ilk 8 sütun gereksiz.
  var ilkSutun = SAYIM_COL.ADET;
  var genislik = Math.min(sheet.getMaxColumns(), SAYIM_HEADERS.length) - ilkSutun + 1;
  var values = sheet.getRange(2, ilkSutun, sheet.getLastRow() - 1, genislik).getValues();
  var o = function (col) { return col - ilkSutun; };
  for (var i = 0; i < values.length; i++) {
    if (String(values[i][o(SAYIM_COL.OTURUM)]) !== hedef) continue;
    var id = values[i][o(SAYIM_COL.KAYIT_ID)];
    if (!id) continue;
    var v = genislik > o(SAYIM_COL.SURUM) ? surumOku(values[i][o(SAYIM_COL.SURUM)]) : 1;
    var onceki = rows[String(id)];
    if (!onceki || onceki[0] < v) rows[String(id)] = [v, values[i][o(SAYIM_COL.ADET)]];
  }
}

// ============================================================
// SİSTEM GÜNLÜĞÜ ve SİSTEM DURUMU
// Her önemli olay (ERP'den katalog/cari yüklemesi, sayım ve mal kayıtları,
// masaüstü aktarımı, reddedilen girişler, sunucu ve telefon hataları) gizli
// 'SistemGunlugu' sekmesine yazılır. Her türün EN SON olayı ayrıca script
// özelliklerinde tutulur ("SON_<tür>") — Sistem Durumu ekranı bunları gösterir.
// Günlüğe yazılamaması asıl işlemi ASLA bozmaz (hatalar yutulur).
// ============================================================
var GUNLUK_BASLIK = ['Zaman', 'Tür', 'Kaynak', 'Detay', 'Durum'];
var GUNLUK_MAX = 2000; // bundan fazlası birikince en eskiler silinir

function simdiMetin() {
  return Utilities.formatDate(new Date(), Session.getScriptTimeZone() || 'GMT+3', 'yyyy-MM-dd HH:mm:ss');
}
function sonKaydet(tur, kaynak, detay, hata) {
  try {
    PropertiesService.getScriptProperties().setProperty('SON_' + tur,
      JSON.stringify({ zaman: simdiMetin(), ms: Date.now(), kaynak: kaynak, detay: String(detay).substring(0, 300), hata: !!hata }));
  } catch (e) { /* günlük asıl işi bozmasın */ }
}
function gunlukYaz(tur, kaynak, detay, hata) {
  try {
    sonKaydet(tur, kaynak, detay, hata);
    if (hata) sonKaydet('hata', kaynak, '[' + tur + '] ' + detay, true);
    var ss = SpreadsheetApp.getActiveSpreadsheet();
    var sheet = ss.getSheetByName('SistemGunlugu');
    if (!sheet) {
      sheet = ss.insertSheet('SistemGunlugu');
      sheet.getRange(1, 1, 1, GUNLUK_BASLIK.length).setValues([GUNLUK_BASLIK]);
      sheet.hideSheet();
    }
    sheet.appendRow([simdiMetin(), tur, String(kaynak || ''), String(detay || '').substring(0, 500), hata ? 'HATA' : 'OK']);
    if (sheet.getLastRow() > GUNLUK_MAX + 500) sheet.deleteRows(2, 500);
  } catch (e) { /* günlük asıl işi bozmasın */ }
}

// Telefonun bildirdiği hata (örn. "3 kez gönderilemedi: zaman aşımı").
// Kimlik doğrulaması istemez; metin kısaltılır, sadece günlüğe yazılır.
// ============================================================
// ŞUBE KONUMLARI
// 'Subeler' sekmesi: Ad | Enlem | Boylam | Yarıçap (m). Telefon uygulamaya
// girişte GPS konumunu alır; herhangi bir şubenin yarıçapı içindeyse fiyat ve
// stok (yetkisi varsa) görünür, dışındaysa gizlenir. Sayım ve mal kaydı her
// durumda çalışır. Hiç şube tanımlı değilse kısıtlama uygulanmaz.
// ============================================================
var SUBE_BASLIK = ['Ad', 'Enlem', 'Boylam', 'Yarıçap (m)'];
function subeleriOku() {
  var sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName('Subeler');
  if (!sheet || sheet.getLastRow() < 2) return [];
  return sheet.getRange(2, 1, sheet.getLastRow() - 1, SUBE_BASLIK.length).getValues().map(function (r) {
    return { ad: String(r[0] || '').trim(), enlem: Number(r[1]), boylam: Number(r[2]), yaricap: Number(r[3]) || 300 };
  }).filter(function (b) { return b.ad && !isNaN(b.enlem) && !isNaN(b.boylam) && b.enlem !== 0 && b.boylam !== 0; });
}
function subeKaydet(user, pass, data, callback) {
  var auth = requirePermission(user, pass, 'ayarlar');
  if (!auth.ok) return outJson({ status: 'error', message: auth.message }, callback);
  var liste;
  try { liste = JSON.parse(data || '[]'); } catch (e) { return outJson({ status: 'error', message: 'Şube listesi okunamadı' }, callback); }
  if (!Array.isArray(liste)) return outJson({ status: 'error', message: 'Şube listesi okunamadı' }, callback);
  var satirlar = [];
  for (var i = 0; i < liste.length; i++) {
    var b = liste[i] || {};
    var ad = String(b.ad || '').trim().substring(0, 60);
    var enlem = Number(b.enlem), boylam = Number(b.boylam), yaricap = Math.round(Number(b.yaricap) || 300);
    if (!ad || isNaN(enlem) || isNaN(boylam) || Math.abs(enlem) > 90 || Math.abs(boylam) > 180) {
      return outJson({ status: 'error', message: 'Geçersiz şube: ' + (ad || '(adsız)') }, callback);
    }
    satirlar.push([ad, enlem, boylam, Math.max(50, Math.min(yaricap, 5000))]);
  }
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sheet = ss.getSheetByName('Subeler');
  if (!sheet) sheet = ss.insertSheet('Subeler');
  sheet.clear();
  sheet.getRange(1, 1, 1, SUBE_BASLIK.length).setValues([SUBE_BASLIK]);
  if (satirlar.length) sheet.getRange(2, 1, satirlar.length, SUBE_BASLIK.length).setValues(satirlar);
  gunlukYaz('yonetim', String(user || ''), 'Şube konumları kaydedildi: ' + (satirlar.map(function (r) { return r[0] + ' (' + r[3] + ' m)'; }).join(', ') || 'hiç şube yok'), false);
  return outJson({ status: 'ok', subeler: subeleriOku() }, callback);
}
function konumBildir(p, callback) {
  var personel = String(p.personel || '?').substring(0, 60);
  var detay;
  if (p.durum === 'icerde') detay = 'Giriş: ' + String(p.sube || '').substring(0, 60) + ' içinde';
  else if (p.durum === 'disarda') detay = 'Giriş: ŞUBE DIŞINDA — en yakın ' + String(p.sube || '').substring(0, 60) + ' ' + String(p.mesafe || '?').substring(0, 12) + ' uzakta (fiyat/stok gizlendi)';
  else detay = 'Giriş: konum alınamadı — ' + String(p.hata || '').substring(0, 120) + ' (fiyat/stok gizlendi)';
  if (p.dogruluk) detay += ' · GPS ±' + String(p.dogruluk).substring(0, 8) + ' m';
  gunlukYaz('konum', 'telefon: ' + personel, detay, false);
  return outJson({ status: 'ok' }, callback);
}

function hataBildir(p, callback) {
  var personel = String(p.personel || '?').substring(0, 60);
  var mesaj = String(p.mesaj || '').substring(0, 300);
  if (mesaj) gunlukYaz('telefon_hata', 'telefon: ' + personel + (p.build ? ' (' + String(p.build).substring(0, 20) + ')' : ''), mesaj, true);
  return outJson({ status: 'ok' }, callback);
}

function sistemDurumu(user, pass, callback) {
  var auth = requirePermission(user, pass, 'canli_durum');
  if (!auth.ok) return outJson({ status: 'error', message: auth.message }, callback);
  var props = PropertiesService.getScriptProperties();
  var son = {};
  ['katalog', 'katalog_urun', 'cari', 'sayim', 'mal', 'masaustu_kontrol', 'masaustu', 'yetki', 'telefon_hata', 'hata', 'yonetim', 'konum', 'veritabani'].forEach(function (t) {
    try { var v = props.getProperty('SON_' + t); if (v) son[t] = JSON.parse(v); } catch (e) { /* bozuk kayıt: atla */ }
  });
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var satir = function (ad) { var sh = ss.getSheetByName(ad); return sh ? Math.max(sh.getLastRow() - 1, 0) : 0; };
  var malBekleyen = 0;
  var mal = ss.getSheetByName('MalHareket');
  if (mal && mal.getLastRow() >= 2 && mal.getLastColumn() >= MAL_COL.AKTARILDI) {
    mal.getRange(2, MAL_COL.BATCH, mal.getLastRow() - 1, 2).getValues().forEach(function (r) { if (r[0] && !r[1]) malBekleyen++; });
  }
  var gunluk = [];
  var g = ss.getSheetByName('SistemGunlugu');
  if (g && g.getLastRow() >= 2) {
    var n = Math.min(150, g.getLastRow() - 1);
    gunluk = g.getRange(g.getLastRow() - n + 1, 1, n, GUNLUK_BASLIK.length).getValues().reverse().map(function (r) {
      return { zaman: r[0] instanceof Date ? Utilities.formatDate(r[0], Session.getScriptTimeZone() || 'GMT+3', 'yyyy-MM-dd HH:mm:ss') : String(r[0]),
        tur: String(r[1]), kaynak: String(r[2]), detay: String(r[3]), hata: String(r[4]) === 'HATA' };
    });
  }
  return outJson({
    status: 'ok', surum: GS_VERSION, sunucuZamani: simdiMetin(), sunucuMs: Date.now(),
    son: son,
    sayilar: { katalog: satir('Katalog'), cari: satir('Cari'), sayim: satir('Sayim'), gecGelen: satir('GecGelenKayitlar'), malBekleyenSatir: malBekleyen, dbKuyruk: satir(DB_KUYRUK_SEKME) },
    veritabani: !!dbAyar(),
    katalogSurumu: props.getProperty('KATALOG_VERSION') || '',
    gunluk: gunluk
  }, callback);
}

function doPost(e) {
  var cevap = doPostIsle(e);
  // Veri tabanı gölge kopyası: kilit bırakıldıktan SONRA, en fazla dakikada bir.
  dbGerekirseGonder();
  return cevap;
}

function doPostIsle(e) {
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
    // Reddedilen verinin türünü ve göndereni günlükte göster (örn. ERP'nin katalog gönderimi).
    var redTur = 'sayım', redKaynak = 'sunucu';
    try {
      var redVeri = JSON.parse(e.postData.contents);
      redTur = redVeri.type || 'sayım';
      redKaynak = redVeri.kaynak || (redVeri.type === 'katalog_bulk' || redVeri.type === 'cari_bulk' ? 'ERP / dış program' : ('telefon: ' + (redVeri.personnel || redVeri.personel || '?')));
    } catch (pe) { /* okunamadıysa genel mesaj */ }
    gunlukYaz('hata', redKaynak, 'Sunucu yoğun: kilit 30 sn içinde alınamadı, gelen ' + redTur + ' verisi REDDEDİLDİ' +
      (redTur === 'katalog_bulk' || redTur === 'cari_bulk' ? ' — bir sonraki zamanlanmış gönderimde tekrar gelmeli' : ' — telefon tekrar gönderecek'), true);
    return ContentService
      .createTextOutput(JSON.stringify({ status: 'error', message: 'Sunucu yoğun, kilit alınamadı — tekrar denenecek' }))
      .setMimeType(ContentService.MimeType.JSON);
  }

  try {
    var data = JSON.parse(e.postData.contents);

    // Kaynak: telefon kendini bildirir ("telefon: Ali"); bildirmeyen gönderici
    // ERP bilgisayarındaki aktarım programıdır.
    var kaynak = data.kaynak ? String(data.kaynak) : 'ERP / dış program';
    if (data.type === 'katalog_bulk') {
      var kOut = saveKatalogBulk(data.entries || []);
      var kDegismedi = kOut.getContent().indexOf('degisiklikYok') !== -1;
      gunlukYaz('katalog', kaynak, (data.entries || []).length + ' ürün geldi' + (kDegismedi ? ' — değişiklik yok, tablo aynen kaldı' : ' — katalog güncellendi'), false);
      return kOut;
    }
    if (data.type === 'katalog_item') {
      var kiOut = saveKatalogItem(data.entry || {});
      gunlukYaz('katalog_urun', kaynak, 'Tek ürün: ' + ((data.entry && data.entry.name) || '') + ' (' + ((data.entry && data.entry.barcode) || '') + ')', false);
      return kiOut;
    }
    if (data.type === 'cari_bulk') {
      var cOut = saveCariBulk(data.entries || []);
      var cDegismedi = cOut.getContent().indexOf('degisiklikYok') !== -1;
      gunlukYaz('cari', kaynak, (data.entries || []).length + ' cari geldi' + (cDegismedi ? ' — değişiklik yok' : ' — liste güncellendi'), false);
      return cOut;
    }
    if (data.type === 'mal_hareket') {
      var mOut = saveMalHareket(data);
      dbKuyrugaEkle('mal', data);
      var mr = {};
      try { mr = JSON.parse(mOut.getContent()); } catch (pe) { /* özet olmadan da günlüğe yaz */ }
      gunlukYaz('mal', 'telefon: ' + (data.personel || '?'),
        (data.tip === 'cikis' ? 'Mal Çıkış' : 'Mal Giriş') + ' · ' + (data.cari || '') + (data.faturaNo ? ' · No ' + data.faturaNo : '') +
        ' · ' + (data.rows || []).length + ' satır (yeni ' + (mr.saved || 0) + ', güncellenen ' + (mr.guncellenen || 0) + ', silinen ' + (mr.silinen || 0) + ')' +
        (mr.kilitli ? ' · ' + mr.kilitli + ' satır ERP\'ye aktarıldığı için değiştirilemedi' : ''), !!mr.kilitli);
      return mOut;
    }

    // ---- Normal sayım verisi ----
    var ss = SpreadsheetApp.getActiveSpreadsheet();
    // ⚠️ ESKİDEN: ss.getSheetByName('Sayim') || ss.getActiveSheet() — "Sayim"
    // sekmesi bulunamazsa, o an kimin tarayıcısında hangi sekme açıksa (ör.
    // Katalog, Kullanicilar) ORAYA yazılıyordu! Bu, farklı bir sekmeye
    // bakarken bir telefon veri gönderirse veri karışmasına yol açabilirdi.
    // Artık "Sayim" sekmesi yoksa GÜVENLE yeni bir tane oluşturuluyor,
    // asla başka bir sekmeye yazılmıyor.
    var sheet = ss.getSheetByName('Sayim');
    if (!sheet) sheet = ss.insertSheet('Sayim');
    ensureSayimColumns(sheet);

    var personnel = data.personnel || '';
    var sessionId = data.sessionId || '';
    var rows = data.rows || [];

    // Silindi işaretleri: yönetici ya da telefon tarafından silinmiş kayıtlar.
    // Eski bir gönderi (örn. sendBeacon ile geç ulaşan) bu kayıtları GERİ
    // GETİREMEZ.
    var silinenler = readSilinenler();

    // GEÇ GELEN KAYITLAR: Yönetici dosyayı temizledikten sonra, temizlikten
    // ÖNCE okutulmuş ama o an gönderilememiş kayıtlar yeni sayımı kirletmesin
    // diye 'Sayim' yerine 'GecGelenKayitlar' sekmesine yazılır (kaybolmaz).
    // Telefon her gönderiye bildiği son temizlik damgasını (resetToken)
    // ekler. Damga eskiyse ve kayıt temizlikten önce okutulduysa (ts) geç
    // gelmiş sayılır.
    var aktifToken = PropertiesService.getScriptProperties().getProperty('RESET_TOKEN') || '';
    var resetZamani = aktifToken ? Date.parse(aktifToken) : NaN;
    var eskiDonem = !!(data.resetToken && aktifToken && String(data.resetToken) !== aktifToken);
    var normalRows = [];
    var gecRows = [];
    rows.forEach(function (row) {
      var ts = Number(row.ts);
      var gec = eskiDonem && (isNaN(resetZamani) || !ts || ts < resetZamani);
      (gec ? gecRows : normalRows).push(row);
    });

    var yazim = writeSayimRows(sheet, normalRows, personnel, sessionId, silinenler);
    var skipped = yazim.skipped;
    var onay = yazim.ack;
    if (gecRows.length > 0) {
      var gecYazim = writeSayimRows(gecGelenSheet(true), gecRows, personnel, sessionId, silinenler);
      skipped += gecYazim.skipped;
      Object.keys(gecYazim.ack).forEach(function (k) { onay[k] = gecYazim.ack[k]; });
    }

    // Telefonda silinmiş kayıtları tablodan da sil. "rows" listesinde
    // artık bulunmaması tek başına yeterli değildir — sunucu bunu "hiç
    // gönderilmedi" ile ayırt edemez, bu yüzden istemci silinen id'leri
    // ayrıca bildirir (deletedIds). Silinen her kayda ayrıca "silindi
    // işareti" konur ki eski bir gönderi onu geri getirmesin.
    var deletedIds = (data.deletedIds || []).map(String);
    if (deletedIds.length > 0) {
      var yeniSilinen = deletedIds.filter(function (d) { return !silinenler[d]; });
      if (yeniSilinen.length > 0) addSilinenler(yeniSilinen, sessionId, personnel || 'telefon');
      deleteSayimIds(sheet, deletedIds);
      var gs = gecGelenSheet(false);
      if (gs) deleteSayimIds(gs, deletedIds);
    }

    // Son yazma zamanı (oturum bazında): yönetici rapor oluştururken
    // "telefonlardan hâlâ veri geliyor mu?" kontrolü için (bkz. handleFinalize).
    if (rows.length > 0 || deletedIds.length > 0) {
      sonYazmaKaydet(sessionId);
      dbKuyrugaEkle('sayim', { personnel: personnel, sessionId: sessionId, resetToken: data.resetToken || '', rows: rows, deletedIds: deletedIds });
    }
    // HIZLI ONAY: Bu gönderinin sonucunu (her kaydın tablodaki sürümü/adedi ve
    // bu oturumda silinenler) kısa süreliğine önbelleğe koy. Telefon hemen
    // ardından "sayim_kontrol" ile aynı "nonce"u sorunca tablo HİÇ taranmadan
    // cevap verilir. Önbellekte yoksa (süresi dolduysa) eski yöntemle tablo taranır.
    if (data.nonce && sessionId) {
      try {
        // Yöneticinin bu oturumda "Düzelt" ekranından değiştirdiği kayıtlar da
        // onaya eklenir — telefon yeni adedi/sürümü hemen kendine alır.
        var duzeltilen = [];
        try { duzeltilen = JSON.parse(CacheService.getScriptCache().get('duzelt_' + sessionId) || '[]'); } catch (de) { duzeltilen = []; }
        duzeltilen.forEach(function (did) {
          if (!onay[did] && yazim.tablo.v[did] !== undefined) onay[did] = [yazim.tablo.v[did], yazim.tablo.q[did]];
        });
        var silinenOturum = deletedIds.slice();
        Object.keys(silinenler).forEach(function (sid) { if (silinenler[sid] === sessionId && silinenOturum.indexOf(sid) === -1) silinenOturum.push(sid); });
        var onayJson = JSON.stringify({ rows: onay, deleted: silinenOturum });
        if (onayJson.length < 90000) CacheService.getScriptCache().put('ack_' + sessionId + '_' + data.nonce, onayJson, 21600);
      } catch (ce) { /* önbellek olmazsa telefon tablo taramasıyla onay alır */ }
    }
    if (rows.length > 0 || deletedIds.length > 0) {
      // Sayım gönderimleri çok sık gelir: "son olay" her seferinde güncellenir
      // (Sistem Durumu kartı anlık kalır) ama günlük sekmesine en fazla
      // dakikada bir satır yazılır — sunucu kilidi gereksiz uzamasın.
      var sayimDetay = rows.length + ' kayıt' + (deletedIds.length ? ', ' + deletedIds.length + ' silme' : '') +
        (skipped ? ', ' + skipped + ' atlandı (eski sürüm/silinmiş)' : '') + (gecRows.length ? ', ' + gecRows.length + ' geç gelen' : '');
      var gProps = PropertiesService.getScriptProperties();
      var sonSatirMs = Number(gProps.getProperty('GUNLUK_SAYIM_MS') || 0);
      if (Date.now() - sonSatirMs > 60000) {
        gProps.setProperty('GUNLUK_SAYIM_MS', String(Date.now()));
        gunlukYaz('sayim', 'telefon: ' + (personnel || '?'), sayimDetay, false);
      } else {
        sonKaydet('sayim', 'telefon: ' + (personnel || '?'), sayimDetay, false);
      }
    }

    return ContentService
      .createTextOutput(JSON.stringify({ status: 'ok', processed: rows.length, skipped: skipped, gecGelen: gecRows.length }))
      .setMimeType(ContentService.MimeType.JSON);

  } catch (err) {
    gunlukYaz('hata', 'sunucu', 'Gelen veri işlenemedi' + (data && data.type ? ' (' + data.type + ')' : '') + ': ' + err.toString(), true);
    return ContentService
      .createTextOutput(JSON.stringify({ status: 'error', message: err.toString() }))
      .setMimeType(ContentService.MimeType.JSON);
  } finally {
    lock.releaseLock();
  }
}

// Sheets, hücreye yazılan METİN sayıları kendi dil ayarına göre otomatik
// yorumlamaya çalışır — Türkçe ayarda "nokta" binlik ayraç sayıldığı için,
// SQL'den gelen "2.00000000" gibi ondalıklı bir metin yanlışlıkla "2 milyar"
// gibi devasa bir sayıya dönüşebiliyordu. Bunu önlemek için, sayısal
// alanları (Eski Stok, Fiyat) sheet'e METİN değil GERÇEK SAYI olarak
// yazıyoruz — bu şekilde Sheets hiçbir yorum yapmadan, olduğu gibi kaydeder.
function cleanNum(v) {
  if (v === '' || v === null || v === undefined) return '';
  var n = Number(v);
  return isNaN(n) ? '' : n;
}

// Gelen listenin özeti (MD5). ERP programı listeyi 15 dk'da bir gönderiyor;
// liste DEĞİŞMEDİYSE tablo yeniden yazılmaz ve sürüm damgası değişmez —
// böylece sunucu kilidi boşuna tutulmaz ve telefonlar aynı kataloğu tekrar
// tekrar indirmez.
function listeOzeti(rows) {
  var d = Utilities.computeDigest(Utilities.DigestAlgorithm.MD5, JSON.stringify(rows), Utilities.Charset.UTF_8);
  return Utilities.base64Encode(d);
}

function saveKatalogBulk(entries) {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sheet = ss.getSheetByName('Katalog');
  if (!sheet) sheet = ss.insertSheet('Katalog');
  var props = PropertiesService.getScriptProperties();
  var ozet = listeOzeti(entries.map(function (e) { return [e.name || '', e.barcode || '', e.stockCode || '', cleanNum(e.oldStock), cleanNum(e.price), cleanNum(e.kdv)]; }));
  if (entries.length > 0 && ozet === props.getProperty('KATALOG_OZET') && sheet.getLastRow() === entries.length + 1) {
    return ContentService.createTextOutput(JSON.stringify({ status: 'ok', saved: 0, degisiklikYok: true })).setMimeType(ContentService.MimeType.JSON);
  }
  sheet.clear();
  sheet.appendRow(['Ürün Adı', 'Barkod', 'Stok Kodu', 'Eski Stok', 'Fiyat', 'KDV %']);
  if (entries.length > 0) {
    var rows = entries.map(function (e) {
      return [e.name || '', e.barcode || '', e.stockCode || '', cleanNum(e.oldStock), cleanNum(e.price), cleanNum(e.kdv)];
    });
    sheet.getRange(2, 1, rows.length, 6).setValues(rows);
    // Fiyat sütununu her zaman 2 ondalık basamakla göster — Sheets'in
    // "Otomatik" biçimi bazen kuruşu gizleyip tam sayıya yuvarlanmış
    // GÖRÜNMESİNE yol açabiliyor (asıl değer bozulmuyor ama kafa karıştırıyor).
    sheet.getRange(2, 5, rows.length, 1).setNumberFormat('0.00');
    sheet.getRange(2, 6, rows.length, 1).setNumberFormat('0.##');
  }
  // Katalog her değiştiğinde bir "sürüm" damgası basıyoruz — telefonlar bunu
  // (resetcheck ile) düzenli kontrol edip kendi sürümünden farklıysa
  // kataloğu OTOMATİK olarak sunucudan çeker, kimse elle "Sunucudan Çek"e
  // basmak zorunda kalmaz.
  props.setProperty('KATALOG_VERSION', new Date().toISOString());
  props.setProperty('KATALOG_OZET', ozet);
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
    sheet.appendRow(['Ürün Adı', 'Barkod', 'Stok Kodu', 'Eski Stok', 'Fiyat', 'KDV %']);
  }
  var lastRow = sheet.getLastRow();
  var rowData = [entry.name, entry.barcode, entry.stockCode || '', cleanNum(entry.oldStock), cleanNum(entry.price), cleanNum(entry.kdv)];
  PropertiesService.getScriptProperties().setProperty('KATALOG_VERSION', new Date().toISOString());
  PropertiesService.getScriptProperties().deleteProperty('KATALOG_OZET'); // bir sonraki ERP listesi tabloyu yeniden yazsın
  if (lastRow >= 2) {
    var barcodes = sheet.getRange(2, 2, lastRow - 1, 1).getValues();
    for (var i = 0; i < barcodes.length; i++) {
      if (String(barcodes[i][0]) === String(entry.barcode)) {
        sheet.getRange(i + 2, 1, 1, 6).setValues([rowData]);
        sheet.getRange(i + 2, 5, 1, 1).setNumberFormat('0.00');
        sheet.getRange(i + 2, 6, 1, 1).setNumberFormat('0.##');
        return ContentService.createTextOutput(JSON.stringify({ status: 'ok', updated: true }))
          .setMimeType(ContentService.MimeType.JSON);
      }
    }
  }
  sheet.appendRow(rowData);
  sheet.getRange(sheet.getLastRow(), 5, 1, 1).setNumberFormat('0.00');
  sheet.getRange(sheet.getLastRow(), 6, 1, 1).setNumberFormat('0.##');
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
    dbKuyrugaEkle('donem', { token: token, aciklama: 'Dosya temizlendi, arşiv: ' + archivedName });
    gunlukYaz('yonetim', String(user || ''), 'Sayım dosyası temizlendi, arşiv: ' + archivedName, false);
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
// Telefonlardan son veri bu kadar süre içinde geldiyse rapor hemen
// oluşturulmaz; yönetici onaylarsa (force=1) yine de oluşturulur.
var FINALIZE_SESSIZ_MS = 45000;

// { oturumId: son yazma zamanı(ms) } — sadece son 5 dakika tutulur.
function sonYazmalariOku() {
  try { return JSON.parse(PropertiesService.getScriptProperties().getProperty('SON_YAZMALAR') || '{}') || {}; }
  catch (e) { return {}; }
}
function sonYazmaKaydet(sessionId) {
  var son = sonYazmalariOku();
  var simdi = Date.now();
  son[String(sessionId || '?')] = simdi;
  Object.keys(son).forEach(function (k) { if (simdi - Number(son[k]) > 300000) delete son[k]; });
  PropertiesService.getScriptProperties().setProperty('SON_YAZMALAR', JSON.stringify(son));
}

// haric: rapor isteyen telefonun kendi oturumları (virgülle) — o telefon
// rapordan hemen önce kendi verisini gönderdiği için bunlar sayılmaz.
function handleFinalize(user, pass, force, haric, callback) {
  var auth = requirePermission(user, pass, 'rapor');
  if (!auth.ok) return outJson({ status: 'error', message: auth.message }, callback);
  var lock = LockService.getScriptLock();
  try { lock.waitLock(30000); } catch (e) { return outJson({ status: 'error', message: 'Sunucu meşgul, birazdan tekrar dene' }, callback); }
  // Gönderim sürerken rapor oluşmasın: telefonlardan çok yakın zamanda veri
  // geldiyse bazı telefonlar hâlâ gönderiyor olabilir — yöneticiye sor.
  if (String(force) !== '1') {
    var haricSet = {};
    String(haric || '').split(',').forEach(function (x) { x = x.trim(); if (x) haricSet[x] = true; });
    var son = sonYazmalariOku();
    var sonYazma = 0;
    Object.keys(son).forEach(function (k) { if (!haricSet[k]) sonYazma = Math.max(sonYazma, Number(son[k]) || 0); });
    var gecen = Date.now() - sonYazma;
    if (sonYazma && gecen < FINALIZE_SESSIZ_MS) {
      lock.releaseLock();
      return outJson({ status: 'busy', saniye: Math.round(gecen / 1000),
        message: 'Telefonlardan ' + Math.round(gecen / 1000) + ' saniye önce veri geldi — gönderim sürüyor olabilir.' }, callback);
    }
  }
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

    // 1. ADIM: Aynı BARKOD birden çok kez okutulmuşsa (koli koli / parça
    //    parça sayım), hepsini TOPLA — düzeltme ihtiyacı olan yanlış bir
    //    okutma varsa zaten "Sayım Kayıtlarını Düzelt" ekranından tek tek
    //    silinip/değiştirilebiliyor, o yüzden burada "son kazanır" değil
    //    "hepsi toplanır" mantığı doğru olan.
    var byBarcode = {};
    rows.forEach(function (r) {
      var stockCode = String(r[idx['Stok Kodu']] || '').trim();
      var barcode = String(r[idx['Barkod']] || '').trim();
      var key = barcode || ('S:' + stockCode);
      if (!key || key === 'S:') return;
      var ts = formatDateValue(r[idx['Tarih']]) + ' ' + formatTimeValue(r[idx['Saat']]);
      if (!byBarcode[key]) {
        byBarcode[key] = {
          stockCode: stockCode, barcode: barcode, name: String(r[idx['Ürün Adı']] || ''),
          unit: String(r[idx['Birim']] || 'Adet'), oldStock: r[idx['Eski Stok']],
          qty: 0, lastPersonnel: String(r[idx['Personel']] || ''),
          lastTs: ts, scanCount: 0
        };
      }
      byBarcode[key].scanCount++;
      byBarcode[key].qty += Number(r[idx['Sayılan Adet']]) || 0;
      if (ts >= byBarcode[key].lastTs) {
        byBarcode[key].lastTs = ts;
        byBarcode[key].lastPersonnel = String(r[idx['Personel']] || '');
        if (r[idx['Eski Stok']] !== '' && r[idx['Eski Stok']] !== undefined) byBarcode[key].oldStock = r[idx['Eski Stok']];
      }
    });

    // 2. ADIM: Aynı STOK KODU altındaki FARKLI barkodların (1. adımdaki
    //    final değerlerini) TOPLA — bunlar gerçek anlamda ayrı sayımlardır
    //    (örn. aynı ürünün 2 farklı barkodu), aynı barkodun tekrarı değil.
    //    "Eski Stok" toplanmaz — kataloğa aynı stok kodu için hangi barkod
    //    satırında girildiyse o değer (hepsinde aynı olması beklenir) esas
    //    alınır.
    var groups = {};
    Object.keys(byBarcode).forEach(function (bKey) {
      var b = byBarcode[bKey];
      var key = b.stockCode || ('B:' + b.barcode);
      if (!groups[key]) {
        groups[key] = {
          stockCode: b.stockCode, barcodes: [], name: b.name,
          unit: b.unit, oldStock: b.oldStock, finalQty: 0,
          lastPersonnel: b.lastPersonnel, lastTs: b.lastTs, scanCount: 0
        };
      }
      groups[key].finalQty += b.qty;
      groups[key].scanCount += b.scanCount;
      if (groups[key].barcodes.indexOf(b.barcode) === -1) groups[key].barcodes.push(b.barcode);
      if (b.lastTs >= groups[key].lastTs) {
        groups[key].lastTs = b.lastTs;
        groups[key].lastPersonnel = b.lastPersonnel;
        if (b.oldStock !== '' && b.oldStock !== undefined) groups[key].oldStock = b.oldStock;
      }
    });

    var finalRows = [];
    var toplamAdet = 0, dogrulukToplam = 0, dogrulukSayisi = 0;
    var anomaliler = [];
    Object.keys(groups).forEach(function (key) {
      var g = groups[key];
      var canonName = (g.stockCode && canonByStock[g.stockCode]) || canonByBarcode[g.barcodes[0]] || g.name;
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
      finalRows.push([g.stockCode, canonName, g.barcodes.join(' + '), g.unit, oldStockNum === null ? '' : oldStockNum, g.finalQty, fark, g.lastPersonnel, g.lastTs, g.scanCount]);
    });

    var sonSheet = ss.getSheetByName('Son Stok Sayimi');
    if (!sonSheet) sonSheet = ss.insertSheet('Son Stok Sayimi'); else sonSheet.clear();
    sonSheet.appendRow(['Stok Kodu', 'Ürün Adı', 'Barkod', 'Birim', 'Eski Stok', 'Final Adet', 'Fark', 'Son Sayan', 'Son Zaman', 'Kaç Kez Okutuldu']);
    if (finalRows.length > 0) sonSheet.getRange(2, 1, finalRows.length, finalRows[0].length).setValues(finalRows);

    var personelStats = {};
    rows.forEach(function (r) {
      var p = String(r[idx['Personel']] || '—');
      var ts = formatDateValue(r[idx['Tarih']]) + ' ' + formatTimeValue(r[idx['Saat']]);
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
    raporSheet.appendRow(['']);
    raporSheet.appendRow(['Toplam farklı ürün çeşidi', Object.keys(groups).length]);
    raporSheet.appendRow(['Toplam sayılan adet (final, birleştirilmiş)', toplamAdet]);
    raporSheet.appendRow(['Toplam okutma (ham satır) sayısı', rows.length]);
    raporSheet.appendRow(['Ortalama doğruluk (eski stoğa göre)', ortalamaDogruluk !== null ? ('%' + ortalamaDogruluk) : '—']);
    raporSheet.appendRow(['']);
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
    raporSheet.appendRow(['']);
    raporSheet.appendRow(['DİKKAT ÇEKEN FARKLAR (eski stoğa göre %30+ sapma)']);
    if (anomaliler.length === 0) raporSheet.appendRow(['(yok)']);
    anomaliler.forEach(function (a) { raporSheet.appendRow([a]); });

    var aiYorum = '';
    var apiKey = PropertiesService.getScriptProperties().getProperty('ANTHROPIC_API_KEY');
    if (apiKey && anomaliler.length > 0) {
      try {
        aiYorum = getAiYorum(apiKey, anomaliler, Object.keys(groups).length, toplamAdet, ortalamaDogruluk);
        if (aiYorum) {
          raporSheet.appendRow(['']);
          raporSheet.appendRow(['YAPAY ZEKA DEĞERLENDİRMESİ']);
          raporSheet.appendRow([aiYorum]);
        }
      } catch (aiErr) {
        raporSheet.appendRow(['YAPAY ZEKA DEĞERLENDİRMESİ (çalışmadı: ' + aiErr + ')']);
      }
    }

    try { raporSheet.hideSheet(); } catch (hideErr) { /* önemli değil */ }

    // Yönetici bir yedek e-posta adresi tanımladıysa, Son Stok Sayımı'nı
    // CSV eki olarak otomatik gönder. Adres tanımlı değilse hiçbir şey
    // yapılmaz, rapor normal şekilde oluşur.
    var backupEmail = PropertiesService.getScriptProperties().getProperty('BACKUP_EMAIL');
    var emailGonderildi = false;
    if (backupEmail) {
      try {
        var csvHeaders = ['Stok Kodu', 'Ürün Adı', 'Barkod', 'Birim', 'Eski Stok', 'Final Adet', 'Fark', 'Son Sayan', 'Son Zaman', 'Kaç Kez Okutuldu'];
        var csvLines = [csvHeaders.join(';')];
        finalRows.forEach(function (r) {
          csvLines.push(r.map(function (v) {
            var s = (v === null || v === undefined) ? '' : String(v);
            if (s.indexOf(';') !== -1 || s.indexOf('"') !== -1) s = '"' + s.replace(/"/g, '""') + '"';
            return s;
          }).join(';'));
        });
        var csvBlob = Utilities.newBlob('\uFEFF' + csvLines.join('\r\n'), 'text/csv', 'son-stok-sayimi.csv');
        var tarihStr = Utilities.formatDate(new Date(), Session.getScriptTimeZone() || 'GMT+3', 'yyyy-MM-dd HH:mm');
        MailApp.sendEmail({
          to: backupEmail,
          subject: 'Murat Gıda Sayım Raporu — ' + tarihStr,
          body: 'Sayım tamamlandı.\n\n' +
            'Ürün çeşidi: ' + Object.keys(groups).length + '\n' +
            'Toplam adet: ' + toplamAdet + '\n' +
            'Ortalama doğruluk: %' + (ortalamaDogruluk !== null ? ortalamaDogruluk : '—') + '\n' +
            'Dikkat çeken fark sayısı: ' + anomaliler.length + '\n\n' +
            'Son Stok Sayımı ekte CSV olarak bulunuyor.' +
            (aiYorum ? ('\n\nYapay zeka değerlendirmesi:\n' + aiYorum) : ''),
          attachments: [csvBlob]
        });
        emailGonderildi = true;
      } catch (mailErr) { /* mail gönderilemezse rapor yine de oluşur, sessiz geç */ }
    }

    gunlukYaz('yonetim', String(user || ''), 'Rapor oluşturuldu: ' + Object.keys(groups).length + ' çeşit, ' + toplamAdet + ' adet' + (String(force) === '1' ? ' (veri gelirken zorla)' : ''), false);
    return outJson({
      status: 'ok',
      toplamCesit: Object.keys(groups).length,
      toplamAdet: toplamAdet,
      ortalamaDogruluk: ortalamaDogruluk !== null ? ortalamaDogruluk : '—',
      anomaliSayisi: anomaliler.length,
      anomaliler: anomaliler.slice(0, 40),
      personelListesi: personelListesi,
      aiYorum: aiYorum,
      emailGonderildi: emailGonderildi,
      backupEmail: emailGonderildi ? backupEmail : ''
    }, callback);
  } catch (err) {
    gunlukYaz('hata', 'sunucu', 'Rapor oluşturulamadı: ' + err.toString(), true);
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
// - BACKUP_EMAIL: "Sayımı Bitir ve Rapor Oluştur" her çalıştığında, Son
//   Stok Sayımı'nı CSV eki olarak bu adrese otomatik gönderir. Boşsa mail
//   hiç gönderilmez.
// Her telefon kendi ekranında bunu elle de değiştirebilir; buradaki değer
// sadece yeni açılan / hiç değiştirilmemiş telefonlar için varsayılanı
// belirler.
// ============================================================
function handleAyarKaydet(user, pass, wakelock, idleMinutes, backupEmail, malEmail, callback) {
  var auth = requirePermission(user, pass, 'ayarlar');
  if (!auth.ok) return outJson({ status: 'error', message: auth.message }, callback);
  var props = PropertiesService.getScriptProperties();
  props.setProperty('DEFAULT_WAKE_LOCK', wakelock === 'false' ? 'false' : 'true');
  var mins = parseInt(idleMinutes, 10);
  if (isNaN(mins) || mins < 0) mins = 0;
  props.setProperty('DEFAULT_IDLE_MINUTES', String(mins));
  var email = String(backupEmail || '').trim();
  if (email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    return outJson({ status: 'error', message: 'Geçersiz e-posta adresi' }, callback);
  }
  // Mal Giriş/Çıkış e-postası: parametre hiç gelmediyse (eski sürüm bir telefon)
  // mevcut değere dokunma; boş gelirse mail özelliğini kapat.
  if (malEmail !== undefined) {
    var mEmail = String(malEmail || '').trim();
    if (mEmail && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(mEmail)) {
      return outJson({ status: 'error', message: 'Geçersiz mal giriş/çıkış e-posta adresi' }, callback);
    }
    props.setProperty('MAL_EMAIL', mEmail);
  }
  props.setProperty('BACKUP_EMAIL', email);
  return outJson({ status: 'ok' }, callback);
}

// Ayarlar sadece 'ayarlar' yetkisi olana gösterilir — resetcheck (herkese
// açık) yalnızca defaultWakeLock/idleMinutes döner, e-posta adresini asla
// içermez (gereksiz yere her telefona sızmasın diye).
function getAyarlar(user, pass, callback) {
  var auth = requirePermission(user, pass, 'ayarlar');
  if (!auth.ok) return outJson({ status: 'error', message: auth.message }, callback);
  var props = PropertiesService.getScriptProperties();
  return outJson({
    status: 'ok',
    defaultWakeLock: props.getProperty('DEFAULT_WAKE_LOCK') || 'true',
    idleMinutes: props.getProperty('DEFAULT_IDLE_MINUTES') || '0',
    backupEmail: props.getProperty('BACKUP_EMAIL') || '',
    // Hiç ayarlanmamışsa (null) sabit varsayılanı göster — panelde boş görünmesin,
    // "zaten bir adrese gidiyor" belli olsun. Bilerek boşaltılmışsa boş kalır.
    malEmail: (function () { var v = props.getProperty('MAL_EMAIL'); return v === null ? VARSAYILAN_MAL_EMAIL : v; })()
  }, callback);
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
      var tsStr = formatDateValue(r[idx['Tarih']]) + 'T' + formatTimeValue(r[idx['Saat']]);
      var ts = new Date(tsStr).getTime();
      if (!stats[p]) stats[p] = { okutma: 0, urunler: {}, sonTs: 0, sonZaman: '', sonUrun: '', sonReyon: '' };
      stats[p].okutma++;
      var stockKey = String(r[idx['Stok Kodu']] || '') || ('B:' + String(r[idx['Barkod']] || ''));
      stats[p].urunler[stockKey] = true;
      if (!isNaN(ts) && ts >= stats[p].sonTs) {
        stats[p].sonTs = ts;
        stats[p].sonZaman = formatDateValue(r[idx['Tarih']]) + ' ' + formatTimeValue(r[idx['Saat']]);
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
        kayitId: String(r[idx['Kayıt ID']] || ''), tarih: formatDateValue(r[idx['Tarih']]), saat: formatTimeValue(r[idx['Saat']]),
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
    var HEADERS = SAYIM_HEADERS;
    var idx = {}; HEADERS.forEach(function (h, i) { idx[h] = i; });
    if (!sheet || sheet.getLastRow() < 2) return outJson({ status: 'error', message: 'Kayıt bulunamadı' }, callback);
    ensureSayimColumns(sheet);
    var values = sheet.getRange(2, 1, sheet.getLastRow() - 1, HEADERS.length).getValues();
    for (var i = 0; i < values.length; i++) {
      if (String(values[i][idx['Kayıt ID']]) === String(kayitId)) {
        var rowNum = i + 2;
        var eskiStok = values[i][idx['Eski Stok']];
        var fark = (eskiStok !== '' && eskiStok !== undefined && !isNaN(Number(eskiStok))) ? (yeniAdet - Number(eskiStok)) : '';
        sheet.getRange(rowNum, idx['Sayılan Adet'] + 1).setValue(yeniAdet);
        sheet.getRange(rowNum, idx['Fark'] + 1).setValue(fark);
        // Sürümü artır: telefonda kuyrukta bekleyen (ya da geç ulaşan) ESKİ
        // sürüm artık bu düzeltmenin üzerine yazamaz. Telefon bir sonraki
        // onayda yeni adedi ve sürümü kendine alır.
        var yeniV = surumOku(values[i][idx['Sürüm']]) + 1;
        sheet.getRange(rowNum, idx['Sürüm'] + 1).setValue(yeniV);
        dbKuyrugaEkle('guncelle', { kayitId: String(kayitId), adet: yeniAdet, yonetici: String(user || '') });
        // Telefonun hızlı onayına eklensin diye oturum bazında not al (6 saat).
        try {
          var oturum = String(values[i][idx['Oturum ID']] || '');
          if (oturum) {
            var c = CacheService.getScriptCache();
            var liste = JSON.parse(c.get('duzelt_' + oturum) || '[]');
            if (liste.indexOf(String(kayitId)) === -1) liste.push(String(kayitId));
            c.put('duzelt_' + oturum, JSON.stringify(liste.slice(-500)), 21600);
          }
        } catch (ce) { /* not alınamazsa 10 dk'lık tam kontrol yakalar */ }
        return outJson({ status: 'ok', v: yeniV }, callback);
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
    var HEADERS = SAYIM_HEADERS;
    var idx = {}; HEADERS.forEach(function (h, i) { idx[h] = i; });
    if (!sheet || sheet.getLastRow() < 2) return outJson({ status: 'error', message: 'Kayıt bulunamadı' }, callback);
    ensureSayimColumns(sheet);
    var values = sheet.getRange(2, 1, sheet.getLastRow() - 1, HEADERS.length).getValues();
    for (var i = 0; i < values.length; i++) {
      if (String(values[i][idx['Kayıt ID']]) === String(kayitId)) {
        // Silindi işareti: telefonun kuyruğunda bekleyen eski bir gönderi bu
        // kaydı tabloya GERİ GETİREMEZ; telefon da bir sonraki onayda kaydı
        // kendi listesinden kaldırır.
        addSilinenler([kayitId], values[i][idx['Oturum ID']], String(user || 'yonetici'));
        sheet.deleteRow(i + 2);
        dbKuyrugaEkle('sil', { kayitId: String(kayitId), yonetici: String(user || 'yonetici') });
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

// ============================================================
// VERİ TABANI GÖLGE KOPYASI (Supabase / PostgreSQL)
// Sheets ASIL kayıt yeri olmaya devam eder. Sheets'e başarıyla yazılan her
// sayım/mal/düzeltme/silme/temizleme ayrıca gizli 'DbKuyruk' sekmesine not
// edilir ve arka planda veri tabanına gönderilir. Veri tabanına ulaşılamazsa
// kuyrukta bekler, sonra tekrar denenir. Telefonlar bundan ETKİLENMEZ:
// onay yine Sheets'ten gelir.
//
// AÇMAK İÇİN (bir kez): Apps Script → Proje Ayarları → Komut dosyası
// özellikleri → ekle:  DB_URL = https://<proje>.supabase.co
//                     DB_ANAHTAR = Supabase "secret" anahtarı (sb_secret_...)
// Sonra düzenleyicide dbKur fonksiyonunu bir kez çalıştırın.
// KAPATMAK İÇİN: DB_KAPALI = 1 ekleyin (kuyruğa yazma ve gönderim durur).
// Bu ayarlar yoksa bu bölümün hiçbir etkisi yoktur.
// ============================================================
var DB_KUYRUK_SEKME = 'DbKuyruk';
var DB_HUCRE_MAX = 45000;       // bir hücreye yazılan en uzun parça (Sheets sınırı 50.000)
var DB_GONDERIM_ARALIK_MS = 60000; // telefon isteklerinin ardından en fazla dakikada bir gönderim

function dbAyar() {
  var p = PropertiesService.getScriptProperties();
  if (String(p.getProperty('DB_KAPALI') || '') === '1') return null;
  var url = String(p.getProperty('DB_URL') || '').trim().replace(/\/+$/, '');
  var anahtar = String(p.getProperty('DB_ANAHTAR') || '').trim();
  return (url && anahtar) ? { url: url, anahtar: anahtar } : null;
}

function dbKuyrukSheet(olustur) {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sheet = ss.getSheetByName(DB_KUYRUK_SEKME);
  if (!sheet && olustur) {
    sheet = ss.insertSheet(DB_KUYRUK_SEKME);
    sheet.getRange(1, 1, 1, 4).setValues([['Kuyruk ID', 'Zaman', 'Tür', 'Veri (parça parça)']]);
    sheet.hideSheet();
  }
  return sheet;
}

// Kuyruğa ekle. Sheets'e yazan fonksiyonlar bunu KİLİT ALTINDA çağırır,
// böylece kuyruk sırası Sheets'teki yazma sırasıyla aynıdır. Hata olursa
// asıl işi (Sheets kaydını) asla bozmaz, sadece günlüğe yazar.
function dbKuyrugaEkle(tur, veri) {
  try {
    if (!dbAyar()) return;
    var metin = JSON.stringify(veri);
    var satir = [Utilities.getUuid(), simdiMetin(), tur];
    for (var i = 0; i < metin.length; i += DB_HUCRE_MAX) satir.push(metin.substring(i, i + DB_HUCRE_MAX));
    var sheet = dbKuyrukSheet(true);
    var hedef = sheet.getLastRow() + 1;
    sheet.getRange(hedef, 1, 1, satir.length).setNumberFormat('@').setValues([satir]);
  } catch (e) {
    gunlukYaz('veritabani', 'gölge kopya', 'Kuyruğa eklenemedi (' + tur + '): ' + e, true);
  }
}

// Veri tabanı fonksiyonunu çağırır. Ağ/HTTP hatasında İSTİSNA atar (kayıt
// kuyrukta kalır); fonksiyonun kendisi "status: error" dönerse sonucu döndürür.
function dbCagir(ayar, fonksiyon, govde) {
  var yanit = UrlFetchApp.fetch(ayar.url + '/rest/v1/rpc/' + fonksiyon, {
    method: 'post',
    contentType: 'application/json',
    payload: JSON.stringify(govde),
    headers: { apikey: ayar.anahtar },
    muteHttpExceptions: true
  });
  var kod = yanit.getResponseCode();
  var metin = yanit.getContentText() || '';
  if (kod < 200 || kod >= 300) throw new Error('HTTP ' + kod + ' — ' + metin.substring(0, 200));
  try { return JSON.parse(metin || 'null'); } catch (pe) { return metin; }
}

function dbKuyrukKaydiGonder(ayar, tur, veri) {
  if (tur === 'sayim') return dbCagir(ayar, 'sayim_yaz', { p: veri });
  if (tur === 'mal') return dbCagir(ayar, 'mal_yaz', { p: veri });
  if (tur === 'guncelle') return dbCagir(ayar, 'sayim_guncelle', { p_kayit: veri.kayitId, p_adet: veri.adet, p_yonetici: veri.yonetici || '' });
  if (tur === 'sil') return dbCagir(ayar, 'sayim_sil', { p_kayit: veri.kayitId, p_yonetici: veri.yonetici || '' });
  if (tur === 'donem') return dbCagir(ayar, 'yeni_donem', { p_aciklama: veri.aciklama || '', p_token: veri.token || '' });
  return { status: 'error', message: 'Bilinmeyen kuyruk türü: ' + tur };
}

// Kuyruktaki kayıtları SIRAYLA gönderir; ilk ağ hatasında durur (sıra
// bozulmasın). Gönderilenler kuyruktan silinir. Aynı anda tek gönderim.
function dbKuyrukGonder(sureMs) {
  var ayar = dbAyar();
  if (!ayar) return { durum: 'kapali' };
  var cache = CacheService.getScriptCache();
  if (cache.get('db_gonderim_aktif')) return { durum: 'mesgul' };
  cache.put('db_gonderim_aktif', '1', 360);
  var props = PropertiesService.getScriptProperties();
  props.setProperty('DB_SON_GONDERIM_MS', String(Date.now()));
  var baslangic = Date.now();
  var gonderilen = {}, gonderilenSayi = 0, reddedilen = 0, agHatasi = null;
  try {
    var sheet = dbKuyrukSheet(false);
    if (!sheet || sheet.getLastRow() < 2) return { durum: 'bos', kalan: 0 };
    var n = Math.min(sheet.getLastRow() - 1, 200);
    var degerler = sheet.getRange(2, 1, n, Math.max(sheet.getLastColumn(), 4)).getValues();
    for (var i = 0; i < degerler.length; i++) {
      if (Date.now() - baslangic > sureMs) break;
      var r = degerler[i];
      var kimlik = String(r[0] || '');
      if (!kimlik) continue;
      var metin = '';
      for (var c = 3; c < r.length; c++) metin += String(r[c] || '');
      var veri;
      try { veri = JSON.parse(metin); } catch (pe) {
        gunlukYaz('veritabani', 'gölge kopya', 'Bozuk kuyruk kaydı atlandı (' + r[2] + ', ' + r[1] + ')', true);
        gonderilen[kimlik] = true; reddedilen++; continue;
      }
      var sonuc;
      try { sonuc = dbKuyrukKaydiGonder(ayar, String(r[2]), veri); }
      catch (ag) { agHatasi = String(ag.message || ag); break; }
      gonderilen[kimlik] = true;
      gonderilenSayi++;
      if (sonuc && sonuc.status === 'error') {
        // Veri tabanı kaydı reddetti (örn. düzeltilen kayıt orada yok): tekrar
        // denemek sonucu değiştirmez — günlüğe yaz, sıradakine geç.
        reddedilen++;
        gunlukYaz('veritabani', 'gölge kopya', 'Veri tabanı kaydı kabul etmedi (' + r[2] + '): ' + sonuc.message, true);
      }
    }
  } finally {
    // Gönderilenleri kuyruktan sil. Telefon istekleri sona satır ekleyebildiği
    // için kısa bir kilitle, satırları KİMLİĞİNE göre bulup siliyoruz.
    var silinecek = Object.keys(gonderilen).length;
    var kalan = 0;
    if (silinecek > 0) {
      var lock = LockService.getScriptLock();
      if (lock.tryLock(20000)) {
        try {
          var sh = dbKuyrukSheet(false);
          var son = sh.getLastRow();
          var idler = son >= 2 ? sh.getRange(2, 1, son - 1, 1).getValues() : [];
          var ilkK = 0;
          while (ilkK < idler.length && gonderilen[String(idler[ilkK][0])]) ilkK++;
          if (ilkK === silinecek) {
            sh.deleteRows(2, ilkK); // olağan durum: baştaki satırlar
          } else {
            for (var j = idler.length - 1; j >= 0; j--) if (gonderilen[String(idler[j][0])]) sh.deleteRow(j + 2);
          }
          kalan = Math.max(sh.getLastRow() - 1, 0);
        } finally { lock.releaseLock(); }
      } else {
        // Silinemediyse bir sonraki turda TEKRAR gönderilir; sayım/mal/dönem
        // tekrarı zararsızdır (sürüm kontrolü), düzeltme bir sürüm fazla artar.
        agHatasi = agHatasi || 'kuyruk temizlenemedi (sunucu meşgul)';
      }
    } else {
      var sh2 = dbKuyrukSheet(false);
      kalan = sh2 ? Math.max(sh2.getLastRow() - 1, 0) : 0;
    }
    cache.remove('db_gonderim_aktif');
    var ozet = gonderilenSayi + ' gönderildi' + (reddedilen ? ', ' + reddedilen + ' reddedildi' : '') + ', kuyrukta ' + kalan;
    if (agHatasi) {
      // Hata günlüğü en fazla 10 dakikada bir (ağ kesintisinde günlük dolmasın).
      var sonHata = Number(props.getProperty('DB_SON_HATA_MS') || 0);
      if (Date.now() - sonHata > 600000) {
        props.setProperty('DB_SON_HATA_MS', String(Date.now()));
        gunlukYaz('veritabani', 'gölge kopya', 'Veri tabanına ulaşılamadı: ' + agHatasi + ' — ' + ozet + ' (veri Sheets\'te güvende)', true);
      } else {
        sonKaydet('veritabani', 'gölge kopya', 'Ulaşılamadı: ' + agHatasi + ' — ' + ozet, true);
      }
    } else if (gonderilenSayi > 0) {
      sonKaydet('veritabani', 'gölge kopya', ozet, false);
    }
  }
  return { durum: agHatasi ? 'hata' : 'ok', gonderilen: gonderilenSayi, reddedilen: reddedilen, hata: agHatasi };
}

// Telefon isteğinden SONRA (kilit bırakıldıktan sonra) çağrılır: son
// gönderimin üzerinden 1 dakika geçtiyse kuyruğu en fazla 10 sn gönderir.
function dbGerekirseGonder() {
  try {
    if (!dbAyar()) return;
    var son = Number(PropertiesService.getScriptProperties().getProperty('DB_SON_GONDERIM_MS') || 0);
    if (Date.now() - son < DB_GONDERIM_ARALIK_MS) return;
    dbKuyrukGonder(10000);
  } catch (e) { /* gölge kopya asıl cevabı asla bozmaz */ }
}

// Zamanlayıcı (5 dakikada bir): telefon isteği gelmese de kuyruk boşalsın.
function dbZamanlayici() {
  dbKuyrukGonder(240000);
}

// BİR KEZ çalıştırın (Apps Script düzenleyicisinde fonksiyonu seçip ▶).
// 1) Bağlantıyı dener, 2) 5 dakikalık zamanlayıcıyı kurar, 3) Sheets'teki
// güncel sayım dönemini veri tabanına bildirir.
function dbKur() {
  var ayar = dbAyar();
  if (!ayar) throw new Error('Önce Komut dosyası özelliklerine DB_URL ve DB_ANAHTAR ekleyin (DB_KAPALI=1 ise kaldırın).');
  var token = PropertiesService.getScriptProperties().getProperty('RESET_TOKEN') || '';
  if (token) dbCagir(ayar, 'yeni_donem', { p_aciklama: 'Sheets dönemi (kurulum)', p_token: token });
  var varMi = ScriptApp.getProjectTriggers().some(function (t) { return t.getHandlerFunction() === 'dbZamanlayici'; });
  if (!varMi) ScriptApp.newTrigger('dbZamanlayici').timeBased().everyMinutes(5).create();
  gunlukYaz('veritabani', 'gölge kopya', 'Kurulum tamam: bağlantı çalışıyor, 5 dk zamanlayıcı ' + (varMi ? 'zaten vardı' : 'kuruldu'), false);
  Logger.log('Tamam — veri tabanı bağlantısı çalışıyor.');
}

// İSTEĞE BAĞLI, bir kez: gölge mod açılmadan ÖNCE Sheets'te olan sayım
// satırlarını da kuyruğa ekler (karşılaştırma tam olsun diye).
function dbMevcutSayimiAktar() {
  if (!dbAyar()) throw new Error('Gölge kopya kapalı (DB_URL / DB_ANAHTAR yok)');
  var lock = LockService.getScriptLock();
  lock.waitLock(30000);
  try {
    var sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName('Sayim');
    if (!sheet || sheet.getLastRow() < 2) return;
    var token = PropertiesService.getScriptProperties().getProperty('RESET_TOKEN') || '';
    var degerler = sheet.getRange(2, 1, sheet.getLastRow() - 1, SAYIM_HEADERS.length).getValues();
    var oturumlar = {};
    degerler.forEach(function (r) {
      var id = String(r[11] || '');
      if (!id) return;
      var anahtar = String(r[10] || '') + '\u0001' + String(r[2] || '');
      (oturumlar[anahtar] = oturumlar[anahtar] || []).push({
        id: id, v: surumOku(r[13]), date: formatDateValue(r[0]), time: formatTimeValue(r[1]), name: String(r[3] || ''),
        stockCode: String(r[4] || ''), barcode: String(r[5] || ''), unit: String(r[6] || 'Adet'), oldStock: r[7] === '' ? '' : String(r[7]),
        qty: r[8], reyon: String(r[12] || '')
      });
    });
    var toplam = 0;
    Object.keys(oturumlar).forEach(function (k) {
      var p = k.split('\u0001');
      var liste = oturumlar[k];
      for (var i = 0; i < liste.length; i += 300) {
        dbKuyrugaEkle('sayim', { sessionId: p[0] || 'eski-kayit', personnel: p[1], resetToken: token, rows: liste.slice(i, i + 300), deletedIds: [] });
      }
      toplam += liste.length;
    });
    gunlukYaz('veritabani', 'gölge kopya', 'Mevcut ' + toplam + ' sayım satırı veri tabanı kuyruğuna eklendi', false);
  } finally { lock.releaseLock(); }
}

// Karşılaştırma: Sheets'teki 'Sayim' ile veri tabanındaki aktif dönem
// kayıtlarını kayıt kayıt karşılaştırır (sürüm + adet). Sonucu günlüğe yazar.
function dbKarsilastir() {
  var ayar = dbAyar();
  if (!ayar) throw new Error('Gölge kopya kapalı');
  var sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName('Sayim');
  var sheetsK = {};
  if (sheet && sheet.getLastRow() >= 2) {
    var n = sheet.getLastRow() - 1;
    var ids = sheet.getRange(2, SAYIM_COL.KAYIT_ID, n, 1).getValues();
    var v = sheet.getRange(2, SAYIM_COL.SURUM, n, 1).getValues();
    var q = sheet.getRange(2, SAYIM_COL.ADET, n, 1).getValues();
    for (var i = 0; i < n; i++) if (ids[i][0]) sheetsK[String(ids[i][0])] = [surumOku(v[i][0]), Number(q[i][0])];
  }
  var token = PropertiesService.getScriptProperties().getProperty('RESET_TOKEN') || '';
  var dbK = {};
  var sayfa = 0, boyut = 1000;
  while (true) {
    var yanit = UrlFetchApp.fetch(ayar.url + '/rest/v1/sayim_kayitlari?select=kayit_id,surum,adet,gec_geldi,sayim_donemleri!inner(token)' +
      '&sayim_donemleri.token=eq.' + encodeURIComponent(token) + '&gec_geldi=eq.false&order=kayit_id', {
      headers: { apikey: ayar.anahtar, Range: (sayfa * boyut) + '-' + (sayfa * boyut + boyut - 1) }, muteHttpExceptions: true });
    if (yanit.getResponseCode() >= 300) throw new Error('Veri tabanı okunamadı: HTTP ' + yanit.getResponseCode() + ' ' + yanit.getContentText().substring(0, 200));
    var liste = JSON.parse(yanit.getContentText());
    liste.forEach(function (r) { dbK[r.kayit_id] = [r.surum, Number(r.adet)]; });
    if (liste.length < boyut) break;
    sayfa++;
  }
  var eksikDb = [], fazlaDb = [], farkli = [];
  Object.keys(sheetsK).forEach(function (id) {
    if (!dbK[id]) eksikDb.push(id);
    else if (dbK[id][0] !== sheetsK[id][0] || dbK[id][1] !== sheetsK[id][1]) farkli.push(id);
  });
  Object.keys(dbK).forEach(function (id) { if (!sheetsK[id]) fazlaDb.push(id); });
  var kuyruk = dbKuyrukSheet(false);
  var bekleyen = kuyruk ? Math.max(kuyruk.getLastRow() - 1, 0) : 0;
  var tamam = !eksikDb.length && !fazlaDb.length && !farkli.length;
  var ozet = 'Karşılaştırma: Sheets ' + Object.keys(sheetsK).length + ' kayıt, veri tabanı ' + Object.keys(dbK).length + ' kayıt — ' +
    (tamam ? 'BİREBİR AYNI ✅' : ('veri tabanında eksik ' + eksikDb.length + ', fazla ' + fazlaDb.length + ', farklı ' + farkli.length +
      (bekleyen ? ' (kuyrukta hâlâ ' + bekleyen + ' kayıt var, gönderilince tekrar deneyin)' : '') +
      ' · örnek: ' + eksikDb.concat(fazlaDb, farkli).slice(0, 5).join(', ')));
  gunlukYaz('veritabani', 'karşılaştırma', ozet, !tamam);
  Logger.log(ozet);
  return ozet;
}

// ============================================================
// ÜRÜN HAREKETLERİ: bir ürünün ERP12'deki alışları (kimden, ne zaman, hangi
// belgeyle, kaç TL'ye) ve satışları. Veri, ERP bilgisayarındaki
// hareket-gonder.ps1 ile veri tabanına (Supabase) yazılır; telefon ona
// DOĞRUDAN erişemez — burada "hareket" yetkisi kontrol edilip gizli
// anahtarla okunur. (DB_KAPALI sadece gölge yazmayı durdurur, bunu değil.)
// ============================================================
function urunHareket(p, callback) {
  var auth = requirePermission(p.user, p.pass, 'hareket');
  if (!auth.ok) return outJson({ status: 'error', message: auth.message }, callback);
  var props = PropertiesService.getScriptProperties();
  var url = String(props.getProperty('DB_URL') || '').trim().replace(/\/+$/, '');
  var anahtar = String(props.getProperty('DB_ANAHTAR') || '').trim();
  if (!url || !anahtar) return outJson({ status: 'error', message: 'Veri tabanı ayarı yok (DB_URL / DB_ANAHTAR)' }, callback);
  var stokKodu = String(p.stokKodu || '').substring(0, 60);
  var barkod = String(p.barkod || '').substring(0, 60);
  if (!stokKodu && !barkod) return outJson({ status: 'error', message: 'Ürün seçilmedi' }, callback);
  var gun = parseInt(p.gun, 10); if (isNaN(gun) || gun < 0 || gun > 3650) gun = 365;
  try {
    var sonuc = dbCagir({ url: url, anahtar: anahtar }, 'urun_hareket', { p_stok_kodu: stokKodu, p_barkod: barkod, p_gun: gun, p_limit: 200 });
    if (!sonuc || sonuc.status !== 'ok') return outJson({ status: 'error', message: (sonuc && sonuc.message) || 'Veri tabanı cevap vermedi' }, callback);
    return outJson(sonuc, callback);
  } catch (err) {
    gunlukYaz('veritabani', 'ürün hareketleri', 'Sorgu başarısız: ' + err, true);
    return outJson({ status: 'error', message: 'Veri tabanına ulaşılamadı — biraz sonra tekrar dene' }, callback);
  }
}
