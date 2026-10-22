# =====================================================================
#  MK Saha - Telefondaki Mal Giris / Mal Cikis -> ERP12 SIPARIS
# =====================================================================
#  Ne yapar: Telefondan kaydedilen Mal Giris / Mal Cikis belgelerini
#  (bulut veri tabanindan) alir ve ERP12'ye SIPARIS olarak yazar:
#    Mal Giris -> Verilen Siparis (SIPARIS_TURU 1), belge no "MK SAHA G-000001"
#    Mal Cikis -> Alinan Siparis  (SIPARIS_TURU 2), belge no "MK SAHA C-000001"
#  Siparis STOGA ve CARIYE etki etmez. ERP'de siparis acilip faturaya /
#  irsaliyeye cevrilir; faturayi ERP kendisi olusturur.
#
#  Fiyatlar:
#    Verilen siparis: urunun ERP'deki SON ALIS fiyati (KDV haric).
#    Alinan siparis : telefondaki fiyat (katalogdaki KDV dahil satis fiyati).
#
#  Guvenlik:
#  - DENEME: "siparis-aktar.ps1 DENEME" her seyi hesaplar, ERP'ye YAZMAZ
#    (islem geri alinir), ne yazilacagini log'a yazar.
#  - Her belge tek bir islemde (transaction) yazilir: ya hepsi ya hicbiri.
#  - Numaralar ERP'nin kendi ortak sayacindan (dbo.ID) alinir.
#  - Ayni belge iki kez aktarilmaz (bulut kaydi + yerel liste).
#  - Aktarildiktan sonra telefonda degistirilen belgeye DOKUNULMAZ, sadece
#    uyari yazilir (duzeltme ERP'de elle yapilir).
#  - Telefonda kaydedildikten sonra $BekleDakika dakika beklenir (personel
#    hala duzeltiyor olabilir).
# =====================================================================

# ---------------------- AYARLAR ----------------------
$script:Argumanlar = @($args | ForEach-Object { ([string]$_).ToUpperInvariant().TrimStart("-") })
$Deneme           = $script:Argumanlar -contains "DENEME"
$SqlServer        = "SERVER\ERP12"
# Bos: ERP12'nin AKTIF yil veri tabani otomatik bulunur (son 7 gunde belge girilen en yeni).
# Elle sabitlemek icin: "ERP122025"
$Database         = ""
$DbUrl            = "https://wjyqempcmyrmruhdpcwk.supabase.co"
$DbAnahtarDosyasi = "C:\Scripts\db-anahtar.txt"
$LogFile          = "C:\Scripts\siparis-aktar-log.txt"
$AktarilanDosya   = "C:\Scripts\siparis-aktarilan.txt"
# ERP'de stok karti olmayan urunler: belge BEKLER (eksik siparis yazilmaz), liste bu dosyaya yazilir.
# Kart ERP'de ayni barkodla acilinca bir sonraki calismada belge kendiliginden aktarilir.
$EksikKartDosya   = "C:\Scripts\acilacak-stok-kartlari.txt"
$HataDosya        = "C:\Scripts\siparis-aktar-hata.txt"
# STOK KARTI OLMAYAN URUN: ERP'deki sablon karttan (MK SAHA SABLON, barkod MKSABLON / 99999001) kopyalanarak
# gecici kart acilir (KDV, grup, birim sablondaki gibi; fiyat 0; stok kodu MKS-000000001...). Muhasebe sonra duzenler.
# Terazi barkodu (13 haneli 27/28/29 ile baslayan ya da 7 ve daha kisa) ve barkodsuz urune kart ACILMAZ.
$KartAc           = $true
$KartSeri         = "MKS-"
$AcilanKartDosya  = "C:\Scripts\acilan-stok-kartlari.txt"
# Bu tarihten ONCE telefonda olusturulan belgeler aktarilmaz (gecmisi doldurmasin).
$BaslangicTarihi  = "2026-10-21"
$BekleDakika      = 0   # telefon belgeyi tek seferde kaydeder; beklemeye gerek yok
$SeriVerilen      = "MK SAHA G-"
$SeriAlinan       = "MK SAHA C-"
# AKTARIM TURU: "IRSALIYE" = telefondaki irsaliye turu ERP'ye AYNI TURDE irsaliye olarak yazilir (stogu etkiler):
#   Alis Irsaliyesi -> Alis irsaliyesi (5), Satis Irsaliyesi -> Satis irsaliyesi (6),
#   Alistan Iade Irsaliyesi -> Alistan iade irsaliyesi (7), Satistan Iade Irsaliyesi -> Satistan iade irsaliyesi (8).
#   ERP'nin el terminalinin (mobil) actigi irsaliyelerle ayni bicimde yazilir (MOBIL_MI = 1); cariye etki etmez.
#   "SIPARIS" = eski yol: Verilen / Alinan Siparis (stoga dokunmaz).
$AktarimTuru      = "IRSALIYE"
$IrsSeri          = @{ 5 = "MK SAHA AL-"; 6 = "MK SAHA ST-"; 7 = "MK SAHA AI-"; 8 = "MK SAHA SI-" }
$IrsBasim         = @{ 5 = 7; 6 = 11; 7 = 10; 8 = 7 }
# -----------------------------------------------------

try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}
$Inv = [Globalization.CultureInfo]::InvariantCulture

function Yaz-Log($mesaj) {
    $satir = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $mesaj"
    Write-Host $satir
    try { Add-Content -Path $LogFile -Value $satir -ErrorAction SilentlyContinue } catch {}
}

function Rpc($fonksiyon, $govde) {
    $json = $govde | ConvertTo-Json -Depth 6 -Compress
    $baytlar = [System.Text.Encoding]::UTF8.GetBytes($json)
    return Invoke-RestMethod -Uri "$DbUrl/rest/v1/rpc/$fonksiyon" -Method Post -Body $baytlar `
        -ContentType "application/json; charset=utf-8" -Headers @{ apikey = $script:Anahtar } -TimeoutSec 120 -UserAgent "MK-Sayim/1.0"
}

function Bildir($b, $siparisId, $belgeNo, $durum, $mesaj) {
    $r = Rpc "siparis_aktarildi" @{ p_batch = [string]$b.batch_id; p_tip = [string]$b.tip; p_kaynak = $Database; p_siparis_id = $siparisId
        p_belge_no = $belgeNo; p_imza = [string]$b.imza; p_durum = $durum; p_mesaj = $mesaj }
    if (-not $r -or [string]$r.status -ne "ok") { throw "Buluta bildirilemedi: $($r | ConvertTo-Json -Compress)" }
}

function Sql($tx, $sql, $param) {
    $cmd = $tx.Connection.CreateCommand(); $cmd.Transaction = $tx; $cmd.CommandText = $sql; $cmd.CommandTimeout = 120
    if ($param) { foreach ($k in $param.Keys) { $v = $param[$k]; if ($v -eq $null) { $v = [DBNull]::Value }; [void]$cmd.Parameters.AddWithValue($k, $v) } }
    return $cmd
}
function Deger($tx, $sql, $param) { $v = (Sql $tx $sql $param).ExecuteScalar(); if ($v -is [DBNull]) { return $null }; return $v }
function Tablo($tx, $sql, $param) {
    $da = New-Object System.Data.SqlClient.SqlDataAdapter((Sql $tx $sql $param))
    $dt = New-Object System.Data.DataTable; [void]$da.Fill($dt); return ,$dt
}
function Yuvarla($x, $n) { return [Math]::Round([decimal]$x, $n, [MidpointRounding]::AwayFromZero) }
function Kisalt($s, $n) { $s = [string]$s; if ($n -gt 0 -and $s.Length -gt $n) { return $s.Substring(0, $n) }; return $s }

$SIP_KOLON = @("ID","SIPARIS_TURU","LOKASYON","CARI","CARI_ADRES","PROJE","BELGENO","SIPARIS_TARIHI","TERMIN_TARIHI","ISLEM_TARIHI","VADE_TARIHI",
    "DOVIZ_AD","DOVIZ_KUR","CARI_PERSONEL","SATIR_TOPLAM","SATIR_ISKONTO_TOPLAM","SIPARIS_ISKONTO_ORAN","SIPARIS_ISKONTO_TOPLAM","YUVARLAMA",
    "KDV_TOPLAM","OTV_TOPLAM","TEFKIFAT_TOPLAM","GENELTOPLAM","ACIKLAMA","FIS","AKTIF","SIPARIS_OZEL_KOD_1","SIPARIS_OZEL_KOD_2",
    "SIPARIS_OZEL_KOD_3","SIPARIS_OZEL_KOD_4","SIPARIS_OZEL_KOD_5","GONDERIM_ADRESI","ONAYLI","VADE_SECENEKLERI","BELGE_YETKILISI",
    "YAZILDI","EMAIL_GONDERILDI","NAKLIYE_ODEME_TIPI","SEVK_SEKLI","KARSI_SIPARIS_NO","ARTTIRIM","DOVIZ_KUR_SECIMI",
    "FIS_ODEME_TIPI_ISKONTOLARI","IHRACAT_GONDERIM_SEKLI","IHRACAT_TESLIM_SEKLI","FIS_ALT_TIPI")
$DET_KOLON = @("ID","SIPARIS","LOKASYON","STOK","STOK_CINSI","STOK_BIRIM","BARKOD","KOLI_BARKODU","DOVIZ_AD","CARPAN","KAB","MIKTAR_FIS",
    "MIKTAR_BEDELSIZ","ANLASMA_FIYAT","FIYAT","DAHIL_FIYAT","TUTAR","DAHIL_TUTAR","ISKONTO","ISKONTO_HESAP","OTV_ORAN","OTV_TUTAR",
    "KDV_TOPTAN","TEVKIF","KUR","FIYAT_FARKI","SERINO_ZORUNLU","YEREL_KARSI_FIYAT","BELGE_TARIHINDEKI_SON_ALIS_FIYATI","HK_MIKTAR_FIS",
    "TOPLAM_SATIR_ISKONTOSU","TOPLAM_FIS_ISKONTOSU","TOPLAM_OTV","TOPLAM_KDV_MATRAHI","TOPLAM_KDV","TOPLAM_TEVKIF","HESAPLANAN_FIYAT",
    "YEREL_FIYAT","ACIKLAMA","KOD","ONERILEN_FIYAT","JOKER","AMBALAJ_BIRIM","AMBALAJ_MIKTAR","AMBALAJ_CARPAN","FK_STOK_TEVKIF_LESTE",
    "FK_PERSONEL","ALT_BIRIM_MIKTARI","SEVK_ADRES","BUNDLE_DETAY","KT_BUNDLE_FIYAT","LISTE_FIYATI")

function Ekle($tx, $tablo, $kolonlar, $deger) {
    $p = @{}; foreach ($k in $kolonlar) { $p["@$k"] = $deger[$k] }
    $sql = "INSERT INTO dbo.$tablo (" + ($kolonlar -join ", ") + ") VALUES (" + (($kolonlar | ForEach-Object { "@$_" }) -join ", ") + ")"
    [void](Sql $tx $sql $p).ExecuteNonQuery()
}

# Sablon satirini kopyalar: tablonun tum sutunlari sablondan, $ust'teki sutunlar verilen degerle.
function Kopyala($tx, $tablo, $kaynakId, $ust) {
    $kol = @((Tablo $tx "SELECT c.name FROM sys.columns c JOIN sys.types y ON y.user_type_id = c.user_type_id WHERE c.object_id = OBJECT_ID('dbo.$tablo') AND c.is_computed = 0 AND c.is_identity = 0 AND y.name NOT IN ('timestamp','rowversion') ORDER BY c.column_id" $null).Rows | ForEach-Object { [string]$_.name })
    $p = @{ "@kaynak" = $kaynakId }; $sec = @()
    foreach ($k in $kol) { if ($ust.ContainsKey($k)) { $p["@u_$k"] = $ust[$k]; $sec += "@u_$k" } else { $sec += "[$k]" } }
    $sql = "INSERT INTO dbo.[$tablo] (" + (($kol | ForEach-Object { "[$_]" }) -join ", ") + ") SELECT " + ($sec -join ", ") + " FROM dbo.[$tablo] WHERE ID = @kaynak"
    $n = (Sql $tx $sql $p).ExecuteNonQuery()
    if ($n -ne 1) { throw "$tablo kopyalanamadi (sablon satiri $kaynakId)" }
}
# ERP'nin her yeni kayit icin tuttugu sayac kaydi (hangi tablo, hangi bilgisayar).
function Sayac($tx, $id, $tablo, $kodPc) {
    if ($kodPc -eq $null) { return }
    [void](Sql $tx "IF NOT EXISTS (SELECT 1 FROM dbo.SEQUNCES WHERE ID = @i) INSERT INTO dbo.SEQUNCES (ID, TABLO, KOD_PC) VALUES (@i, @t, @p)" @{ "@i" = $id; "@t" = $tablo; "@p" = $kodPc }).ExecuteNonQuery()
}
# Terazi bayraklari (ERP FIRMASABITLERI): 29, 28, 26 tartim, 24 tutar, 27 adet.
function Terazi($bar) { return ($bar.Length -le 7) -or ($bar.Length -eq 13 -and @("24","26","27","28","29") -contains $bar.Substring(0, 2)) }
# Stok karti olmayan urune sablondan gecici kart acar. Doner: yeni STOK ID ya da $null (acilamazsa).
function Kart-Ac($tx, $r, $b) {
    if (-not $KartAc) { return $null }
    $bar = ([string]$r.barkod).Trim()
    if (-not $bar -or $bar.Length -gt 20 -or (Terazi $bar)) { return $null }
    $sab = Deger $tx "SELECT TOP 1 STOK FROM dbo.STOK_BARKOD_BIRIM WHERE BARKOD IN ('MKSABLON', '99999001') ORDER BY CASE WHEN BARKOD = 'MKSABLON' THEN 0 ELSE 1 END" $null
    if (-not $sab) { throw "Sablon stok karti bulunamadi: ERP'de 'MK SAHA SABLON' kartini barkod MKSABLON (ya da 99999001) ile acin" }
    $sabBirim = Deger $tx "SELECT TOP 1 ID FROM dbo.STOK_STOK_BIRIM WHERE STOK = @s ORDER BY VARSAYILAN DESC, ID" @{ "@s" = $sab }
    $sabBarkod = Deger $tx "SELECT TOP 1 ID FROM dbo.STOK_BARKOD WHERE STOK_STOK_BIRIM = @u ORDER BY ID" @{ "@u" = $sabBirim }
    if (-not $sabBirim -or -not $sabBarkod) { throw "Sablon stok kartinin birimi / barkodu eksik" }
    $sabFiyat = @((Tablo $tx "SELECT ID FROM dbo.STOK_STOK_BIRIM_FIYAT WHERE STOK_STOK_BIRIM = @u ORDER BY ID" @{ "@u" = $sabBirim }).Rows | ForEach-Object { $_.ID })
    $kodPc = Deger $tx "SELECT KOD_PC FROM dbo.SEQUNCES WHERE ID = @s" @{ "@s" = $sab }
    # Stok kodu: kendi serimiz (MKS-000000001...), kilitli
    # 9 haneli (MKS-000000001). Yalniz bu uzunluktaki kodlar sayilir (yazi siralamasi karismasin).
    $son = Deger $tx "SELECT MAX(KOD) FROM dbo.STOK WITH (UPDLOCK, HOLDLOCK) WHERE KOD LIKE @p AND LEN(KOD) = @n" @{ "@p" = "$KartSeri%"; "@n" = ($KartSeri.Length + 9) }
    $no = 1; if ($son) { $no = [long]([string]$son).Substring($KartSeri.Length) + 1 }
    $kod = $KartSeri + $no.ToString("000000000")
    $ad = ([string]$r.urun_adi).Trim()
    if (-not $ad -or $ad -match '^\s*.simsiz') { $ad = "MK SAHA YENI URUN $bar" }
    $ad = Kisalt $ad 100
    $sira = $null
    if ([int](Deger $tx "SELECT COUNT(*) FROM sys.sequences WHERE name = 'SATIR_NO'" $null) -gt 0) { $sira = [long](Deger $tx "SELECT NEXT VALUE FOR dbo.SATIR_NO" $null) }
    else { $sira = [long](Deger $tx "SELECT ISNULL(MAX(SIRA), 0) + 1 FROM dbo.STOK" $null) }
    $sid = [long](Deger $tx "SELECT NEXT VALUE FOR dbo.ID" $null)
    Kopyala $tx "STOK" $sab @{ ID = $sid; KOD = $kod; AD = $ad; SIRA = $sira }
    Sayac $tx $sid "STOK" $kodPc
    $uid = [long](Deger $tx "SELECT NEXT VALUE FOR dbo.ID" $null)
    Kopyala $tx "STOK_STOK_BIRIM" $sabBirim @{ ID = $uid; STOK = $sid }
    Sayac $tx $uid "STOK_STOK_BIRIM" $kodPc
    foreach ($f in $sabFiyat) {
        $fid = [long](Deger $tx "SELECT NEXT VALUE FOR dbo.ID" $null)
        Kopyala $tx "STOK_STOK_BIRIM_FIYAT" $f @{ ID = $fid; STOK_STOK_BIRIM = $uid; FIYAT = [decimal]0 }
        Sayac $tx $fid "STOK_STOK_BIRIM_FIYAT" $kodPc
    }
    $bid = [long](Deger $tx "SELECT NEXT VALUE FOR dbo.ID" $null)
    $bsira = [int](Deger $tx "SELECT ISNULL(MAX(unboundSIRA), 0) + 1 FROM dbo.STOK_BARKOD WITH (UPDLOCK, HOLDLOCK)" $null)
    Kopyala $tx "STOK_BARKOD" $sabBarkod @{ ID = $bid; STOK_STOK_BIRIM = $uid; BARKOD = $bar; unboundSIRA = $bsira }
    Sayac $tx $bid "STOK_BARKOD" $kodPc
    [void]$script:AcilanKart.Add(("{0}`t{1}`t{2}`t{3}`t{4} x {5}`t{6} ({7})" -f (Get-Date -Format "yyyy-MM-dd HH:mm"), $kod, $bar, $ad, $b.tip, $r.miktar, $b.cari, $b.belge_turu))
    Yaz-Log "$(if ($Deneme) { 'DENEME: acilacakti' } else { 'YENI STOK KARTI' }): $kod / $bar / $ad (sablondan, fiyat 0)"
    return $sid
}

# Telefondaki belge turunden ERP irsaliye turu (0 = irsaliye degil).
function Irsaliye-Turu($b) {
    $bt = ([string]$b.belge_turu).Trim()
    if ($bt -notmatch 'rsaliye') { return 0 }
    if ($bt -match 'ade') { if ($bt -match '^Al') { return 7 } else { return 8 } }
    if (([string]$b.tip).StartsWith("G")) { return 5 } else { return 6 }
}

$FIS_KOLON = @("ID","FIS_TURU","LOKASYON","CARI","CARI_ADRES","GONDERIM_ADRESI","PROJE","BELGENO","FIS_TARIHI","ISLEM_TARIHI","SEVK_TARIHI",
    "DOVIZ_AD","DOVIZ_KUR","CARI_PERSONEL","SATIR_TOPLAM","SATIR_ISKONTO_TOPLAM","FIS_ISKONTO_TOPLAM","YUVARLAMA","KDV_TOPLAM","OTV_TOPLAM",
    "TEFKIFAT_TOPLAM","GENELTOPLAM","DURUM","VADE","VADE_SECENEKLERI","YAZAR_KASA_NO","FIS_CARIYI_ETKILERMI","CARI_DOVIZ_AD","CARI_DOVIZ_KUR",
    "CARI_TAKIP_SEKLI","AKTIF","SEVKIYAT_YAPILSIN","MOBIL_MI","FIS_SEZON","MARKET_KASA_TERAZI_MARKALARI","FIS_BASIM_TIPI","KARGO_CARISI",
    "INTERNET_ODEME_SEKLI","VIO_MUHENTYAPILDI","ONAY_BEKLIYOR","BAGKUR_ORAN","BAGKUR_TUTAR","STOPAJ_ORAN","STOPAJ_TUTAR","BORSA_ORAN","BORSA_TUTAR",
    "MERA_ORAN","MERA_TUTAR","TEVKIF","FIS_OZEL_KOD_1","FIS_OZEL_KOD_2","FIS_OZEL_KOD_3","FIS_OZEL_KOD_4","FIS_OZEL_KOD_5","BELGE_YETKILISI",
    "YAZILDI","EMAIL_GONDERILDI","NAKLIYE_ODEME_TIPI","SEVK_SEKLI","ARTTIRIM","IHRACAT_GONDERIM_SEKLI","IHRACAT_TESLIM_SEKLI","VERGI_MUAFIYET_KODU",
    "E_FATURA_KABUL_DURUMU","DOVIZ_KUR_SECIMI","FIS_ODEME_TIPI_ISKONTOLARI","FIS_STOK_HAREKETLERINI_ETKILER","FIS_ALT_TIPI","SGK_DONEM_BASLANGIC",
    "SGK_DONEM_BITIS","MUHASEBELESTI","PAREKENDE_KDV_KULLAN","ODEMEMNIN_YAPILDIGI_TARIH","GONDERIM_TARIHI","SEVK_NEDENI","ASIL_SATICI_CARISI",
    "HAREKET_TARIHI","SATIR_STOPAJ_TOPLAM","ALIS_BELGE_TARIHI","ALIS_BELGE_TARIHI_2","ALIS_BELGE_TARIHI_3","ALIS_BELGE_TARIHI_4","ALIS_BELGE_TARIHI_5",
    "E_FATURA_TIPI")
$FISD_KOLON = @("ID","FIS","LOKASYON","STOK","STOK_CINSI","STOK_BIRIM","BARKOD","DOVIZ_AD","CARPAN","KAB","MIKTAR_FIS","MIKTAR_BEDELSIZ",
    "MIKTAR_GIRIS","MIKTAR_CIKIS","ANLASMA_FIYAT","FIYAT","DAHIL_FIYAT","TUTAR","DAHIL_TUTAR","ISKONTO_HESAP","OTV_ORAN","OTV_TUTAR","KDV_TOPTAN",
    "TEVKIF","KUR","PUAN","FIYAT_FARKI","SERINO_ZORUNLU","FK_PERSONEL","SATIR","YEREL_KARSI_FIYAT","BELGE_TARIHINDEKI_SON_ALIS_FIYATI",
    "FATRALANDIRILMIS_IRSALIYEMI","URETILENMI","FK_VERGI_MUAFIYET_KODU","TOPLAM_SATIR_ISKONTOSU","TOPLAM_FIS_ISKONTOSU","TOPLAM_OTV",
    "TOPLAM_KDV_MATRAHI","TOPLAM_KDV","TOPLAM_TEVKIF","HESAPLANAN_FIYAT","PRIM","FIS_DETAY_SATIR_TURU","LISTE_FIYATI","RECETE_MALIYET_ORANI",
    "RECETE","PARTINO_ZORUNLU","YEREL_FIYAT","FIS_TARIHI","ISLENDI","KOD","BAGLI_SATIR","FIS_TURU","MASA","AMBALAJ_BIRIM","AMBALAJ_MIKTAR",
    "AMBALAJ_CARPAN","POS_PROMASYON","POS_PROMASYON_TOPLAM","FK_STOK_TEVKIF_LESTE","LOKASYON_MALIYETI","MALIYET_ELLE_GIRILDI","ALT_BIRIM_MIKTARI",
    "ANLASMA_DETAY_ID","STOK_FIYAT_AD","BURUT","FIRE","FIYAT_MANUEL_GIRILDI","FK_IHRACAT_KAB_CINSI","IHRACAT_KAB_NO","IHRACAT_KAB_ADET",
    "PARTI_NO_SON_KULLANMA_TARIHI","BUNDLE_DETAY","FK_GIDER_YERI","KT_BUNDLE_FIYAT","SATIR_STOPAJ_TUTAR","URETIM_TARIHI","FK_E_FATURA_SATIR_TIPI")

# Bir telefon belgesini ERP'ye IRSALIYE olarak yaz. Doner: @{ id; belge; uyari; satir }
function Irsaliye-Yaz($baglanti, $b) {
    $tur = Irsaliye-Turu $b
    if ($tur -eq 0) { throw "Irsaliye turu degil ($($b.belge_turu)); ERP'ye aktarilmaz" }
    $giris = ($tur -eq 5 -or $tur -eq 8)
    if ($giris -ne ([string]$b.tip).StartsWith("G")) { throw "Belge turu ($($b.belge_turu)) ile hareket yonu ($($b.tip)) uyusmuyor" }
    $tx = $baglanti.BeginTransaction([System.Data.IsolationLevel]::Serializable)
    try {
        $cari = $null
        if ([string]$b.cari_kodu) { $cari = Deger $tx "SELECT TOP 1 ID FROM dbo.CARI WHERE KOD = @k ORDER BY ID" @{ "@k" = [string]$b.cari_kodu } }
        if (-not $cari -and [string]$b.cari) { $cari = Deger $tx "SELECT TOP 1 ID FROM dbo.CARI WHERE AD = @a ORDER BY ID" @{ "@a" = [string]$b.cari } }
        if (-not $cari) { throw "Cari ERP'de bulunamadi: '$($b.cari)' (kod '$($b.cari_kodu)')" }
        $adres = Deger $tx "SELECT TOP 1 ID FROM dbo.CARI_ADRES WHERE CARI = @c ORDER BY ID" @{ "@c" = $cari }
        if (-not $adres) { $adres = 0 }
        $lp = Tablo $tx "SELECT TOP 1 LOKASYON, PROJE FROM dbo.FIS WHERE FIS_TURU = @t AND BELGENO NOT LIKE 'MK SAHA%' ORDER BY ID DESC" @{ "@t" = $tur }
        if ($lp.Rows.Count -eq 0) { $lp = Tablo $tx "SELECT TOP 1 LOKASYON, PROJE FROM dbo.FIS ORDER BY ID DESC" $null }
        $lokasyon = $lp.Rows[0].LOKASYON; $proje = $lp.Rows[0].PROJE

        # --- Belge no: alis / satistan iade: tedarikcinin (karsi tarafin) belge no'su; yoksa kendi serimiz ---
        $belgeNo = ([string]$b.belge_no).Trim()
        if ($belgeNo -and ($tur -eq 5 -or $tur -eq 8)) {
            $turler = if ($tur -eq 5) { "1, 5" } else { "4, 8" }
            $var = [int](Deger $tx "SELECT COUNT(*) FROM dbo.FIS WHERE CARI = @c AND BELGENO = @n AND AKTIF = 1 AND FIS_TURU IN ($turler)" @{ "@c" = $cari; "@n" = $belgeNo })
            if ($var -gt 0) { throw "ERP'de bu cariye $belgeNo numarali belge ZATEN VAR (Excel ile alinmis olabilir). Mal iki kez girmesin diye aktarilmadi." }
        } else {
            # Belge no girilmediyse: kaydin tarih-saat-dakikasi (MKS202610221634). Ayni dakikada ikinci belge: sonuna 2, 3... (tire yok)
            # Muhasebe gercek numarayi ERP'de duzeltir.
            $kayitZamani = [DateTimeOffset]::Parse([string]$b.tarih, $Inv).LocalDateTime
            $temel = "MKS" + $kayitZamani.ToString("yyyyMMddHHmm", $Inv)
            $belgeNo = $temel; $ek = 2
            while ([int](Deger $tx "SELECT COUNT(*) FROM dbo.FIS WITH (UPDLOCK, HOLDLOCK) WHERE BELGENO = @n" @{ "@n" = $belgeNo }) -gt 0) { $belgeNo = "$temel$ek"; $ek++ }
        }

        $kdvKolon = Deger $tx "SELECT TOP 1 name FROM sys.columns WHERE object_id = OBJECT_ID('dbo.STOK_VERGI') AND name IN ('KDV_TOPTAN','KDV_PAREKENDE') ORDER BY CASE name WHEN 'KDV_TOPTAN' THEN 0 ELSE 1 END" $null
        $satirlar = New-Object System.Collections.ArrayList
        $kartsiz = New-Object System.Collections.ArrayList
        foreach ($r in @($b.satirlar)) {
            if (-not $r) { continue }
            $bbSql = "SELECT TOP 1 bb.STOK, bb.STOK_BIRIM, s.KOD, ISNULL(v.$kdvKolon, 0) AS KDV, bb.BARKOD FROM dbo.STOK_BARKOD_BIRIM bb JOIN dbo.STOK s ON s.ID = bb.STOK LEFT JOIN dbo.STOK_VERGI v ON v.ID = s.STOK_VERGI WHERE bb.BARKOD = @b"
            $bar = ([string]$r.barkod).Trim()
            $bb = Tablo $tx $bbSql @{ "@b" = $bar }
            # Terazi etiketi (13 hane, 26-29 ile baslar): ERP'deki urun barkodu ilk 7 hanedir.
            if ($bb.Rows.Count -eq 0 -and $bar.Length -eq 13 -and @("24","26","27","28","29") -contains $bar.Substring(0, 2)) { $bb = Tablo $tx $bbSql @{ "@b" = $bar.Substring(0, 7) } }
            if ($bb.Rows.Count -eq 0 -and (Kart-Ac $tx $r $b)) { $bb = Tablo $tx $bbSql @{ "@b" = $bar } }
            if ($bb.Rows.Count -eq 0) {
                [void]$kartsiz.Add("$bar $($r.urun_adi)")
                $script:EksikKart["$bar"] = ("{0}`t{1}`t{2} x {3}`t{4} ({5})" -f $bar, $r.urun_adi, $b.tip, $r.miktar, $b.cari, $b.belge_turu)
                continue
            }
            $stok = $bb.Rows[0].STOK; $birim = $bb.Rows[0].STOK_BIRIM; $kdv = [decimal]$bb.Rows[0].KDV; $miktar = [decimal]$r.miktar
            $sonAlis = Deger $tx "SELECT TOP 1 d.FIYAT FROM dbo.FIS_DETAY d JOIN dbo.FIS f ON f.ID = d.FIS WHERE d.STOK = @s AND d.STOK_BIRIM = @u AND f.FIS_TURU IN (1, 5) AND f.AKTIF = 1 AND d.FIYAT > 0 AND d.MIKTAR_FIS > 0 ORDER BY f.FIS_TARIHI DESC, d.ID DESC" @{ "@s" = $stok; "@u" = $birim }
            # Bu birimde alis yoksa: stok kartindaki son alis fiyati (ERP'nin kendi tuttugu), o da yoksa 0.
            if ($sonAlis -eq $null -or [decimal]$sonAlis -le 0) { $sonAlis = Deger $tx "SELECT SON_ALIS_FIYAT FROM dbo.STOK WHERE ID = @s AND SON_ALIS_FIYAT > 0" @{ "@s" = $stok } }
            if ($sonAlis -eq $null) { $sonAlis = [decimal]0 } else { $sonAlis = [decimal]$sonAlis }
            $satirAcik = ""
            if ($tur -eq 5 -or $tur -eq 7) {
                $fiyat = $sonAlis; $dahil = Yuvarla ($fiyat * (1 + $kdv / 100)) 4
            } elseif ($tur -eq 6) {
                # SATIS: bu cariye EN SON verdigimiz fiyat esas (net, KDV haric).
                #  - O satistan SONRA urun farkli alis fiyatiyla geldiyse: normal urun fiyati (telefondaki katalog fiyati) yazilir,
                #    satir aciklamasina "Kontrol T.E.F. ........ <fiyat>" yazilir: son satistaki kar orani yeni alisa uygulanmis hali.
                #  - Bu cariye daha once satis yoksa: normal urun fiyati.
                $normalDahil = if ($r.fiyat -ne $null -and [decimal]$r.fiyat -gt 0) { [decimal]$r.fiyat } else { [decimal]0 }
                $ss = Tablo $tx "SELECT TOP 1 f.FIS_TARIHI AS T, CAST(d.TOPLAM_KDV_MATRAHI AS decimal(18,6)) / NULLIF(d.MIKTAR_FIS, 0) AS NET FROM dbo.FIS_DETAY d JOIN dbo.FIS f ON f.ID = d.FIS WHERE f.CARI = @c AND d.STOK = @s AND d.STOK_BIRIM = @u AND f.FIS_TURU IN (2, 6) AND f.AKTIF = 1 AND d.MIKTAR_FIS > 0 AND d.FIYAT > 0 ORDER BY f.FIS_TARIHI DESC, d.ID DESC" @{ "@c" = $cari; "@s" = $stok; "@u" = $birim }
                $fiyat = $null
                if ($ss.Rows.Count -gt 0 -and $ss.Rows[0].NET -isnot [DBNull] -and [decimal]$ss.Rows[0].NET -gt 0) {
                    $sonSatis = [decimal]$ss.Rows[0].NET; $satisT = $ss.Rows[0].T
                    $alisSql = "SELECT TOP 1 CAST(d.TOPLAM_KDV_MATRAHI AS decimal(18,6)) / NULLIF(d.MIKTAR_FIS, 0) AS NET FROM dbo.FIS_DETAY d JOIN dbo.FIS f ON f.ID = d.FIS WHERE d.STOK = @s AND d.STOK_BIRIM = @u AND f.FIS_TURU IN (1, 5) AND f.AKTIF = 1 AND d.MIKTAR_FIS > 0 AND d.FIYAT > 0 AND f.FIS_TARIHI {0} @t ORDER BY f.FIS_TARIHI DESC, d.ID DESC"
                    $aOnce = Deger $tx ($alisSql -f "<=") @{ "@s" = $stok; "@u" = $birim; "@t" = $satisT }
                    $aSonra = Deger $tx ($alisSql -f ">") @{ "@s" = $stok; "@u" = $birim; "@t" = $satisT }
                    if ($aSonra -ne $null -and $aOnce -ne $null -and [decimal]$aOnce -gt 0 -and [Math]::Abs([decimal]$aSonra - [decimal]$aOnce) -gt 0.005) {
                        # Alis fiyati degisti: normal fiyat + aciklamada kontrol fiyati
                        $oran = $sonSatis / [decimal]$aOnce
                        $tef = Yuvarla ([decimal]$aSonra * $oran) 2
                        $satirAcik = "Kontrol T.E.F. ........ " + $tef.ToString("0.00", [Globalization.CultureInfo]::GetCultureInfo("tr-TR"))
                    } else {
                        $fiyat = Yuvarla $sonSatis 4
                    }
                }
                if ($fiyat -eq $null) { $dahil = $normalDahil; $fiyat = Yuvarla ($dahil / (1 + $kdv / 100)) 4 }
                else { $dahil = Yuvarla ($fiyat * (1 + $kdv / 100)) 4 }
            } else {
                $dahil = if ($r.fiyat -ne $null -and [decimal]$r.fiyat -gt 0) { [decimal]$r.fiyat } else { [decimal]0 }
                $fiyat = Yuvarla ($dahil / (1 + $kdv / 100)) 4
            }
            $tutar = Yuvarla ($fiyat * $miktar) 4
            [void]$satirlar.Add(@{ stok = $stok; birim = $birim; kod = [string]$bb.Rows[0].KOD; barkod = [string]$bb.Rows[0].BARKOD; ad = [string]$r.urun_adi
                kdv = $kdv; miktar = $miktar; fiyat = $fiyat; dahil = $dahil; tutar = $tutar; dahilTutar = (Yuvarla ($dahil * $miktar) 4)
                kdvTutar = (Yuvarla ($tutar * $kdv / 100) 4); sonAlis = $sonAlis; acik = $satirAcik })
        }
        # Irsaliye stogu degistirir: ERP'de karsiligi olmayan urun varsa belge YAZILMAZ (eksik irsaliye olmasin), bekler.
        if ($kartsiz.Count -gt 0) { throw "ERP'de stok karti yok / acilamadi (terazi ya da barkodsuz): $($kartsiz -join ', '). Kart acilinca aktarilir." }
        if ($satirlar.Count -eq 0) { throw "Belgede urun yok" }

        $id = [long](Deger $tx "SELECT NEXT VALUE FOR dbo.ID" $null)
        $tarih = [DateTimeOffset]::Parse([string]$b.tarih, $Inv).LocalDateTime
        $gun = $tarih.Date; $simdi = Get-Date
        $satirToplam = ($satirlar | ForEach-Object { $_.tutar } | Measure-Object -Sum).Sum
        $kdvToplam = ($satirlar | ForEach-Object { $_.kdvTutar } | Measure-Object -Sum).Sum
        $genel = ($satirlar | ForEach-Object { $_.dahilTutar } | Measure-Object -Sum).Sum
        Ekle $tx "FIS" $FIS_KOLON @{ ID = $id; FIS_TURU = $tur; LOKASYON = $lokasyon; CARI = $cari; CARI_ADRES = $adres; GONDERIM_ADRESI = $adres; PROJE = $proje
            BELGENO = $belgeNo; FIS_TARIHI = $tarih; ISLEM_TARIHI = $simdi; SEVK_TARIHI = $tarih; DOVIZ_AD = 1; DOVIZ_KUR = 1; CARI_PERSONEL = 0
            SATIR_TOPLAM = (Yuvarla $satirToplam 2); SATIR_ISKONTO_TOPLAM = 0; FIS_ISKONTO_TOPLAM = 0; YUVARLAMA = 0; KDV_TOPLAM = (Yuvarla $kdvToplam 2)
            OTV_TOPLAM = 0; TEFKIFAT_TOPLAM = 0; GENELTOPLAM = (Yuvarla $genel 2); DURUM = $true; VADE = $gun.AddDays(30); VADE_SECENEKLERI = 7
            YAZAR_KASA_NO = 0; FIS_CARIYI_ETKILERMI = $false; CARI_DOVIZ_AD = 1; CARI_DOVIZ_KUR = 1; CARI_TAKIP_SEKLI = 1; AKTIF = $true
            SEVKIYAT_YAPILSIN = $false; MOBIL_MI = $true; FIS_SEZON = 0; MARKET_KASA_TERAZI_MARKALARI = 300; FIS_BASIM_TIPI = $IrsBasim[$tur]
            KARGO_CARISI = 0; INTERNET_ODEME_SEKLI = 0; VIO_MUHENTYAPILDI = " "; ONAY_BEKLIYOR = $false; BAGKUR_ORAN = 0; BAGKUR_TUTAR = 0
            STOPAJ_ORAN = 0; STOPAJ_TUTAR = 0; BORSA_ORAN = 0; BORSA_TUTAR = 0; MERA_ORAN = 0; MERA_TUTAR = 0; TEVKIF = $false
            FIS_OZEL_KOD_1 = 0; FIS_OZEL_KOD_2 = 0; FIS_OZEL_KOD_3 = 0; FIS_OZEL_KOD_4 = 0; FIS_OZEL_KOD_5 = 0; BELGE_YETKILISI = 0; YAZILDI = $false
            EMAIL_GONDERILDI = $false; NAKLIYE_ODEME_TIPI = 0; SEVK_SEKLI = 0; ARTTIRIM = 0; IHRACAT_GONDERIM_SEKLI = 0; IHRACAT_TESLIM_SEKLI = 0
            VERGI_MUAFIYET_KODU = 0; E_FATURA_KABUL_DURUMU = 0; DOVIZ_KUR_SECIMI = 2; FIS_ODEME_TIPI_ISKONTOLARI = 0; FIS_STOK_HAREKETLERINI_ETKILER = $true
            FIS_ALT_TIPI = 1; SGK_DONEM_BASLANGIC = $gun; SGK_DONEM_BITIS = $gun; MUHASEBELESTI = $false; PAREKENDE_KDV_KULLAN = $false
            ODEMEMNIN_YAPILDIGI_TARIH = $gun; GONDERIM_TARIHI = $gun; SEVK_NEDENI = 0; ASIL_SATICI_CARISI = 0; HAREKET_TARIHI = $simdi; SATIR_STOPAJ_TOPLAM = 0
            ALIS_BELGE_TARIHI = $gun; ALIS_BELGE_TARIHI_2 = $gun; ALIS_BELGE_TARIHI_3 = $gun; ALIS_BELGE_TARIHI_4 = $gun; ALIS_BELGE_TARIHI_5 = $gun; E_FATURA_TIPI = 0 }
        Sayac $tx $id "FIS" 0
        $acikKolon = [int](Deger $tx "SELECT COUNT(*) FROM sys.columns WHERE object_id = OBJECT_ID('dbo.FIS_DETAY') AND name = 'ACIKLAMA'" $null) -gt 0
        $acikMaxD = if ($acikKolon) { Deger $tx "SELECT CHARACTER_MAXIMUM_LENGTH FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'FIS_DETAY' AND COLUMN_NAME = 'ACIKLAMA'" $null } else { $null }
        $detKolon = if ($acikKolon) { $FISD_KOLON + @("ACIKLAMA") } else { $FISD_KOLON }
        foreach ($s in $satirlar) {
            $did = [long](Deger $tx "SELECT NEXT VALUE FOR dbo.ID" $null)
            $acikDeger = if ($s.acik) { if ($acikMaxD -and [int]$acikMaxD -gt 0) { Kisalt $s.acik ([int]$acikMaxD) } else { $s.acik } } else { $null }
            Ekle $tx "FIS_DETAY" $detKolon @{ ACIKLAMA = $acikDeger; ID = $did; FIS = $id; LOKASYON = $lokasyon; STOK = $s.stok; STOK_CINSI = 1; STOK_BIRIM = $s.birim; BARKOD = $s.barkod
                DOVIZ_AD = 1; CARPAN = 1; KAB = 0; MIKTAR_FIS = $s.miktar; MIKTAR_BEDELSIZ = 0
                MIKTAR_GIRIS = $(if ($giris) { $s.miktar } else { [decimal]0 }); MIKTAR_CIKIS = $(if ($giris) { [decimal]0 } else { $s.miktar })
                ANLASMA_FIYAT = 0; FIYAT = $s.fiyat; DAHIL_FIYAT = $s.dahil; TUTAR = $s.tutar; DAHIL_TUTAR = $s.dahilTutar; ISKONTO_HESAP = 0
                OTV_ORAN = 0; OTV_TUTAR = 0; KDV_TOPTAN = $s.kdv; TEVKIF = 0; KUR = 1; PUAN = 0; FIYAT_FARKI = 0; SERINO_ZORUNLU = $false; FK_PERSONEL = 0
                SATIR = 0; YEREL_KARSI_FIYAT = $s.sonAlis; BELGE_TARIHINDEKI_SON_ALIS_FIYATI = $s.sonAlis; FATRALANDIRILMIS_IRSALIYEMI = $false
                URETILENMI = 0; FK_VERGI_MUAFIYET_KODU = 0; TOPLAM_SATIR_ISKONTOSU = 0; TOPLAM_FIS_ISKONTOSU = 0; TOPLAM_OTV = 0
                TOPLAM_KDV_MATRAHI = $s.tutar; TOPLAM_KDV = $s.kdvTutar; TOPLAM_TEVKIF = 0; HESAPLANAN_FIYAT = $s.fiyat; PRIM = 0; FIS_DETAY_SATIR_TURU = 0
                LISTE_FIYATI = $s.fiyat; RECETE_MALIYET_ORANI = 0; RECETE = 0; PARTINO_ZORUNLU = $false; YEREL_FIYAT = $s.fiyat; FIS_TARIHI = $tarih
                ISLENDI = $false; KOD = $s.kod; BAGLI_SATIR = 0; FIS_TURU = $tur; MASA = 0; AMBALAJ_BIRIM = $s.birim; AMBALAJ_MIKTAR = $s.miktar
                AMBALAJ_CARPAN = 1; POS_PROMASYON = 0; POS_PROMASYON_TOPLAM = 0; FK_STOK_TEVKIF_LESTE = 0; LOKASYON_MALIYETI = 0; MALIYET_ELLE_GIRILDI = $false
                ALT_BIRIM_MIKTARI = $s.miktar; ANLASMA_DETAY_ID = 0; STOK_FIYAT_AD = 0; BURUT = 0; FIRE = 0; FIYAT_MANUEL_GIRILDI = $false
                FK_IHRACAT_KAB_CINSI = 0; IHRACAT_KAB_NO = 0; IHRACAT_KAB_ADET = 0; PARTI_NO_SON_KULLANMA_TARIHI = $simdi; BUNDLE_DETAY = 0
                FK_GIDER_YERI = 0; KT_BUNDLE_FIYAT = 0; SATIR_STOPAJ_TUTAR = 0; URETIM_TARIHI = $simdi; FK_E_FATURA_SATIR_TIPI = 0 }
            Sayac $tx $did "FIS_DETAY" 0
        }
        if ($Deneme) {
            $tx.Rollback()
            Yaz-Log "DENEME (ERP'ye YAZILMADI): IRSALIYE tur $tur / $belgeNo / $($b.cari) / $($satirlar.Count) satir / toplam KDV dahil $(Yuvarla $genel 2)"
            foreach ($s in $satirlar) { Yaz-Log ("   {0} {1} x {2} {3} fiyat {4} (KDV dahil {5}) {6}" -f $s.barkod, $s.ad, $s.miktar, $(if ($giris) { 'GIRIS' } else { 'CIKIS' }), $s.fiyat, $s.dahil, $s.acik) }
        } else { $tx.Commit() }
        return @{ id = $id; belge = $belgeNo; uyari = ""; satir = $satirlar.Count }
    } catch {
        try { $tx.Rollback() } catch {}
        throw
    }
}

# Bir telefon belgesini ERP'ye yaz. Doner: @{ id; belge; uyari }
function Belge-Yaz($baglanti, $b) {
    $giris = ([string]$b.tip).StartsWith("G")
    $tur = if ($giris) { 1 } else { 2 }
    $seri = if ($giris) { $SeriVerilen } else { $SeriAlinan }
    $tx = $baglanti.BeginTransaction([System.Data.IsolationLevel]::Serializable)
    try {
        # --- Cari ---
        $cari = $null
        if ([string]$b.cari_kodu) { $cari = Deger $tx "SELECT TOP 1 ID FROM dbo.CARI WHERE KOD = @k ORDER BY ID" @{ "@k" = [string]$b.cari_kodu } }
        if (-not $cari -and [string]$b.cari) { $cari = Deger $tx "SELECT TOP 1 ID FROM dbo.CARI WHERE AD = @a ORDER BY ID" @{ "@a" = [string]$b.cari } }
        if (-not $cari) { throw "Cari ERP'de bulunamadi: '$($b.cari)' (kod '$($b.cari_kodu)')" }
        $adres = Deger $tx "SELECT TOP 1 ID FROM dbo.CARI_ADRES WHERE CARI = @c ORDER BY ID" @{ "@c" = $cari }
        if (-not $adres) { $adres = 0 }

        # --- Lokasyon / proje: ERP'nin kendi son siparisinden (yoksa son fisten) ---
        $lp = Tablo $tx "SELECT TOP 1 LOKASYON, PROJE FROM dbo.SIPARIS WHERE BELGENO NOT LIKE 'MK SAHA%' AND BELGENO NOT LIKE 'MOB %' ORDER BY ID DESC" $null
        if ($lp.Rows.Count -eq 0) { $lp = Tablo $tx "SELECT TOP 1 LOKASYON, PROJE FROM dbo.FIS ORDER BY ID DESC" $null }
        if ($lp.Rows.Count -eq 0) { throw "LOKASYON/PROJE bulunamadi" }
        $lokasyon = $lp.Rows[0].LOKASYON; $proje = $lp.Rows[0].PROJE

        # --- KDV sutunu ---
        $kdvKolon = Deger $tx "SELECT TOP 1 name FROM sys.columns WHERE object_id = OBJECT_ID('dbo.STOK_VERGI') AND name IN ('KDV_TOPTAN','KDV_PAREKENDE') ORDER BY CASE name WHEN 'KDV_TOPTAN' THEN 0 ELSE 1 END" $null

        # --- Satirlar ---
        $satirlar = New-Object System.Collections.ArrayList
        $atlanan = New-Object System.Collections.ArrayList
        foreach ($r in @($b.satirlar)) {
            $bbSql = "SELECT TOP 1 bb.STOK, bb.STOK_BIRIM, s.KOD, ISNULL(v.$kdvKolon, 0) AS KDV FROM dbo.STOK_BARKOD_BIRIM bb JOIN dbo.STOK s ON s.ID = bb.STOK LEFT JOIN dbo.STOK_VERGI v ON v.ID = s.STOK_VERGI WHERE bb.BARKOD = @b"
            $bb = Tablo $tx $bbSql @{ "@b" = [string]$r.barkod }
            if ($bb.Rows.Count -eq 0 -and (Kart-Ac $tx $r $b)) { $bb = Tablo $tx $bbSql @{ "@b" = ([string]$r.barkod).Trim() } }
            if ($bb.Rows.Count -eq 0) {
                # Aciklamada okunakli satir: "1) 8690123456789 - URUN ADI - 12 adet" (barkod yoksa yazilmaz)
                $mikYazi = ([decimal]$r.miktar).ToString("0.###", $Inv)
                $parca = @(); if ([string]$r.barkod) { $parca += [string]$r.barkod }; $parca += ([string]$r.urun_adi).Trim(); $parca += "$mikYazi adet"
                [void]$atlanan.Add("$($atlanan.Count + 1)) " + ($parca -join " - "))
                $script:EksikKart["$($r.barkod)"] = ("{0}`t{1}`t{2} x {3}`t{4} ({5})" -f $r.barkod, $r.urun_adi, $b.tip, $r.miktar, $b.cari, $b.belge_turu)
                continue
            }
            $stok = $bb.Rows[0].STOK; $kdv = [decimal]$bb.Rows[0].KDV; $miktar = [decimal]$r.miktar
            # Son alis: AYNI BIRIMDE (adet / koli karismasin), bedelsiz olmayan, fiyati olan en yeni alis satiri.
            $sonAlis = Deger $tx "SELECT TOP 1 d.FIYAT FROM dbo.FIS_DETAY d JOIN dbo.FIS f ON f.ID = d.FIS WHERE d.STOK = @s AND d.STOK_BIRIM = @u AND f.FIS_TURU IN (1, 5) AND f.AKTIF = 1 AND d.FIYAT > 0 AND d.MIKTAR_FIS > 0 ORDER BY f.FIS_TARIHI DESC, d.ID DESC" @{ "@s" = $stok; "@u" = $bb.Rows[0].STOK_BIRIM }
            if ($sonAlis -eq $null) { $sonAlis = [decimal]0 } else { $sonAlis = [decimal]$sonAlis }
            if ($giris) {
                $fiyat = $sonAlis
                $dahil = Yuvarla ($fiyat * (1 + $kdv / 100)) 4
            } else {
                $dahil = if ($r.fiyat -ne $null) { [decimal]$r.fiyat } else { [decimal]0 }
                $fiyat = Yuvarla ($dahil / (1 + $kdv / 100)) 4
            }
            $tutar = Yuvarla ($fiyat * $miktar) 4
            [void]$satirlar.Add(@{ stok = $stok; birim = $bb.Rows[0].STOK_BIRIM; kod = [string]$bb.Rows[0].KOD; barkod = [string]$r.barkod
                kdv = $kdv; miktar = $miktar; fiyat = $fiyat; dahil = $dahil; tutar = $tutar; dahilTutar = (Yuvarla ($dahil * $miktar) 4)
                kdvTutar = (Yuvarla ($tutar * $kdv / 100) 4); sonAlis = $sonAlis; ad = [string]$r.urun_adi })
        }
        # Stok karti olmayan urune once sablondan kart acilir (Kart-Ac). Acilamayanlar (terazi / barkodsuz) ACIKLAMAYA yazilir (KARTI OLMAYAN URUNLER: ...),
        # liste acilacak-stok-kartlari.txt dosyasina da yazilir. Hic karti olan urun yoksa belge bekler.
        if ($satirlar.Count -eq 0) { throw "Belgedeki urunlerin hicbirinin ERP'de stok karti yok: $($atlanan -join ', ')" }

        # --- Belge numarasi: kendi serimizin en buyugu + 1 (kilitli) ---
        $son = Deger $tx "SELECT MAX(BELGENO) FROM dbo.SIPARIS WITH (UPDLOCK, HOLDLOCK) WHERE BELGENO LIKE @p" @{ "@p" = "$seri%" }
        $no = 1
        if ($son) { $no = [int]([string]$son).Substring($seri.Length) + 1 }
        $belgeNo = $seri + $no.ToString("000000")

        # --- Aciklama (sutun uzunluguna gore) ---
        # Sutunun KARAKTER uzunlugu (nvarchar/varchar fark etmez); -1 = sinirsiz.
        $acikMax = Deger $tx "SELECT CHARACTER_MAXIMUM_LENGTH FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'SIPARIS' AND COLUMN_NAME = 'ACIKLAMA'" $null
        $sinir = if ($acikMax -and [int]$acikMax -gt 0) { [int]$acikMax } else { 100000 }
        $mk = ("MK Saha: " + (@([string]$b.belge_turu, [string]$b.belge_no) | Where-Object { $_ }) -join " ") + " / $($b.personel)"
        if ([string]$b.sebep) { $mk += " / $($b.sebep)" }
        if ([string]$b.aciklama) { $mk += " / $($b.aciklama)" }
        if ($atlanan.Count -gt 0) {
            # Her urun ayri satirda (muhasebe karistirmasin). Sigmayanlar icin "+N urun daha" yazilir;
            # tam liste ERP bilgisayarinda acilacak-stok-kartlari.txt dosyasinda.
            $acik = "KARTI OLMAYAN URUNLER:"; $yazilan = 0
            for ($k = 0; $k -lt $atlanan.Count; $k++) {
                $kalan = $atlanan.Count - $k - 1
                $ek = "`r`n" + $atlanan[$k]
                $sonEk = if ($kalan -gt 0) { "`r`n+$kalan urun daha (liste: acilacak-stok-kartlari.txt)" } else { "" }
                if (($acik + $ek + $sonEk).Length -gt $sinir -and $yazilan -gt 0) { break }
                $acik += $ek; $yazilan++
            }
            if ($yazilan -lt $atlanan.Count) { $acik += "`r`n+$($atlanan.Count - $yazilan) urun daha (liste: acilacak-stok-kartlari.txt)" }
            if (($acik + "`r`n" + $mk).Length -le $sinir) { $acik += "`r`n" + $mk }
        } else { $acik = $mk }
        $acik = Kisalt $acik $sinir

        # --- Baslik ---
        $id = [long](Deger $tx "SELECT NEXT VALUE FOR dbo.ID" $null)
        $tarih = [DateTimeOffset]::Parse([string]$b.tarih, $Inv).LocalDateTime
        $satirToplam = ($satirlar | ForEach-Object { $_.tutar } | Measure-Object -Sum).Sum
        $kdvToplam = ($satirlar | ForEach-Object { $_.kdvTutar } | Measure-Object -Sum).Sum
        $genel = ($satirlar | ForEach-Object { $_.dahilTutar } | Measure-Object -Sum).Sum
        $sipPc = Deger $tx "SELECT TOP 1 KOD_PC FROM dbo.SEQUNCES WHERE TABLO = 'SIPARIS' ORDER BY ID DESC" $null
        Ekle $tx "SIPARIS" $SIP_KOLON @{ ID = $id; SIPARIS_TURU = $tur; LOKASYON = $lokasyon; CARI = $cari; CARI_ADRES = $adres; PROJE = $proje
            BELGENO = $belgeNo; SIPARIS_TARIHI = $tarih; TERMIN_TARIHI = $tarih.Date.AddDays(1); ISLEM_TARIHI = (Get-Date); VADE_TARIHI = $tarih.Date
            DOVIZ_AD = 1; DOVIZ_KUR = 1; CARI_PERSONEL = 0; SATIR_TOPLAM = (Yuvarla $satirToplam 2); SATIR_ISKONTO_TOPLAM = 0
            SIPARIS_ISKONTO_ORAN = "          "; SIPARIS_ISKONTO_TOPLAM = 0; YUVARLAMA = 0; KDV_TOPLAM = (Yuvarla $kdvToplam 2); OTV_TOPLAM = 0
            TEFKIFAT_TOPLAM = 0; GENELTOPLAM = (Yuvarla $genel 2); ACIKLAMA = $acik; FIS = 0; AKTIF = $true
            SIPARIS_OZEL_KOD_1 = 0; SIPARIS_OZEL_KOD_2 = 0; SIPARIS_OZEL_KOD_3 = 0; SIPARIS_OZEL_KOD_4 = 0; SIPARIS_OZEL_KOD_5 = 0
            GONDERIM_ADRESI = $adres; ONAYLI = $true; VADE_SECENEKLERI = $(if ($giris) { 17 } else { 7 }); BELGE_YETKILISI = 0; YAZILDI = $false; EMAIL_GONDERILDI = $false
            NAKLIYE_ODEME_TIPI = 0; SEVK_SEKLI = 0; KARSI_SIPARIS_NO = ""; ARTTIRIM = 0; DOVIZ_KUR_SECIMI = 2; FIS_ODEME_TIPI_ISKONTOLARI = $(if ($giris) { 0 } else { 1 })
            IHRACAT_GONDERIM_SEKLI = 0; IHRACAT_TESLIM_SEKLI = 0; FIS_ALT_TIPI = 1 }
        Sayac $tx $id "SIPARIS" $sipPc

        # --- Satirlar ---
        foreach ($s in $satirlar) {
            $did = [long](Deger $tx "SELECT NEXT VALUE FOR dbo.ID" $null)
            Ekle $tx "SIPARIS_DETAY" $DET_KOLON @{ ID = $did; SIPARIS = $id; LOKASYON = $lokasyon; STOK = $s.stok; STOK_CINSI = 1; STOK_BIRIM = $s.birim
                BARKOD = $s.barkod; KOLI_BARKODU = ""; DOVIZ_AD = 1; CARPAN = 1; KAB = 0; MIKTAR_FIS = $s.miktar; MIKTAR_BEDELSIZ = 0; ANLASMA_FIYAT = 0
                FIYAT = $s.fiyat; DAHIL_FIYAT = $s.dahil; TUTAR = $s.tutar; DAHIL_TUTAR = $s.dahilTutar; ISKONTO = ""; ISKONTO_HESAP = 0
                OTV_ORAN = 0; OTV_TUTAR = 0; KDV_TOPTAN = $s.kdv; TEVKIF = 0; KUR = 1; FIYAT_FARKI = 0; SERINO_ZORUNLU = $false
                YEREL_KARSI_FIYAT = 0; BELGE_TARIHINDEKI_SON_ALIS_FIYATI = $s.sonAlis; HK_MIKTAR_FIS = ""; TOPLAM_SATIR_ISKONTOSU = 0
                TOPLAM_FIS_ISKONTOSU = 0; TOPLAM_OTV = 0; TOPLAM_KDV_MATRAHI = $s.tutar; TOPLAM_KDV = $s.kdvTutar; TOPLAM_TEVKIF = 0
                HESAPLANAN_FIYAT = $s.fiyat; YEREL_FIYAT = $s.fiyat; ACIKLAMA = ""; KOD = $s.kod; ONERILEN_FIYAT = 0; JOKER = ""
                AMBALAJ_BIRIM = $s.birim; AMBALAJ_MIKTAR = $s.miktar; AMBALAJ_CARPAN = 1; FK_STOK_TEVKIF_LESTE = 0; FK_PERSONEL = 0
                ALT_BIRIM_MIKTARI = $s.miktar; SEVK_ADRES = 0; BUNDLE_DETAY = 0; KT_BUNDLE_FIYAT = 0; LISTE_FIYATI = 0 }
            Sayac $tx $did "SIPARIS_DETAY" $sipPc
        }
        $uyari = if ($atlanan.Count -gt 0) { "Stok karti olmayan urunler aciklamaya yazildi: " + ($atlanan -join ", ") } else { "" }
        if ($Deneme) {
            $tx.Rollback()
            Yaz-Log "DENEME (ERP'ye YAZILMADI): $belgeNo / $($b.tip) / $($b.cari) / $($satirlar.Count) satir / toplam KDV dahil $(Yuvarla $genel 2) $uyari"
            foreach ($s in $satirlar) { Yaz-Log ("   {0} {1} x {2} fiyat {3} (KDV dahil {4})" -f $s.barkod, $s.ad, $s.miktar, $s.fiyat, $s.dahil) }
        } else { $tx.Commit() }
        return @{ id = $id; belge = $belgeNo; uyari = $uyari; satir = $satirlar.Count }
    } catch {
        try { $tx.Rollback() } catch {}
        throw
    }
}

# ---------------------------------------------------------------------

# Bir tur: buluttan bekleyen belgeleri al, ERP'ye yaz.
function Tur-Calis {

    $aktarilan = @{}
    if (Test-Path $AktarilanDosya) { Get-Content $AktarilanDosya | ForEach-Object { $p = $_.Split("`t"); if ($p[0]) { $aktarilan[$p[0]] = $_ } } }
    $script:EksikKart = @{}
    $script:AcilanKart = New-Object System.Collections.ArrayList
    $bas = [datetime]::ParseExact($BaslangicTarihi, "yyyy-MM-dd", $Inv)
    $is = Rpc "aktarilacak_mal" @{ p_baslangic = $bas.ToString("yyyy-MM-ddT00:00:00", $Inv) + "+03:00"; p_bekle_dk = $(if ($Deneme) { 0 } else { $BekleDakika }); p_limit = 50 }
    if (-not $is -or [string]$is.status -ne "ok") { throw "Bekleyen belgeler alinamadi: $($is | ConvertTo-Json -Compress)" }

    foreach ($d in @($is.degisen)) {
        if (-not $d -or $Deneme) { continue }
        Yaz-Log "UYARI: $($d.belge_no) ERP'ye aktarildiktan SONRA telefonda degistirildi. ERP'deki siparis degistirilmedi; elle kontrol edin."
        $b = [PSCustomObject]@{ batch_id = $d.batch_id; tip = ""; imza = "" }
        Bildir $b $null $d.belge_no "degisti" "Aktarildiktan sonra telefonda degisti; ERP'de elle kontrol edin"
    }

    $belgeler = @($is.belgeler | Where-Object { $_ })
    if ($belgeler.Count -eq 0) { Write-Host "Aktarilacak belge yok."; return }   # sik calisir: log'a yazilmaz

    if ($script:baglanti -eq $null) {
    $script:baglanti = New-Object System.Data.SqlClient.SqlConnection("Server=$SqlServer;Database=master;Integrated Security=SSPI;")
    $script:baglanti.Open()
    if (-not $Database) {
        $cmd = $baglanti.CreateCommand(); $cmd.CommandText = "SELECT name FROM sys.databases WHERE name LIKE 'ERP12[0-9][0-9][0-9][0-9]' AND state = 0 ORDER BY name DESC"
        $rd = $cmd.ExecuteReader(); $adaylar = @(); while ($rd.Read()) { $adaylar += [string]$rd[0] }; $rd.Close()
        if ($adaylar.Count -eq 0) { throw "ERP12 yil veri tabani bulunamadi" }
        foreach ($aday in $adaylar) {
            $cmd = $baglanti.CreateCommand(); $cmd.CommandText = "SELECT COUNT(*) FROM [$aday].dbo.FIS WHERE FIS_TARIHI >= DATEADD(day, -7, GETDATE())"
            if ([int]$cmd.ExecuteScalar() -gt 0) { $Database = $aday; break }
        }
        if (-not $Database) { $Database = $adaylar[0] }
    }
    $script:baglanti.ChangeDatabase($Database)
    $script:Database = $Database
    # Onceki surumle yazilan MK SAHA siparislerinin eksik sayac (SEQUNCES) kayitlari bir kez tamamlanir.
    if (-not $Deneme) {
        try {
            $otx = $script:baglanti.BeginTransaction()
            $pc = Deger $otx "SELECT TOP 1 KOD_PC FROM dbo.SEQUNCES WHERE TABLO = 'SIPARIS' ORDER BY ID DESC" $null
            if ($pc -ne $null) {
                $n1 = (Sql $otx "INSERT INTO dbo.SEQUNCES (ID, TABLO, KOD_PC) SELECT s.ID, 'SIPARIS', @p FROM dbo.SIPARIS s WHERE s.BELGENO LIKE 'MK SAHA%' AND NOT EXISTS (SELECT 1 FROM dbo.SEQUNCES q WHERE q.ID = s.ID)" @{ "@p" = $pc }).ExecuteNonQuery()
                $n2 = (Sql $otx "INSERT INTO dbo.SEQUNCES (ID, TABLO, KOD_PC) SELECT d.ID, 'SIPARIS_DETAY', @p FROM dbo.SIPARIS_DETAY d JOIN dbo.SIPARIS s ON s.ID = d.SIPARIS WHERE s.BELGENO LIKE 'MK SAHA%' AND NOT EXISTS (SELECT 1 FROM dbo.SEQUNCES q WHERE q.ID = d.ID)" @{ "@p" = $pc }).ExecuteNonQuery()
                if ($n1 + $n2 -gt 0) { Yaz-Log "Onceki MK SAHA siparisleri icin $($n1 + $n2) sayac kaydi tamamlandi" }
            }
            $otx.Commit()
        } catch { try { $otx.Rollback() } catch {}; Yaz-Log "UYARI: sayac tamamlama yapilamadi: $($_.Exception.Message)" }
    }
    }
    $baglanti = $script:baglanti; $Database = $script:Database
    $script:TurLog = New-Object System.Collections.ArrayList
    [void]$script:TurLog.Add("$(if ($Deneme) { 'DENEME - ' })ERP veri tabani: $Database, $($belgeler.Count) belge")
    $ok = 0; $hata = 0; $yeniHata = 0
    foreach ($b in $belgeler) {
        if (-not $Deneme -and $aktarilan.ContainsKey([string]$b.batch_id)) {
            # ERP'ye yazilmis ama buluta bildirilememis: tekrar YAZMA, sadece bildir.
            $p = $aktarilan[[string]$b.batch_id].Split("`t")
            Bildir $b ([long]$p[1]) $p[2] "ok" "Yerel listeden bildirildi"
            continue
        }
        try {
            $sonuc = if ($AktarimTuru -eq "IRSALIYE") { Irsaliye-Yaz $baglanti $b } else { Belge-Yaz $baglanti $b }
            if ($Deneme) { $ok++; continue }
            Add-Content -Path $AktarilanDosya -Value ("{0}`t{1}`t{2}" -f $b.batch_id, $sonuc.id, $sonuc.belge)
            Bildir $b $sonuc.id $sonuc.belge "ok" $(if ($sonuc.uyari) { $sonuc.uyari } else { "$($sonuc.satir) satir" })
            if ($script:TurLog.Count) { $script:TurLog | ForEach-Object { Yaz-Log $_ }; $script:TurLog.Clear() }
            Yaz-Log "TAMAM: $($sonuc.belge) ($($b.tip), $($b.cari), $($sonuc.satir) satir) $($sonuc.uyari)"
            $ok++
        } catch {
            $hata++
            # Ayni hata her calismada tekrar yazilmaz / bildirilmez (gunluk dolmasin).
            $mesaj = [string]$_.Exception.Message
            if ($Deneme -or $script:SonHata[[string]$b.batch_id] -ne $mesaj) {
                $yeniHata++
                Yaz-Log "HATA: belge $($b.batch_id) ($($b.cari)): $mesaj"
                if (-not $Deneme) { try { Bildir $b $null "" "hata" $mesaj; $script:SonHata[[string]$b.batch_id] = $mesaj } catch {} }
            } else { Write-Host "Bekliyor (ayni hata): $($b.cari)" }
        }
    }
    try {
        if (-not $Deneme -and $script:AcilanKart.Count -gt 0) {
            if (-not (Test-Path $AcilanKartDosya)) { [System.IO.File]::WriteAllText($AcilanKartDosya, "MK SAHA'NIN ACTIGI GECICI STOK KARTLARI - muhasebe KDV / grup / ad / fiyati duzenlesin`r`nTarih`tStok kodu`tBarkod`tAd`tHareket`tCari (belge)`r`n", [System.Text.Encoding]::UTF8) }
            [System.IO.File]::AppendAllText($AcilanKartDosya, (($script:AcilanKart) -join "`r`n") + "`r`n", [System.Text.Encoding]::UTF8)
            Yaz-Log "$($script:AcilanKart.Count) yeni stok karti acildi. Liste: $AcilanKartDosya"
        }
        if ($script:EksikKart.Count -gt 0 -and ($ok + $yeniHata -gt 0)) {
            $baslik = "ERP'de STOK KARTI OLMAYAN URUNLER ($(Get-Date -Format 'yyyy-MM-dd HH:mm')). Siparisin aciklamasinda 'KARTI OLMAYAN URUNLER' basliginda yaziyor; faturaya cevirirken kart acip satiri elle ekleyin.`r`nBarkod`tUrun`tHareket`tCari (belge)"
            [System.IO.File]::WriteAllText($EksikKartDosya, $baslik + "`r`n" + (($script:EksikKart.Values | Sort-Object) -join "`r`n") + "`r`n", [System.Text.Encoding]::UTF8)
            Yaz-Log "UYARI: $($script:EksikKart.Count) urunun ERP'de stok karti yok ve acilamadi (terazi / kisa / barkodsuz); $(if ($AktarimTuru -eq 'IRSALIYE') { 'bu urunlerin oldugu belgeler bekliyor' } else { 'siparis aciklamasina yazildi' }). Liste: $EksikKartDosya"
        } elseif ($script:EksikKart.Count -eq 0 -and (Test-Path $EksikKartDosya)) { Remove-Item $EksikKartDosya -ErrorAction SilentlyContinue }
        if (-not $Deneme) { [System.IO.File]::WriteAllText($HataDosya, (($script:SonHata.Keys | ForEach-Object { "$_`t$($script:SonHata[$_])" }) -join "`r`n"), [System.Text.Encoding]::UTF8) }
    } catch {}
    if ($ok + $yeniHata -gt 0 -or $Deneme) {
        if ($script:TurLog.Count) { $script:TurLog | ForEach-Object { Yaz-Log $_ }; $script:TurLog.Clear() }
        Yaz-Log "Bitti: $ok $(if ($Deneme) { 'denendi (yazilmadi)' } else { 'aktarildi' }), $hata hata$(if ($hata -gt $yeniHata) { " ($($hata - $yeniHata) belge onceki hatayla bekliyor)" })."
    } else { Write-Host "Yeni bir sey yok ($hata belge bekliyor)." }
}

$script:baglanti = $null
try {
    if (-not (Test-Path $DbAnahtarDosyasi)) { Yaz-Log "HATA: $DbAnahtarDosyasi yok."; exit 1 }
    $script:Anahtar = (Get-Content -Path $DbAnahtarDosyasi -TotalCount 1).Trim()
    $aktarilan = @{}
    $script:EksikKart = @{}
    $script:AcilanKart = New-Object System.Collections.ArrayList
    $script:SonHata = @{}
    if (Test-Path $HataDosya) { Get-Content $HataDosya -Encoding UTF8 | ForEach-Object { $p = $_.Split("`t", 2); if ($p[0] -and $p.Count -eq 2) { $script:SonHata[$p[0]] = $p[1] } } }
    
    # DONGU: gorev dakikada bir baslatir; program o dakika icinde 10 saniyede bir bakar (telefondan ~30 sn'de ERP'ye).
    $tekrar = if ($script:Argumanlar -contains "DONGU") { 5 } else { 1 }
    for ($tk = 0; $tk -lt $tekrar; $tk++) {
        if ($tk -gt 0) { Start-Sleep -Seconds 10 }
        Tur-Calis
    }
}
catch {
    Yaz-Log "HATA: $($_.Exception.Message)"
    exit 1
}
finally {
    if ($script:baglanti -ne $null) { $script:baglanti.Close() }
}

