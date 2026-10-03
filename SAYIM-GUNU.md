# Büyük Sayım — Hazırlık ve Sayım Günü Kontrol Listesi

Hedef: en az 10 telefon, ~80.000 okutma (depo + reyon), **18 saat** (dakikada ortalama ~74 okutma), **sıfır veri kaybı**.

## 1) Sayımdan önce (bir kez)

- [ ] **Sunucu kodu güncel:** `/exec` adresinde en güncel `kod sürümü` görünüyor (şu an `build117`).
- [ ] **Uygulama güncel:** Her telefonda üstte aynı build numarası görünüyor.
- [ ] **Yük testi yapıldı** (`yuk-testi.html`, sadece TEST KOPYASINDA):
  - [ ] Önce "Tabloyu 80.000 satıra doldur".
  - [ ] Sonra 10 telefon × 20/dk, 30 dk, ERP taklidi açık → sonuç **✅ BAŞARILI**, gönderim p95 < 20 sn.
  - [ ] Sınır testi: 10 telefon × 30/dk, 15 dk → yine **✅ BAŞARILI** (geçici hata olabilir, eksik/yanlış kayıt olmamalı).
- [ ] **Prova sayımı:** 3–5 gerçek telefonla 1 saat okutma → "Sayımı Bitir ve Rapor Oluştur" → rapor doğru.
- [ ] **ERP bilgisayarı ("server"):**
  - [ ] Görev Zamanlayıcı → "Stok Otomatik Gönderim": tetikleyici **Etkin**, 15 dk'da bir, "30 dakikadan uzun çalışırsa durdur" işaretli, Ayarlar → "Var olan örneği durdur".
  - [ ] Windows güç ayarı: **uyku modu = Hiçbir zaman**.
  - [ ] SQL yedek görevleri (`SqlBackupFree_*`) başarılı — (0xFFFFFFFF) görünmüyor.
- [ ] **Kullanıcılar:** Her personelin kendi kullanıcı adı var; fiyat/stok görmemesi gerekenlerde "💰 Fiyat Görme" ve "📦 Stok Görme" kapalı.
- [ ] **Telefonlar:** şarjlı, powerbank hazır, Chrome güncel, uygulama ana ekrana eklenmiş, kamera izni verilmiş.
- [ ] **iPhone'larda Dikey Yön Kilidi açık** (sağ üstten aşağı kaydır → 🔒). iPhone uygulamanın ekranı kilitlemesine izin vermez; Android'de uygulama kendisi kilitler.
- [ ] **Personele koli kuralı söylendi:** koli barkodu okutulunca turuncu "📦 KOLİ BARKODU" yazar → KOLİ sayısı girilir, telefon adede çevirir (ör. 3 koli × 24 = 72). Adet barkodunda adet girilir.

## 2) Sayım başlarken

- [ ] Yönetici Paneli → **🧹 Dosyayı Temizle** (eski test/prova verisi arşive gider).
- [ ] Yönetici telefonunda **🩺 Sistem Durumu** açık: Katalog kartı son 15 dk içinde güncellenmiş, Hatalar = 0.
- [ ] Her telefonda bir deneme okutması → nokta 🟢 oluyor.

## 3) Sayım sırasında (18 saat)

- [ ] Saatte bir Sistem Durumu'na bakılır: kırmızı hata, sarı kart var mı?
- [ ] **Vardiya sonunda her telefonda "Bitir / Yeni"** — telefon hafızası boşalır (veri sunucuda güvende). Telefon "%60 dolu" uyarısı verirse vardiya beklenmeden yapılır.
- [ ] Bir telefonda bekleyen sayısı uzun süre düşmüyorsa: internetini kontrol edin, "Gönder"e basın; olmazsa "Excel (CSV)" ile yedek alın.
- [ ] Sunucu PC'si kapanırsa: telefonlar ETKİLENMEZ (sayım verisi Google'a gider); sadece ERP katalog güncellemesi durur. PC açılınca Görev Zamanlayıcı'yı kontrol edin.

## 4) Sayım biterken

- [ ] **Tüm telefonlarda bekleyen = 0** ve son okutmalar 🟢 (Sistem Durumu → "Bu telefon" kartı, her telefonda).
- [ ] Yönetici Paneli → **📊 Sayımı Bitir ve Rapor Oluştur**. "Veri hâlâ geliyor" uyarısı çıkarsa birkaç dakika bekleyip tekrar deneyin.
- [ ] **📥 Son Stok Sayımını İndir (CSV)** → ERP12'ye aktarım.
- [ ] Rapor e-postası geldi (yedek).

## Sorun olursa

Sistem Durumu ekranının ve varsa hata mesajının ekran görüntüsünü alın. Veri telefonda ya da sunucuda **silinmez**; gönderilemeyen her kayıt telefonda bekler ve bağlantı gelince kendiliğinden gider.
