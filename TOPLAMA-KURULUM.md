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
