# 🕐 Ekip — mesai, vardiya, izin, duyuru, görev

Uygulamanın menüsünde **🕐 Mesai** (ve üstteki hızlı geçişte). Kodu ayrı dosyada
(`mesai.html`) durur, uygulamanın içinde açılır; **sayıma, mal giriş/çıkışa ve ERP'ye
dokunmaz.** Veriler Google Sheets'te yeni sekmelere yazılır: Mesai, Bolumler,
PersonelBilgi, Vardiya, Izinler, Duyurular, Gorevler.

## Roller (Yönetici Paneli → kullanıcı → yetkiler)
| Yetki | Kim | Ne yapar |
|---|---|---|
| **🕐 Mesai (personel)** | Tüm personel | Giriş/çıkış, kendi vardiyası, izin talebi ve bakiyesi, duyuruları okur, görevlerini tamamlar |
| **⭐ Ekip Lideri** | Mağaza sorumlusu | Yukarıdakiler + bölümler, personel bilgileri, vardiya planı, izin onayı, eksik kayıt düzeltme, duyuru/görev, pano, puantaj, kasa QR ekranı |
| Yönetici | Sen | Her şey (otomatik) |

Ekip Lideri kullanıcı şifresi/rolü/yetkisi **değiştiremez** — o sadece Yönetici Paneli'nde.

## Giriş / çıkış nasıl çalışır?
1. Kasa bilgisayarında (ya da bir tablette) `.../mesai.html` açılır, Ekip Lideri
   hesabıyla girilir, **📺 Kod Ekranı**'na basılır. Ekranda bir **QR kod** ve altında
   6 haneli bir sayı çıkar; **30 saniyede bir değişir.**
2. Personel telefonda **🕐 Mesai → 🟢 GİRİŞ YAP**'a basar. Telefon konumu bir kez alır
   ve kamerayı açar; personel kasadaki QR'ı okutur (ya da sayıyı yazar). Bitti.
3. Sunucu kontrol eder: **QR/sayı güncel mi** + **konum mağazada mı** + GPS net mi.
   Hepsi tamamsa **sunucunun saatiyle** kaydeder.

Neden ikisi birden? Telefonun konumu sahte konum programıyla kandırılabilir, ama
kasadaki QR'ı sadece mağazadaki görebilir ve en fazla ~1 dakika geçerlidir.
Konum ve kamera **sadece düğmeye basıldığında** kullanılır; sürekli takip yoktur.
Reddedilen her deneme Sistem Günlüğü'ne "mesai — REDDEDİLDİ" olarak yazılır.

## Ekip Lideri sekmeleri
- **📊 Pano:** bugün kim içeride, kim gelmedi (vardiyası başladı + 15 dk), kim izinde,
  kim geç kaldı; bölüme göre süzülür. Yaklaşan doğum günleri ve iş yıl dönümleri.
- **🗓️ Vardiya Planı:** hafta seç → gün seç → herkesin saatini yaz (`09:00-18:00`,
  `9-18`, gece `22-06`, `İzin`, `Tatil`). "Geçen haftayı kopyala" ile hızlı plan.
- **📝 İzin Onay:** bekleyen talepler → Onayla / Reddet (sebep). Onaylı izni iptal edebilir.
  Personel adına izin/rapor girmek için 🌴 İzin sekmesinde personel seçilir (doğrudan onaylı).
- **👥 Ekip:** bölümler (Gıda, Züccaciye, Temizlik, Muhasebe…); her personele bir ya da
  birden fazla bölüm, işe giriş ve doğum tarihi, izin devri. **Eksik giriş/çıkış ekle**
  (gerekçe zorunlu, kimin eklediği kayıtlı kalır).
- **📋 Puantaj:** ay seç → kişi başı toplam saat, çalışılan gün, **fazla mesai**
  (haftalık 45 saati aşan), geç kalma, erken çıkış, izin, eksik kayıt; gün gün döküm;
  **⬇ Excel**; **🖨 İmza sayfası** (personel / Ekip Lideri / işveren imza alanlı).
- **📢 Duyuru / ✅ Görevler:** herkese ya da seçilen bölümlere duyuru (kim okudu görünür);
  bölüme ya da kişiye günlük görev (kim ne zaman tamamladı görünür).

## Yıllık izin hesabı
İşe giriş tarihinden itibaren her tamamlanan yıl için: 1–5. yıl **14**, 6–14. yıl **20**,
15. yıl ve sonrası **26** gün; o yıl dönümünde 18 yaş ve altı ya da 50 yaş ve üstü olana
en az **20** gün (4857 s. İş Kanunu md. 53). Kalan = hak edilen + devir − onaylı yıllık izin.
Yıllık izinde Pazar sayılmaz; **resmî tatiller otomatik düşülmez** (gerekirse devir alanıyla düzeltilir).
Önceden kullanılmış izinler için personelin **İzin devri** alanına (−/+) gün girilir.

## Kurulum
1. Yeni `Code.gs` → Apps Script → yeni sürüm (build116).
2. Ayarlar → Şube Konumları'nda mağaza tanımlı olmalı (zaten var).
3. Yönetici Paneli: personele **🕐 Mesai (personel)**, sorumluya **⭐ Ekip Lideri**.
4. Ekip Lideri: 👥 Ekip → bölümleri ve personel bilgilerini girer.
5. Kasa bilgisayarında `mesai.html` → Ekip Lideri girişi → 📺 Kod Ekranı (açık kalır).

## Resmî kullanım (öneri — muhasebeci/avukat onayıyla)
- Ay sonunda **🖨 İmza sayfası** yazdırılıp ıslak imzalanır; izinlerde **🖨 İzin formu**.
- Konum kişisel veridir (KVKK): personele kısa bir aydınlatma metni imzalatılmalı.
