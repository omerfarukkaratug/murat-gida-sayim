# Personel Mesai Takibi — DENEME

Sayım uygulamasından **tamamen ayrı** bir sayfa: `mesai.html`. Sayıma, mal
giriş/çıkışa ve ERP'ye dokunmaz. Kayıtlar Google Sheets'te **Mesai** sekmesine yazılır.

## Nasıl çalışır
1. Personel telefonda `.../mesai.html` sayfasını açar. Sayım uygulamasında giriş
   yaptıysa tekrar şifre sormaz.
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
1. Yeni `Code.gs` Apps Script'e yapıştırılıp yeni sürüm dağıtılır (build110).
2. Ayarlar → Şube Konumları'nda mağaza tanımlı olmalı (sayım uygulamasında zaten var).
3. Mağaza müdürüne **🕐 Mesai Yönetimi** yetkisi verilir (yöneticilerde otomatik var).
4. Kasa bilgisayarında/tabletinde `mesai.html` açılır, müdür hesabıyla girilip
   **📺 Mağaza Kod Ekranı**'na basılır. Ekran açık kaldığı sürece kod kendiliğinden yenilenir.

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
- Sayım uygulamasının menüsüne "🕐 Mesai" düğmesi
