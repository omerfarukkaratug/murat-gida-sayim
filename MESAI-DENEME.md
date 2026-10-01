# Personel Mesai Takibi — DENEME

Uygulamanın menüsünde **🕐 Mesai** (ve üstteki hızlı geçişte). Sadece yetkisi
olan görür. Kodu ayrı dosyada (`mesai.html`) durur ve uygulamanın içinde açılır;
sayıma, mal giriş/çıkışa ve ERP'ye dokunmaz. Kayıtlar Google Sheets'te **Mesai**
sekmesine yazılır.

## Yetkiler
- **🕐 Mesai (giriş/çıkış):** personel giriş/çıkış yapar, kendi günlerini görür.
- **🕐 Mesai Yönetimi:** mağaza kod ekranı + aylık puantaj (+ kendi giriş/çıkışı).
- Yöneticilerde ikisi de otomatik var. Yetkisi olmayan menüde düğmeyi görmez,
  sunucu da kaydı kabul etmez.

## Nasıl çalışır
1. Personel uygulamada **🕐 Mesai**'ye dokunur (ayrıca şifre sorulmaz).
2. **🟢 GİRİŞ YAP**'a basar. Konum **sadece bu anda bir kez** alınır.
3. Mağazadaki ekranda (kasa bilgisayarı / tablet) görünen **6 haneli kodu** girer.
   Kod 30 saniyede bir değişir. Biri kodu ekrandan okuyup telefonla başka birine
   gönderse bile kod en fazla ~1 dakika geçerli kalır.
4. Sunucu kontrol eder: kod doğru mu, konum şube yarıçapı içinde mi, GPS yeterince
   net mi. Hepsi tamamsa **sunucunun saatiyle** kaydeder (telefon saati önemsiz).
5. Çıkışta aynısı (**🔴 ÇIKIŞ YAP**).

## Sahte konuma karşı
- Web uygulaması telefonun "sahte konum" uygulaması kullanıp kullanmadığını
  **doğrudan göremez**. O yüzden asıl kontrol **mağaza ekranındaki kod**: kod sadece
  mağazada görülür.
- Ek olarak: GPS doğruluğu 0 gelirse ya da telefonun saati 5 dakikadan fazla
  farklıysa kayıt **"Not"** sütununda şüpheli olarak işaretlenir.
- Reddedilen her deneme (yanlış kod, şube dışı, zayıf GPS) Sistem Günlüğü'ne
  "mesai — REDDEDİLDİ" olarak yazılır.

## Kurulum (yönetici)
1. Yeni `Code.gs` Apps Script'e yapıştırılıp yeni sürüm dağıtılır (build111).
2. Ayarlar → Şube Konumları'nda mağaza tanımlı olmalı (sayım uygulamasında zaten var).
3. Yönetici panelinden personele **🕐 Mesai**, mağaza müdürüne **🕐 Mesai Yönetimi** yetkisi verilir.
4. Kasa bilgisayarında/tabletinde uygulama adresinin sonundaki `index.html` yerine
   `mesai.html` yazılarak açılır, müdür hesabıyla girilip **📺 Mağaza Kod Ekranı**'na
   basılır. Ekran açık kaldığı sürece kod kendiliğinden yenilenir.

## Yönetici ekranı
- **📊 Aylık Puantaj:** herkesin gün gün giriş→çıkış saatleri, günlük ve aylık toplam,
  eksik giriş/çıkış uyarısı, şu an içeride olanlar. **⬇ Excel** ile CSV indirilir.
- Gece yarısını geçen vardiya, girişin olduğu güne yazılır.

## Resmî kullanım (öneri — muhasebeci/avukat onayıyla)
- Günlük kayıt uygulamada tutulur. Ay sonunda puantaj yazdırılıp personele ve
  müdüre **ıslak imzayla** imzalatılır (ayda bir sayfa).
- Konum kişisel veri sayılır (KVKK). Personele kısa bir aydınlatma metni
  imzalatılmalı. Konum sadece giriş/çıkış anında alınır, sürekli takip yoktur.
  Kamera bu sayfada hiç kullanılmaz.

## Sonraki adımlar (Kasım)
- Haftalık vardiya planı ve geç kalma / erken çıkma / fazla mesai hesabı
- Yıllık izin (kıdeme göre hak, talep → müdür onayı → izin formu)
- Müdürün eksik giriş/çıkışı gerekçeyle düzeltmesi (düzeltme kaydı tutularak)
