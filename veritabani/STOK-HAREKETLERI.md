# Stok Hareketleri ekranı (build 189)

Ürün okutulur (barkod / ad / kamera): o ürünün BÜTÜN giriş ve çıkışları, yeniden eskiye.
Belgeli satıra (📄) dokununca faturanın / fişin tamamı açılır (cari, ürünler, tutar).

## Kaynak (ERP12, erp/cari-hareket-gonder.ps1)
- `FIS` + `FIS_DETAY` + `FIS_TURU`: stoğa etki eden bütün belgeler (`FIS_TURU.GIRIS` = ±1; Finans 18 hariç):
  alış/satış fatura-irsaliye-fiş, iadeler, depo giriş/çıkış, sarf, fire, sayım → `erp_fis_satir`.
- Perakende: kasa fişleri (11, 12), perakende fatura/irsaliye (35, 36) ve Peşin Satış carisinin belgeleri
  → ürün + gün TOPLAMI (`erp_stok_perakende`). İlk çalışmada bütün geçmiş, günlük tam gönderimde son 60 gün,
  diğer saatlerde son 7 gün.
- "stok" sütunu: telefondaki güncel sistem stoğundan geriye doğru hesaplanır; yalnızca "Stok Görme" yetkisi olana.

## Parçalar
- `veritabani/007_stok_hareketleri.sql` — `erp_stok_perakende`, `stok_perakende_yukle`, `stok_hareket`,
  `fis_detay` (cari adı eklendi), `erp_fis_satir.cari_ad`.
- `Code.gs` (build171) — `action=stok_hareket` (+ `ne=fis`), "stok_hareket" yetkisi.
- `index.html` (build 189) — menüde "📦 Stok Hareketleri", yetki "📦 Stok Hareketleri", şube dışında gizli.
