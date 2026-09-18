# Tüm Telefonların Sayımını Tek Google E-Tablo'da Toplama

Bu kurulum **bir kereliktir** ve ~5 dakika sürer. Sonrasında her telefon
kendi sayımını internet bulduğunda otomatik olarak bu tabloya ekler —
uygulama zaten offline çalışıp internet gelince otomatik gönderiyor,
burada sadece "nereye göndersin" adresini kuruyoruz.

## 1) Google E-Tablo oluştur
1. Google Drive'da (drive.google.com) yeni bir **Google E-Tablolar** dosyası aç
2. Adını "Sayım Sonuçları" gibi bir şey yap
3. İlk sayfanın adını (alt sekme) **Sayim** yap (büyük/küçük harf ve Türkçe
   karakter önemli — script'in aradığı isim bu)

## 2) Script'i ekle
1. Üst menüden **Uzantılar (Extensions) → Apps Script**
2. Açılan editördeki hazır kodu (myFunction vs.) tamamen sil
3. Bu klasördeki **toplama-scripti.gs** dosyasının içeriğini yapıştır
4. Üstteki 💾 (Kaydet) ikonuna bas, projeye bir isim ver (örn. "Sayım Toplayıcı")

## 3) Web uygulaması olarak yayınla
1. Sağ üstteki mavi **Dağıt (Deploy) → Yeni dağıtım (New deployment)** butonuna bas
2. Dişli ikonundan tür olarak **Web uygulaması (Web app)** seç
3. "Yürüten (Execute as)": **Ben (Me)**
4. "Erişimi olanlar (Who has access)": **Herkes (Anyone)** — bu önemli,
   "Anyone with Google account" değil, düz **Anyone** seçilecek
5. **Dağıt (Deploy)** butonuna bas
6. Google "Bu uygulama doğrulanmadı" gibi bir uyarı gösterebilir — bu
   normal, kendi script'in olduğu için: **Gelişmiş (Advanced) →
   [proje adına] git (unsafe)** deyip devam et, izin ver
7. Sana `https://script.google.com/macros/s/......../exec` şeklinde bir
   **Web app URL'si** verecek — bunu kopyala

## 4) Her telefona bu adresi tanıt
1. Market Sayım uygulamasını aç (ya da ilk kurulum ekranına dön)
2. **"Gönderim Adresi"** kutusuna kopyaladığın `/exec` ile biten adresi yapıştır
3. Bunu **her personelin telefonunda** tek tek yapman gerekiyor — hepsi
   aynı adrese göndersin ki hepsi aynı tabloda birleşsin

## Eski Stok ve Fark
CSV/TXT listeye 4. bir sütun ekleyebilirsin: **Eski Stok**. Eklersen:
- Ürün okutulduğunda ekranda ürün adının yanında sistemdeki eski stok da görünür
- Excel çıktısında ve Google Tablo'da "Eski Stok" ve otomatik hesaplanan
  "Fark" (Sayılan − Eski Stok) sütunları da olur — büyük sapmaları anında görürsün
Bu sütun tamamen opsiyoneldir, boş bırakabilir ya da hiç yazmayabilirsin.
- Her sayım oturumunun görünmez bir "Oturum ID"si vardır.
- Aynı oturumu (yani "Bitir/Yeni"ye basmadan önce) tekrar gönderirsen —
  örneğin bir ürünün adedini düzelttiysen — tabloda yeni satır **eklenmez**,
  var olan satır **güncellenir**. Yani telefon tarafında düzeltme yapıp
  tekrar gönderdiğinde, tablo da otomatik düzelir.
- "Bitir / Yeni"ye bastığında oturum kapanır, yeni oturum farklı bir kimlik
  alır — o noktadan sonraki taramalar tabloya yeni satır olarak eklenir.

## Tabloda elle düzeltme yapabilir miyim?
Evet, tamamen normal bir Google E-Tablo — istediğin hücreyi elle
değiştirebilirsin. Tek dikkat: aynı oturum telefonda hâlâ açıksa ve
tekrar "Gönder"e basılırsa, telefondaki rakam o satırın üzerine yazılır.
Bu yüzden: ya düzeltmeyi telefonda yapıp öyle gönder, ya da o oturum
"Bitir/Yeni" ile kapatıldıktan sonra tabloda rahatça elle düzelt.

## Test etmek için
Kurulumu bitirdikten sonra bir telefonda birkaç ürün say, internete
bağlıyken birkaç saniye bekle, Google E-Tablo'yu aç — satırların
otomatik düştüğünü göreceksin.

## 5) Giriş Sistemi (Kullanıcı Adı + Şifre)
PIN sistemi kaldırıldı — artık her personel kendi kullanıcı adı ve
şifresiyle giriş yapıyor, yönetici işlemleri PIN yerine **kişinin kendi
yetkisine** göre çalışıyor.

**İlk kurulum:** Uygulamayı ilk açtığında kullanıcı listesi boştur.
Kullanıcı adı **admin**, şifre **admin** ile giriş yap — bu, sana tüm
yetkileri (rapor, temizleme, kullanıcı yönetimi, ekran ayarı) veren bir
yönetici hesabıdır. **Giriş yapar yapmaz Yönetici Paneli → Kullanıcı
Yönetimi'nden admin şifresini değiştir.**

⚠️ Şifreler `Kullanicilar` sekmesinde düz metin olarak durur — bu,
kurumsal bir güvenlik sistemi değil, ekip içi basit bir yetkilendirmedir.
Tabloyu düzenleme yetkisi olan biri şifreleri görebilir.

## 6) Yapay zeka değerlendirmesini açma (opsiyonel)
"Sayımı Bitir ve Rapor Oluştur" işlemi, dikkat çeken stok farkları varsa
bunları kısaca Türkçe yorumlatmak için Anthropic API'ye istek atabilir.
Bunun çalışması için bir Anthropic API anahtarı gerekir (console.anthropic.com
üzerinden alınır):
1. Apps Script editöründe sol menüden **Proje Ayarları (Project Settings)**
2. **Script Özellikleri (Script Properties)** → **Özellik Ekle (Add script property)**
3. Özellik adı: `ANTHROPIC_API_KEY`, değer: kendi API anahtarın
4. Bu özellik boşsa rapor sorunsuz oluşur, sadece yapay zeka yorumu olmadan —
   yani bu adım tamamen opsiyoneldir

## "Yönetici Raporu" sekmesi hakkında not
Bu sekme personel bazlı hız/performans bilgisi içerdiği için rapor
oluşturulunca otomatik gizlenir (sekme çubuğunda görünmez). Ama bu **kesin
bir gizlilik değildir** — tabloyu düzenleme/görme yetkisi olan biri "Gizli
sayfaları göster" ile açabilir. Gerçekten sadece senin görmen gerekiyorsa,
ya bu sekmeyi ayrı, sadece sana paylaşılmış bir Google E-Tablo'ya taşımanı
ya da ana tabloyu sadece kendi hesabınla paylaşmanı öneririm.

## 7) Kullanıcı Yönetimi ve Yetkilendirme
Giriş yaptıktan sonra, yetkin varsa "⚙ Yönetici Paneli" bağlantısı
görünür (yetkisi olmayan personelin ekranında bu bağlantı hiç çıkmaz).
**👤 Kullanıcı Yönetimi** bölümünde her satır bir kişi:

```
Ad;Şifre;Rol;Yetkiler
```
- **Rol** `yonetici` ise o kişi otomatik olarak TÜM işlemleri yapabilir
  (rapor, temizleme, kullanıcı yönetimi, ekran ayarı)
- **Rol** boş/`kullanici` ise, sadece **Yetkiler** alanına yazdıkların
  çalışır — virgülle ayrılmış şu dörtten istediğin kadarını yaz:
  `rapor`, `temizle`, `kullanici_yonetimi`, `ayarlar`

Örnek — 2 yönetici + kısmi yetkili bir kullanıcı + hiç yetkisi olmayanlar
(bu formatlar artık Yönetici Paneli'ndeki kartlı ekrandan otomatik
oluşturuluyor, elle yazmana gerek yok — bilgi amaçlı):
```
admin;yeniSifre123;yonetici;;evet
Ayşe Yılmaz;4521;yonetici;;evet
Mehmet Demir;1111;kullanici;rapor;evet
Fatma Kaya;2222;kullanici;;hayir
```
Burada Mehmet raporu görebilir ama dosyayı temizleyemez veya kullanıcı
ekleyemez; Fatma pasif durumda olduğu için artık hiç giriş yapamaz
(hesabı silmeden geçici olarak devre dışı bırakmak için kullanılır).

Yetkiler artık altısı: `rapor`, `temizle`, `kullanici_yonetimi`,
`ayarlar`, `canli_durum` (kim ne sayıyor canlı görme), `duzelt` (yanlış
girilmiş sayım kayıtlarını düzeltme/silme).

**Şifremi unuttum / admin dışarıda kaldı:** Kullanıcı Yönetimi yetkisi
olan kimse kalmadıysa, Google E-Tablo'yu aç → **Kullanicilar** sekmesi →
ilgili kişinin **Şifre** hücresini elle değiştir (ya da o satırı tamamen
silip admin/admin yedek girişinin tekrar çalışmasını sağla — bunun için
sekmede "admin" adında bir satır kalmamalı).

**Kullanıcı Listesini Kaydet**'e bastığında panel önce mevcut listeyi
sunucudan çeker ve kutuyu onunla doldurur — üstüne ekleme/çıkarma
yaparak kaydet, TÜM liste o an kutuda ne yazıyorsa onunla değişir.

Bu liste ayrıca giriş ekranındaki "Kullanıcı Adı" kutusunda otomatik
tamamlama olarak da kullanılır (telefonlar bunu online olduklarında
otomatik çeker).

## 9) Canlı Durum (📡 canli_durum yetkisi)
Yönetici Paneli'nde, o an (ya da en son) kim ne sayıyor gösterir —
personel bazlı toplam okutma, farklı ürün sayısı, son okutulan ürün ve
"kaç dakika önce" bilgisi. Telefonlar bir "buradayım" sinyali göndermiyor;
bu yüzden "🟢 şu an sayıyor olabilir" etiketi, o kişinin son 10 dakika
içinde en az bir okutma yapmış olmasına dayanır — kesin bir çevrimiçi
göstergesi değil, iyi bir tahmindir.

## 10) Sayım Kayıtlarını Düzelt (✏️ duzelt yetkisi)
Google E-Tablo'yu hiç açmadan, telefon/personel/ürün adıyla arayıp
yanlış girilmiş bir sayım kaydının adedini düzeltebilir ya da tamamen
silebilirsin. Arama kutusu boşken en son 50 kayıt listelenir.

## 11) Son Stok Sayımını CSV Olarak İndirme (📥 rapor yetkisi)
"Sayımı Bitir ve Rapor Oluştur" çalıştırıldıktan sonra, aynı Yönetici
Paneli'nden "📥 Son Stok Sayımını İndir (CSV)" ile o anki "Son Stok
Sayimi" sekmesini doğrudan telefona/bilgisayara CSV olarak indirebilirsin
— ERP12'ye aktarmak için Google Sheets'e hiç girmene gerek kalmaz.

## 8) Ekran Açık Kalma ve Boşta Kalma Ayarları (pil tasarrufu)
Sayım sırasında telefon ekranı hiç kararmasın diye uygulama varsayılan
olarak ekranı sürekli açık tutar — uzun sayımlarda pili hızlı bitirebilir.
- **Her telefonda**: üst çubuktaki 🔆/🌙 butonuna dokunarak o telefonda
  anlık açıp kapatabilirsin. Bir kez elle değiştirdiğinde, o telefon
  yöneticinin göndereceği varsayılandan artık etkilenmez.
- **Yönetici Paneli → 🔆 Ekran Ayarı** (bu yetkiye sahip olanlarda
  görünür): hiç dokunulmamış (yeni açılan) telefonlar için ekranın açık
  kalıp kalmayacağını, VE kaç dakika hiç dokunulmazsa ekranın normal
  kararmaya bırakılacağını (0 = hiç bırakılmasın, örn. 10 = 10 dakika
  boşta kalınca telefonun kendi ekran kararma süresine bırakılır)
  buradan tek seferde ayarlarsın.
