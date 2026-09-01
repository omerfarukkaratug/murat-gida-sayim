# Murat Gıda Sayım Uygulaması — Kurulum ve Kullanım (build 38)

## Bu uygulama ne yapar
Kamera ile hızlı barkod okuma, telefona simge olarak kurulan, offline
çalışan bir web uygulaması üzerinden yapılır. 10'dan fazla telefon aynı anda,
saatlerce kesintisiz sayım yapabilir; veriler telefonda kalıcı olarak saklanır
ve internet geldiğinde otomatik olarak ortak Google E-Tablo'ya gönderilir.

## 1) Yayında — adres hazır
Uygulama şu adreste yayında (GitHub Pages üzerinden, https ile):

```
https://omerfarukkaratug.github.io/murat-gida-sayim/
```

Kamera, tarayıcı güvenliği gereği yalnızca **https** adreste çalışır. Dosyayı
telefona indirip doğrudan açarsan kamera izni verilmez — mutlaka yukarıdaki
adresten açılmalı.

**Not (geliştirici için):** Dosyaları güncelleyip GitHub Pages'e yeniden
yüklerken `index.html`'in gerçekten yüklendiğinden emin ol — bazen yükleme
sırasında bu dosya sessizce atlanabiliyor. Sayfayı açtıktan sonra en üstteki
"build XX" numarasının beklediğin sürümle eşleştiğini kontrol et.

## 2) Telefona kurma (her telefon için tek seferlik, ~1 dakika)
1. Yukarıdaki adresi Android telefonda **Chrome** ile aç
2. Sağ üst ⋮ menüsü → **"Ana ekrana ekle"** / **"Uygulama yükle"**
3. Artık telefonda gerçek bir uygulama gibi simgesi olacak, tam ekran açılacak
4. İlk açılışta kamera izni istenecek — **İzin Ver**'e dokun

**Not:** Otomatik barkod tarama Chrome (Android) üzerinde, tarayıcının
donanım hızlandırmalı motoruyla çalışır. iPhone'da bu motor yok; barkod elle
girilebilir ama otomatik tarama olmaz.

## 3) Ürün listesini yükleme — 3 yol
Uygulama açılış ekranında üç seçenek sunar:

1. **① Sunucudan Kataloğu Çek** — Eğer başka bir telefon listeyi zaten
   yüklediyse, en hızlısı bu. Tek dokunuşla tüm liste (50 bine kadar ürün)
   telefona iner.
2. **② Dosya seç** (veya bilgisayarda sürükle-bırak) — CSV/TXT dosyası.
   Her satır: `Ürün Adı;Barkod;Stok Kodu;Eski Stok` (son iki alan opsiyonel).
3. **③ Doğrudan yapıştır** — listeyi elle kopyala-yapıştır.

Bir telefon listeyi dosyadan yüklediğinde, liste **otomatik olarak buluta da
gönderilir** — diğer telefonlar "① Sunucudan Kataloğu Çek" ile hemen
indirebilir, aynı dosyayı tekrar aramalarına gerek kalmaz.

### Katalog neden ayrı tutulur (IndexedDB)?
50.000 ürünlük katalog, telefonun büyük veri deposunda (IndexedDB) tutulur —
sayım verisinden tamamen ayrıdır:
- Bir kez yüklenir, telefonda kalıcı kalır, her açılışta yeniden yüklemeye gerek yok.
- Barkod eşleştirme bellekten anında yapılır, 50 bin ürün olsa da gecikme olmaz.
- Katalog her taramada yeniden yazılmaz — hız ve veri güvenliği için.

## 4) Sayım yaparken
1. Personel adını gir → "Sayıma Başla"
2. Kamerayı barkoda tut, otomatik okur → adet gir → kaydedilir
3. Barkod okunmazsa alttaki kutuya elle yazıp "Ekle"ye bas
4. Barkod **listede yoksa** uygulama sorar: yeni ürün olarak eklemek ister
   misin? Evet dersen ürün adı + adet girip eklersin — bu yeni ürün otomatik
   olarak diğer telefonların da kataloğuna (arka planda, sessizce) eklenir.
5. Listede her ürünün adedini elle de düzeltebilirsin (yanlışlıkla 0 girersen
   kayıt silinir, onay ister)
6. "Excel (CSV)" her an dosyayı indirir — internete hiç ihtiyaç duymaz
7. "Bitir / Yeni" mevcut sayımı gönderim kuyruğuna ekler, gözden geçirme
   ekranı açar, onaylayınca sıfırdan yeni bir sayıma başlar — hiçbir veri
   silinmez

## 5) Veri güvenliği — 10+ kişi, 72 saate kadar kesintisiz sayım için
- Her okutmadan hemen sonra veri telefonun kendi hafızasına (localStorage)
  yazılır — uygulama kapansa, telefon yeniden başlasa, internet kesilse bile
  **veri kaybolmaz**.
- Gönderim internet geldiğinde **otomatik** olur; "Gönder" butonuna elle
  basmaya gerek yok. Hızlı art arda taramalarda uygulama gönderimi birkaç
  saniye toplu hâle getirir (sunucuyu boğmamak için) — ama veri o an
  telefona zaten yazılmış olur.
- Uygulama arka plana alınırken/kapanırken bile son bir gönderim denemesi
  yapılır (`sendBeacon`); aynı kayıt iki kez gitse bile kayıt kimliği (ID)
  sayesinde tabloda kopya satır oluşmaz, üzerine yazılır.
- Sunucu tarafında (Google E-Tablo + Apps Script) **kilitleme mekanizması**
  var: 10+ telefon aynı anda veri gönderse bile satırlar birbirinin üzerine
  yazılmaz, sırayla işlenir.
- Excel (CSV) indirme her zaman çalışır, internete hiç ihtiyaç duymaz —
  en kötü senaryoda bile veri telefonda güvendedir ve elle dışa aktarılabilir.
- Hatalar ekranda **kırmızı ve ❌ emojili**, uyarılar **turuncu ve ⚠️
  emojili**, başarılı işlemler **yeşil ve ✅ emojili** olarak net şekilde
  gösterilir — "bir şey ters gitti mi" sorusunu tahmin etmene gerek kalmaz.

## Sunucu tarafı (Google E-Tablo + Apps Script) ne alır?
Uygulama iki tür veri gönderir:

**Sayım verisi** (`Sayim` sekmesi):
```json
{
  "personnel": "Ayşe Yılmaz",
  "sessionId": "id-...",
  "rows": [
    {"id":"...", "name":"Süt 1L", "barcode":"8690001112223", "stockCode":"STK001",
     "unit":"Adet", "oldStock":32, "date":"2026-09-01", "time":"14:12:03", "qty":24}
  ]
}
```

**Katalog verisi** (`Katalog` sekmesi) — telefonlar arası paylaşım için:
```json
{ "type": "katalog_bulk", "entries": [ {"name":"...", "barcode":"...", "stockCode":"...", "oldStock":"..."} ] }
```

`toplama-scripti.gs` dosyasının tamamını Google Apps Script projesine
yapıştırıp **Dağıt → Yeni Dağıtım** ile yayınlaman yeterli. Her yeni
dağıtımda Apps Script farklı bir URL üretebilir — bu durumda `index.html`
içindeki `DEFAULT_SERVER_URL` değerini güncelleyip eski URL'yi
`OLD_WRONG_URLS` listesine eklemeyi unutma, böylece daha önce kurulmuş
telefonlar otomatik olarak yeni adrese geçer.

## Gerçek bir .apk istersen
https://www.pwabuilder.com sitesine yukarıdaki GitHub Pages adresini
yapıştırıp "Package for Android" ile imzalı bir .apk/.aab indirebilirsin —
kod yazmaya gerek kalmadan, ücretsiz. (Şu anki build, Package ID
`com.muratgida.sayim` ile paketlenmiştir.)

## Sınırlamalar
- Otomatik barkod tarama yalnızca Android + Chrome'da çalışır. Farklı
  tarayıcı/işletim sisteminde elle barkod girişi devreye girer.
- Ürün listesi içe aktarma CSV/TXT formatındadır (Excel'den "CSV olarak
  kaydet" ile 1 saniyede alınır).
