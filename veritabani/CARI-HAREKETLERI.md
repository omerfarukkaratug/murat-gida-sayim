# Cari Hareketleri ekranı (build 187, ekler build 188)

Cari ekstresi: seçilen carinin borç / alacak hareketleri ve yürüyen bakiyesi. Salt okunur.

## Kaynak (ERP12)
- `FINANS_DETAY` + `FINANS` (tarih, belge no) + `FINANS_ISLEM_TURU` (hareket adı) + `DOVIZ_AD`.
- Cari `KART_BORCLU` ise BORÇ, `KART_ALACAKLI` ise ALACAK. ERP12'nin `CARI_BAKIYELER` görünümü ve
  `AS_CARI_HESAP_EKSTRESI` prosedürü de aynı mantıkla çalışır (keşif: erp/kesif-cari.ps1, 11.10.2026).
- Sadece `CARI_TUR = 1` (personel cari değil), varsayılan cari (Peşin Satış, `FIRMASABITLERI.VARSAYILANCARI`) hariç.
- Bakiye = borç − alacak. Artı: cari bize borçlu (B). Eksi: biz cariye borçluyuz (A).

## Parçalar
- `veritabani/005_cari_hareketleri.sql` — `erp_cari_hareket`, `cari_hareket_yukle`, `cari_hareket`. Telefon anahtarına kapalı.
- `erp/cari-hareket-gonder.ps1` (+ `CARI-HAREKET-GONDER.bat` elle çalıştırmak için) — ERP12'den okur;
  günde bir TÜM hareketler, diğer saatlerde son 7 gün. Sadece en yeni yıl veri tabanı.
- `Code.gs` (build169) — `action=cari_hareket`, "cari_hareket" yetkisi, gizli anahtarla okur.
- `index.html` (build 187) — menüde "📒 Cari Hareketleri", yetki "📒 Cari Hareketleri", şube dışında gizli.

## Ekler (build 188, 006_cari_detay.sql)
- **Fatura / fiş detayı:** belgeli satıra (📄) dokununca ürün satırları açılır (`erp_fis_satir`, `fis_detay`).
- **Stok hareketleri sekmesi:** carinin belgelerindeki ürünler, + giriş / − çıkış (`cari_stok`).
  Kaynak FIS + FIS_DETAY, stoğa etki eden türler (`FIS_TURU.GIRIS` = ±1), Finans (18) hariç.
- **🛒 Perakende:** varsayılan cari (Peşin Satış) hareketleri gün + hareket türü başına TOPLAM,
  cari kodu `__PERAKENDE__`. Tek tek kasa fişleri gönderilmez.

## Sonra
- Tahsilat / ödeme girişi bu ekranın üstüne eklenecek.

## Vade (build 193, 008_vade.sql)
- Açık kalemler FIFO ile bulunur: ödemeler en eski borçları kapatmış sayılır; açık bakiye en yeni belgelerden oluşur.
  Vade = satırın vade tarihi (yoksa belge tarihi). Yalnızca TL; perakende hariç.
- `cari_vade(kod)`: açık kalemler, geçmiş / 7 gün içinde / ileri, ortalama gecikme, ağırlıklı ortalama vade,
  faturaların ortalama vade günü (son 365 gün). Ekranda carinin "📅 Vade" sekmesi.
- `vade_raporu('alacak' | 'borc')`: bütün cariler; ekranda "📅 Vade" düğmesi (Alacaklarımız / Borçlarımız).
- `Code.gs` (build172): `action=cari_hareket&ne=vade|vadeRapor`.

## Ödeme alışkanlığı ve risk (build 195, 009_odeme_risk.sql)
- `cari_odeme(kod)`: son 2 yılın ödemeleri belgelerle FIFO eşleştirilir → gerçek ödeme günü (ağırlıklı ort.),
  anlaşılan vade günü, vadeden sonra ortalama gecikme; son 90 gün sevk / ödeme oranı; risk 0–100 ve nedenleri.
- Risk carinin KENDİ alışkanlığına göredir: en eski açık belge her zamanki ödeme gününü aştı mı (40),
  90 günlük ödeme/sevk oranı (30), vadesi geçmiş oranı (20), genel gecikme eğilimi (10).
  0–24 normal (yeşil) · 25–49 dikkat (sarı) · 50+ riskli (kırmızı).
- `vade_raporu('alacak')` satırlarına risk eklendi; riskliler en üstte.
- `Code.gs` (build173): vade sekmesi cevabına `odeme` eklenir.

## Stoğa etki etmeyen faturalar (012_fatura_satirlari.sql, 13.10.2026)
- İrsaliyeden kesilen fatura gibi stoğa dokunmayan belgelerin (FIS_TURU.GIRIS = 0) satırları da gönderilir
  (`giris = 0`); eskiden bu faturaların içi "ürün satırı yok" görünüyordu.
- Fatura detayında görünür; stok hareketlerinde ve carinin stok hareketlerinde sayılmaz (mal irsaliyede sayıldı).
- Plasiyerin son satış/alış fiyatında kullanılır; aynı gün irsaliye + fatura tek sayılır.
- Kurulum: Supabase'de `012_fatura_satirlari.sql`; ERP bilgisayarında `cari-hareket-gonder.ps1` yenisi.
  Hemen görünsün diye `CARI-HAREKET-TAM.bat` çift tıklanır (tüm geçmişi yeniden gönderir; yoksa en geç ertesi gün).
