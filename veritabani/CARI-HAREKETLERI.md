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
