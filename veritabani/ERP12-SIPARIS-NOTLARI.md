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

## Eksik
- SIPARIS_DETAY örnek satırları.
- SIPARIS_TURU değerlerinin anlamı (alınan / verilen sipariş / teklif).
- Belge numarası serisinin nereden alındığı (TKLF için sequence adı).
