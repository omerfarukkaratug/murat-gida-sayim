# Market Sayım Uygulaması — Kurulum

## Neden sadece bir .apk göndermedim
Kamera ile hızlı barkod okuma, gerçek bir Android derleme ortamı (Android
Studio + SDK) gerektirir; bu sohbet ortamında böyle bir derleyici yok. Onun
yerine aynı işi gören, telefona simge olarak kurulan, tamamen offline
çalışan bir web uygulaması hazırladım. İstersen en altta anlatılan yöntemle
bunu gerçek bir .apk'ya da çevirebilirsin (kod yazmadan, ücretsiz).

## 1) Yayına alma (2 dakika, tek seferlik)
Kamera, tarayıcı güvenliği gereği yalnızca **https** adreste çalışır — dosyayı
telefonda doğrudan açarsan kamera izni verilmez. En kolay ücretsiz yöntem:

1. https://app.netlify.com/drop adresini bilgisayarda aç
2. Bu klasördeki 4 dosyayı (index.html, manifest.json, sw.js, icon.svg)
   sürükleyip bırak
3. Sana `https://.....netlify.app` gibi bir adres verecek — bu senin
   uygulamanın adresi

(Netlify yerine GitHub Pages, Vercel gibi başka ücretsiz servisler de olur.)

## 2) Telefona kurma
1. Verilen adresi Android telefonda **Chrome** ile aç
2. Sağ üst ⋮ menüsü → "Ana ekrana ekle" / "Uygulama yükle"
3. Artık telefonda gerçek bir uygulama gibi simgesi olacak, tam ekran açılacak

**Not:** Bu sürüm sadece Android için optimize edilmiştir — tarayıcının
kendi donanım hızlandırmalı barkod motorunu kullanır (en hızlı seçenek).
iPhone'da bu motor çalışmaz.

## 50.000 ürünlük liste hakkında
Ürün kataloğu telefonun büyük veri deposunda (IndexedDB) tutulur, sayım
verisinden tamamen ayrıdır. Bu sayede:
- Kataloğu bir kez yüklersin, telefonda kalıcı kalır — her açılışta yeniden
  yüklemene gerek yok.
- Tarama sırasında barkod eşleştirme bellekten anında yapılır, 50 bin
  ürün olsa da gecikme olmaz.
- Her barkod okutuşunda sadece o anki sayım kaydı güncellenir, dev katalog
  tekrar yazılmaz — hem hız hem veri güvenliği için.
Listeyi güncellemek istediğinde (yeni ürün eklendiğinde vb.) sadece güncel
dosyayı tekrar yükle — eski liste tamamen yenisiyle değişir.

## 3) Kullanım
1. İlk açılışta: Personel adı gir, (istersen) gönderim adresini gir,
   ürün+barkod listesini yükle (CSV/TXT dosyası veya yapıştır)
2. "Sayıma Başla" → kamera açılır, barkoda tutunca otomatik sayar
3. Barkod okunmazsa alttaki kutuya elle yazıp "Ekle"ye bas
4. Listede her ürünün +/- ile adedini elle de düzeltebilirsin
5. "Excel (CSV)" butonu her an dosyayı indirir — bu dosyayı doğrudan Excel'de
   açabilir, mevcut programına aktarabilirsin
6. Gönderim adresi girdiysen, telefon internete bağlanınca veriler otomatik
   olarak o adrese gönderilir (POST + JSON). "Gönder" butonuyla da elle
   tetikleyebilirsin
7. "Bitir / Yeni" mevcut sayımı gönderim kuyruğuna ekler ve sıfırdan
   yeni bir sayıma başlar — hiçbir veri silinmez, internet gelene kadar
   telefonda bekler

## Veri güvenliği
- Her okutmadan hemen sonra veriler telefonun kendi hafızasına
  (localStorage) yazılır — uygulama kapansa/telefon yeniden başlasa bile
  veri kaybolmaz.
- Excel indirme her zaman çalışır, internete hiç ihtiyaç duymaz.
- Gönderim adresi sadece "internet görünce otomatik ilet" içindir; onsuz da
  uygulama tam çalışır.

## Sunucu tarafı (senin ekleyeceğin adres) ne alır?
Uygulama o adrese şu formatta bir JSON gönderir:
```json
{
  "personnel": "Ayşe Yılmaz",
  "finishedAt": {"date":"2026-08-25","time":"14:32:10"},
  "rows": [
    {"name":"Süt 1L","barcode":"8690001112223","date":"2026-08-25","time":"14:12:03","qty":24}
  ]
}
```
Kendi programına bu adresi bağlarken bu formatı esas alabilirsin.

## Gerçek bir .apk istersen
Uygulama yayına alındıktan sonra (adım 1), o https adresini
https://www.pwabuilder.com sitesine yapıştırıp "Package for Android"
seçeneğiyle imzalı bir .apk / .aab dosyası indirebilirsin — kod yazmaya
gerek kalmadan, ücretsiz.

## Sınırlamalar (dürüst olmak gerekirse)
- Otomatik barkod tarama Chrome (Android) üzerinde çalışır; bu sürüm
  bilinçli olarak sadece Android için optimize edilmiştir. Farklı bir
  tarayıcı kullanılırsa elle barkod girişi devreye girer.
- Ürün listesi içe aktarma CSV/TXT formatındadır (Excel'den "CSV olarak
  kaydet" ile 1 saniyede alınır). İstersen ileride doğrudan .xlsx
  okuma da eklenebilir.
