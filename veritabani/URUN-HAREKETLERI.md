# Ürün Hareketleri ekranı — kararlaştırılan tasarım (sayımdan sonra, Kasım)

Fiyat Gör'e benzer: ürün okutulur, iki düğme çıkar.

## 📥 GELEN (toplam adet)
- ERP12 `FIS` + `FIS_DETAY`, **FIS_TURU 1 (alış faturası) ve 5 (alış irsaliyesi)**.
- Tüm cariler (alıcı/satıcı ayrımı yok), **tek tek** listelenir:
  cari adı · tarih · belge no · adet · **KDV DAHİL birim fiyat**.

## 📤 SATILAN (toplam adet — perakende DAHİL)
- **FIS_TURU 2, 6, 12** (Peşin Satış Carisi hariç) → tek tek listelenir (cari · tarih · belge no · adet · KDV dahil fiyat).
- **FIS_TURU 11 (kasa/POS) + Peşin Satış Carisi** → tek satır özet: "🛒 Perakende: N adet".

## Kararlar
- Fiyatlar: sadece **KDV dahil** gösterilir.
- Varsayılan aralık son 12 ay; seçim: 3 ay / 12 ay / tümü.
- Ayrı yetki: "Ürün Hareketleri"; şube dışında gizli. Veri sunucu (yetki kontrollü) üzerinden gelir.
- Fire/iade (FIS_TURU 20) şimdilik dahil değil.

## Eksik bilgi
- `FIS_DETAY` sütun adları (adet, birim fiyat, KDV) — alınacak.
- Belge türlerinin anlamı örnek carilerden çıkarıldı: 1 Multinet (alış e-fatura), 5 Kılıçaslan/Coca-Cola (alış),
  2 Quzine (satış faturası), 6 Düşünür Eğitim (satış irsaliyesi), 12 Peşin Satış Carisi, 11 kasa fişleri,
  20 fire/iade, 35 diğer.
