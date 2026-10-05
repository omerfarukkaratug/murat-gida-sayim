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

## Fiyat izleme ve indirim önerisi (sunucu build 116+)
Sunucu, katalog her yenilendiğinde fiyatı değişen ürünü kaydeder:
- **Fiyat Tarihi** (Katalog 9. sütun): fiyatın değiştiği gün. Etiketteki "fiyat
  değişiklik tarihi" buradan kendiliğinden gelir.
- **Önceki Fiyat** (10. sütun): değişimden önceki **30 gün** içindeki en düşük
  fiyat. (Fiyat Etiketi Yönetmeliği 10 gün, reklam kılavuzu 30 gün der; 30
  günün en düşüğü ikisini de karşılar.)
- **FiyatGecmisi** sekmesi: her değişimin kaydı (zaman, barkod, eski, yeni).
  "Önceki fiyat buydu" diyebilmenin kanıtıdır; silmeyin.

İzleme, build 116'nın yüklendiği gün başlar; öncesi bilinmez. İlk 30 gün
içinde sayfa bunu hatırlatır.

**İndirim kendiliğinden yazılmaz.** Fiyatı düşen ürün eklenince sayfa "fiyat
şu gün şundan şuna düşmüş, indirim etiketi basılsın mı?" diye sorar; personel
onaylar. İndirim etiketinde önceki fiyat ve **bitiş tarihi** zorunludur
(indirimli satış reklamında başlangıç ve bitiş tarihi belirtilmelidir).

**Toplu ekle:** "Fiyatı değişenler" son 1/3/7/30 günde fiyatı değişen ürünleri
listeye ekler (etiketleri yenilemek için). "Fiyatı düşenleri indirimli ekle"
son 30 günde fiyatı düşenleri indirim etiketi olarak ekler. Bir seferde en
fazla 150 ürün eklenir.

## Üretim yeri ERP'den gelir (build 117)

- Kaynak: ERP12 stok kartındaki **Ülke** alanı (`dbo.STOK.ULKE` → `dbo.ULKE.AD`).
  `stok-otomatik-gonder.ps1` bunu katalogla birlikte gönderir; Katalog sekmesinde
  11. sütun **Üretim Yeri** olarak durur.
- Etiket sayfasında ürün eklenince üretim yeri kendiliğinden dolar (alan başlığında
  "· ERP'den" yazar). Ülke "Türkiye" ise yerli üretim işareti de kendiliğinden gelir.
- Stok kartında ülke **boşsa** alan boş kalır ve etiket "Eksik: üretim yeri" uyarısı
  verir — ya ERP'de stok kartına ülke girilir (kalıcı çözüm) ya da etiket ekranında
  elle yazılır.
- Aynı fiyatlı çeşitleri tek etikette toplarken üretim yeri farklı olanlar gruba alınmaz.

## 868/869 barkodlu ürünlerde üretim yeri (build 119)

ERP'de ülke boşsa ve bu telefonda daha önce yazılmamışsa, barkodu 868 ya da 869 ile
başlayan ürünlerde üretim yeri kendiliğinden "Türkiye" yazılır (alan başlığında
"· barkoddan" görünür). Barkod ön eki firmanın Türkiye'de kayıtlı olduğunu gösterir,
üretim yerini kanıtlamaz: Türk firmasının ithal ettiği ürünlerde ülke elle düzeltilmelidir.

## Liste aktarma: telefonda hazırla, bilgisayardan bas (build 120)

Yazıcı yalnızca USB ile bir bilgisayara bağlıysa (ör. Epson L1300) telefondan doğrudan
basılamaz. Bunun yerine:

1. Telefonda Etiket ekranında ürünler okutulur, bilgiler tamamlanır, **📤 Listeyi gönder** denir.
2. Yazıcının bağlı olduğu bilgisayarda uygulama açılır, giriş yapılır, Etiket > **📥 Gönderilen listeyi getir**.
3. Çıkan listelerden (gönderen · saat · ürün sayısı) biri seçilir; ürünler listeye eklenir, biçim seçilip yazdırılır.

Listeler tablodaki `EtiketListe` sekmesinde durur; son 30 liste saklanır. Çok uzun listeler
(yaklaşık 150 üründen fazla) bölünerek gönderilmelidir.

## A4'e dizme (build 121)

Yazıcı yalnızca A4 basıyorsa A6/A5 afişler A4 kâğıda dizilir ("A4 kâğıda diz" kutusu, varsayılan açık):
A6 → dik A4'te 4 tane, A5 → yatık A4'te yan yana 2 tane. Kesik çizgilerden kesilir.
Yazdırma penceresinde: kâğıt A4, ölçek %100, kenar boşluğu "Yok", "Üstbilgi ve altbilgi" kapalı.

## Fiyat tarihi ERP'den ve "Basılacak etiketler" kuyruğu (build 122)

- **Fiyat değişiklik tarihi** ERP12'nin kendi kaydından gelir (`dbo.STOK_STOK_BIRIM_DEGISIM`:
  FIYAT, ESKI_FIYAT, TARIH; KDV dâhil fiyat listesi). Betik her ürün-birim için son değişikliği
  ve ondan önceki 30 günün en düşük fiyatını gönderir; Katalog sekmesinde "Fiyat Tarihi" ve
  "Önceki Fiyat" sütunlarına yazılır. ERP kaydı olmayan ürünlerde sunucunun kendi takibi geçerlidir.
- Bu sorgu başarısız olursa katalog yine gönderilir; günlükte "UYARI: Fiyat degisiklik tarihleri
  alinamadi" yazar.
- **Basılacak etiketler:** fiyatı değişen ürün, etiketi basılana kadar Etiket ekranının üstündeki
  sarı kartta görünür. "Hepsini listeye ekle" → bas → "Etiketler basıldı mı?" sorusuna Tamam.
  Basıldı bilgisi `EtiketBasildi` sekmesinde ortak tutulur; bir cihazda basılan diğerinde de düşer.
  Kuyruk, sunucu build 122 olduktan sonraki ilk açılış gününden itibaren olan değişimleri sayar.

## Ortak bilgi, kendiliğinden yenilenen katalog, baskı kaydı (build 126–127)

- **Çeşit grupları:** marka + aynı fiyat yeter; gramajı farklı olanlar da aynı etikette toplanabilir (her gramajın
  birim fiyatı ayrı yazılır). Gruba katalogdan ürün eklenebilir; yalnızca etiketle aynı fiyattaki ürün seçilir.
  Grup etiketinde çeşitlerden birinin barkodu basılır (rafta fiyat kontrolü için).
- **Ortak etiket bilgisi (`EtiketBilgi` sekmesi):** bir cihazda girilen üretim yeri, net miktar ve paket/koli adedi
  sunucuya yazılır, bütün cihazlara gelir. ERP'de ülke yazılıysa yine o esastır.
- **Katalog:** Etiket sayfası açılınca sunucudaki sürümü kontrol eder; daha yenisi varsa kendisi indirir.
- **Baskı kaydı (`EtiketBaskiKaydi` sekmesi):** basılan her etiket için zaman, kullanıcı, barkod, ürün, fiyat,
  fiyat tarihi, biçim, indirim/önceki fiyat/bitiş, adet ve baskı yolu yazılır (son 30.000 satır saklanır).

## Çeşitli etikette bir ürünün fiyatı değişirse (build 128)

Birden çok ürünü kapsayan etiket basılınca grup `EtiketGrup` sekmesine kaydedilir (ürünler + fiyat).
Gruptaki bir ürünün katalog fiyatı etiketteki fiyattan farklılaşınca "Basılacak etiketler" kartında
"N çeşitli etikette fiyat değişti" uyarısı çıkar. "Çeşitli etiketleri düzelt" denince ürünler şimdiki
fiyatlarına göre yeniden gruplanır: aynı fiyatta kalanlar tek etikette, fiyatı ayrılan ürün kendi
etiketinde listeye gelir. Basılınca yeni gruplar kaydedilir, eski grup silinir. Çeşitli etikette barkod
basılmaz; tek ürünlü etikette barkod ve ayrı bir "Stok kodu" kutusu vardır.

## Zebra rulo etiketi (build 129)

"Zebra etiket" biçimi rulo etikete tek tek basar (varsayılan 80 × 34 mm; sarı fiyat kutusu 35 × 20 mm, soldan 43 mm,
üstten 8 mm). Ölçüler biçim ayarlarından değiştirilir. "Deneme çerçevesi" sarı kutunun yerini kesik çizgiyle basar:
çizgi kutuya oturana kadar "soldan/üstten" değerlerini düzelt, sonra çerçeveyi kapat.
Windows'ta Zebra sürücüsünün "Yazdırma tercihleri"nde etiket boyutu ruloyla aynı (80 × 34 mm) olmalıdır.
Dizili A5, tarayıcıdan baskıda dik A4 sayfanın içinde 90° çevrilmiş basılır (kâğıt yatık seçmeye gerek yok).

## Çeşitli etiket kodu, koli ürünleri, dizili A5 (build 135)

- **Etiket kodu:** çok ürünlü (çeşitli) etikete 5 haneli kod verilir, `Ç-12345` olarak yazılır ve mağaza içi
  EAN-13 (`2400000` + kod + kontrol hanesi) olarak barkodu basılır. Kod, grup kaydıyla birlikte sunucuda
  (`EtiketGrup` sayfası, `Kod` sütunu) tutulur.
- **Kontrol:** kodu kamerayla okut ya da arama kutusuna `Ç-12345` yaz → grubun ürünleri, şimdiki fiyatları ve
  etiketin geçerli/geçersiz olduğu görünür. Geçersizse "Düzelt ve listeye ekle": fiyatı aynı kalanlar aynı kodla
  tek etikette kalır, fiyatı değişen ürün kendi etiketini alır.
- **Basılacak etiketler** kutusunda geçersiz çeşitli etiketler kodu ve değişen fiyatıyla (`55,00 → 60,00`) listelenir.
- **Koli/paket barkodu:** okutulan barkod koli ya da paketse ad `… 200 ML × 24 ADET` olur, altta yalnız
  `Koli: 24 adet` yazar, birim fiyat koli adedine bölünür (net miktar tek parçanınki girilmelidir).
- **Dizili A5:** baskı programında da dik A4 sayfa (afişler içinde çevrili); `baski-ajani.ps1` yenilenmeli.
- **Zebra barkodu:** çizgiler tam yazıcı noktasına (modül başına 2–3 nokta) oturtulur.
- Sunucu: `Code.gs` → `GS_VERSION = build135` (Apps Script'e yeniden yüklenmeli).

## QR etiket doğrulama (build 137)

- **Etikette QR:** Zebra etiketinde (ürün barkodunun sağında) ve afişlerde (sağ altta) küçük bir QR basılır.
  İçeriği: `M1*<barkod ya da C+etiket kodu>*<fiyat, kuruş>*<fiyat tarihi YYAAGG>*<indirim bitişi YYAAGG>`.
  Ürün barkodu etikette kalır (kasa ve el terminali için); çeşitli etiketlerde çizgili kod yerine QR basılır.
  24'lü raf etiketinde (A4) yer olmadığı için QR yoktur; orada çeşitli etiket kodu çizgili barkod olarak kalır.
- **Doğrulama ekranı:** ana menüde "QR Etiket Doğrulama" ya da etiket sayfasının en üstündeki düğme. Tam ekran
  kamera açılır; okutulan her etiket için etikette yazan fiyat katalogdaki güncel fiyatla karşılaştırılır:
  ✅ DOĞRU · ❌ YANLIŞ (etikette X → şimdi Y) · ❌ İNDİRİM BİTMİŞ · ⚠️ QR YOK / KAYIT YOK / KATALOGDA YOK.
  Sunucu ve baskı kaydı gerekmez (çeşitli etiketlerde grup kaydı kullanılır); internet olmadan da çalışır.
- "Hatalıları listeye ekle" işaretliyse yanlış çıkan etiketin yenisi kendiliğinden baskı listesine girer.
- Normal ürün ekleme kamerasında QR okutulursa ürünün barkodu okutulmuş gibi davranır.
- QR üretimi sayfanın içindedir (kütüphane indirilmez): alfasayısal kip, hata düzeltme M, sürüm 1–5.
