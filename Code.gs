/**
 * MURAT GIDA - SAYIM TOPLAMA SERVİSİ
 * Bu dosyanın tamamını Apps Script'e yapıştırın (eski kodun üzerine, hiçbir
 * satır kalmayacak şekilde tamamen silip baştan yapıştırın).
 */

// KOD SÜRÜMÜ — dağıtımın güncel olup olmadığını kontrol etmek için. Yeni
// bir sürüm dağıttıktan sonra /exec adresini boş açtığında burada yazan
// numarayı görmelisin; index.html'in üstündeki "build" numarasıyla
// eşleşecek şekilde ben her ikisini birlikte güncelliyorum.
var GS_VERSION = 'build148';

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
  var P = e.parameter || {};
  var kapi = function (ne) { return kimlikGerek(P.user, P.pass, ne); };
  var k;
  if (P.action === 'katalog') {
    k = kapi('katalog okuma'); if (!k.ok) return kimlikRed(k, P.callback);
    return getKatalog(P.callback);
  }
  if (P.action === 'iade_bekleyen') {
    k = kapi('bekleyen iade okuma'); if (!k.ok) return kimlikRed(k, P.callback);
    return iadeBekleyenGetir(P.cari, P.callback);
  }
  if (P.action === 'cari') {
    k = kapi('cari okuma'); if (!k.ok) return kimlikRed(k, P.callback);
    // Bakiye: sadece yönetici / "fiyat" yetkisi olan görür. (Geçiş döneminde
    // kimliksiz gelen eski telefonlara eskisi gibi gönderilir.)
    return getCari(P.callback, k.kimliksiz && !k.auth ? true : fiyatGorur(k.auth));
  }
  if (P.action === 'ilerleme') {
    k = kapi('ilerleme okuma'); if (!k.ok) return kimlikRed(k, P.callback);
    return getIlerleme(P.callback);
  }
  if (P.action === 'etiket_liste') {
    k = kapi('etiket listesi okuma'); if (!k.ok) return kimlikRed(k, P.callback);
    if (!etiketYetki(k.auth)) return etiketRed(k.auth, P.callback);
    return etiketListeGetir(P.id, P.callback);
  }
  if (P.action === 'etiket_grup') {
    k = kapi('etiket grubu okuma'); if (!k.ok) return kimlikRed(k, P.callback);
    if (!etiketYetki(k.auth)) return etiketRed(k.auth, P.callback);
    return etiketGrupGetir(P.callback);
  }
  if (P.action === 'etiket_bilgi') {
    k = kapi('etiket bilgisi okuma'); if (!k.ok) return kimlikRed(k, P.callback);
    if (!etiketYetki(k.auth)) return etiketRed(k.auth, P.callback);
    return etiketBilgiGetir(P.callback);
  }
  if (P.action === 'etiket_ayar') {
    k = kapi('etiket ayarı okuma'); if (!k.ok) return kimlikRed(k, P.callback);
    if (!etiketYetki(k.auth)) return etiketRed(k.auth, P.callback);
    return etiketAyarGetir(P.callback);
  }
  if (P.action === 'etiket_kuyruk') {
    k = kapi('etiket kuyruğu okuma'); if (!k.ok) return kimlikRed(k, P.callback);
    if (!etiketYetki(k.auth)) return etiketRed(k.auth, P.callback);
    return etiketKuyrukGetir(P.callback);
  }
  // ---- Baskı programı (yazıcının bağlı olduğu bilgisayar) : ERP anahtarıyla ----
  if (P.action === 'baski_ajan_al' || P.action === 'baski_ajan_bitti' || P.action === 'baski_ajan_veri') {
    if (!erpAnahtarDogru(P.anahtar)) return outJson({ status: 'error', kimlik: true, message: 'Anahtar geçersiz' }, P.callback);
    if (P.action === 'baski_ajan_al') return baskiAjanAl(P.bilgisayar, P.yazicilar, P.callback);
    if (P.action === 'baski_ajan_bitti') return baskiAjanBitti(P.id, P.durum, P.mesaj, P.callback);
    return baskiAjanVeri(P.id, P.callback);
  }
  // ---- Baskı işleri: giriş yapmış kullanıcı ----
  if (P.action === 'baski_durum' || P.action === 'baski_islem' || P.action === 'baski_yazici_ayar') {
    k = kapi('baskı işleri'); if (!k.ok) return kimlikRed(k, P.callback);
    if (!etiketYetki(k.auth)) return etiketRed(k.auth, P.callback);
    if (P.action === 'baski_durum') return baskiDurum(P.callback);
    if (P.action === 'baski_islem') {
      if (!etiketYetki(k.auth, 'etiket_yazici')) return outJson({ status: 'error', message: 'Baskı işlerini yönetme yetkin yok' }, P.callback);
      return baskiIslem(P.id, P.islem, P.callback);
    }
    if (!k.auth || k.auth.role !== 'yonetici') return outJson({ status: 'error', message: 'Yazıcı ayarını yalnızca yönetici değiştirir' }, P.callback);
    return baskiYaziciAyar(P, P.callback);
  }
  if (P.action === 'guvenlik_getir') return guvenlikGetir(P.user, P.pass, P.callback);
  if (P.action === 'guvenlik_kaydet') return guvenlikKaydet(P.user, P.pass, P.zorunlu, P.callback);
  if (P.action === 'guvenlik_anahtar') return guvenlikAnahtarUret(P.user, P.pass, P.callback);
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
  if (P.action === 'kullanicilar') {
    // Giriş ekranı bu listeyi isim önerisi için girişten ÖNCE de ister; zorunlu
    // modda reddedilir ama günlüğe hata olarak yazılmaz.
    k = kimlikGerek(P.user, P.pass, 'personel listesi okuma', null, true); if (!k.ok) return kimlikRed(k, P.callback);
    return getKullanicilar(P.callback);
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
  if (P.action === 'mal_kontrol') {
    k = kapi('mal kaydı kontrolü'); if (!k.ok) return kimlikRed(k, P.callback);
    return malKontrol(P.batch, P.callback);
  }
  // sayim_kontrol: telefon, gönderdiği sayım kayıtlarının sunucuya hangi
  // SÜRÜMLE yazıldığını sorar. Telefon kuyruğundan sadece burada doğrulanan
  // kayıtları çıkarır (bkz. sayimKontrol).
  // Sistem Durumu ekranı: son gelen veriler, sayılar, günlük ve hatalar.
  // Şube konumları: telefonlar girişte konumlarını bunlarla karşılaştırır.
  if (P.action === 'subeler') {
    k = kapi('şube listesi okuma'); if (!k.ok) return kimlikRed(k, P.callback);
    return outJson({ status: 'ok', subeler: subeleriOku() }, P.callback);
  }
  if (e.parameter && e.parameter.action === 'sube_kaydet') {
    return subeKaydet(e.parameter.user, e.parameter.pass, e.parameter.data, e.parameter.callback);
  }
  // Telefon girişte nerede olduğunu bildirir (Sistem Durumu günlüğüne yazılır).
  if (P.action === 'konum_bildir') {
    k = kapi('konum bildirimi'); if (!k.ok) return kimlikRed(k, P.callback);
    return konumBildir(P, P.callback);
  }
  if (e.parameter && e.parameter.action === 'sistem_durumu') {
    return sistemDurumu(e.parameter.user, e.parameter.pass, e.parameter.callback);
  }
  // Telefon, gönderemediği verinin hatasını bildirir (günlüğe yazılır).
  if (P.action === 'hata_bildir') {
    k = kapi('hata bildirimi'); if (!k.ok) return kimlikRed(k, P.callback);
    return hataBildir(P, P.callback);
  }
  if (P.action === 'sayim_kontrol') {
    k = kapi('sayım onayı'); if (!k.ok) return kimlikRed(k, P.callback);
    return sayimKontrol(P.session, P.nonce, P.callback);
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
  // ---- Personel mesai takibi (deneme) — sayımdan tamamen ayrı ----
  if (e.parameter && e.parameter.action === 'mesai_kaydet') return mesaiKaydet(e.parameter, e.parameter.callback);
  if (e.parameter && e.parameter.action === 'mesai_benim') return mesaiBenim(e.parameter, e.parameter.callback);
  if (e.parameter && e.parameter.action === 'mesai_kod') return mesaiKod(e.parameter, e.parameter.callback);
  if (e.parameter && e.parameter.action === 'mesai_rapor') return mesaiRapor(e.parameter, e.parameter.callback);
  if (e.parameter && String(e.parameter.action || '').indexOf('ekip_') === 0) return ekipIstek(e.parameter, e.parameter.callback);
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
// | evet) — elle yazılan düz metin şifre ilk girişte özete çevrilir.
// Şifreler tabloda tuzlu SHA-256 özeti olarak saklanır (bkz. ŞİFRE ÖZETİ);
// tabloyu açan biri şifreleri okuyamaz. Şifre telefonda hâlâ saklanır ve her
// istekte sunucuya gönderilir — tam oturum sistemi veri tabanı geçişinde.
// ============================================================
var ALL_PERMS = ['rapor', 'temizle', 'kullanici_yonetimi', 'ayarlar', 'canli_durum', 'duzelt', 'hareket', 'mesai', 'mesai_yonetim'];

// ---- ŞİFRE ÖZETİ ----
// Şifreler tabloda artık DÜZ METİN durmaz: "s256$<tuz>$<özet>" biçiminde,
// kullanıcıya özel rastgele tuzla SHA-256 özeti saklanır. Tabloyu açan biri
// şifreleri okuyamaz; yönetici paneline de şifre geri gönderilmez.
// GEÇİŞ: tabloda hâlâ düz metin duran şifre, o kullanıcı ilk kez doğru
// şifreyle giriş yaptığında (ya da herhangi bir yetkili işlem yaptığında)
// kendiliğinden özete çevrilir — kimsenin şifresi değişmez, kimse tekrar
// şifre belirlemek zorunda kalmaz.
var SIFRE_ON_EK = 's256$';
function sifreHex(tuz, pass) {
  var d = Utilities.computeDigest(Utilities.DigestAlgorithm.SHA_256, tuz + ':' + String(pass), Utilities.Charset.UTF_8);
  var out = '';
  for (var i = 0; i < d.length; i++) { var b = (d[i] + 256) % 256; out += (b < 16 ? '0' : '') + b.toString(16); }
  return out;
}
function sifreOzetle(pass) {
  var tuz = Utilities.getUuid().replace(/-/g, '').slice(0, 16);
  return SIFRE_ON_EK + tuz + '$' + sifreHex(tuz, pass);
}
function sifreOzetMi(kayitli) { return String(kayitli || '').indexOf(SIFRE_ON_EK) === 0; }
function sifreDogru(kayitli, pass) {
  kayitli = String(kayitli || '');
  if (!sifreOzetMi(kayitli)) return kayitli !== '' && kayitli === String(pass); // eski düz metin kayıt
  var p = kayitli.split('$');
  if (p.length !== 3 || !p[1] || !p[2]) return false;
  return sifreHex(p[1], pass) === p[2];
}

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
      if (!sifreDogru(pw, pass)) return { ok: false, message: 'Şifre yanlış' };
      // Düz metin duran şifreyi ilk doğru girişte özete çevir (başarısız
      // olursa giriş yine de geçerli; bir sonraki girişte tekrar denenir).
      if (!sifreOzetMi(pw)) {
        try { sheet.getRange(i + 2, 2).setValue(sifreOzetle(pass)); } catch (ozErr) { /* geçiş sonraya kalır */ }
      }
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

// ============================================================
// GÜVENLİK: KİMLİKSİZ İSTEKLERİ KAPATMA (build 114)
// Eskiden katalog, cari (bakiyeler), personel listesi ve ilerleme GİRİŞ
// YAPMADAN okunabiliyor; sayım, mal hareketi ve katalog da kimlik sorulmadan
// yazılabiliyordu — adresi bilen herkes için. Artık bu isteklerin hepsi
// kullanıcı adı + şifre (ERP bilgisayarı için gizli anahtar) taşır.
//
// GEÇİŞ DÖNEMİ: Telefonlar, sunucu ve ERP bilgisayarı aynı anda güncellenemez.
// 'GUVENLIK_ZORUNLU' ayarı KAPALIYKEN (varsayılan) kimliksiz istekler eskisi
// gibi kabul edilir ama Sistem Günlüğü'ne "kimliksiz istek" diye not düşülür.
// Tüm telefonlar yeni sürüme geçip ERP anahtarı kurulunca yönetici panelden
// "Kimlik zorunlu"yu açar; o andan sonra kimliksiz istek REDDEDİLİR.
// ============================================================
var GUV_OZELLIK = 'GUVENLIK_ZORUNLU';
var ERP_ANAHTAR_OZELLIK = 'ERP_ANAHTAR';
function guvenlikZorunlu() { return PropertiesService.getScriptProperties().getProperty(GUV_OZELLIK) === 'true'; }

// Kimlik doğrulama, 2 dakikalık önbellekle: sayım günü her telefon birkaç
// saniyede bir istek atar; her seferinde Kullanicilar sekmesini okumayalım.
// (Şifre değişikliği / pasife alma en geç 2 dakikada geçerli olur.)
function kimlikOnbellek(user, pass) {
  user = String(user || '').trim(); pass = String(pass || '');
  if (!user || !pass) return { ok: false, message: 'Giriş gerekli' };
  var anahtar = 'kimlik_' + sifreHex('onbellek', user.toLowerCase() + '\n' + pass);
  var cache = null;
  try { cache = CacheService.getScriptCache(); var v = cache.get(anahtar); if (v) return JSON.parse(v); } catch (e) { /* önbelleksiz devam */ }
  var a = authenticate(user, pass);
  if (a.ok && cache) { try { cache.put(anahtar, JSON.stringify(a), 120); } catch (e2) { /* önemli değil */ } }
  return a;
}
// Aynı tür not en fazla 10 dakikada bir günlüğe düşer (günlük dolmasın).
function guvenlikNot(tur, ne, detay, hata) {
  try {
    var c = CacheService.getScriptCache(), k = 'guvnot_' + tur + '_' + ne;
    if (c.get(k)) return;
    c.put(k, '1', 600);
  } catch (e) { /* önbellek yoksa her seferinde yaz */ }
  gunlukYaz(tur, ne, detay, hata);
}
// İstek kimlikli mi? Dönüş: { ok, auth, kimliksiz } ya da { ok:false, kimlik, message }.
// yetki verilirse (örn. 'ayarlar') kullanıcının o yetkisi de olmalı.
function kimlikGerek(user, pass, ne, yetki, sessiz) {
  var a = kimlikOnbellek(user, pass);
  if (a.ok && (!yetki || a.permissions.indexOf(yetki) !== -1)) return { ok: true, auth: a };
  if (!guvenlikZorunlu()) {
    guvenlikNot('guvenlik', ne, (a.ok ? 'Yetkisiz' : 'Kimliksiz') + ' istek kabul edildi (geçiş dönemi) — "Kimlik zorunlu" açılınca reddedilecek', false);
    return { ok: true, auth: a.ok ? a : null, kimliksiz: true };
  }
  // sessiz: giriş ekranındaki telefonların olağan istekleri günlüğü doldurmasın.
  if (!sessiz) guvenlikNot('guvenlik_red', ne, (a.ok ? 'Yetkisiz' : 'Kimliksiz') + ' istek REDDEDİLDİ' + (user ? ' (' + String(user).substring(0, 60) + ')' : ''), true);
  if (a.ok) return { ok: false, message: 'Bu işlem için yetkin yok' };
  return { ok: false, kimlik: true, message: 'Giriş gerekli — çıkış yapıp tekrar giriş yap' };
}
function kimlikRed(k, callback) { return outJson({ status: 'error', kimlik: !!k.kimlik, message: k.message }, callback); }
function erpAnahtarDogru(anahtar) {
  var k = PropertiesService.getScriptProperties().getProperty(ERP_ANAHTAR_OZELLIK);
  return !!k && String(anahtar || '') === k;
}
// Fiyat/bakiye görebilir mi: yönetici ya da "fiyat" yetkisi olan.
function fiyatGorur(auth) { return !!auth && (auth.role === 'yonetici' || auth.permissions.indexOf('fiyat') !== -1); }

// ---- Yönetici paneli: güvenlik durumu / ayarı / ERP anahtarı ----
function guvenlikGetir(user, pass, callback) {
  var auth = requirePermission(user, pass, 'ayarlar');
  if (!auth.ok) return outJson({ status: 'error', message: auth.message }, callback);
  var props = PropertiesService.getScriptProperties();
  var son = null;
  try { var v = props.getProperty('SON_guvenlik'); if (v) son = JSON.parse(v); } catch (e) { son = null; }
  return outJson({ status: 'ok', zorunlu: guvenlikZorunlu(), erpAnahtarVar: !!props.getProperty(ERP_ANAHTAR_OZELLIK), sonKimliksiz: son, sunucuMs: Date.now() }, callback);
}
function guvenlikKaydet(user, pass, zorunlu, callback) {
  var auth = requirePermission(user, pass, 'ayarlar');
  if (!auth.ok) return outJson({ status: 'error', message: auth.message }, callback);
  var props = PropertiesService.getScriptProperties();
  var ac = String(zorunlu) === 'true';
  if (ac && !props.getProperty(ERP_ANAHTAR_OZELLIK)) {
    return outJson({ status: 'error', message: 'Önce ERP anahtarını oluşturup ERP bilgisayarına yaz — yoksa katalog ve cari aktarımı durur' }, callback);
  }
  props.setProperty(GUV_OZELLIK, ac ? 'true' : 'false');
  gunlukYaz('yonetim', String(user || ''), 'Kimlik zorunluluğu ' + (ac ? 'AÇILDI — kimliksiz istekler artık reddediliyor' : 'KAPATILDI — kimliksiz istekler kabul ediliyor'), false);
  return outJson({ status: 'ok', zorunlu: ac }, callback);
}
// Yeni ERP anahtarı üretir ve SADECE bu cevapta bir kez gösterir. Eski anahtar
// o anda geçersiz olur.
function guvenlikAnahtarUret(user, pass, callback) {
  var auth = requirePermission(user, pass, 'ayarlar');
  if (!auth.ok) return outJson({ status: 'error', message: auth.message }, callback);
  var anahtar = (Utilities.getUuid() + Utilities.getUuid()).replace(/-/g, '').slice(0, 40);
  PropertiesService.getScriptProperties().setProperty(ERP_ANAHTAR_OZELLIK, anahtar);
  gunlukYaz('yonetim', String(user || ''), 'Yeni ERP anahtarı oluşturuldu (eskisi geçersiz)', false);
  return outJson({ status: 'ok', anahtar: anahtar }, callback);
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
// ---- BEKLEYEN ALIŞTAN İADE İRSALİYELERİ (ERP12: FIS_TURU = 7, henüz faturalanmamış satırlar) ----
// ERP programı her gönderimde listenin TAMAMINI yollar; tablo aynen onunla değişir (boş liste = bekleyen yok).
var IADE_SEKME = 'BekleyenIade';
var IADE_BASLIK = ['Cari Kodu', 'Cari', 'Belge No', 'Tarih', 'Toplam', 'Satırlar (JSON)'];
function iadeBulkKaydet(fisler) {
  if (!Array.isArray(fisler)) return jsonCikti({ status: 'error', message: 'Geçersiz iade listesi' });
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sheet = ss.getSheetByName(IADE_SEKME) || ss.insertSheet(IADE_SEKME);
  var rows = fisler.slice(0, 2000).map(function (f) {
    var satirlar = (Array.isArray(f.satirlar) ? f.satirlar : []).slice(0, 200).map(function (x) {
      return { b: String(x.b || '').substring(0, 30), a: String(x.a || '').substring(0, 80), m: cleanNum(x.m), f: cleanNum(x.f) };
    });
    var j = JSON.stringify(satirlar);
    while (j.length > 45000 && satirlar.length > 1) { satirlar.pop(); j = JSON.stringify(satirlar); }
    return [String(f.cariKod || ''), String(f.cari || '').substring(0, 120), String(f.belgeNo || '').substring(0, 60), String(f.tarih || '').substring(0, 10), cleanNum(f.toplam), j];
  });
  if (sheet.getMaxRows() > 1) sheet.getRange(1, 1, sheet.getMaxRows(), 4).setNumberFormat('@');
  tabloyuDegistir(sheet, IADE_BASLIK, rows);
  return jsonCikti({ status: 'ok', saved: rows.length });
}
function iadeBekleyenGetir(cariKod, callback) {
  var sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName(IADE_SEKME), fisler = [], kod = String(cariKod || '').trim();
  if (sheet && sheet.getLastRow() >= 2 && kod) {
    sheet.getRange(2, 1, sheet.getLastRow() - 1, IADE_BASLIK.length).getValues().forEach(function (r) {
      if (String(r[0]).trim() !== kod) return;
      var satirlar = []; try { satirlar = JSON.parse(String(r[5] || '[]')); } catch (e) { satirlar = []; }
      fisler.push({ belgeNo: String(r[2] || ''), tarih: fiyatTarihiMetni(r[3]) || String(r[3] || ''), toplam: cleanNum(r[4]), satirlar: satirlar });
    });
  }
  return outJson({ status: 'ok', fisler: fisler }, callback);
}
function getCari(callback, bakiyeGoster) {
  if (bakiyeGoster === undefined) bakiyeGoster = true;
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sheet = ss.getSheetByName('Cari');
  var entries = [];
  if (sheet && sheet.getLastRow() >= 2) {
    var values = sheet.getRange(2, 1, sheet.getLastRow() - 1, 3).getValues();
    entries = values
      .filter(function (r) { return r[0]; })
      .map(function (r) { return { name: String(r[0]), code: String(r[1] || ''), balance: bakiyeGoster ? String(r[2] || '') : '' }; });
  }
  var json = JSON.stringify({ entries: entries });
  if (callback) {
    return ContentService.createTextOutput(callback + '(' + json + ')').setMimeType(ContentService.MimeType.JAVASCRIPT);
  }
  return ContentService.createTextOutput(json).setMimeType(ContentService.MimeType.JSON);
}

// ============================================================
// TABLOYU GÜVENLİ DEĞİŞTİRME
// Eskiden "önce sheet.clear(), sonra yaz" yapılıyordu: yazma yarıda kalırsa
// (zaman aşımı, kota, bağlantı) tablo BOŞ kalıyordu — kullanıcı listesinde bu
// olursa kimse giriş yapamaz, katalogda olursa telefonlar boş katalog çeker.
// Artık yeni içerik eskisinin ÜZERİNE tek bir yazma işlemiyle konur; yazma
// başarısız olursa eski içerik aynen durur. Fazla kalan eski satırlar ancak
// yeni içerik yerine oturduktan SONRA silinir.
// ============================================================
function tabloyuDegistir(sheet, basliklar, rows) {
  var n = basliklar.length;
  for (var i = 0; i < rows.length; i++) {
    if (!rows[i] || rows[i].length !== n) throw new Error('Tablo satırı ' + (i + 1) + ' beklenen ' + n + ' sütunda değil');
  }
  var hepsi = [basliklar].concat(rows);
  if (sheet.getMaxColumns() < n) sheet.insertColumnsAfter(sheet.getMaxColumns(), n - sheet.getMaxColumns());
  if (sheet.getMaxRows() < hepsi.length) sheet.insertRowsAfter(sheet.getMaxRows(), hepsi.length - sheet.getMaxRows());
  var eskiSon = sheet.getLastRow();
  var eskiSutun = sheet.getLastColumn();
  sheet.getRange(1, 1, hepsi.length, n).setValues(hepsi);
  if (eskiSon > hepsi.length) sheet.getRange(hepsi.length + 1, 1, eskiSon - hepsi.length, Math.max(eskiSutun, n)).clearContent();
  if (eskiSutun > n) sheet.getRange(1, n + 1, hepsi.length, eskiSutun - n).clearContent();
}
// ---- ETİKET LİSTESİ AKTARMA ----
// Telefonda hazırlanan etiket listesi buraya kaydedilir; yazıcının bağlı olduğu
// bilgisayar aynı listeyi çekip basar. Son ETIKET_LISTE_SAKLA liste tutulur.
var ETIKET_LISTE_SEKME = 'EtiketListe';
var ETIKET_LISTE_BASLIK = ['Id', 'Zaman', 'Kullanıcı', 'Adet', 'Veri'];
var ETIKET_LISTE_SAKLA = 30;
var ETIKET_LISTE_SINIR = 45000; // bir hücreye sığan metin sınırının (50.000) altında
function etiketListeSayfa(olustur) {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sheet = ss.getSheetByName(ETIKET_LISTE_SEKME);
  if (!sheet && olustur) {
    sheet = ss.insertSheet(ETIKET_LISTE_SEKME);
    sheet.getRange(1, 1, 1, ETIKET_LISTE_BASLIK.length).setValues([ETIKET_LISTE_BASLIK]);
  }
  return sheet;
}
function etiketListeKaydet(data, gonderen) {
  var id = String(data.id || '').replace(/[^A-Za-z0-9_-]/g, '').substring(0, 40);
  var liste = data.liste;
  if (!id || !Array.isArray(liste) || !liste.length) return jsonCikti({ status: 'error', message: 'Boş etiket listesi' });
  var veri = JSON.stringify(liste);
  if (veri.length > ETIKET_LISTE_SINIR) return jsonCikti({ status: 'error', buyuk: true, message: 'Liste çok uzun — ikiye bölerek gönderin' });
  var sheet = etiketListeSayfa(true);
  var son = sheet.getLastRow();
  if (son >= 2) {
    // Aynı liste iki kez geldiyse (tekrar deneme) ikinci kez yazılmaz.
    var idler = sheet.getRange(2, 1, son - 1, 1).getValues();
    for (var i = 0; i < idler.length; i++) if (String(idler[i][0]) === id) return jsonCikti({ status: 'ok', id: id, zatenVar: true });
  }
  var zaman = Utilities.formatDate(new Date(), fiyatTz(), 'dd.MM.yyyy HH:mm');
  sheet.getRange(son + 1, 1, 1, 5).setNumberFormat('@').setValues([[id, zaman, String(gonderen || '').substring(0, 60), String(liste.length), veri]]);
  var fazla = sheet.getLastRow() - 1 - ETIKET_LISTE_SAKLA;
  if (fazla > 0) sheet.deleteRows(2, fazla);
  return jsonCikti({ status: 'ok', id: id });
}
// id verilmezse son listelerin özeti (yeniden eskiye), verilirse o listenin kendisi.
function etiketListeGetir(id, callback) {
  var sheet = etiketListeSayfa(false);
  var son = sheet ? sheet.getLastRow() : 0;
  var satirlar = son >= 2 ? sheet.getRange(2, 1, son - 1, 5).getValues() : [];
  var zamanMetni = function (v) { return v instanceof Date ? Utilities.formatDate(v, fiyatTz(), 'dd.MM.yyyy HH:mm') : String(v || ''); };
  if (id) {
    for (var i = satirlar.length - 1; i >= 0; i--) {
      if (String(satirlar[i][0]) !== String(id)) continue;
      var liste = [];
      try { liste = JSON.parse(String(satirlar[i][4] || '[]')); } catch (pe) { return outJson({ status: 'error', message: 'Liste okunamadı' }, callback); }
      return outJson({ status: 'ok', id: String(id), zaman: zamanMetni(satirlar[i][1]), kullanici: String(satirlar[i][2] || ''), liste: liste }, callback);
    }
    return outJson({ status: 'ok', yok: true }, callback);
  }
  var ozet = satirlar.map(function (r) { return { id: String(r[0]), zaman: zamanMetni(r[1]), kullanici: String(r[2] || ''), adet: Number(r[3]) || 0 }; }).reverse();
  return outJson({ status: 'ok', listeler: ozet }, callback);
}

// ---- ORTAK ETİKET BİLGİSİ ----
// Bir cihazda girilen üretim yeri, net miktar ve paket/koli adedi burada tutulur;
// bütün cihazlar aynı bilgiyi kullanır (ERP'de ülke yazılıysa etikette yine o esastır).
var ETIKET_BILGI_SEKME = 'EtiketBilgi';
var ETIKET_BILGI_BASLIK = ['Barkod', 'Üretim Yeri', 'Net Miktar', 'Birim', 'Koli Adedi', 'Koli Adı', 'Zaman', 'Kullanıcı'];
function etiketBilgiOku() {
  var sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName(ETIKET_BILGI_SEKME);
  var son = sheet ? sheet.getLastRow() : 0, m = {};
  if (son >= 2) sheet.getRange(2, 1, son - 1, 8).getValues().forEach(function (r) {
    var b = String(r[0] || ''); if (b) m[b] = [String(r[1] || ''), String(r[2] === 0 ? 0 : (r[2] || '')), String(r[3] || ''), String(r[4] || ''), String(r[5] || ''), String(r[6] || ''), String(r[7] || '')];
  });
  return m;
}
function etiketBilgiGetir(callback) {
  var m = etiketBilgiOku(), bilgi = {};
  Object.keys(m).forEach(function (b) { bilgi[b] = m[b].slice(0, 5); });
  return outJson({ status: 'ok', bilgi: bilgi }, callback);
}
function etiketBilgiKaydet(urunler, gonderen) {
  if (!Array.isArray(urunler) || !urunler.length) return jsonCikti({ status: 'error', message: 'Boş liste' });
  var m = etiketBilgiOku(), simdi = Utilities.formatDate(new Date(), fiyatTz(), 'dd.MM.yyyy HH:mm'), kim = String(gonderen || '').substring(0, 60), n = 0;
  urunler.slice(0, 500).forEach(function (u) {
    var b = String((u && u.b) || '').trim(); if (!b || b.length > 40) return;
    var mik = cleanNum(u.mik), koli = parseInt(u.koli, 10);
    m[b] = [ulkeMetni(u.yer), (typeof mik === 'number' && mik > 0) ? String(mik) : '', String(u.birim || '').substring(0, 8),
      koli > 1 ? String(koli) : '', String(u.koliAd || '').substring(0, 20), simdi, kim];
    n++;
  });
  var rows = Object.keys(m).map(function (b) { return [b].concat(m[b]); });
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sheet = ss.getSheetByName(ETIKET_BILGI_SEKME) || ss.insertSheet(ETIKET_BILGI_SEKME);
  if (sheet.getMaxRows() < rows.length + 1) sheet.insertRowsAfter(sheet.getMaxRows(), rows.length + 1 - sheet.getMaxRows());
  sheet.getRange(1, 1, rows.length + 1, 8).setNumberFormat('@');
  tabloyuDegistir(sheet, ETIKET_BILGI_BASLIK, rows);
  return jsonCikti({ status: 'ok', kaydedilen: n });
}
// ---- BASILMIŞ ÇEŞİT GRUPLARI ----
// Birden çok ürünü kapsayan etiket basılınca grup burada saklanır: hangi ürünler, hangi fiyatla.
// Böylece (1) grup bütün cihazlarda hazır gelir, (2) gruptaki bir ürünün fiyatı değişince
// uygulama "raftaki çeşit etiketi artık yanlış" diye uyarabilir.
// ============================================================
// ETİKET GÜVENLİĞİ (build 139) — etiket müşterinin gördüğü fiyattır.
//  * Etiket işlemleri "Kimlik zorunlu" ayarından BAĞIMSIZ olarak giriş ister: kimliksiz istek her zaman reddedilir.
//  * Yetkiler: etiket (ekrana giriş, basma) · etiket_duzenle (ad, üretim yeri, net miktar…) · etiket_indirim ·
//    etiket_cesit (çok ürünlü etiket) · etiket_ayar (ölçü, logo, yazı) · etiket_yazici (yazıcı seçme, işleri yönetme) ·
//    etiket_kuyruk (fiyatı değişenler listesi, "basıldı say"). Yönetici hepsine sahiptir.
//  * FİYAT, STOK KODU ve BARKOD etikete yalnızca katalogdan (ERP) gelir: baskı işi sunucuda katalogla
//    karşılaştırılır; uyuşmayan iş basılmaz. Katalogda olmayan (elle) ürünü yalnızca yönetici basabilir.
// ============================================================
var ETIKET_POST_TURLERI = { etiket_liste: 1, etiket_grup: 1, etiket_bilgi: 1, etiket_baski_kaydi: 1, baski_is: 1, etiket_basildi: 1, etiket_ayar: 1 };
function etiketYetki(auth, ek) {
  if (!auth || !auth.ok) return false;
  if (auth.role === 'yonetici') return true;
  var p = auth.permissions || [];
  return p.indexOf('etiket') !== -1 && (!ek || p.indexOf(ek) !== -1);
}
function etiketRed(auth, callback) {
  return outJson({ status: 'error', kimlik: !(auth && auth.ok), message: (auth && auth.ok) ? 'Bu etiket işlemi için yetkin yok' : 'Giriş gerekli — çıkış yapıp tekrar giriş yap' }, callback);
}
// Katalog: barkod -> { ad, kod, fiyat }
function etiketKatalogHarita() {
  var sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName('Katalog'), m = {};
  if (!sheet || sheet.getLastRow() < 2) return m;
  sheet.getRange(2, 1, sheet.getLastRow() - 1, 5).getValues().forEach(function (r) {
    var b = String(r[1] || '').trim(); if (!b) return;
    m[b] = { ad: String(r[0] || ''), kod: String(r[2] || '').trim(), fiyat: cleanNum(r[4]) };
  });
  return m;
}
// Ortak etiket ayarları (Zebra ölçüleri, logo, yazı…): bütün cihazlar aynı ayarla basar.
var ETIKET_AYAR_OZELLIK = 'ETIKET_AYAR';
function etiketAyarGetir(callback) {
  var v = null; try { v = JSON.parse(PropertiesService.getScriptProperties().getProperty(ETIKET_AYAR_OZELLIK) || 'null'); } catch (e) { v = null; }
  return outJson({ status: 'ok', ayar: v }, callback);
}
function etiketAyarKaydet(ayar, gonderen) {
  if (!ayar || typeof ayar !== 'object') return jsonCikti({ status: 'error', message: 'Boş ayar' });
  var t = {}, z = ayar.zebra || {};
  ['kesim', 'logo', 'bosluk', 'a4diz'].forEach(function (k) { if (ayar[k] !== undefined) t[k] = !!ayar[k]; });
  if (ayar.slogan !== undefined) t.slogan = String(ayar.slogan).substring(0, 28);
  t.zebra = {};
  ['w', 'h', 'kw', 'kh', 'kx', 'ky', 'ox', 'oy'].forEach(function (k) { var n = Number(z[k]); if (isFinite(n) && n >= -30 && n <= 300) t.zebra[k] = n; });
  t.zebra.cerceve = !!z.cerceve;
  t.zaman = Utilities.formatDate(new Date(), fiyatTz(), 'dd.MM.yyyy HH:mm'); t.kullanici = String(gonderen || '').substring(0, 60);
  PropertiesService.getScriptProperties().setProperty(ETIKET_AYAR_OZELLIK, JSON.stringify(t));
  gunlukYaz('etiket_ayar', t.kullanici, 'Etiket ayarları değişti', false);
  return jsonCikti({ status: 'ok' });
}

var ETIKET_GRUP_SEKME = 'EtiketGrup';
var ETIKET_GRUP_BASLIK = ['Id', 'Ad', 'Fiyat', 'Ürünler', 'Zaman', 'Kullanıcı', 'Kod'];   // Kod: etikete basılan 5 haneli çeşitli etiket kodu
function etiketGrupOku() {
  var sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName(ETIKET_GRUP_SEKME);
  var son = sheet ? sheet.getLastRow() : 0, l = [];
  // Eski sayfada 'Kod' sütunu olmayabilir: var olan sütun kadar okunur.
  if (son >= 2) sheet.getRange(2, 1, son - 1, Math.min(7, sheet.getMaxColumns())).getValues().forEach(function (r) {
    var uyeler = []; try { uyeler = JSON.parse(String(r[3] || '[]')); } catch (e) { uyeler = []; }
    if (r[0] && Array.isArray(uyeler) && uyeler.length > 1) l.push({ id: String(r[0]), ad: String(r[1] || ''), fiyat: cleanNum(r[2]), uyeler: uyeler, zaman: String(r[4] || ''), kullanici: String(r[5] || ''), kod: /^\d{5}$/.test(String(r[6] || '').trim()) ? String(r[6]).trim() : '' });
  });
  return l;
}
function etiketGrupGetir(callback) {
  return outJson({ status: 'ok', gruplar: etiketGrupOku().map(function (g) { return { id: g.id, ad: g.ad, fiyat: g.fiyat, uyeler: g.uyeler, kod: g.kod }; }) }, callback);
}
// gruplar: yeni basılan gruplar. dagit: artık tek başına basılan (gruptan ayrılan) ürünlerin barkodları.
// Yeni grupla ya da "dagit" ile ortak ürünü olan eski gruplar silinir: bir ürün tek bir grupta olur.
function etiketGrupKaydet(gruplar, dagit, gonderen) {
  gruplar = Array.isArray(gruplar) ? gruplar.slice(0, 100) : [];
  dagit = Array.isArray(dagit) ? dagit.slice(0, 500).map(String) : [];
  if (!gruplar.length && !dagit.length) return jsonCikti({ status: 'error', message: 'Boş liste' });
  var eski = etiketGrupOku(), cikan = {};
  dagit.forEach(function (b) { cikan[b] = true; });
  var simdi = Utilities.formatDate(new Date(), fiyatTz(), 'dd.MM.yyyy HH:mm'), kim = String(gonderen || '').substring(0, 60), yeni = [];
  gruplar.forEach(function (g) {
    var uyeler = (Array.isArray(g && g.uyeler) ? g.uyeler : []).slice(0, 80).map(function (x) { return { barkod: String((x && x.barkod) || '').substring(0, 40), ad: String((x && x.ad) || '').substring(0, 120) }; })
      .filter(function (x) { return x.barkod; });
    var f = cleanNum(g && g.fiyat);
    if (uyeler.length < 2 || typeof f !== 'number' || !(f > 0)) return;
    uyeler.forEach(function (x) { cikan[x.barkod] = true; });
    yeni.push({ id: Utilities.getUuid().substring(0, 12), ad: String(g.ad || '').substring(0, 120), fiyat: f, uyeler: uyeler, zaman: simdi, kullanici: kim, kod: /^\d{5}$/.test(String((g && g.kod) || '')) ? String(g.kod) : '' });
  });
  // Yeni grupla ortak ürünü olan eski grup silinir (yerine yenisi basıldı). "dagit"teki ürün ise yalnızca
  // grubundan düşülür; geriye 2'den az ürün kalırsa grup silinir. (build 138: eskiden bütün grup siliniyordu.)
  var yeniUye = {}, ayrilan = {};
  yeni.forEach(function (g) { g.uyeler.forEach(function (x) { yeniUye[x.barkod] = true; }); });
  dagit.forEach(function (b) { ayrilan[b] = true; });
  var kalan = eski.filter(function (g) { return !g.uyeler.some(function (x) { return yeniUye[String(x.barkod)]; }); })
    .map(function (g) { g.uyeler = g.uyeler.filter(function (x) { return !ayrilan[String(x.barkod)]; }); return g; })
    .filter(function (g) { return g.uyeler.length > 1; });
  var rows = kalan.concat(yeni).map(function (g) { return [g.id, g.ad, String(g.fiyat), JSON.stringify(g.uyeler), g.zaman, g.kullanici, g.kod || '']; });
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sheet = ss.getSheetByName(ETIKET_GRUP_SEKME) || ss.insertSheet(ETIKET_GRUP_SEKME);
  if (sheet.getMaxRows() < rows.length + 1) sheet.insertRowsAfter(sheet.getMaxRows(), rows.length + 1 - sheet.getMaxRows());
  if (sheet.getMaxColumns() < 7) sheet.insertColumnsAfter(sheet.getMaxColumns(), 7 - sheet.getMaxColumns());
  sheet.getRange(1, 1, Math.max(rows.length, 1) + 1, 7).setNumberFormat('@');
  tabloyuDegistir(sheet, ETIKET_GRUP_BASLIK, rows);
  return jsonCikti({ status: 'ok', grup: rows.length });
}

// ---- ETİKET BASKI KAYDI ----
// Hangi ürüne, hangi fiyatla, ne zaman, kim etiket bastı. İndirim etiketinde önceki
// fiyat ve bitiş tarihi de yazılır: denetimde "neye göre indirim yazdınız" sorusunun kaydı.
var ETIKET_KAYIT_SEKME = 'EtiketBaskiKaydi';
var ETIKET_KAYIT_BASLIK = ['Zaman', 'Kullanıcı', 'Barkod', 'Ürün', 'Fiyat', 'Fiyat Tarihi', 'Biçim', 'İndirim', 'Önceki Fiyat', 'Bitiş', 'Adet', 'Yol'];
var ETIKET_KAYIT_SINIR = 30000;
function etiketBaskiKaydi(satirlar, gonderen) {
  if (!Array.isArray(satirlar) || !satirlar.length) return jsonCikti({ status: 'error', message: 'Boş kayıt' });
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sheet = ss.getSheetByName(ETIKET_KAYIT_SEKME);
  if (!sheet) { sheet = ss.insertSheet(ETIKET_KAYIT_SEKME); sheet.getRange(1, 1, 1, ETIKET_KAYIT_BASLIK.length).setValues([ETIKET_KAYIT_BASLIK]); }
  var simdi = Utilities.formatDate(new Date(), fiyatTz(), 'dd.MM.yyyy HH:mm:ss'), kim = String(gonderen || '').substring(0, 60);
  var met = function (v, n) { return String(v == null ? '' : v).substring(0, n); };
  var rows = satirlar.slice(0, 400).map(function (x) {
    return [simdi, kim, met(x.b, 200), met(x.ad, 120), met(x.fiyat, 16), met(x.ft, 10), met(x.bicim, 8), x.indirim ? 'EVET' : '', met(x.onceki, 16), met(x.bitis, 10), met(x.adet, 4), met(x.yol, 60)];
  });
  var son = sheet.getLastRow();
  if (sheet.getMaxRows() < son + rows.length) sheet.insertRowsAfter(sheet.getMaxRows(), son + rows.length - sheet.getMaxRows());
  sheet.getRange(son + 1, 1, rows.length, 12).setNumberFormat('@').setValues(rows);
  var fazla = sheet.getLastRow() - 1 - ETIKET_KAYIT_SINIR;
  if (fazla > 0) sheet.deleteRows(2, fazla);
  return jsonCikti({ status: 'ok', kaydedilen: rows.length });
}

// ---- TELEFONDAN YAZICIYA BASKI ----
// Yazıcının bağlı olduğu bilgisayarda küçük bir program (yazici/baski-ajani.ps1)
// çalışır: birkaç saniyede bir "iş var mı" diye sorar, işi alır, basar, sonucu yazar.
// Yazıcının modu "manuel" ise iş önce bilgisayardaki kişinin onayını bekler.
var BASKI_IS_SEKME = 'BaskiIsleri';
var BASKI_IS_BASLIK = ['Id', 'Zaman', 'Kullanıcı', 'Yazıcı', 'Biçim', 'Ürün', 'Durum', 'Mesaj', 'Güncelleme', 'Veri'];
var BASKI_YAZICI_SEKME = 'Yazicilar';
var BASKI_YAZICI_BASLIK = ['Kimlik', 'Ad', 'Bilgisayar', 'Windows Adı', 'Mod', 'Son Görülme', 'Konum', 'Biçimler', 'Gizli'];
var BASKI_BICIMLER = ['zebra', 'raf', 'a6', 'a5', 'a4', 'a3'];
var BASKI_IS_SAKLA = 40;
var BASKI_CEVRIMICI_SN = 90;   // program bu kadar saniyedir sormadıysa bilgisayar kapalı sayılır
function baskiSayfa(ad, baslik) {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sheet = ss.getSheetByName(ad);
  if (!sheet) { sheet = ss.insertSheet(ad); sheet.getRange(1, 1, 1, baslik.length).setValues([baslik]); }
  return sheet;
}
function baskiSatirlar(sheet, n) {
  var son = sheet.getLastRow();
  return son >= 2 ? sheet.getRange(2, 1, son - 1, n).getValues() : [];
}
function baskiZaman() { return Utilities.formatDate(new Date(), fiyatTz(), 'dd.MM.yyyy HH:mm:ss'); }
function baskiYazicilar() {
  var simdi = Date.now();
  var sheet = baskiSayfa(BASKI_YAZICI_SEKME, BASKI_YAZICI_BASLIK);
  // Eski sürümde açılmış sekmede yeni başlıklar (Konum, Biçimler, Gizli) yoksa eklenir.
  if (String(sheet.getRange(1, 7).getValue()) !== 'Konum') sheet.getRange(1, 1, 1, BASKI_YAZICI_BASLIK.length).setValues([BASKI_YAZICI_BASLIK]);
  return baskiSatirlar(sheet, 9).map(function (r) {
    var gorulme = Number(r[5]) || 0;
    // Biçimler boşsa yazıcı her biçimi basar; doluysa yalnızca yazılanları (ör. "raf" ya da "a4,a5,a6").
    var bicimler = String(r[7] || '').split(',').map(function (x) { return x.trim(); }).filter(function (x) { return BASKI_BICIMLER.indexOf(x) !== -1; });
    return { kimlik: String(r[0]), ad: String(r[1] || r[3]), bilgisayar: String(r[2]), windowsAdi: String(r[3]), mod: String(r[4]) === 'manuel' ? 'manuel' : 'otomatik',
      cevrimici: simdi - gorulme < BASKI_CEVRIMICI_SN * 1000, konum: String(r[6] || ''), bicimler: bicimler, gizli: String(r[8]) === 'evet' };
  });
}
function baskiIsOzet(r) {
  return { id: String(r[0]), zaman: String(r[1]), kullanici: String(r[2]), yazici: String(r[3]), bicim: String(r[4]), urun: Number(r[5]) || 0, durum: String(r[6]), mesaj: String(r[7] || '') };
}
// Telefon: yeni iş. Yazıcı "manuel" ise onay bekler, değilse doğrudan sıraya girer.
// Reddedilen iş de "hata" durumuyla listeye yazılır: telefon neden basılmadığını oradan görür.
function baskiIsRed(id, gonderen, yaziciKimlik, bicim, adet, mesaj) {
  try {
    var sheet = baskiSayfa(BASKI_IS_SEKME, BASKI_IS_BASLIK), z = baskiZaman();
    sheet.getRange(sheet.getLastRow() + 1, 1, 1, 10).setNumberFormat('@').setValues([[id, z, String(gonderen || '').substring(0, 60), String(yaziciKimlik || ''), String(bicim || ''), String(adet || 0), 'hata', String(mesaj).substring(0, 300), z, '{"liste":[],"ayar":{}}']]);
  } catch (e) { /* kayıt yazılamasa da iş reddedilir */ }
  gunlukYaz('hata', String(gonderen || ''), 'Baskı işi reddedildi: ' + String(mesaj).substring(0, 200), true);
  return jsonCikti({ status: 'error', message: mesaj });
}
function baskiIsEkle(data, gonderen, auth) {
  var id = String(data.id || '').replace(/[^A-Za-z0-9_-]/g, '').substring(0, 40);
  if (!id || !Array.isArray(data.liste) || !data.liste.length) return jsonCikti({ status: 'error', message: 'Boş baskı işi' });
  var yz = baskiYazicilar().filter(function (y) { return y.kimlik === String(data.yazici); })[0];
  if (!yz) return jsonCikti({ status: 'error', message: 'Yazıcı bulunamadı' });
  var bicimAd = String((data.ayar && data.ayar.bicim) || ''), yonetici = !!auth && auth.role === 'yonetici';
  var red = function (m) { return baskiIsRed(id, gonderen, yz.kimlik, bicimAd, data.liste.length, m); };
  // Yazıcı seçme yetkisi olmayan kişi yalnızca o biçimi basan, gizlenmemiş yazıcıya gönderebilir.
  if (!etiketYetki(auth, 'etiket_yazici') && (yz.gizli || (yz.bicimler.length && yz.bicimler.indexOf(bicimAd) === -1))) return red('Bu yazıcıya gönderme yetkin yok');
  // FİYAT / STOK KODU / BARKOD yalnızca katalogdan: her ürün katalogla karşılaştırılır.
  var kat = etiketKatalogHarita(), para2 = function (n) { return (Math.round(n * 100) / 100).toFixed(2).replace('.', ','); };
  var adDegisen = [];
  for (var u = 0; u < data.liste.length; u++) {
    var x = data.liste[u] || {}, f = cleanNum(x.fiyat), ad = String(x.ad || '').substring(0, 120);
    if (typeof f !== 'number' || !(f > 0)) return red('Fiyatı olmayan ürün basılamaz: ' + ad);
    var uyeler = (Array.isArray(x.grup) && x.grup.length > 1) ? x.grup.map(function (g) { return String((g && g.barkod) || '').trim(); }) : null;
    if (uyeler) {
      if (!etiketYetki(auth, 'etiket_cesit')) return red('Çok ürünlü etiket basma yetkin yok: ' + ad);
      for (var g2 = 0; g2 < uyeler.length; g2++) {
        var ku = kat[uyeler[g2]];
        if (!ku) return red('Katalogda olmayan ürün: ' + uyeler[g2] + ' (' + ad + ')');
        if (typeof ku.fiyat !== 'number' || Math.abs(ku.fiyat - f) > 0.005) return red('Fiyat katalogla uyuşmuyor: ' + ku.ad + ' (etikette ' + para2(f) + ', katalogda ' + (typeof ku.fiyat === 'number' ? para2(ku.fiyat) : 'yok') + ') — kataloğu yenileyip tekrar gönder');
      }
      continue;
    }
    var b = String(x.barkod || '').trim();
    if (x.elle || !b) { if (!yonetici) return red('Katalogda olmayan (elle eklenen) ürünü yalnızca yönetici basabilir: ' + ad); continue; }
    var k = kat[b];
    if (!k) return red('Katalogda olmayan ürün: ' + b + ' (' + ad + ')');
    if (typeof k.fiyat !== 'number' || Math.abs(k.fiyat - f) > 0.005) return red('Fiyat katalogla uyuşmuyor: ' + k.ad + ' (etikette ' + para2(f) + ', katalogda ' + (typeof k.fiyat === 'number' ? para2(k.fiyat) : 'yok') + ') — kataloğu yenileyip tekrar gönder');
    x.kod = k.kod;                                   // stok kodu her zaman katalogdaki
    if (ad.trim() !== k.ad.trim()) {
      if (!etiketYetki(auth, 'etiket_duzenle')) x.ad = k.ad;          // yetkisi yoksa katalogdaki ad basılır
      else adDegisen.push('"' + k.ad + '" → "' + ad + '" (' + b + ')');
    }
  }
  if (adDegisen.length) gunlukYaz('etiket_ad', String(gonderen || ''), 'Etikette ürün adı değiştirildi: ' + adDegisen.slice(0, 5).join(' · ').substring(0, 400), false);
  var veri = JSON.stringify({ liste: data.liste, ayar: data.ayar || {} });
  if (veri.length > ETIKET_LISTE_SINIR) return jsonCikti({ status: 'error', buyuk: true, message: 'Liste çok uzun — bölerek gönderin' });
  var sheet = baskiSayfa(BASKI_IS_SEKME, BASKI_IS_BASLIK), satirlar = baskiSatirlar(sheet, 1);
  for (var i = 0; i < satirlar.length; i++) if (String(satirlar[i][0]) === id) return jsonCikti({ status: 'ok', id: id, zatenVar: true });
  var z = baskiZaman();
  sheet.getRange(sheet.getLastRow() + 1, 1, 1, 10).setNumberFormat('@').setValues([[id, z, String(gonderen || '').substring(0, 60), yz.kimlik,
    String((data.ayar && data.ayar.bicim) || ''), String(data.liste.length), yz.mod === 'manuel' ? 'onay_bekliyor' : 'bekliyor', '', z, veri]]);
  var fazla = sheet.getLastRow() - 1 - BASKI_IS_SAKLA;
  if (fazla > 0) sheet.deleteRows(2, fazla);
  return jsonCikti({ status: 'ok', id: id });
}
// Uygulama: yazıcılar + son işler (durum ekranı ve telefondaki takip).
function baskiDurum(callback) {
  var isler = baskiSatirlar(baskiSayfa(BASKI_IS_SEKME, BASKI_IS_BASLIK), 9).map(baskiIsOzet).reverse().slice(0, 15);
  return outJson({ status: 'ok', yazicilar: baskiYazicilar(), isler: isler }, callback);
}
function baskiIsGuncelle(id, fn) {
  var sheet = baskiSayfa(BASKI_IS_SEKME, BASKI_IS_BASLIK), satirlar = baskiSatirlar(sheet, 9);
  for (var i = satirlar.length - 1; i >= 0; i--) {
    if (String(satirlar[i][0]) !== String(id)) continue;
    var yeni = fn(String(satirlar[i][6]));
    if (!yeni) return false;
    sheet.getRange(i + 2, 7, 1, 3).setNumberFormat('@').setValues([[yeni.durum, String(yeni.mesaj || '').substring(0, 300), baskiZaman()]]);
    return true;
  }
  return false;
}
// Uygulama: manuel işi onayla / bekleyen işi iptal et / hatalı işi yeniden dene.
function baskiIslem(id, islem, callback) {
  var lock = LockService.getScriptLock();
  try { lock.waitLock(15000); } catch (e) { return outJson({ status: 'error', message: 'Sunucu yoğun, tekrar dene' }, callback); }
  try {
    var ok = baskiIsGuncelle(id, function (durum) {
      if (islem === 'onayla' && durum === 'onay_bekliyor') return { durum: 'bekliyor' };
      if (islem === 'iptal' && (durum === 'onay_bekliyor' || durum === 'bekliyor')) return { durum: 'iptal' };
      if (islem === 'tekrar' && (durum === 'hata' || durum === 'basildi' || durum === 'iptal')) return { durum: 'bekliyor' };
      return null;
    });
    return outJson(ok ? { status: 'ok' } : { status: 'error', message: 'İşin durumu değişmiş — listeyi yenile' }, callback);
  } finally { lock.releaseLock(); }
}
// p: { kimlik, ad, mod, konum, bicimler ("raf,a4"), gizli ("evet"/"hayir"), sil ("evet") } — verilmeyen alan değişmez.
function baskiYaziciAyar(p, callback) {
  var sheet = baskiSayfa(BASKI_YAZICI_SEKME, BASKI_YAZICI_BASLIK), satirlar = baskiSatirlar(sheet, 6);
  for (var i = 0; i < satirlar.length; i++) {
    if (String(satirlar[i][0]) !== String(p.kimlik)) continue;
    // Silinen yazıcı, bilgisayarındaki program çalışıyorsa bir sonraki sorguda yeniden kaydolur (kalıcı gizlemek için "gizli").
    if (p.sil === 'evet') { sheet.deleteRows(i + 2, 1); return outJson({ status: 'ok' }, callback); }
    if (p.ad !== undefined && String(p.ad).trim()) sheet.getRange(i + 2, 2).setNumberFormat('@').setValue(String(p.ad).trim().substring(0, 40));
    if (p.mod === 'manuel' || p.mod === 'otomatik') sheet.getRange(i + 2, 5).setValue(p.mod);
    if (p.konum !== undefined) sheet.getRange(i + 2, 7).setNumberFormat('@').setValue(String(p.konum).trim().substring(0, 40));
    if (p.bicimler !== undefined) sheet.getRange(i + 2, 8).setNumberFormat('@').setValue(String(p.bicimler).split(',').map(function (x) { return x.trim(); }).filter(function (x) { return BASKI_BICIMLER.indexOf(x) !== -1; }).join(','));
    if (p.gizli === 'evet' || p.gizli === 'hayir') sheet.getRange(i + 2, 9).setValue(p.gizli);
    return outJson({ status: 'ok' }, callback);
  }
  return outJson({ status: 'error', message: 'Yazıcı bulunamadı' }, callback);
}
// Program: "ben buradayım, yazıcılarım şunlar, iş var mı?" — sıradaki işi verir.
function baskiAjanAl(bilgisayar, yazicilarJson, callback) {
  var pc = String(bilgisayar || '').substring(0, 40), adlar = [];
  try { adlar = JSON.parse(yazicilarJson || '[]'); } catch (e) { adlar = []; }
  if (!pc || !Array.isArray(adlar)) return outJson({ status: 'error', message: 'Eksik bilgi' }, callback);
  var lock = LockService.getScriptLock();
  try { lock.waitLock(15000); } catch (e2) { return outJson({ status: 'ok', is: null, mesgul: true }, callback); }
  try {
    var ysheet = baskiSayfa(BASKI_YAZICI_SEKME, BASKI_YAZICI_BASLIK), yr = baskiSatirlar(ysheet, 6), simdi = Date.now(), benim = {};
    adlar.slice(0, 30).forEach(function (wad) {
      wad = String(wad).substring(0, 120); if (!wad) return;
      var kimlik = pc + '|' + wad, sat = -1;
      for (var i = 0; i < yr.length; i++) if (String(yr[i][0]) === kimlik) { sat = i; break; }
      if (sat === -1) { yr.push([kimlik, wad, pc, wad, 'otomatik', simdi]); ysheet.getRange(yr.length + 1, 1, 1, 6).setValues([yr[yr.length - 1]]); }
      else ysheet.getRange(sat + 2, 6).setValue(simdi);
      benim[kimlik] = wad;
    });
    var isheet = baskiSayfa(BASKI_IS_SEKME, BASKI_IS_BASLIK), ir = baskiSatirlar(isheet, 10);
    for (var j = 0; j < ir.length; j++) {
      if (String(ir[j][6]) !== 'bekliyor' || !benim[String(ir[j][3])]) continue;
      isheet.getRange(j + 2, 7, 1, 3).setNumberFormat('@').setValues([['basiliyor', '', baskiZaman()]]);
      var ayar = {}; try { ayar = (JSON.parse(String(ir[j][9])) || {}).ayar || {}; } catch (pe) { ayar = {}; }
      return outJson({ status: 'ok', is: { id: String(ir[j][0]), windowsAdi: benim[String(ir[j][3])], bicim: String(ir[j][4]), ayar: ayar } }, callback);
    }
    return outJson({ status: 'ok', is: null }, callback);
  } finally { lock.releaseLock(); }
}
function baskiAjanVeri(id, callback) {
  var ir = baskiSatirlar(baskiSayfa(BASKI_IS_SEKME, BASKI_IS_BASLIK), 10);
  for (var j = ir.length - 1; j >= 0; j--) {
    if (String(ir[j][0]) !== String(id)) continue;
    try { var v = JSON.parse(String(ir[j][9])); return outJson({ status: 'ok', liste: v.liste || [], ayar: v.ayar || {} }, callback); }
    catch (e) { return outJson({ status: 'error', message: 'İş verisi okunamadı' }, callback); }
  }
  return outJson({ status: 'error', message: 'İş bulunamadı' }, callback);
}
function baskiAjanBitti(id, durum, mesaj, callback) {
  // "kontrol": program basmadan hemen önce sorar — iş hâlâ "basılıyor" mu (iptal/hata olmadı mı)?
  if (durum === 'kontrol') {
    var hala = false;
    baskiIsGuncelle(id, function (eski) { hala = eski === 'basiliyor'; return null; });
    return outJson({ status: hala ? 'ok' : 'error' }, callback);
  }
  var ok = baskiIsGuncelle(id, function (eski) { return eski === 'basiliyor' ? { durum: durum === 'basildi' ? 'basildi' : 'hata', mesaj: mesaj } : null; });
  if (durum !== 'basildi') gunlukYaz('hata', 'baskı programı', 'Baskı işi başarısız: ' + String(mesaj || '').substring(0, 200), true);
  return outJson({ status: ok ? 'ok' : 'error' }, callback);
}

// ---- BASILACAK ETİKETLER KUYRUĞU ----
// Fiyatı değişen ürün "basılacak"tır; etiketi basılınca (barkod + o fiyatın tarihi)
// buraya yazılır ve bütün telefonlarda kuyruktan düşer. Fiyat yeniden değişirse
// tarih değiştiği için ürün kuyruğa yeniden girer.
var ETIKET_BASILDI_SEKME = 'EtiketBasildi';
var ETIKET_BASILDI_BASLIK = ['Barkod', 'Fiyat Tarihi', 'Zaman', 'Kullanıcı'];
var ETIKET_BASILDI_SAKLA_GUN = 60;
function etiketBasildiOku() {
  var sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName(ETIKET_BASILDI_SEKME);
  var son = sheet ? sheet.getLastRow() : 0, m = {};
  if (son >= 2) sheet.getRange(2, 1, son - 1, 4).getValues().forEach(function (r) {
    var b = String(r[0] || ''); if (b) m[b] = [fiyatTarihiMetni(r[1]), String(r[2] || ''), String(r[3] || '')];
  });
  return m;
}
function etiketBasildiKaydet(urunler, gonderen) {
  if (!Array.isArray(urunler) || !urunler.length) return jsonCikti({ status: 'error', message: 'Boş liste' });
  var m = etiketBasildiOku();
  var simdi = Utilities.formatDate(new Date(), fiyatTz(), 'dd.MM.yyyy HH:mm'), kim = String(gonderen || '').substring(0, 60), n = 0;
  urunler.slice(0, 2000).forEach(function (u) {
    var b = String((u && u[0]) || '').trim(), ft = erpFiyatTarihi(u && u[1]);
    if (!b || !ft) return;
    m[b] = [ft, simdi, kim]; n++;
  });
  // Eski kayıtlar atılır: o tarihli değişim artık kuyruk penceresinin dışında.
  var sinir = Utilities.formatDate(new Date(Date.now() - ETIKET_BASILDI_SAKLA_GUN * 86400000), fiyatTz(), 'yyyy-MM-dd');
  var rows = Object.keys(m).filter(function (b) { return m[b][0] >= sinir; }).map(function (b) { return [b, m[b][0], m[b][1], m[b][2]]; });
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sheet = ss.getSheetByName(ETIKET_BASILDI_SEKME) || ss.insertSheet(ETIKET_BASILDI_SEKME);
  if (sheet.getMaxRows() < rows.length + 1) sheet.insertRowsAfter(sheet.getMaxRows(), rows.length + 1 - sheet.getMaxRows());
  sheet.getRange(1, 1, Math.max(rows.length, 1) + 1, 4).setNumberFormat('@');
  if (rows.length) tabloyuDegistir(sheet, ETIKET_BASILDI_BASLIK, rows);
  return jsonCikti({ status: 'ok', kaydedilen: n });
}
function etiketKuyrukGetir(callback) {
  var props = PropertiesService.getScriptProperties();
  var bas = props.getProperty('ETIKET_KUYRUK_BASLANGIC');
  if (!bas) { bas = Utilities.formatDate(new Date(), fiyatTz(), 'yyyy-MM-dd'); props.setProperty('ETIKET_KUYRUK_BASLANGIC', bas); }
  var m = etiketBasildiOku(), basilan = {};
  Object.keys(m).forEach(function (b) { basilan[b] = m[b][0]; });
  return outJson({ status: 'ok', baslangic: bas, basilan: basilan }, callback);
}

function jsonCikti(o) { return ContentService.createTextOutput(JSON.stringify(o)).setMimeType(ContentService.MimeType.JSON); }

function saveCariBulk(entries) {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sheet = ss.getSheetByName('Cari');
  if (!sheet) sheet = ss.insertSheet('Cari');
  var props = PropertiesService.getScriptProperties();
  var ozet = listeOzeti(entries.map(function (e) { return [e.name || '', e.code || '', cleanNum(e.balance)]; }));
  if (entries.length > 0 && ozet === props.getProperty('CARI_OZET') && sheet.getLastRow() === entries.length + 1) {
    return ContentService.createTextOutput(JSON.stringify({ status: 'ok', saved: 0, degisiklikYok: true })).setMimeType(ContentService.MimeType.JSON);
  }
  // BOŞ liste = büyük ihtimalle ERP sorgusu başarısız oldu. Mevcut cari
  // listesini silmek yerine reddet; eldeki liste aynen kalır.
  if (!Array.isArray(entries) || entries.length === 0) {
    return jsonCikti({ status: 'error', bosListe: true, message: 'Boş cari listesi geldi — mevcut liste korunuyor' });
  }
  var rows = entries.map(function (e) { return [e.name || '', e.code || '', cleanNum(e.balance)]; });
  tabloyuDegistir(sheet, ['Cari Adı', 'Cari Kodu', 'Bakiye'], rows);
  sheet.getRange(2, 3, rows.length, 1).setNumberFormat('0.00');
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
    var genislik = Math.min(Math.max(sheet.getLastColumn(), 8), KATALOG_BASLIK.length);
    var values = sheet.getRange(2, 1, sheet.getLastRow() - 1, genislik).getValues();
    entries = values
      .filter(function (r) { return r[0] && r[1]; })
      .map(function (r) {
        // ⚠️ "r[3] || ''" yazınca sayısal 0 değeri (stok 0, KDV %0) boş sayılıyordu:
        // sıfır stoklu ürün "stok bilgisi yok" gibi görünüyordu. Sadece gerçekten
        // boş hücreler boş kalır, 0 olduğu gibi gelir.
        var e = { name: String(r[0]), barcode: String(r[1]), stockCode: String(r[2] || ''), oldStock: numOrEmpty(r[3]), price: numOrEmpty(r[4]), kdv: numOrEmpty(r[5]) };
        // Koli barkodu (çarpan > 1): telefon girilen koli sayısını adede çevirir.
        if (Number(r[6]) > 1) e.carpan = String(r[6]);
        if (r[7]) e.birim = String(r[7]); // ERP12 birim adı: ADET, KOLİ, KG…
        // Fiyat izleme (etiket için): fiyatın son değiştiği gün ve o günden
        // önceki 30 gün içindeki en düşük fiyat. Hiç değişmediyse alan gelmez.
        var ft = fiyatTarihiMetni(r[8]);
        if (ft) { e.ft = ft; if (r[9] !== '' && r[9] !== null && r[9] !== undefined) e.of = String(r[9]); }
        if (r[10]) e.yer = String(r[10]); // üretim yeri (ERP stok kartındaki ülke)
        if (r[11]) { var pr = promosyonMetni(r[11]); if (pr) e.pr = pr; } // kasanın miktar indirimi
        if (typeof r[12] === 'number' && r[12] > 0) e.af = String(r[12]); // son alış fiyatı (KDV hariç) — mal girişte kullanılır
        return e;
      });
  }
  // fiyatIzleme: fiyat geçmişinin tutulmaya başlandığı gün (öncesi bilinmez).
  var json = JSON.stringify({ entries: entries, fiyatIzleme: PropertiesService.getScriptProperties().getProperty('FIYAT_IZLEME_BASLANGIC') || '' });
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
  tabloyuDegistir(sheet, SUBE_BASLIK, satirlar);
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
  ['katalog', 'katalog_urun', 'cari', 'sayim', 'mal', 'masaustu_kontrol', 'masaustu', 'yetki', 'telefon_hata', 'hata', 'yonetim', 'konum', 'veritabani', 'guvenlik', 'guvenlik_red'].forEach(function (t) {
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

    // ---- KİMLİK KAPISI (bkz. GÜVENLİK bölümü) ----
    // Katalog/cari listesinin tamamını değiştirmek: ERP anahtarı ya da
    // "ayarlar" yetkili kullanıcı. Diğer her yazma: giriş yapmış kullanıcı.
    var topluMu = data.type === 'katalog_bulk' || data.type === 'cari_bulk' || data.type === 'iade_bulk';
    var postKapi = (topluMu && erpAnahtarDogru(data.anahtar)) ? { ok: true }
      : kimlikGerek(data.user, data.pass,
          data.type === 'katalog_bulk' ? 'katalog gönderimi' : data.type === 'cari_bulk' ? 'cari gönderimi'
            : data.type === 'etiket_liste' ? 'etiket listesi gönderimi' : data.type === 'etiket_basildi' ? 'etiket basıldı kaydı' : data.type === 'baski_is' ? 'baskı işi gönderimi' : (data.type === 'etiket_bilgi' || data.type === 'etiket_baski_kaydi' || data.type === 'etiket_grup') ? 'etiket bilgisi gönderimi' : data.type === 'katalog_item' ? 'yeni ürün gönderimi' : data.type === 'mal_hareket' ? 'mal hareketi gönderimi' : 'sayım gönderimi',
          topluMu ? 'ayarlar' : null);
    var gonderenAd = data.user ? String(data.user) : '';
    // Etiket işlemleri: geçiş dönemi ayarından bağımsız, her zaman giriş + yetki ister.
    var etiketAuth = null, etiketRedMesaj = '';
    if (ETIKET_POST_TURLERI[data.type]) {
      etiketAuth = kimlikOnbellek(data.user, data.pass);
      var ekYetki = data.type === 'etiket_ayar' ? 'etiket_ayar'
        : (data.type === 'etiket_grup' && Array.isArray(data.gruplar) && data.gruplar.length) ? 'etiket_cesit'
        : (data.type === 'etiket_basildi' && data.elle) ? 'etiket_kuyruk' : null;
      if (!etiketYetki(etiketAuth, ekYetki)) etiketRedMesaj = etiketAuth.ok ? 'Bu etiket işlemi için yetkin yok' : 'Giriş gerekli — çıkış yapıp tekrar giriş yap';
    }
    // Şifre ve anahtar bundan sonra HİÇBİR yere (günlük, kuyruk, veri tabanı) taşınmaz.
    delete data.user; delete data.pass; delete data.anahtar;
    if (etiketRedMesaj) {
      guvenlikNot('guvenlik_red', 'etiket ' + data.type, 'Etiket isteği REDDEDİLDİ (' + (gonderenAd || 'kimliksiz').substring(0, 60) + '): ' + etiketRedMesaj, true);
      return ContentService.createTextOutput(JSON.stringify({ status: 'error', kimlik: !(etiketAuth && etiketAuth.ok), message: etiketRedMesaj })).setMimeType(ContentService.MimeType.JSON);
    }
    if (!postKapi.ok) {
      return ContentService.createTextOutput(JSON.stringify({ status: 'error', kimlik: !!postKapi.kimlik, message: postKapi.message })).setMimeType(ContentService.MimeType.JSON);
    }

    if (data.type === 'etiket_liste') {
      var eOut = etiketListeKaydet(data, gonderenAd);
      gunlukYaz('etiket_liste', kaynak, 'Etiket listesi: ' + ((data.liste || []).length) + ' ürün', eOut.getContent().indexOf('"error"') !== -1);
      return eOut;
    }
    if (data.type === 'etiket_grup') return etiketGrupKaydet(data.gruplar, data.dagit, gonderenAd);
    if (data.type === 'etiket_bilgi') return etiketBilgiKaydet(data.urunler, gonderenAd);
    if (data.type === 'etiket_baski_kaydi') return etiketBaskiKaydi(data.satirlar, gonderenAd);
    if (data.type === 'baski_is') return baskiIsEkle(data, gonderenAd, etiketAuth);
    if (data.type === 'etiket_ayar') return etiketAyarKaydet(data.ayar, gonderenAd);
    if (data.type === 'etiket_basildi') return etiketBasildiKaydet(data.urunler, gonderenAd);
    if (data.type === 'katalog_bulk') {
      // ERP'nin fiyat değişiklik kaydı ne kadar geriye gidiyorsa "geçmiş başlangıcı" o gündür.
      var gb = erpFiyatTarihi(data.fiyatGecmisBas), gbProps = PropertiesService.getScriptProperties(), gbEski = gbProps.getProperty('FIYAT_IZLEME_BASLANGIC');
      if (gb && (!gbEski || gb < gbEski)) gbProps.setProperty('FIYAT_IZLEME_BASLANGIC', gb);
      var kOut = saveKatalogBulk(data.entries || []);
      var kDegismedi = kOut.getContent().indexOf('degisiklikYok') !== -1;
      var kBos = kOut.getContent().indexOf('bosListe') !== -1;
      gunlukYaz('katalog', kaynak, kBos ? 'BOŞ katalog geldi — reddedildi, mevcut katalog korundu'
        : (data.entries || []).length + ' ürün geldi' + (kDegismedi ? ' — değişiklik yok, tablo aynen kaldı' : ' — katalog güncellendi'), kBos);
      return kOut;
    }
    if (data.type === 'katalog_item') {
      var kiOut = saveKatalogItem(data.entry || {});
      gunlukYaz('katalog_urun', kaynak, 'Tek ürün: ' + ((data.entry && data.entry.name) || '') + ' (' + ((data.entry && data.entry.barcode) || '') + ')', false);
      return kiOut;
    }
    if (data.type === 'iade_bulk') return iadeBulkKaydet(data.fisler);
    if (data.type === 'cari_bulk') {
      var cOut = saveCariBulk(data.entries || []);
      var cDegismedi = cOut.getContent().indexOf('degisiklikYok') !== -1;
      var cBos = cOut.getContent().indexOf('bosListe') !== -1;
      gunlukYaz('cari', kaynak, cBos ? 'BOŞ cari listesi geldi — reddedildi, mevcut liste korundu'
        : (data.entries || []).length + ' cari geldi' + (cDegismedi ? ' — değişiklik yok' : ' — liste güncellendi'), cBos);
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

// Koli çarpanı: sadece 1'den büyükse yazılır (adet barkodlarında boş kalır).
function koliCarpan(v) {
  var n = Number(v);
  return (isFinite(n) && n > 1) ? n : '';
}

// ============================================================
// FİYAT İZLEME (etiket ve indirim için)
// Katalog her yenilendiğinde gelen fiyat, tablodaki önceki fiyatla
// karşılaştırılır. Fiyatı değişen her ürün için:
//   • 'Fiyat Tarihi' (9. sütun): fiyatın değiştiği gün → etiketteki "fiyat
//     değişiklik tarihi" buradan gelir, personel elle yazmaz.
//   • 'Önceki Fiyat' (10. sütun): değişimden önceki 30 gün içinde uygulanan EN
//     DÜŞÜK fiyat → "indirim" etiketi basılacaksa gösterilecek önceki fiyat.
//     (Fiyat Etiketi Yönetmeliği m.11 on gün der; reklam kılavuzu otuz gün
//     diyor. Otuz günün en düşüğü ikisini de karşılar.)
//   • 'FiyatGecmisi' sekmesine bir satır: Zaman | Barkod | Eski | Yeni. Bu
//     sekme, "önceki fiyat buydu" diyebilmenin KANITIDIR; 400 günden eski
//     satırlar silinir.
// İzleme bu sürümün yüklendiği gün başlar (FIYAT_IZLEME_BASLANGIC); öncesi
// bilinmez, o yüzden ilk 30 gün içindeki "önceki fiyat" eksik olabilir.
// ============================================================
// 11. sütun 'Üretim Yeri': ERP12 stok kartındaki ülke (dbo.ULKE.AD). Etiketteki
// "Üretim yeri" ve yerli üretim logosu buradan gelir; ERP'de boşsa boş kalır.
var KATALOG_BASLIK = ['Ürün Adı', 'Barkod', 'Stok Kodu', 'Eski Stok', 'Fiyat', 'KDV %', 'Koli Çarpanı', 'Birim', 'Fiyat Tarihi', 'Önceki Fiyat', 'Üretim Yeri', 'Promosyon', 'Son Alış'];
// Promosyon: kasanın miktar indirimi (ERP12 POS_PROMASYON) — "ADET:YÜZDE:BİTİŞ" (örn. "24:10:2029-12-28").
function promosyonMetni(v) { var m = String(v == null ? '' : v).trim(); return /^\d{1,4}(\.\d+)?:\d{1,2}(\.\d+)?:\d{4}-\d\d-\d\d$/.test(m) ? m : ''; }
// ERP'den gelen fiyat tarihi: yalnızca 'yyyy-MM-dd' ve bugünden ileri olmayan değer kabul edilir.
function erpFiyatTarihi(v) {
  var m = /^(\d{4}-\d{2}-\d{2})$/.exec(String(v == null ? '' : v).trim());
  if (!m) return '';
  return m[1] <= Utilities.formatDate(new Date(), fiyatTz(), 'yyyy-MM-dd') ? m[1] : '';
}
function ulkeMetni(v) { return String(v == null ? '' : v).replace(/\s+/g, ' ').trim().substring(0, 60); }
var FIYAT_GECMIS_SEKME = 'FiyatGecmisi';
var FIYAT_GECMIS_BASLIK = ['Zaman', 'Barkod', 'Eski Fiyat', 'Yeni Fiyat'];
var ONCEKI_FIYAT_GUN = 30;
function fiyatTz() { return Session.getScriptTimeZone() || 'Europe/Istanbul'; }
// Hücredeki tarih (Sheets metni Date'e çevirebilir) → 'yyyy-MM-dd' ya da ''.
function fiyatTarihiMetni(v) {
  if (v instanceof Date) return isNaN(v.getTime()) ? '' : Utilities.formatDate(v, fiyatTz(), 'yyyy-MM-dd');
  var m = /^(\d{4}-\d{2}-\d{2})/.exec(String(v || '').trim());
  return m ? m[1] : '';
}
// Değişen barkodlar için son 30 gündeki en düşük fiyat (geçmiş sekmesinden).
function fiyatGecmisEnDusuk(barkodlar) {
  var sonuc = {};
  var sh = SpreadsheetApp.getActiveSpreadsheet().getSheetByName(FIYAT_GECMIS_SEKME);
  if (!sh || sh.getLastRow() < 2) return sonuc;
  var sinir = Date.now() - ONCEKI_FIYAT_GUN * 86400000;
  sh.getRange(2, 1, sh.getLastRow() - 1, 4).getValues().forEach(function (r) {
    var b = String(r[1]);
    if (!barkodlar[b]) return;
    var z = r[0] instanceof Date ? r[0].getTime() : Date.parse(r[0]);
    if (isNaN(z) || z < sinir) return;
    // O değişimin iki ucu da son 30 günde uygulanmış fiyatlardır.
    [r[2], r[3]].forEach(function (f) { f = Number(f); if (isFinite(f) && f > 0 && (sonuc[b] === undefined || f < sonuc[b])) sonuc[b] = f; });
  });
  return sonuc;
}
function fiyatGecmisYaz(degisen) {
  if (!degisen.length) return;
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sh = ss.getSheetByName(FIYAT_GECMIS_SEKME);
  if (!sh) {
    sh = ss.insertSheet(FIYAT_GECMIS_SEKME);
    sh.getRange(1, 1, 1, FIYAT_GECMIS_BASLIK.length).setValues([FIYAT_GECMIS_BASLIK]);
  }
  var zaman = Utilities.formatDate(new Date(), fiyatTz(), 'yyyy-MM-dd HH:mm:ss');
  var satirlar = degisen.map(function (d) { return [zaman, d[0], d[1], d[2]]; });
  if (sh.getMaxRows() < sh.getLastRow() + satirlar.length) sh.insertRowsAfter(sh.getMaxRows(), sh.getLastRow() + satirlar.length - sh.getMaxRows());
  var ilk = sh.getLastRow() + 1;
  sh.getRange(ilk, 2, satirlar.length, 1).setNumberFormat('@'); // barkod metin kalsın
  sh.getRange(ilk, 1, satirlar.length, 4).setValues(satirlar);
  // 400 günden eski kayıtları baştan sil (sekme sonsuza kadar büyümesin).
  if (sh.getLastRow() > 60000) {
    var sinir = Date.now() - 400 * 86400000;
    var zamanlar = sh.getRange(2, 1, Math.min(sh.getLastRow() - 1, 20000), 1).getValues();
    var sil = 0;
    while (sil < zamanlar.length) { var z = zamanlar[sil][0] instanceof Date ? zamanlar[sil][0].getTime() : Date.parse(zamanlar[sil][0]); if (isNaN(z) || z >= sinir) break; sil++; }
    if (sil > 0) sh.deleteRows(2, sil);
  }
}

function saveKatalogBulk(entries) {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sheet = ss.getSheetByName('Katalog');
  if (!sheet) sheet = ss.insertSheet('Katalog');
  var props = PropertiesService.getScriptProperties();
  var ozet = listeOzeti(entries.map(function (e) { return [e.name || '', e.barcode || '', e.stockCode || '', cleanNum(e.oldStock), cleanNum(e.price), cleanNum(e.kdv), koliCarpan(e.carpan), String(e.birim || ''), ulkeMetni(e.ulke), erpFiyatTarihi(e.ft), cleanNum(e.of), promosyonMetni(e.pr), cleanNum(e.af)]; }));
  if (entries.length > 0 && ozet === props.getProperty('KATALOG_OZET') && sheet.getLastRow() === entries.length + 1) {
    return ContentService.createTextOutput(JSON.stringify({ status: 'ok', saved: 0, degisiklikYok: true })).setMimeType(ContentService.MimeType.JSON);
  }
  // BOŞ liste = büyük ihtimalle ERP sorgusu başarısız oldu ya da dosya yanlış
  // okundu. Kataloğu silmek yerine reddet; eldeki katalog aynen kalır.
  if (!Array.isArray(entries) || entries.length === 0) {
    return jsonCikti({ status: 'error', bosListe: true, message: 'Boş katalog geldi — mevcut katalog korunuyor' });
  }

  // ---- Fiyat izleme: tablodaki mevcut fiyatlarla karşılaştır ----
  var bugun = Utilities.formatDate(new Date(), fiyatTz(), 'yyyy-MM-dd');
  if (!props.getProperty('FIYAT_IZLEME_BASLANGIC')) props.setProperty('FIYAT_IZLEME_BASLANGIC', bugun);
  var eski = {}; // barkod -> { f: fiyat, ft: fiyat tarihi, of: önceki fiyat }
  if (sheet.getLastRow() >= 2) {
    var gen = Math.min(Math.max(sheet.getLastColumn(), 8), 11); // fiyat izleme + üretim yeri
    sheet.getRange(2, 1, sheet.getLastRow() - 1, gen).getValues().forEach(function (r) {
      var b = String(r[1] || ''); if (!b) return;
      eski[b] = { f: cleanNum(r[4]), ft: gen > 8 ? fiyatTarihiMetni(r[8]) : '', of: gen > 9 ? cleanNum(r[9]) : '', y: gen > 10 ? ulkeMetni(r[10]) : '' };
    });
  }
  var degisen = [], degisenBarkod = {}, erpli = {};
  var rows = entries.map(function (e) {
    var b = String(e.barcode || ''), f = cleanNum(e.price), o = eski[b], ft = '', of = '';
    if (o) {
      ft = o.ft; of = o.of;
      if (typeof f === 'number' && typeof o.f === 'number' && f > 0 && o.f > 0 && Math.abs(f - o.f) > 0.004) {
        degisen.push([b, o.f, f]); degisenBarkod[b] = true;
        ft = bugun; of = o.f; // en düşük fiyat aşağıda geçmişe bakılarak düzeltilir
      }
    }
    // ERP kendi fiyat değişiklik kaydını gönderdiyse (STOK_STOK_BIRIM_DEGISIM) o esastır:
    // gerçek değişiklik günü ve değişiklikten önceki 30 günün en düşük fiyatı.
    var eft = erpFiyatTarihi(e.ft);
    if (eft) { ft = eft; var eof = cleanNum(e.of); of = (typeof eof === 'number' && eof > 0) ? eof : ''; erpli[b] = true; }
    return [e.name || '', e.barcode || '', e.stockCode || '', cleanNum(e.oldStock), f, cleanNum(e.kdv), koliCarpan(e.carpan), String(e.birim || ''), ft, of,
      // Ülke alanı HİÇ gelmediyse (eski ERP betiği) tablodaki üretim yeri silinmez, korunur.
      e.ulke === undefined ? (o ? o.y : '') : ulkeMetni(e.ulke), promosyonMetni(e.pr), cleanNum(e.af)];
  });
  if (degisen.length) {
    var enDusuk = fiyatGecmisEnDusuk(degisenBarkod);
    rows.forEach(function (r) {
      var b = String(r[1]);
      if (degisenBarkod[b] && !erpli[b] && enDusuk[b] !== undefined && typeof r[9] === 'number' && enDusuk[b] < r[9]) r[9] = enDusuk[b];
    });
  }

  // 'Fiyat Tarihi' sütunu METİN kalsın: Sheets "2026-10-03" yazısını tarihe
  // çevirirse saat dilimi farkıyla bir gün kayabiliyor.
  if (sheet.getMaxColumns() < KATALOG_BASLIK.length) sheet.insertColumnsAfter(sheet.getMaxColumns(), KATALOG_BASLIK.length - sheet.getMaxColumns());
  if (sheet.getMaxRows() < rows.length + 1) sheet.insertRowsAfter(sheet.getMaxRows(), rows.length + 1 - sheet.getMaxRows());
  sheet.getRange(1, 9, rows.length + 1, 1).setNumberFormat('@');

  tabloyuDegistir(sheet, KATALOG_BASLIK, rows);
  // Fiyat sütununu her zaman 2 ondalık basamakla göster — Sheets'in
  // "Otomatik" biçimi bazen kuruşu gizleyip tam sayıya yuvarlanmış
  // GÖRÜNMESİNE yol açabiliyor (asıl değer bozulmuyor ama kafa karıştırıyor).
  sheet.getRange(2, 5, rows.length, 1).setNumberFormat('0.00');
  sheet.getRange(2, 6, rows.length, 1).setNumberFormat('0.##');
  sheet.getRange(2, 10, rows.length, 1).setNumberFormat('0.00');
  // Geçmiş, katalog yerine oturduktan SONRA yazılır; yazılamazsa katalog yine
  // doğrudur, sadece o değişimin kanıt satırı eksik kalır (günlüğe düşer).
  if (degisen.length) {
    try { fiyatGecmisYaz(degisen); }
    catch (ge) { gunlukYaz('hata', 'fiyat izleme', 'Fiyat geçmişi yazılamadı (' + degisen.length + ' değişim): ' + ge, true); }
  }
  // Katalog her değiştiğinde bir "sürüm" damgası basıyoruz — telefonlar bunu
  // (resetcheck ile) düzenli kontrol edip kendi sürümünden farklıysa
  // kataloğu OTOMATİK olarak sunucudan çeker, kimse elle "Sunucudan Çek"e
  // basmak zorunda kalmaz.
  props.setProperty('KATALOG_VERSION', new Date().toISOString());
  props.setProperty('KATALOG_OZET', ozet);
  return ContentService
    .createTextOutput(JSON.stringify({ status: 'ok', saved: entries.length, fiyatDegisen: degisen.length }))
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
    sheet.appendRow(['Ürün Adı', 'Barkod', 'Stok Kodu', 'Eski Stok', 'Fiyat', 'KDV %', 'Koli Çarpanı', 'Birim']);
  }
  var lastRow = sheet.getLastRow();
  var rowData = [entry.name, entry.barcode, entry.stockCode || '', cleanNum(entry.oldStock), cleanNum(entry.price), cleanNum(entry.kdv), koliCarpan(entry.carpan), String(entry.birim || '')];
  PropertiesService.getScriptProperties().setProperty('KATALOG_VERSION', new Date().toISOString());
  PropertiesService.getScriptProperties().deleteProperty('KATALOG_OZET'); // bir sonraki ERP listesi tabloyu yeniden yazsın
  if (lastRow >= 2) {
    var barcodes = sheet.getRange(2, 2, lastRow - 1, 1).getValues();
    for (var i = 0; i < barcodes.length; i++) {
      if (String(barcodes[i][0]) === String(entry.barcode)) {
        sheet.getRange(i + 2, 1, 1, 8).setValues([rowData]);
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
        name: String(r[0]).trim(), pass: '', // şifre ASLA geri gönderilmez
        role: String(r[2] || 'kullanici').trim().toLowerCase() === 'yonetici' ? 'yonetici' : 'kullanici',
        yetkiler: String(r[3] || ''), active: String(r[4] || 'evet').trim().toLowerCase() !== 'hayir'
      };
    });
  }
  // sifreOzet: true → uygulama "şifre boş = değişmesin" düzenini kullanabilir.
  return outJson({ status: 'ok', users: users, sifreOzet: true }, callback);
}

// data: "Ad;Şifre;Rol;Yetkiler;Aktif;EskiAd" formatında, her satırda bir kullanıcı.
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

    // Mevcut şifreler (ad -> tabloda kayıtlı değer): şifresi boş gönderilen
    // kullanıcının şifresi DEĞİŞMEZ, eski kaydı aynen korunur.
    var eski = {};
    if (sheet.getLastRow() >= 2) {
      sheet.getRange(2, 1, sheet.getLastRow() - 1, 2).getValues().forEach(function (r) {
        var ad = String(r[0] || '').trim().toLowerCase();
        if (ad) eski[ad] = String(r[1] || '');
      });
    }

    // ÖNCE tüm listeyi doğrula — hata varsa tabloya HİÇ dokunulmaz.
    var lines = String(data || '').split('\n');
    var rows = [], gorulen = {}, aktifYonetici = 0, hata = '';
    lines.forEach(function (line) {
      if (hata) return;
      line = line.trim();
      if (!line) return;
      var parts = line.split(';');
      var name = (parts[0] || '').trim();
      if (!name) return;
      var anahtar = name.toLowerCase();
      if (gorulen[anahtar]) { hata = '"' + name + '" adı listede iki kez geçiyor'; return; }
      gorulen[anahtar] = true;
      var passw = (parts[1] || '').trim();
      var role = (parts[2] || 'kullanici').trim().toLowerCase();
      if (role !== 'yonetici') role = 'kullanici';
      var yetkiler = (parts[3] || '').trim();
      var aktif = (parts[4] || 'evet').trim().toLowerCase();
      if (aktif !== 'hayir') aktif = 'evet';
      var eskiAd = (parts[5] || '').trim().toLowerCase();
      var kayit;
      if (passw) {
        kayit = sifreOzetle(passw);                       // yeni / değiştirilen şifre
      } else {
        kayit = eski[eskiAd] || eski[anahtar] || '';      // boş = mevcut şifre aynen kalsın
        if (!kayit) { hata = '"' + name + '" için şifre girilmeli'; return; }
        if (!sifreOzetMi(kayit)) kayit = sifreOzetle(kayit); // düz metin kaldıysa şimdi özetle
      }
      if (role === 'yonetici' && aktif === 'evet') aktifYonetici++;
      rows.push([name, kayit, role, yetkiler, aktif]);
    });
    if (hata) return outJson({ status: 'error', message: hata }, callback);
    if (rows.length === 0) return outJson({ status: 'error', message: 'Liste boş — en az bir kullanıcı olmalı' }, callback);
    if (aktifYonetici === 0) return outJson({ status: 'error', message: 'En az bir AKTİF yönetici olmalı — yoksa kimse kullanıcıları düzenleyemez' }, callback);

    tabloyuDegistir(sheet, ['Ad', 'Şifre', 'Rol', 'Yetkiler', 'Aktif'], rows);
    gunlukYaz('yonetim', String(user || ''), 'Kullanıcı listesi kaydedildi: ' + rows.length + ' kullanıcı', false);
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


// ============================================================
// PERSONEL MESAİ TAKİBİ (deneme) — sayım ve mal kayıtlarından tamamen ayrı
// 'Mesai' sekmesi: her giriş/çıkış bir satır. Saat TELEFONDAN DEĞİL sunucudan
// alınır (telefon saati değiştirilerek oynanamaz). Bir giriş/çıkışın kabul
// edilmesi için İKİSİ BİRDEN gerekir:
//   1) Telefonun konumu bir şubenin yarıçapı içinde ('Subeler' sekmesi),
//   2) Mağazadaki ekranda görünen, 30 saniyede bir değişen 6 haneli kod.
// Sahte konum uygulamasıyla GPS kandırılsa bile kod ancak mağazada görülür.
// Konum sadece personel Giriş/Çıkış'a bastığı anda bir kez alınır (sürekli
// takip YOK). Reddedilen denemeler Sistem Günlüğü'ne yazılır.
// ============================================================
var MESAI_SEKME = 'Mesai';
var MESAI_BASLIK = ['Zaman', 'Tarih', 'Saat', 'Personel', 'Tip', 'Şube', 'Mesafe (m)', 'GPS ± (m)', 'Enlem', 'Boylam', 'Konum Yaşı (sn)', 'Cihaz', 'Not'];
var MESAI_KOD_SN = 30;

function mesaiSir() {
  var props = PropertiesService.getScriptProperties();
  var s = props.getProperty('MESAI_SIR');
  if (!s) { s = Utilities.getUuid() + Utilities.getUuid(); props.setProperty('MESAI_SIR', s); }
  return s;
}
function mesaiKodHesapla(pencere) {
  var b = Utilities.computeHmacSha256Signature('MKM' + pencere, mesaiSir());
  var n = ((b[0] & 0x7f) * 16777216) + ((b[1] & 0xff) * 65536) + ((b[2] & 0xff) * 256) + (b[3] & 0xff);
  return ('000000' + (n % 1000000)).slice(-6);
}
function mesaiPencere(ms) { return Math.floor((ms || Date.now()) / 1000 / MESAI_KOD_SN); }
// Ekrandaki kod en fazla ~1 dakika geçerli (şimdiki ve bir önceki pencere).
function mesaiKodGecerli(kod) {
  kod = String(kod || '').replace(/\D/g, '');
  if (kod.length !== 6) return false;
  var w = mesaiPencere();
  return kod === mesaiKodHesapla(w) || kod === mesaiKodHesapla(w - 1);
}
function mesaiSheet() {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sh = ss.getSheetByName(MESAI_SEKME);
  if (!sh) { sh = ss.insertSheet(MESAI_SEKME); sh.appendRow(MESAI_BASLIK); sh.setFrozenRows(1); }
  return sh;
}
function mesaiTz() { return Session.getScriptTimeZone() || 'Europe/Istanbul'; }
function mesaiSatirlar() {
  var sh = mesaiSheet();
  if (sh.getLastRow() < 2) return [];
  return sh.getRange(2, 1, sh.getLastRow() - 1, MESAI_BASLIK.length).getValues().map(function (r, i) {
    var z = r[0] instanceof Date ? r[0] : new Date(r[0]);
    return { satir: i + 2, zaman: z, personel: String(r[3] || ''), tip: String(r[4] || ''), sube: String(r[5] || ''), not: String(r[12] || '') };
  }).filter(function (x) { return !isNaN(x.zaman.getTime()) && x.personel && x.not.indexOf('İPTAL') !== 0; });
}
function mesaiSaat(d) { return Utilities.formatDate(d, mesaiTz(), 'HH:mm'); }
function mesaiTarih(d) { return Utilities.formatDate(d, mesaiTz(), 'yyyy-MM-dd'); }

// Bir kişinin kayıtlarını günlere böler: giriş → sonraki çıkış bir çalışma
// aralığıdır ve GİRİŞİN günü sayılır (gece yarısını geçen vardiya dahil).
function mesaiGunler(kayitlar) {
  kayitlar = kayitlar.slice().sort(function (a, b) { return a.zaman - b.zaman; });
  var gunler = {}, acik = null;
  function gun(t) { if (!gunler[t]) gunler[t] = { tarih: t, araliklar: [], dakika: 0, eksik: false }; return gunler[t]; }
  kayitlar.forEach(function (k) {
    if (k.tip === 'giris') {
      if (acik) gun(mesaiTarih(acik.zaman)).araliklar.push({ giris: mesaiSaat(acik.zaman), cikis: '', eksik: true });
      acik = k;
    } else if (k.tip === 'cikis') {
      if (!acik) { gun(mesaiTarih(k.zaman)).araliklar.push({ giris: '', cikis: mesaiSaat(k.zaman), eksik: true }); return; }
      var dk = Math.round((k.zaman - acik.zaman) / 60000);
      var g = gun(mesaiTarih(acik.zaman));
      g.araliklar.push({ giris: mesaiSaat(acik.zaman), cikis: mesaiSaat(k.zaman), dakika: dk });
      g.dakika += dk;
      acik = null;
    }
  });
  var simdiIceride = null;
  if (acik) {
    gun(mesaiTarih(acik.zaman)).araliklar.push({ giris: mesaiSaat(acik.zaman), cikis: '', acik: true });
    simdiIceride = { giris: mesaiSaat(acik.zaman), tarih: mesaiTarih(acik.zaman), sube: acik.sube };
  }
  Object.keys(gunler).forEach(function (t) { gunler[t].eksik = gunler[t].araliklar.some(function (a) { return a.eksik; }); });
  return { gunler: Object.keys(gunler).sort().reverse().map(function (t) { return gunler[t]; }), iceride: simdiIceride };
}

// Giriş/çıkış yapabilmek için "mesai" (ya da "mesai_yonetim") yetkisi gerekir.
function mesaiYetkili(p) {
  var auth = authenticate(p.user, p.pass);
  if (!auth.ok) return auth;
  if (auth.permissions.indexOf('mesai') === -1 && auth.permissions.indexOf('mesai_yonetim') === -1) {
    gunlukYaz('yetki', String(p.user || ''), '"mesai" yetkisi yok, işlem reddedildi', true);
    return { ok: false, message: 'Mesai yetkin yok — yöneticinden iste' };
  }
  return auth;
}

function mesaiKaydet(p, callback) {
  var auth = mesaiYetkili(p);
  if (!auth.ok) return outJson({ status: 'error', message: auth.message }, callback);
  var personel = String(p.user || '').trim();
  var tip = p.tip === 'cikis' ? 'cikis' : (p.tip === 'giris' ? 'giris' : '');
  if (!tip) return outJson({ status: 'error', message: 'Giriş mi çıkış mı belli değil' }, callback);
  var red = function (sebep) {
    gunlukYaz('mesai', personel, (tip === 'giris' ? 'Giriş' : 'Çıkış') + ' REDDEDİLDİ: ' + sebep, true);
    return outJson({ status: 'error', message: sebep }, callback);
  };
  if (!mesaiKodGecerli(p.kod)) return red('Mağaza kodu yanlış ya da süresi geçmiş — ekrandaki GÜNCEL kodu gir');
  var enlem = Number(p.enlem), boylam = Number(p.boylam), dogruluk = Math.round(Number(p.dogruluk) || 0);
  if (!p.enlem || !p.boylam || isNaN(enlem) || isNaN(boylam)) return red('Konum alınamadı — konum iznini aç');
  var subeler = subeleriOku();
  if (!subeler.length) return red('Şube konumu tanımlı değil — yönetici Ayarlar\'dan şube eklemeli');
  var enYakin = null;
  subeler.forEach(function (b) {
    var m = mesaiMesafe(enlem, boylam, b.enlem, b.boylam);
    if (!enYakin || m < enYakin.m) enYakin = { b: b, m: m };
  });
  if (enYakin.m > enYakin.b.yaricap) return red('Şube dışındasın (' + enYakin.b.ad + '\'e ' + Math.round(enYakin.m) + ' m)');
  if (dogruluk > Math.max(150, enYakin.b.yaricap)) return red('GPS çok zayıf (±' + dogruluk + ' m) — açık alana çıkıp tekrar dene');
  var simdi = new Date();
  var yas = p.konumZaman ? Math.round((simdi.getTime() - Number(p.konumZaman)) / 1000) : '';
  var notlar = [];
  if (dogruluk === 0) notlar.push('GPS doğruluğu 0 (şüpheli)');
  if (yas !== '' && Math.abs(yas) > 300) notlar.push('telefon saati/konum zamanı ' + yas + ' sn farklı');

  var lock = LockService.getScriptLock();
  try { lock.waitLock(20000); } catch (e) { return outJson({ status: 'error', message: 'Sunucu meşgul — birazdan tekrar dene' }, callback); }
  try {
    var sh = mesaiSheet();
    // Aynı kişinin 1 dakika içindeki aynı kaydı (çift dokunma / tekrar gönderim) yazılmaz.
    var kendi = mesaiSatirlar().filter(function (k) { return k.personel.toLowerCase() === personel.toLowerCase(); });
    var son = kendi.length ? kendi.reduce(function (a, b) { return a.zaman > b.zaman ? a : b; }) : null;
    if (son && son.tip === tip && simdi - son.zaman < 60000) {
      return outJson({ status: 'ok', tekrar: true, zaman: mesaiSaat(son.zaman), sube: son.sube, tip: tip }, callback);
    }
    if (son && son.tip === tip) notlar.push(tip === 'giris' ? 'önceki girişin çıkışı yok' : 'önceki çıkışın girişi yok');
    sh.appendRow([simdi, mesaiTarih(simdi), mesaiSaat(simdi), personel, tip, enYakin.b.ad, Math.round(enYakin.m), dogruluk,
      enlem, boylam, yas, String(p.cihaz || '').substring(0, 120), notlar.join('; ')]);
  } finally { lock.releaseLock(); }
  gunlukYaz('mesai', personel, (tip === 'giris' ? 'Giriş' : 'Çıkış') + ': ' + enYakin.b.ad + ' (' + Math.round(enYakin.m) + ' m, GPS ±' + dogruluk + ' m)' + (notlar.length ? ' — ' + notlar.join('; ') : ''), false);
  return outJson({ status: 'ok', zaman: mesaiSaat(simdi), sube: enYakin.b.ad, tip: tip }, callback);
}
function mesaiMesafe(a1, o1, a2, o2) {
  var R = 6371000, r = Math.PI / 180;
  var da = (a2 - a1) * r, dO = (o2 - o1) * r;
  var x = Math.sin(da / 2) * Math.sin(da / 2) + Math.cos(a1 * r) * Math.cos(a2 * r) * Math.sin(dO / 2) * Math.sin(dO / 2);
  return 2 * R * Math.asin(Math.sqrt(x));
}

// Kişinin kendi son 31 günü (ve şu an içeride mi).
function mesaiBenim(p, callback) {
  var auth = mesaiYetkili(p);
  if (!auth.ok) return outJson({ status: 'error', message: auth.message }, callback);
  var ad = String(p.user || '').trim().toLowerCase();
  var sinir = Date.now() - 32 * 86400000;
  var kendi = mesaiSatirlar().filter(function (k) { return k.personel.toLowerCase() === ad && k.zaman.getTime() >= sinir; });
  var g = mesaiGunler(kendi);
  return outJson({ status: 'ok', gunler: g.gunler.slice(0, 31), iceride: g.iceride, yonetici: auth.permissions.indexOf('mesai_yonetim') !== -1 }, callback);
}

// Mağaza ekranındaki 6 haneli kod (sadece mesai yöneticisi açabilir).
function mesaiKod(p, callback) {
  var auth = requirePermission(p.user, p.pass, 'mesai_yonetim');
  if (!auth.ok) return outJson({ status: 'error', message: auth.message }, callback);
  var simdi = Date.now();
  var w = mesaiPencere(simdi);
  var kalan = MESAI_KOD_SN - Math.floor((simdi / 1000) % MESAI_KOD_SN);
  return outJson({ status: 'ok', kod: mesaiKodHesapla(w), kalanSn: kalan, sureSn: MESAI_KOD_SN }, callback);
}

// Aylık puantaj: herkesin gün gün giriş/çıkış ve toplam süresi + şu an içeride olanlar.
function mesaiRapor(p, callback) {
  var auth = requirePermission(p.user, p.pass, 'mesai_yonetim');
  if (!auth.ok) return outJson({ status: 'error', message: auth.message }, callback);
  var ay = /^\d{4}-\d{2}$/.test(String(p.ay || '')) ? String(p.ay) : Utilities.formatDate(new Date(), mesaiTz(), 'yyyy-MM');
  var kisiler = {};
  mesaiSatirlar().forEach(function (k) { (kisiler[k.personel] = kisiler[k.personel] || []).push(k); });
  var sonuc = [], iceride = [];
  Object.keys(kisiler).sort(function (a, b) { return a.localeCompare(b, 'tr'); }).forEach(function (ad) {
    var g = mesaiGunler(kisiler[ad]);
    if (g.iceride) iceride.push({ personel: ad, giris: g.iceride.giris, tarih: g.iceride.tarih, sube: g.iceride.sube });
    var gunler = g.gunler.filter(function (x) { return x.tarih.indexOf(ay) === 0; }).reverse();
    if (!gunler.length) return;
    sonuc.push({ personel: ad, gunler: gunler, toplamDakika: gunler.reduce(function (t, x) { return t + x.dakika; }, 0) });
  });
  return outJson({ status: 'ok', ay: ay, kisiler: sonuc, iceride: iceride }, callback);
}

// ============================================================
// EKİP — bölümler, personel bilgisi, vardiya, izin, duyuru, görev, pano
// Yetkiler: "mesai" = personel (giriş/çıkış, kendi vardiyası/izni, duyuru,
// görev). "mesai_yonetim" = ⭐ EKİP LİDERİ (bölümleri ve personeli tanımlar,
// vardiya planı, izin onayı, düzeltme, duyuru/görev, pano, puantaj).
// Yöneticilerde ikisi de otomatik var. Kullanıcı şifreleri/rolleri buradan
// DEĞİŞTİRİLEMEZ (o iş Yönetici Paneli'nde).
// Sekmeler: Bolumler, PersonelBilgi, Vardiya, Izinler, Duyurular, Gorevler.
// ============================================================
var EKIP_SEKME = {
  Bolumler: ['Bölüm'],
  PersonelBilgi: ['Personel', 'Bölümler', 'İşe Giriş', 'Doğum Tarihi', 'İzin Devri (gün)', 'Not'],
  Vardiya: ['Hafta', 'Personel', 'Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz', 'Güncelleyen', 'Zaman'],
  Izinler: ['ID', 'Personel', 'Tür', 'Başlangıç', 'Bitiş', 'Gün', 'Açıklama', 'Durum', 'Talep Zamanı', 'Karar Veren', 'Karar Zamanı', 'Karar Notu'],
  Duyurular: ['ID', 'Zaman', 'Yazan', 'Hedef', 'Başlık', 'Metin', 'Okuyanlar'],
  Gorevler: ['ID', 'Tarih', 'Bölüm', 'Görev', 'Atanan', 'Oluşturan', 'Durum', 'Tamamlayan', 'Tamamlama Zamanı']
};
var IZIN_TURLERI = { yillik: 'Yıllık İzin', rapor: 'Raporlu', mazeret: 'Mazeret İzni', ucretsiz: 'Ücretsiz İzin' };
var EKIP_GEC_TOLERANS_DK = 5;
var HAFTALIK_NORMAL_DK = 45 * 60;

function ekipSheet(ad) {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sh = ss.getSheetByName(ad);
  if (!sh) { sh = ss.insertSheet(ad); sh.appendRow(EKIP_SEKME[ad]); sh.setFrozenRows(1); }
  return sh;
}
function ekipOku(ad) {
  var sh = ekipSheet(ad), n = EKIP_SEKME[ad].length;
  if (sh.getLastRow() < 2) return [];
  return sh.getRange(2, 1, sh.getLastRow() - 1, n).getValues().map(function (r, i) { r.satir = i + 2; return r; });
}
function ekipYazSatir(ad, satir, degerler) { ekipSheet(ad).getRange(satir, 1, 1, degerler.length).setValues([degerler]); }
function ekipTarihMetni(v) {
  if (v instanceof Date) return Utilities.formatDate(v, mesaiTz(), 'yyyy-MM-dd');
  var s = String(v || '').trim();
  return /^\d{4}-\d{2}-\d{2}$/.test(s) ? s : '';
}
// Benzersiz kayıt kimliği (aynı milisaniyede iki kayıt çakışmasın).
function ekipId(on) { return on + Date.now().toString(36) + Utilities.getUuid().replace(/-/g, '').slice(0, 6); }
function ekipBugun() { return Utilities.formatDate(new Date(), mesaiTz(), 'yyyy-MM-dd'); }
function ekipGunEkle(t, n) { var p = t.split('-'); var d = new Date(Date.UTC(+p[0], +p[1] - 1, +p[2] + n)); return d.toISOString().slice(0, 10); }
function ekipHaftaGunu(t) { var p = t.split('-'); return (new Date(Date.UTC(+p[0], +p[1] - 1, +p[2])).getUTCDay() + 6) % 7; } // 0=Pzt
function ekipPazartesi(t) { return ekipGunEkle(t, -ekipHaftaGunu(t)); }
function ekipMetin(v, n) { return String(v == null ? '' : v).replace(/[\r\n\t]+/g, ' ').trim().substring(0, n || 200); }
function ekipListe(v) { return String(v || '').split(',').map(function (x) { return x.trim(); }).filter(Boolean); }

// Mesai kullanan aktif kullanıcılar (Kullanicilar sekmesinden; şifreler okunmaz).
function ekipKullanicilar() {
  var sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName('Kullanicilar');
  if (!sheet || sheet.getLastRow() < 2) return [];
  return sheet.getRange(2, 1, sheet.getLastRow() - 1, 5).getValues().map(function (r) {
    var rol = String(r[2] || '').trim().toLowerCase() === 'yonetici' ? 'yonetici' : 'kullanici';
    var yetki = ekipListe(r[3]);
    return { ad: String(r[0] || '').trim(), rol: rol, lider: rol === 'yonetici' || yetki.indexOf('mesai_yonetim') !== -1,
      mesai: rol === 'yonetici' || yetki.indexOf('mesai') !== -1 || yetki.indexOf('mesai_yonetim') !== -1,
      aktif: String(r[4] || 'evet').trim().toLowerCase() !== 'hayir' };
  }).filter(function (u) { return u.ad && u.aktif && u.mesai; });
}
function ekipBolumler() { return ekipOku('Bolumler').map(function (r) { return ekipMetin(r[0], 40); }).filter(Boolean); }
function ekipPersonelBilgi() {
  var m = {};
  ekipOku('PersonelBilgi').forEach(function (r) {
    var ad = String(r[0] || '').trim(); if (!ad) return;
    m[ad.toLowerCase()] = { satir: r.satir, ad: ad, bolumler: ekipListe(r[1]), iseGiris: ekipTarihMetni(r[2]), dogum: ekipTarihMetni(r[3]),
      izinDevri: Number(r[4]) || 0, not: String(r[5] || '') };
  });
  return m;
}
function ekipPersonel(adi, bilgi) {
  var b = (bilgi || ekipPersonelBilgi())[String(adi || '').toLowerCase()];
  return b || { ad: adi, bolumler: [], iseGiris: '', dogum: '', izinDevri: 0, not: '' };
}

// ---- Yıllık izin hakkı (4857 s. İş K. md. 53): 1-5 yıl (5 dahil) 14, 5-15 yıl 20,
// 15 yıl ve üstü 26 gün; 18 yaş ve altı / 50 yaş ve üstü en az 20 gün. ----
function ekipYilFarki(bas, son) {
  var a = bas.split('-').map(Number), b = son.split('-').map(Number);
  var y = b[0] - a[0];
  if (b[1] < a[1] || (b[1] === a[1] && b[2] < a[2])) y--;
  return y;
}
function ekipIzinHak(p, izinler) {
  var bugun = ekipBugun();
  var sonuc = { kidemYil: 0, kazanilan: 0, kullanilan: 0, bekleyen: 0, devir: p.izinDevri || 0, kalan: 0, yillikHak: 0, sonrakiHak: '' };
  izinler.forEach(function (z) {
    if (z.personel.toLowerCase() !== String(p.ad).toLowerCase() || z.tur !== 'yillik') return;
    if (z.durum === 'onaylandi') sonuc.kullanilan += z.gun; else if (z.durum === 'bekliyor') sonuc.bekleyen += z.gun;
  });
  if (p.iseGiris) {
    var yil = Math.max(0, ekipYilFarki(p.iseGiris, bugun));
    sonuc.kidemYil = yil;
    for (var y = 1; y <= yil; y++) {
      var gun = y <= 5 ? 14 : (y < 15 ? 20 : 26);
      if (p.dogum) {
        var yildonumu = (Number(p.iseGiris.slice(0, 4)) + y) + p.iseGiris.slice(4);
        var yas = ekipYilFarki(p.dogum, yildonumu);
        if (yas <= 18 || yas >= 50) gun = Math.max(gun, 20);
      }
      sonuc.kazanilan += gun;
      sonuc.yillikHak = gun;
    }
    sonuc.sonrakiHak = (Number(p.iseGiris.slice(0, 4)) + yil + 1) + p.iseGiris.slice(4);
  }
  sonuc.kalan = sonuc.kazanilan + sonuc.devir - sonuc.kullanilan;
  return sonuc;
}
// Yıllık izinde Pazar (hafta tatili) sayılmaz; diğer türlerde takvim günü.
function ekipIzinGun(tur, bas, bit) {
  var n = 0;
  for (var t = bas; t <= bit; t = ekipGunEkle(t, 1)) { if (tur === 'yillik' && ekipHaftaGunu(t) === 6) continue; n++; if (n > 400) break; }
  return n;
}
function ekipIzinler() {
  return ekipOku('Izinler').map(function (r) {
    return { satir: r.satir, id: String(r[0]), personel: String(r[1] || ''), tur: String(r[2] || ''), bas: ekipTarihMetni(r[3]), bit: ekipTarihMetni(r[4]),
      gun: Number(r[5]) || 0, aciklama: String(r[6] || ''), durum: String(r[7] || ''), talep: r[8] instanceof Date ? Utilities.formatDate(r[8], mesaiTz(), 'yyyy-MM-dd HH:mm') : String(r[8] || ''),
      karar: String(r[9] || ''), kararNot: String(r[11] || '') };
  }).filter(function (z) { return z.id && z.personel && z.bas && z.bit; });
}
function ekipIzinGunde(izinler, ad, t) {
  for (var i = 0; i < izinler.length; i++) {
    var z = izinler[i];
    if (z.durum === 'onaylandi' && z.personel.toLowerCase() === ad.toLowerCase() && z.bas <= t && t <= z.bit) return z;
  }
  return null;
}

// ---- Vardiya: hücre "09:00-18:00" (ya da "9-18"), "İzin", "Tatil" ya da boş ----
function ekipVardiyaCoz(h) {
  h = String(h || '').trim();
  var m = /^(\d{1,2})(?::(\d{2}))?\s*-\s*(\d{1,2})(?::(\d{2}))?$/.exec(h);
  if (!m) return null;
  var bas = Number(m[1]) * 60 + Number(m[2] || 0), bit = Number(m[3]) * 60 + Number(m[4] || 0);
  if (bas >= 24 * 60 || bit > 24 * 60) return null;
  if (bit <= bas) bit += 24 * 60; // gece vardiyası
  return { bas: bas, bit: bit, dakika: bit - bas };
}
function ekipVardiyaNormal(h) {
  h = String(h || '').trim();
  if (!h) return '';
  if (/^(izin|tatil|off|yok)$/i.test(h)) return h.charAt(0).toLocaleUpperCase('tr') + h.slice(1).toLocaleLowerCase('tr');
  var v = ekipVardiyaCoz(h);
  if (!v) return null;
  var f = function (dk) { dk = dk % (24 * 60); return ('0' + Math.floor(dk / 60)).slice(-2) + ':' + ('0' + dk % 60).slice(-2); };
  return f(v.bas) + '-' + f(v.bit);
}
function ekipVardiyalar() {
  var m = {}; // "hafta|personel" -> {satir, gunler[7]}
  ekipOku('Vardiya').forEach(function (r) {
    var h = ekipTarihMetni(r[0]), ad = String(r[1] || '').trim();
    if (!h || !ad) return;
    m[h + '|' + ad.toLowerCase()] = { satir: r.satir, gunler: [r[2], r[3], r[4], r[5], r[6], r[7], r[8]].map(function (x) { return String(x || ''); }) };
  });
  return m;
}
function ekipVardiyaGunde(vardiyalar, ad, t) {
  var v = vardiyalar[ekipPazartesi(t) + '|' + ad.toLowerCase()];
  return v ? v.gunler[ekipHaftaGunu(t)] : '';
}
function ekipDk(saat) { var p = String(saat || '').split(':'); return p.length === 2 ? Number(p[0]) * 60 + Number(p[1]) : null; }

// ---- Tek bir günün özeti: gerçek çalışma + plan + geç/erken + izin ----
function ekipGunOzeti(ad, t, gun, vardiyalar, izinler) {
  var plan = ekipVardiyaGunde(vardiyalar, ad, t);
  var pv = ekipVardiyaCoz(plan);
  var izin = ekipIzinGunde(izinler, ad, t);
  var o = { tarih: t, plan: plan, dakika: gun ? gun.dakika : 0, araliklar: gun ? gun.araliklar : [], eksik: gun ? gun.eksik : false,
    izin: izin ? (IZIN_TURLERI[izin.tur] || izin.tur) : '', gecDk: 0, erkenDk: 0, planDk: pv ? pv.dakika : 0 };
  if (pv && gun && gun.araliklar.length) {
    var ilk = ekipDk(gun.araliklar[0].giris), son = ekipDk(gun.araliklar[gun.araliklar.length - 1].cikis);
    if (ilk !== null && ilk - pv.bas > EKIP_GEC_TOLERANS_DK) o.gecDk = ilk - pv.bas;
    if (son !== null) { if (son < ilk) son += 24 * 60; if (pv.bit - son > EKIP_GEC_TOLERANS_DK) o.erkenDk = pv.bit - son; }
  }
  return o;
}

function ekipIstek(p, callback) {
  var a = String(p.action || '');
  try {
    var auth = mesaiYetkili(p);
    if (!auth.ok) return outJson({ status: 'error', message: auth.message }, callback);
    var ben = String(p.user || '').trim();
    var lider = auth.permissions.indexOf('mesai_yonetim') !== -1;
    var liderGerek = function () { if (!lider) throw new Error('Bu işlem için Ekip Lideri yetkisi gerekir'); };
    // ---- herkes ----
    if (a === 'ekip_benim') return outJson(ekipBenim(ben, lider), callback);
    if (a === 'ekip_izin_talep') return outJson(ekipYaz(function () { return ekipIzinTalep(ben, lider, p); }), callback);
    if (a === 'ekip_duyuru_okudum') return outJson(ekipYaz(function () { return ekipDuyuruOkudum(ben, p.id); }), callback);
    if (a === 'ekip_gorev_tamam') return outJson(ekipYaz(function () { return ekipGorevTamam(ben, lider, p.id); }), callback);
    // ---- Ekip Lideri ----
    liderGerek();
    if (a === 'ekip_lider') return outJson(ekipLider(p), callback);
    if (a === 'ekip_bolum_kaydet') return outJson(ekipYaz(function () { return ekipBolumKaydet(ben, p.liste); }), callback);
    if (a === 'ekip_personel_kaydet') return outJson(ekipYaz(function () { return ekipPersonelKaydet(ben, p); }), callback);
    if (a === 'ekip_vardiya_kaydet') return outJson(ekipYaz(function () { return ekipVardiyaKaydet(ben, p); }), callback);
    if (a === 'ekip_izin_karar') return outJson(ekipYaz(function () { return ekipIzinKarar(ben, p); }), callback);
    if (a === 'ekip_duzeltme') return outJson(ekipYaz(function () { return ekipDuzeltme(ben, p); }), callback);
    if (a === 'ekip_duyuru_ekle') return outJson(ekipYaz(function () { return ekipDuyuruEkle(ben, p); }), callback);
    if (a === 'ekip_gorev_ekle') return outJson(ekipYaz(function () { return ekipGorevEkle(ben, p); }), callback);
    if (a === 'ekip_puantaj') return outJson(ekipPuantaj(p), callback);
    return outJson({ status: 'error', message: 'Bilinmeyen işlem' }, callback);
  } catch (err) {
    var m = String(err && err.message || err);
    if (!/yetki|geçersiz|gir|seç|bulunamadı|zaten|olmalı|boş/i.test(m)) gunlukYaz('mesai', String(p.user || ''), a + ' hatası: ' + m, true);
    return outJson({ status: 'error', message: m }, callback);
  }
}
function ekipYaz(fn) {
  var lock = LockService.getScriptLock();
  try { lock.waitLock(20000); } catch (e) { throw new Error('Sunucu meşgul — birazdan tekrar dene'); }
  try { var r = fn(); r.status = r.status || 'ok'; return r; } finally { lock.releaseLock(); }
}

// ---- Personelin kendi ekranı: durum, son günler, vardiya, izin, duyuru, görev ----
function ekipBenim(ben, lider) {
  var bilgi = ekipPersonelBilgi(), p = ekipPersonel(ben, bilgi), bugun = ekipBugun();
  var sinir = Date.now() - 32 * 86400000;
  var g = mesaiGunler(mesaiSatirlar().filter(function (k) { return k.personel.toLowerCase() === ben.toLowerCase() && k.zaman.getTime() >= sinir; }));
  var vardiyalar = ekipVardiyalar(), izinler = ekipIzinler();
  var buHafta = ekipPazartesi(bugun);
  var vardiya = [0, 7].map(function (ek) {
    var h = ekipGunEkle(buHafta, ek), v = vardiyalar[h + '|' + ben.toLowerCase()];
    return { hafta: h, gunler: v ? v.gunler : ['', '', '', '', '', '', ''] };
  });
  var gunMap = {}; g.gunler.forEach(function (x) { gunMap[x.tarih] = x; });
  var gunler = g.gunler.slice(0, 31).map(function (x) { return ekipGunOzeti(ben, x.tarih, x, vardiyalar, izinler); });
  var benimIzin = izinler.filter(function (z) { return z.personel.toLowerCase() === ben.toLowerCase(); }).reverse().slice(0, 30);
  var duyurular = ekipDuyurular().filter(function (d) { return lider || d.hedef === 'Herkes' || d.hedefler.some(function (h) { return p.bolumler.indexOf(h) !== -1; }); })
    .slice(0, 30).map(function (d) { return { id: d.id, zaman: d.zaman, yazan: d.yazan, hedef: d.hedef, baslik: d.baslik, metin: d.metin, okudum: d.okuyanlar.indexOf(ben) !== -1 }; });
  var gorevler = ekipGorevler().filter(function (t) {
    if (t.tarih > bugun || t.tarih < ekipGunEkle(bugun, -7)) return false;
    if (t.durum === 'tamam' && t.tarih < bugun) return false;
    return t.atanan ? t.atanan.toLowerCase() === ben.toLowerCase() : (lider || p.bolumler.indexOf(t.bolum) !== -1);
  });
  var kutlama = '';
  if (p.dogum && p.dogum.slice(5) === bugun.slice(5)) kutlama = '🎂 Doğum günün kutlu olsun!';
  else if (p.iseGiris && p.iseGiris.slice(5) === bugun.slice(5) && p.iseGiris < bugun) kutlama = '🎉 Bizimle ' + ekipYilFarki(p.iseGiris, bugun) + '. yılın — iyi ki varsın!';
  return { status: 'ok', ben: ben, lider: lider, bolumler: p.bolumler, iceride: g.iceride, gunler: gunler, vardiya: vardiya,
    bugunPlan: ekipVardiyaGunde(vardiyalar, ben, bugun), izinHak: ekipIzinHak(p, izinler), izinler: benimIzin, duyurular: duyurular, gorevler: gorevler,
    kutlama: kutlama, izinTurleri: IZIN_TURLERI, bugun: bugun };
}

function ekipIzinTalep(ben, lider, p) {
  var kim = lider && p.personel ? ekipMetin(p.personel, 60) : ben;
  var tur = IZIN_TURLERI[p.tur] ? p.tur : '';
  if (!tur) throw new Error('İzin türünü seç');
  var bas = ekipTarihMetni(p.bas), bit = ekipTarihMetni(p.bit || p.bas);
  if (!bas || !bit || bit < bas) throw new Error('Tarihleri kontrol et (bitiş, başlangıçtan önce olamaz)');
  var gun = ekipIzinGun(tur, bas, bit);
  if (!gun) throw new Error('Seçilen aralıkta izin günü yok');
  var cakisan = ekipIzinler().filter(function (z) { return z.personel.toLowerCase() === kim.toLowerCase() && z.durum !== 'reddedildi' && z.durum !== 'iptal' && !(z.bit < bas || z.bas > bit); });
  if (cakisan.length) throw new Error('Bu tarihlerde zaten bir izin kaydı var (' + cakisan[0].bas + ' – ' + cakisan[0].bit + ')');
  var otomatik = lider && kim.toLowerCase() !== ben.toLowerCase(); // lider başkası için girerse onaylı
  var simdi = new Date(), id = ekipId('IZ');
  ekipSheet('Izinler').appendRow([id, kim, tur, bas, bit, gun, ekipMetin(p.aciklama, 300), otomatik ? 'onaylandi' : 'bekliyor', simdi,
    otomatik ? ben : '', otomatik ? simdi : '', otomatik ? 'Ekip Lideri girdi' : '']);
  gunlukYaz('mesai', ben, 'İzin ' + (otomatik ? 'girildi' : 'talebi') + ': ' + kim + ' · ' + IZIN_TURLERI[tur] + ' ' + bas + ' – ' + bit + ' (' + gun + ' gün)', false);
  return { id: id, gun: gun, durum: otomatik ? 'onaylandi' : 'bekliyor' };
}
function ekipIzinKarar(ben, p) {
  var karar = p.karar === 'onay' ? 'onaylandi' : (p.karar === 'red' ? 'reddedildi' : (p.karar === 'iptal' ? 'iptal' : ''));
  if (!karar) throw new Error('Karar geçersiz');
  var z = ekipIzinler().filter(function (x) { return x.id === String(p.id); })[0];
  if (!z) throw new Error('İzin kaydı bulunamadı');
  if (karar !== 'iptal' && z.durum !== 'bekliyor') throw new Error('Bu talep zaten karara bağlanmış');
  var sh = ekipSheet('Izinler');
  sh.getRange(z.satir, 8, 1, 5).setValues([[karar, sh.getRange(z.satir, 9).getValue(), ben, new Date(), ekipMetin(p.not, 200)]]);
  gunlukYaz('mesai', ben, 'İzin ' + karar + ': ' + z.personel + ' · ' + (IZIN_TURLERI[z.tur] || z.tur) + ' ' + z.bas + ' – ' + z.bit, false);
  return { durum: karar };
}

function ekipBolumKaydet(ben, liste) {
  var l;
  try { l = JSON.parse(liste || '[]'); } catch (e) { throw new Error('Bölüm listesi okunamadı'); }
  var temiz = [];
  (l || []).forEach(function (x) { x = ekipMetin(x, 40).replace(/,/g, ' '); if (x && temiz.indexOf(x) === -1) temiz.push(x); });
  var sh = ekipSheet('Bolumler');
  if (sh.getLastRow() >= 2) sh.getRange(2, 1, sh.getLastRow() - 1, 1).clearContent();
  if (temiz.length) sh.getRange(2, 1, temiz.length, 1).setValues(temiz.map(function (x) { return [x]; }));
  gunlukYaz('mesai', ben, 'Bölümler: ' + (temiz.join(', ') || '(boş)'), false);
  return { bolumler: temiz };
}
function ekipPersonelKaydet(ben, p) {
  var ad = ekipMetin(p.personel, 60);
  if (!ekipKullanicilar().some(function (u) { return u.ad.toLowerCase() === ad.toLowerCase(); })) throw new Error('Personel bulunamadı (Mesai yetkisi olan aktif kullanıcı olmalı)');
  var tanimli = ekipBolumler();
  var bolumler = ekipListe(p.bolumler).filter(function (b) { return tanimli.indexOf(b) !== -1; });
  var iseGiris = p.iseGiris ? ekipTarihMetni(p.iseGiris) : '', dogum = p.dogum ? ekipTarihMetni(p.dogum) : '';
  if (p.iseGiris && !iseGiris) throw new Error('İşe giriş tarihi geçersiz');
  if (p.dogum && !dogum) throw new Error('Doğum tarihi geçersiz');
  var satir = [ad, bolumler.join(', '), iseGiris, dogum, Number(p.izinDevri) || 0, ekipMetin(p.not, 200)];
  var mevcut = ekipPersonelBilgi()[ad.toLowerCase()];
  if (mevcut) ekipYazSatir('PersonelBilgi', mevcut.satir, satir); else ekipSheet('PersonelBilgi').appendRow(satir);
  return { personel: ad };
}
function ekipVardiyaKaydet(ben, p) {
  var hafta = ekipTarihMetni(p.hafta);
  if (!hafta || ekipHaftaGunu(hafta) !== 0) throw new Error('Hafta Pazartesi tarihi olmalı');
  var ad = ekipMetin(p.personel, 60);
  if (!ekipKullanicilar().some(function (u) { return u.ad.toLowerCase() === ad.toLowerCase(); })) throw new Error('Personel bulunamadı');
  var g;
  try { g = JSON.parse(p.gunler || '[]'); } catch (e) { throw new Error('Vardiya okunamadı'); }
  if (!Array.isArray(g) || g.length !== 7) throw new Error('Vardiya 7 gün olmalı');
  var norm = g.map(function (h, i) {
    var n = ekipVardiyaNormal(h);
    if (n === null) throw new Error(['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'][i] + ' geçersiz: "' + ekipMetin(h, 20) + '" — örnek: 09:00-18:00, İzin, boş');
    return n;
  });
  var satir = [hafta, ad].concat(norm).concat([ben, new Date()]);
  var mevcut = ekipVardiyalar()[hafta + '|' + ad.toLowerCase()];
  if (mevcut) ekipYazSatir('Vardiya', mevcut.satir, satir); else ekipSheet('Vardiya').appendRow(satir);
  return { gunler: norm };
}
function ekipDuzeltme(ben, p) {
  var ad = ekipMetin(p.personel, 60), gerekce = ekipMetin(p.gerekce, 200);
  if (!gerekce) throw new Error('Gerekçe yazmak zorunlu');
  if (p.iptalSatir) {
    var k = mesaiSatirlar().filter(function (x) { return x.satir === Number(p.iptalSatir) && x.personel.toLowerCase() === ad.toLowerCase(); })[0];
    if (!k) throw new Error('Kayıt bulunamadı');
    mesaiSheet().getRange(k.satir, 13).setValue('İPTAL (' + ben + ', ' + Utilities.formatDate(new Date(), mesaiTz(), 'yyyy-MM-dd HH:mm') + '): ' + gerekce + (k.not ? ' | önceki not: ' + k.not : ''));
    gunlukYaz('mesai', ben, 'Düzeltme — kayıt iptal: ' + ad + ' ' + mesaiTarih(k.zaman) + ' ' + mesaiSaat(k.zaman) + ' (' + gerekce + ')', false);
    return { iptal: true };
  }
  if (!ekipKullanicilar().some(function (u) { return u.ad.toLowerCase() === ad.toLowerCase(); })) throw new Error('Personel bulunamadı');
  var tip = p.tip === 'cikis' ? 'cikis' : (p.tip === 'giris' ? 'giris' : '');
  var t = ekipTarihMetni(p.tarih), dk = ekipDk(p.saat);
  if (!tip || !t || dk === null || dk >= 24 * 60) throw new Error('Tür, tarih ve saati kontrol et');
  var p2 = t.split('-').map(Number);
  // Türkiye saati (UTC+3) ile kayıt zamanı
  var zaman = new Date(Date.UTC(p2[0], p2[1] - 1, p2[2], Math.floor(dk / 60) - 3, dk % 60));
  if (zaman.getTime() > Date.now() + 60000) throw new Error('İleri bir saate kayıt eklenemez');
  mesaiSheet().appendRow([zaman, t, mesaiSaat(zaman), ad, tip, '', '', '', '', '', '', 'Ekip Lideri: ' + ben, 'DÜZELTME (' + ben + '): ' + gerekce]);
  gunlukYaz('mesai', ben, 'Düzeltme — ' + (tip === 'giris' ? 'giriş' : 'çıkış') + ' eklendi: ' + ad + ' ' + t + ' ' + mesaiSaat(zaman) + ' (' + gerekce + ')', false);
  return { eklendi: true };
}

function ekipDuyurular() {
  return ekipOku('Duyurular').map(function (r) {
    var hedef = String(r[3] || 'Herkes');
    return { satir: r.satir, id: String(r[0]), zaman: r[1] instanceof Date ? Utilities.formatDate(r[1], mesaiTz(), 'yyyy-MM-dd HH:mm') : String(r[1] || ''),
      yazan: String(r[2] || ''), hedef: hedef, hedefler: hedef === 'Herkes' ? [] : ekipListe(hedef), baslik: String(r[4] || ''), metin: String(r[5] || ''), okuyanlar: ekipListe(r[6]) };
  }).filter(function (d) { return d.id; }).reverse();
}
function ekipDuyuruEkle(ben, p) {
  var baslik = ekipMetin(p.baslik, 80), metin = String(p.metin || '').trim().substring(0, 1000);
  if (!baslik) throw new Error('Başlık boş olamaz');
  var hedefler = ekipListe(p.hedef).filter(function (b) { return ekipBolumler().indexOf(b) !== -1; });
  var id = ekipId('DY');
  ekipSheet('Duyurular').appendRow([id, new Date(), ben, hedefler.length ? hedefler.join(', ') : 'Herkes', baslik, metin, '']);
  return { id: id };
}
function ekipDuyuruOkudum(ben, id) {
  var d = ekipDuyurular().filter(function (x) { return x.id === String(id); })[0];
  if (!d) throw new Error('Duyuru bulunamadı');
  if (d.okuyanlar.indexOf(ben) === -1) { d.okuyanlar.push(ben); ekipSheet('Duyurular').getRange(d.satir, 7).setValue(d.okuyanlar.join(', ')); }
  return {};
}
function ekipGorevler() {
  return ekipOku('Gorevler').map(function (r) {
    return { satir: r.satir, id: String(r[0]), tarih: ekipTarihMetni(r[1]), bolum: String(r[2] || ''), gorev: String(r[3] || ''), atanan: String(r[4] || ''),
      olusturan: String(r[5] || ''), durum: String(r[6] || 'acik'), tamamlayan: String(r[7] || ''),
      tamamZaman: r[8] instanceof Date ? Utilities.formatDate(r[8], mesaiTz(), 'HH:mm') : String(r[8] || '') };
  }).filter(function (t) { return t.id && t.tarih; });
}
function ekipGorevEkle(ben, p) {
  var gorev = ekipMetin(p.gorev, 200), t = ekipTarihMetni(p.tarih) || ekipBugun();
  if (!gorev) throw new Error('Görev boş olamaz');
  var bolum = ekipMetin(p.bolum, 40), atanan = ekipMetin(p.atanan, 60);
  if (!bolum && !atanan) throw new Error('Bölüm ya da kişi seç');
  var id = ekipId('GV');
  ekipSheet('Gorevler').appendRow([id, t, bolum, gorev, atanan, ben, 'acik', '', '']);
  return { id: id };
}
function ekipGorevTamam(ben, lider, id) {
  var t = ekipGorevler().filter(function (x) { return x.id === String(id); })[0];
  if (!t) throw new Error('Görev bulunamadı');
  if (t.durum === 'tamam') return { zaten: true };
  if (!lider && t.atanan && t.atanan.toLowerCase() !== ben.toLowerCase()) throw new Error('Bu görev başkasına atanmış');
  ekipSheet('Gorevler').getRange(t.satir, 7, 1, 3).setValues([['tamam', ben, new Date()]]);
  return {};
}

// ---- Ekip Lideri ekranı: pano, personel, bölümler, bekleyen izinler, vardiya haftası ----
function ekipLider(p) {
  var bugun = ekipBugun(), simdiDk = ekipDk(Utilities.formatDate(new Date(), mesaiTz(), 'HH:mm'));
  var kullanicilar = ekipKullanicilar(), bilgi = ekipPersonelBilgi(), izinler = ekipIzinler(), vardiyalar = ekipVardiyalar();
  var hafta = ekipTarihMetni(p.hafta); if (!hafta) hafta = ekipPazartesi(bugun); hafta = ekipPazartesi(hafta);
  var kisiler = {}; mesaiSatirlar().forEach(function (k) { (kisiler[k.personel.toLowerCase()] = kisiler[k.personel.toLowerCase()] || []).push(k); });
  var personel = kullanicilar.map(function (u) {
    var b = ekipPersonel(u.ad, bilgi);
    var kayit = kisiler[u.ad.toLowerCase()] || [];
    var g = mesaiGunler(kayit.filter(function (k) { return k.zaman.getTime() >= Date.now() - 3 * 86400000; }));
    var bugunGun = g.gunler.filter(function (x) { return x.tarih === bugun; })[0];
    var plan = ekipVardiyaGunde(vardiyalar, u.ad, bugun), pv = ekipVardiyaCoz(plan), izin = ekipIzinGunde(izinler, u.ad, bugun);
    var durum, detay = '';
    if (g.iceride) { durum = 'iceride'; detay = g.iceride.giris + '\'den beri'; }
    else if (izin) { durum = 'izinde'; detay = IZIN_TURLERI[izin.tur] || izin.tur; }
    else if (bugunGun && bugunGun.araliklar.length) { durum = 'cikti'; detay = sureMetniSunucu(bugunGun.dakika) + ' çalıştı'; }
    else if (pv && simdiDk > pv.bas + 15) { durum = 'gelmedi'; detay = 'Vardiya ' + plan; }
    else if (pv) { durum = 'bekleniyor'; detay = 'Vardiya ' + plan; }
    else { durum = 'plansiz'; detay = /izin|tatil/i.test(plan) ? plan : 'Bugün vardiya yok'; }
    var gecDk = 0;
    if (pv && bugunGun && bugunGun.araliklar.length) { var ilk = ekipDk(bugunGun.araliklar[0].giris); if (ilk !== null && ilk - pv.bas > EKIP_GEC_TOLERANS_DK) gecDk = ilk - pv.bas; }
    var v = vardiyalar[hafta + '|' + u.ad.toLowerCase()];
    return { ad: u.ad, lider: u.lider, bolumler: b.bolumler, iseGiris: b.iseGiris, dogum: b.dogum, izinDevri: b.izinDevri, not: b.not,
      durum: durum, detay: detay, gecDk: gecDk, izinHak: ekipIzinHak(b, izinler), vardiya: v ? v.gunler : ['', '', '', '', '', '', ''] };
  });
  // Yaklaşan doğum günleri / iş yıldönümleri (7 gün)
  var kutlamalar = [];
  for (var i = 0; i <= 7; i++) {
    var t = ekipGunEkle(bugun, i);
    personel.forEach(function (x) {
      if (x.dogum && x.dogum.slice(5) === t.slice(5)) kutlamalar.push({ tarih: t, ad: x.ad, tur: '🎂 Doğum günü', gun: i });
      if (x.iseGiris && x.iseGiris.slice(5) === t.slice(5) && x.iseGiris < t) kutlamalar.push({ tarih: t, ad: x.ad, tur: '🎉 ' + ekipYilFarki(x.iseGiris, t) + '. iş yılı', gun: i });
    });
  }
  var gorevler = ekipGorevler().filter(function (t) { return t.tarih >= ekipGunEkle(bugun, -7); }).reverse();
  var duyurular = ekipDuyurular().slice(0, 20).map(function (d) { return { id: d.id, zaman: d.zaman, yazan: d.yazan, hedef: d.hedef, baslik: d.baslik, metin: d.metin, okuyanlar: d.okuyanlar }; });
  var bekleyen = izinler.filter(function (z) { return z.durum === 'bekliyor'; });
  var sonIzinler = izinler.filter(function (z) { return z.durum !== 'bekliyor'; }).reverse().slice(0, 40);
  return { status: 'ok', bugun: bugun, hafta: hafta, bolumler: ekipBolumler(), personel: personel, kutlamalar: kutlamalar,
    bekleyenIzin: bekleyen, sonIzinler: sonIzinler, gorevler: gorevler, duyurular: duyurular, izinTurleri: IZIN_TURLERI };
}
function sureMetniSunucu(dk) { dk = Math.round(dk || 0); return Math.floor(dk / 60) + ' sa ' + ('0' + dk % 60).slice(-2) + ' dk'; }

// ---- Aylık puantaj: gün gün plan/gerçek, geç/erken, izin; haftalık fazla mesai ----
function ekipPuantaj(p) {
  var ay = /^\d{4}-\d{2}$/.test(String(p.ay || '')) ? String(p.ay) : ekipBugun().slice(0, 7);
  var kullanicilar = ekipKullanicilar(), bilgi = ekipPersonelBilgi(), izinler = ekipIzinler(), vardiyalar = ekipVardiyalar();
  var kisiler = {}; mesaiSatirlar().forEach(function (k) { (kisiler[k.personel.toLowerCase()] = kisiler[k.personel.toLowerCase()] || []).push(k); });
  var ayBas = ay + '-01', aySon = ekipGunEkle(ekipGunEkle(ayBas, 32).slice(0, 8) + '01', -1);
  var bugun = ekipBugun();
  var sonuc = kullanicilar.map(function (u) {
    var g = mesaiGunler(kisiler[u.ad.toLowerCase()] || []);
    var gm = {}; g.gunler.forEach(function (x) { gm[x.tarih] = x; });
    var gunler = [], toplam = 0, gecToplam = 0, erkenToplam = 0, izinGun = 0, eksik = 0;
    for (var t = ayBas; t <= aySon && t <= bugun; t = ekipGunEkle(t, 1)) {
      var o = ekipGunOzeti(u.ad, t, gm[t], vardiyalar, izinler);
      if (!o.dakika && !o.plan && !o.izin && !o.araliklar.length) continue;
      gunler.push(o); toplam += o.dakika; gecToplam += o.gecDk; erkenToplam += o.erkenDk; if (o.izin) izinGun++; if (o.eksik) eksik++;
    }
    // Haftalık fazla mesai: Pzt–Paz toplamı 45 saati aşan kısım; haftayı Perşembesi bu ayda olan ay sayar.
    var haftalar = [], fazla = 0;
    for (var h = ekipPazartesi(ayBas); h <= aySon; h = ekipGunEkle(h, 7)) {
      var per = ekipGunEkle(h, 3); if (per.slice(0, 7) !== ay) continue;
      var dk = 0; for (var d = 0; d < 7; d++) { var x = gm[ekipGunEkle(h, d)]; if (x) dk += x.dakika; }
      var f = Math.max(0, dk - HAFTALIK_NORMAL_DK); fazla += f;
      haftalar.push({ hafta: h, dakika: dk, fazlaDk: f });
    }
    var b = ekipPersonel(u.ad, bilgi);
    return { personel: u.ad, bolumler: b.bolumler, gunler: gunler, toplamDakika: toplam, gecDk: gecToplam, erkenDk: erkenToplam, izinGun: izinGun,
      eksikGun: eksik, haftalar: haftalar, fazlaDk: fazla, calisilanGun: gunler.filter(function (x) { return x.dakika > 0; }).length };
  }).filter(function (x) { return x.gunler.length; });
  return { status: 'ok', ay: ay, kisiler: sonuc };
}
