# Fiyat Etiketi (etiket.html)

Menüdeki **🏷️ Etiket Yazdır** ile açılır. Yetki: yönetici ya da **Etiket Yazdırma**
yetkisi (Yönetici Paneli → Kullanıcılar). Katalog telefondaki kopyadan okunur,
sunucuya hiçbir şey gönderilmez; baskı telefonun yazdırma penceresiyle yapılır.

## Biçimler
| Biçim | Ölçü | Kâğıt |
|---|---|---|
| Raf etiketi | 70 × 37 mm, sayfada 3 × 8 = 24 | A4 (hazır 70×37 etiket kâğıdı ya da düz kâğıt + kesim çizgisi) |
| A6 / A5 / A4 / A3 afiş | sayfanın tamamı, dikey | seçilen boyutta kâğıt |

A6 ve A5'te **üstte 2 cm boşluk** bırakılabilir (varsayılan açık): kâğıt raf etiketliğine sıkıştırıldığında yazı kapanmaz.

Yazdırırken: kâğıt boyutu seçilen biçimle aynı, ölçek **%100**, kenar boşluğu **yok**.

## Yönetmelik karşılığı
Fiyat Etiketi Yönetmeliği (RG 28.06.2014 / 29044, son değişiklik 11.10.2025) m.5:

| Zorunlu bilgi | Etikette |
|---|---|
| Üretim yeri | "Üretim yeri" — boşsa etiket basılmaz |
| Ayırıcı özellik | Ürün adı |
| Tüm vergiler dâhil satış fiyatı | Büyük fiyat + "KDV dâhil" |
| Birim fiyatı | Net miktardan hesaplanır (₺/kg, ₺/L, ₺/m, ₺/adet) |
| Fiyatın uygulanmaya başlandığı tarih | "Fiyat değişiklik tarihi" |
| Yerli üretim logosu (Türkiye'de üretilenler) | `yerli-uretim.png` |

**İndirim (m.11):** "İNDİRİM" yalnızca "İndirimli satış" işaretlenince yazılır ve
indirimden önceki fiyat girilmeden basılmaz. Önceki fiyat = indirimden önceki
**10 gün** içindeki en düşük fiyat (çabuk bozulan üründe bir önceki fiyat). İspat
satıcıdadır. Piyasanın altında fiyatlı ama indirim yapılmamış ürüne "indirim"
yazılmaz; bunun için "ÖNE ÇIKAN ÜRÜN", "HAFTANIN ÜRÜNÜ" gibi başlıklar vardır.

## Yerli üretim logosu
Logo Ticaret Bakanlığı'nın ilan ettiği resmî işarettir; uygulama onu kendisi
çizmez. Bakanlığın sitesinden indirip repoya **`yerli-uretim.png`** adıyla
ekleyin (GitHub → Add file → Upload files). Oran 6,345 : 2,5 (yatay), renk
kırmızı ya da siyah. Dosya yokken sayfa kırmızı uyarı gösterir ve yerli ürün
etiketleri logosuz (eksik) basılır.

## Dikkat
- **Katalogdaki fiyat KDV dâhil perakende fiyat olmalı.** Etiket onu aynen basar.
- Etiketteki fiyat kasadakinden farklıysa tüketici lehine olan uygulanır;
  basmadan önce kataloğun güncel olduğuna bakın (sayfanın üstünde tarih yazar).
- "Fiyat tarihi" varsayılan olarak bugündür; fiyat daha önce değiştiyse o günü seçin.
- Net miktar ürün adından tahmin edilir ("500 ML", "6X200 GR"); yanlışsa düzeltin.
- Üretim yeri ve net miktar ürün bazında **bu telefonda** hatırlanır.

## Çeşitler tek etikette
Aynı ürünün fiyatı aynı olan çeşitleri (örn. yumuşatıcının kokuları) için tek
etiket basılabilir. Bir çeşidi ekleyince sayfa, katalogda **fiyatı ve net
miktarı aynı, adının ilk iki sözcüğü aynı** olan diğer çeşitleri bulur ve "tek
etikette topla" önerir; ad "… ÇEŞİTLERİ 1440 ML" biçiminde gelir, düzeltilebilir.
Gruptaki ürünlerden birinin fiyatı sonradan değişirse etiket basılmaz; o ürün
gruptan çıkarılır. Üretim yeri de hepsinde aynı olmalıdır — farklı olanı
gruptan çıkarıp ayrı etiket basın.

Afişlerde grup etiketinin altında kapsanan çeşitler küçük yazıyla listelenir ("Çeşitler: Lavanta · Gül · …"). Raf etiketinde yer olmadığı için liste basılmaz.
