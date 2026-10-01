# ERP12 Sipariş modülü — inceleme notları (ERP122025, SQL Server 2017)

Amaç: telefondan girilen Mal Giriş / Mal Çıkış kayıtlarını ERP12'ye SİPARİŞ olarak yazmak
(stoğa ve cariye etki etmez; ERP'de faturaya çevrilir). Canlıya: sayımdan sonra, önce kopya DB'de test.

## Bulunanlar
- Tablolar: SIPARIS (6 satır), SIPARIS_DETAY (44), SIPARIS_EKTABLOLAR, SIPARIS_IRSALIYE_KOTROL_ALANLARI…
- ID'ler ortak `dbo.ID` sequence'ından (NEXT VALUE FOR dbo.ID). `SATIR_NO` sequence'ı da var.
  ID sütunlarında identity/varsayılan YOK, SIPARIS/SIPARIS_DETAY'da trigger YOK.
- Belge numaraları seri sequence'larından (örn. SK22026, SJS2025 …).

## Örnek SIPARIS satırı (TKLF -000005)
SIPARIS_TURU 3 (teklif?), LOKASYON 75919, PROJE 75916, CARI 660347, CARI_ADRES = GONDERIM_ADRESI 660348,
BELGENO "TKLF -000005", SIPARIS_TARIHI / TERMIN (+1 gün) / ISLEM_TARIHI / VADE (+30 gün),
DOVIZ_AD 1, DOVIZ_KUR 1, SATIR_TOPLAM 1318.73, KDV_TOPLAM 254.67, GENELTOPLAM 1573.40,
SIPARIS_ISKONTO_ORAN "          " (10 boşluk), FIS 0, AKTIF 1, ONAYLI 1, VADE_SECENEKLERI 7, YAZILDI 1,
EMAIL_GONDERILDI 0, DOVIZ_KUR_SECIMI 2, FIS_ODEME_TIPI_ISKONTOLARI 1, FIS_ALT_TIPI 1, diğerleri 0 / ''.

## SIPARIS_TURU (deneme kayıtlarıyla doğrulandı, 01.10.2026)
- **1 = Verilen Sipariş** (tedarikçiye) — BELGENO "SPRS VRLN-000001", ID 7024541
- **2 = Alınan Sipariş** (müşteriden) — BELGENO "SPRS LNN1-000001", ID 7024551
- **3 = Teklif** — "TKLF -00000N"
Eşleme: telefondaki Mal Giriş → 1 (Verilen), Mal Çıkış → 2 (Alınan).

Farklar: Verilen'de VADE_TARIHI = sipariş günü, VADE_SECENEKLERI 17, FIS_ODEME_TIPI_ISKONTOLARI 0;
Alınan'da VADE +31 gün, VADE_SECENEKLERI 7, FIS_ODEME_TIPI_ISKONTOLARI 1 (carinin varsayılanından geliyor olabilir).
ERP'nin kendi kaydında YAZILDI = 0 (yazdırılmadı), ACIKLAMA boş (açıklama başka alanda/tabloda olabilir).
Detay ID'si başlıktan hemen sonra (7024551 → 7024552): önce başlık, sonra satırlar aynı sayaçtan.

## SIPARIS_DETAY (her satır ayrı ID, başlıktan sonra aynı sayaçtan)
SIPARIS (başlık ID), LOKASYON 75919, STOK (ürün ID), STOK_CINSI 1, STOK_BIRIM 1012, BARKOD, KOLI_BARKODU '',
DOVIZ_AD 1, CARPAN 1, KAB 0, MIKTAR_FIS (miktar), MIKTAR_BEDELSIZ 0, ANLASMA_FIYAT 0,
FIYAT (KDV hariç birim), DAHIL_FIYAT (KDV dahil birim), TUTAR = FIYAT×MIKTAR, DAHIL_TUTAR,
ISKONTO '', ISKONTO_HESAP 0, OTV_ORAN 0, OTV_TUTAR 0, KDV_TOPTAN (oran: 1/10/20), TEVKIF 0, KUR 1, FIYAT_FARKI 0,
SERINO_ZORUNLU 0, YEREL_KARSI_FIYAT / BELGE_TARIHINDEKI_SON_ALIS_FIYATI / LISTE_FIYATI (ERP'nin hesapladığı bilgi alanları),
HK_MIKTAR_FIS '', TOPLAM_SATIR_ISKONTOSU 0, TOPLAM_FIS_ISKONTOSU 0, TOPLAM_OTV 0, TOPLAM_KDV_MATRAHI = TUTAR,
TOPLAM_KDV = TUTAR×oran/100, TOPLAM_TEVKIF 0, HESAPLANAN_FIYAT = YEREL_FIYAT = FIYAT, ACIKLAMA '', KOD (stok kodu),
ONERILEN_FIYAT 0, JOKER '', AMBALAJ_BIRIM = STOK_BIRIM, AMBALAJ_MIKTAR = MIKTAR, AMBALAJ_CARPAN 1, FK_STOK_TEVKIF_LESTE 0,
FK_PERSONEL 0, ALT_BIRIM_MIKTARI = MIKTAR, SEVK_ADRES 0, BUNDLE_DETAY 0, KT_BUNDLE_FIYAT 0.
Başlık: SATIR_TOPLAM = Σ TUTAR, KDV_TOPLAM = round(Σ TOPLAM_KDV, 2), GENELTOPLAM = Σ DAHIL_TUTAR (doğrulandı).

## Belge numarası serileri: KOD_BELGE
Bilgisayar (PC_AD) + belge türü (FK_FIS_TURU) başına seri ön eki ve ilk numara:
23 "SPRS LNN-" (alınan sipariş), 32 "SPRS VRLN-" (verilen sipariş), 31 "TKLF -", 33 "TKLF LNN -", 29 "MNT VRLN-", 34 "MNT LNN-";
ILK_NO "000001". Sayaç tutulmuyor → ERP sonraki numarayı mevcut belgelerden (aynı ön ek, en büyük + 1) hesaplıyor olmalı.
Deneme kaydı "SPRS LNN1-000001" başka bir bilgisayarın serisi (PC_AD farklı).
Plan: program KENDİ ön ekini kullanır (örn. "MOB VRLN-" / "MOB LNN-"), numara = aynı ön ekli en büyük + 1,
işlem içinde kilitle (aynı anda iki numara çakışmasın). ERP'nin kendi serileriyle karışmaz.

## Eksik
- Açıklamanın yazıldığı alan (deneme kayıtlarında ACIKLAMA boş).
- FIS_DETAY'ın da MIKTAR_FIS / DAHIL_FIYAT kullandığı doğrulanacak (hareket-gonder.ps1 buna göre güncellendi).
