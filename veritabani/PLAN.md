# Veri Tabanına Geçiş Planı

## Neden?
Google Sheets şu an çalışıyor ama bir tablo; kilit (aynı anda tek yazma), satır sınırı ve yavaşlık riski var.
Gerçek veri tabanı (PostgreSQL) aynı anda çok telefonun yazmasını, sorguyu ve yedeği çok daha sağlıklı yapar.

## Mimari
- **Ana veri tabanı: bulut** (Supabase / PostgreSQL, Frankfurt). Telefonlar buraya yazar — mağazadaki PC kapansa da sayım durmaz.
- **Kopya: kendi SQL Server'ımız.** Küçük bir servis bulut verisini düzenli olarak yerel SQL'e çeker (ERP12 yanında yedek + raporlama).
- **ERP → bulut:** Mevcut "Stok Otomatik Gönderim" programı Sheets yerine `katalog_yukle` fonksiyonunu çağırır.
- Güvenlik kuralları (sürüm, silinen kayıt, geç gelen, ERP'ye aktarılan mal kalemi kilidi, boş katalog koruması) **veri tabanının içinde** (001_sema.sql) — uygulama hata yapsa da veri bozulmaz.

## Aşamalar
1. **Şema + testler** — ✅ (`001_sema.sql`, `002_testler.sql`, yerel PostgreSQL'de tüm testler geçti).
2. **Bulut hesabı** — ✅ Supabase, Frankfurt, şema yüklendi.
3. **Gölge mod** (Code.gs build99): Telefonlar Sheets'e yazmaya DEVAM eder, uygulama değişmedi. Sunucu Sheets'e
   yazdığı her sayım/mal/düzeltme/silme/temizlemeyi gizli `DbKuyruk` sekmesine not eder ve veri tabanına gönderir
   (telefon isteklerinden sonra en fazla dakikada bir + 5 dakikalık zamanlayıcı). Veri tabanına ulaşılamazsa kuyrukta bekler.
   - Açma: Apps Script → Proje Ayarları → Komut dosyası özellikleri: `DB_URL`, `DB_ANAHTAR` (secret key) → `dbKur` çalıştır.
   - Eski kayıtlar: `dbMevcutSayimiAktar` (bir kez). Karşılaştırma: `dbKarsilastir` (sonuç Sistem Durumu günlüğünde).
   - Acil kapatma: `DB_KAPALI = 1`.
4. Sayım sonrası: telefonlar doğrudan veri tabanına geçer, Sheets sadece rapor/yedek kalır.
5. Kişisel kullanıcılar (şifreler bcrypt ile), fiyatların sunucu tarafında gizlenmesi, firma alan adı.

## Kural
Sayımdan önceki son 10 günde (20 Ekim sonrası) canlı sisteme yeni bağlantı eklenmez; sadece hata düzeltmesi.
