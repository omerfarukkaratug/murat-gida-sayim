# =====================================================================
#  KRT Saha - MAGAZA SAGLIK RAPORU (ERP12)
#  ERP12 veri tabanini SADECE OKUR, hicbir sey yazmaz. Sonuc tek bir HTML dosyasidir:
#     C:\Scripts\magaza-saglik-raporu.html   (tarayicida acilir, PDF olarak kaydedilebilir)
#  Yanindaki saglik-sablon.html dosyasi raporun gorunumudur; ikisi ayni klasorde olmali.
#  Bolumler (her biri ayri hesaplanir; biri hata verirse digerleri yine cikar):
#    1) Son 90 gun satis, maliyet, brut kar (kasa + firma, KDV haric)
#    2) Alisin altinda satilan urunler ve aylik zarar
#    3) Alis fiyati artmis ama satis fiyati guncellenmemis urunler (marj erimesi)
#    4) 90 gundur satilmayan stok ve bagli para
#    5) Kasa iptalleri (son 30 gun) kasiyer bazinda
#    6) Son 6 ayin aylik ciro / kar egilimi
#    7) Sermaye: stok degeri (hizli/yavas/olu), musteri alacaklari, tedarikci borclari, nakit dongusu
#       ve aylik sermaye hareketi (alis ile stoga giren, satisla cikan para; sermaye artti mi azaldi mi)
#    9) Buyume: tukenen cok satanlar, sepet, musteri trafigi (gun/saat), yukselen/dusen urunler,
#       alimi azalan firma musterileri, cironun %80'ini yapan urunler -> rapordaki "Buyume plani"
#   10) Oneriler (uygulamada Karlilik -> Oneriler): musteri ceken urunler, kar firsati, fiyat sonu,
#       sepet dagilimi, birlikte alinanlar, kasa onu adaylari, one cikarilacaklar
#    8) Her ayda kari en cok dusuren urunler (dusuk marjli ayin nedeni)
#  Rapor KRT Saha'ya da gonderilir: uygulamada Karlilik -> Saglik sekmesinde gorunur (038_saglik_raporu.sql).
#  -Gorev ile (SAGLIK-RAPORU-GOREV.bat 30 dakikada bir calistirir): rapor yalniz uygulamadan istenmisse
#  ya da son rapor 20 saatten eskiyse hazirlanir; pencere/tarayici acilmaz.
# =====================================================================
param(
    [string]$SqlServer = "SERVER\ERP12",
    [string]$Database = "",
    [double]$AylikEnflasyon = 2.0,     # satilmayan stokta bekleyen paranin aylik deger kaybi (%)
    [string]$Cikti = "",
    [switch]$Gorev
)
$DbUrl = "https://wjyqempcmyrmruhdpcwk.supabase.co"
$DbAnahtarDosyasi = "C:\Scripts\db-anahtar.txt"
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}
function DbAnahtar { if (Test-Path $DbAnahtarDosyasi) { return (Get-Content -Path $DbAnahtarDosyasi -TotalCount 1).Trim() }; return "" }
function DbCagir($fonksiyon, $govde, $sn = 120) {
    $anahtar = DbAnahtar; if (-not $anahtar) { throw "db-anahtar.txt yok ($DbAnahtarDosyasi)" }
    return Invoke-RestMethod -Uri "$DbUrl/rest/v1/rpc/$fonksiyon" -Method Post -Body ([Text.Encoding]::UTF8.GetBytes($govde)) `
        -ContentType "application/json; charset=utf-8" -Headers @{ apikey = $anahtar } -TimeoutSec $sn -UserAgent "MK-Sayim/1.0"
}
function Nabiz($mesaj) { try { [void](DbCagir "erp_nabiz_yaz" (@{ p_ad = "saglik_raporu"; p_mesaj = $mesaj; p_baslangic = $null } | ConvertTo-Json -Compress) 30) } catch {} }
$Klasor = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $Cikti) { $Cikti = Join-Path $Klasor "magaza-saglik-raporu.html" }
$Sablon = Join-Path $Klasor "saglik-sablon.html"
$Log = Join-Path $Klasor "saglik-raporu-log.txt"
function Yaz($m) { $s = "$(Get-Date -Format 'HH:mm:ss') $m"; Write-Host $s; try { Add-Content -Path $Log -Value $s } catch {} }
$Inv = [Globalization.CultureInfo]::InvariantCulture
if ($Gorev) {
    try { $g = DbCagir "saglik_gerekli" "{}" 30 } catch { Nabiz ("HATA: " + $_.Exception.Message); exit 0 }
    if (-not $g.gerekli) { Nabiz "OK: bekliyor"; exit 0 }
    Yaz "Gorev: rapor hazirlaniyor ($($g.neden))"
}

$bag = $null
function Tablo($sql, $sn = 600) {
    $cmd = $bag.CreateCommand(); $cmd.CommandText = $sql; $cmd.CommandTimeout = $sn
    $da = New-Object System.Data.SqlClient.SqlDataAdapter($cmd); $dt = New-Object System.Data.DataTable; [void]$da.Fill($dt); return ,$dt
}
function Calistir($sql, $sn = 600) { $cmd = $bag.CreateCommand(); $cmd.CommandText = $sql; $cmd.CommandTimeout = $sn; [void]$cmd.ExecuteNonQuery() }
function D($v) { if ($v -is [DBNull] -or $v -eq $null) { return $null }; return [Math]::Round([double]$v, 2) }
function M($v) { if ($v -is [DBNull] -or $v -eq $null) { return "" }; return ([string]$v).Trim() }
function I($v) { if ($v -is [DBNull] -or $v -eq $null) { return 0 }; return [int]$v }
function T($v) { if ($v -is [DBNull] -or $v -eq $null) { return "" }; return ([datetime]$v).ToString("dd.MM.yyyy") }

$veri = [ordered]@{ surum = "5"; olusturma = (Get-Date).ToString("yyyy-MM-dd HH:mm"); firma = ""; veritabani = ""; enflasyon = $AylikEnflasyon; hatalar = @() }
$hatalar = New-Object System.Collections.ArrayList

try {
    if (-not (Test-Path $Sablon)) { throw "saglik-sablon.html bulunamadi ($Sablon). Iki dosya ayni klasorde olmali." }
    $bag = New-Object System.Data.SqlClient.SqlConnection("Server=$SqlServer;Database=master;Integrated Security=SSPI;")
    $bag.Open()
    if (-not $Database) {
        $dbler = Tablo "SELECT name FROM sys.databases WHERE name LIKE 'ERP12[0-9][0-9][0-9][0-9]' AND state = 0 ORDER BY name DESC"
        foreach ($d in $dbler.Rows) {
            $n = (Tablo ("SELECT COUNT(*) AS n FROM [" + $d.name + "].dbo.FIS WITH (NOLOCK) WHERE FIS_TARIHI >= DATEADD(day, -7, GETDATE())")).Rows[0].n
            if ([int]$n -gt 0) { $Database = [string]$d.name; break }
        }
        if (-not $Database -and $dbler.Rows.Count) { $Database = [string]$dbler.Rows[0].name }
    }
    if (-not $Database) { throw "ERP12 veri tabani bulunamadi." }
    $bag.ChangeDatabase($Database)
    $veri.veritabani = $Database
    Yaz "Veri tabani: $Database"
    Calistir "SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED"

    # Firma adi (varsa)
    try {
        $kol = @((Tablo "SELECT c.name FROM sys.columns c WHERE c.object_id = OBJECT_ID('dbo.FIRMASABITLERI')").Rows | ForEach-Object { [string]$_.name })
        $ad = @("UNVAN", "FIRMA_UNVANI", "FIRMA_UNVAN", "FIRMA_ADI", "FIRMAADI", "AD", "ADI") | Where-Object { $kol -contains $_ } | Select-Object -First 1
        if ($ad) { $r = Tablo "SELECT TOP 1 CAST([$ad] AS nvarchar(200)) AS A FROM dbo.FIRMASABITLERI"; if ($r.Rows.Count) { $veri.firma = M $r.Rows[0].A } }
    } catch {}

    # ---- Ortak ara tablolar ----
    Yaz "Satislar okunuyor (son 6 ay)..."
    $satisAile = "(FT.AD LIKE N'%Sat' + NCHAR(305) + NCHAR(351) + N'%' OR FT.AD LIKE N'%SATI' + NCHAR(350) + N'%' OR f.FIS_TURU IN (11, 12, 35, 36))"
    $kasaMi = "(ISNULL(f.CARI, 0) = COALESCE((SELECT TOP 1 VARSAYILANCARI FROM dbo.FIRMASABITLERI), -1) OR (f.CARI IS NULL AND f.FIS_TURU IN (11, 12, 35, 36)) OR f.FIS_TURU = 11)"
    $g = "(CASE WHEN f.FIS_TURU IN (5, 6, 7, 8, 36) AND ISNULL(d.FATRALANDIRILMIS_IRSALIYEMI, 0) = 1 THEN 0 ELSE FT.GIRIS END)"
    # Belge satirindaki birim carpani (koli = 24 adet gibi): miktar ve birim maliyet ana birime (adet / kg) cevrilir.
    $carp = "(CASE WHEN ISNULL(d.CARPAN, 0) > 0.0001 AND ISNULL(d.CARPAN, 0) < 100000 THEN CAST(d.CARPAN AS float) ELSE 1 END)"
    Calistir @"
IF OBJECT_ID('tempdb..#kdv') IS NOT NULL DROP TABLE #kdv;
-- Mal olmayan kartlar (fiyat farki, iskonto, nakliye, kargo) haric tutulur: kar hesabini bozuyorlardi.
SELECT s.ID AS STOK, CAST(ISNULL(v.KDV_PAREKENDE, 0) AS float) AS KDV, s.KOD, s.AD INTO #kdv FROM dbo.STOK s LEFT JOIN dbo.STOK_VERGI v ON v.ID = s.STOK_VERGI
WHERE NOT (s.AD LIKE N'%FIYAT FARK%' OR s.AD LIKE N'%F' + NCHAR(304) + N'YAT FARK%' OR s.AD LIKE N'%ISKONTO%' OR s.AD LIKE N'%' + NCHAR(304) + N'SKONTO%'
           OR s.AD LIKE N'%NAKL%YE%' OR s.AD LIKE N'%NAVLUN%' OR s.AD LIKE N'%KARGO BEDEL%');
CREATE CLUSTERED INDEX i ON #kdv (STOK);
IF OBJECT_ID('tempdb..#sat') IS NOT NULL DROP TABLE #sat;
SELECT d.STOK, CAST(f.FIS_TARIHI AS date) AS GUN, f.CARI AS CARI,
       CASE WHEN $kasaMi THEN 1 ELSE 0 END AS KASA, k.KDV AS KDV,
       -$g * CAST(d.MIKTAR_FIS AS float) * $carp AS MIKTAR,
       -$g * CASE WHEN ISNULL(d.TOPLAM_KDV_MATRAHI, 0) <> 0 THEN CAST(d.TOPLAM_KDV_MATRAHI AS float)
                  ELSE CAST(d.MIKTAR_FIS AS float) * CAST(ISNULL(d.FIYAT, 0) AS float) / (1 + k.KDV / 100.0) END AS TUTAR
INTO #sat
FROM dbo.FIS f
JOIN dbo.FIS_DETAY d ON d.FIS = f.ID
JOIN dbo.FIS_TURU FT ON FT.ID = f.FIS_TURU
JOIN #kdv k ON k.STOK = d.STOK
WHERE f.FIS_TARIHI >= DATEADD(month, DATEDIFF(month, 0, GETDATE()) - 6, 0)
  AND ISNULL(f.AKTIF, 1) = 1 AND f.FIS_TURU <> 18 AND $satisAile AND $g <> 0;
CREATE CLUSTERED INDEX i ON #sat (STOK, GUN);
"@
    Yaz "Alislar okunuyor..."
    Calistir @"
IF OBJECT_ID('tempdb..#alis') IS NOT NULL DROP TABLE #alis;
SELECT d.STOK, f.FIS_TARIHI AS TARIH, d.ID AS DID, CAST(d.TOPLAM_KDV_MATRAHI AS float) / (CAST(d.MIKTAR_FIS AS float) * $carp) AS MALIYET, ISNULL(c.AD, '') AS CARI
INTO #alis
FROM dbo.FIS f JOIN dbo.FIS_DETAY d ON d.FIS = f.ID LEFT JOIN dbo.CARI c ON c.ID = f.CARI JOIN #kdv k ON k.STOK = d.STOK
WHERE f.FIS_TURU IN (1, 5) AND ISNULL(f.AKTIF, 1) = 1 AND d.MIKTAR_FIS > 0 AND ISNULL(d.TOPLAM_KDV_MATRAHI, 0) > 0;
-- Bedelsiz / sembolik fiyatli alis satirlari (urunun ortalama alisinin %20'sinden ucuz) maliyet sayilmaz.
DELETE a FROM #alis a JOIN (SELECT STOK, AVG(MALIYET) AS ORT FROM #alis GROUP BY STOK) o ON o.STOK = a.STOK WHERE a.MALIYET < o.ORT * 0.2;
CREATE CLUSTERED INDEX i ON #alis (STOK, TARIH);
IF OBJECT_ID('tempdb..#son') IS NOT NULL DROP TABLE #son;
IF OBJECT_ID('tempdb..#sira') IS NOT NULL DROP TABLE #sira;
SELECT STOK, MALIYET, TARIH, CARI, ROW_NUMBER() OVER (PARTITION BY STOK ORDER BY TARIH DESC, DID DESC) AS SIRA INTO #sira FROM #alis;
SELECT a.STOK, a.MALIYET, a.TARIH, a.CARI, b.MALIYET AS ONCEKI INTO #son
FROM #sira a LEFT JOIN #sira b ON b.STOK = a.STOK AND b.SIRA = 2 WHERE a.SIRA = 1;
CREATE CLUSTERED INDEX i ON #son (STOK);
"@
    Yaz "Fiyat ve stok okunuyor..."
    Calistir @"
IF OBJECT_ID('tempdb..#fiyat') IS NOT NULL DROP TABLE #fiyat;
SELECT bb.STOK, MAX(CAST(fv.FIYAT AS float)) AS FIYAT
INTO #fiyat
FROM dbo.STOK_BARKOD_BIRIM bb JOIN dbo.STOK_BARKOD_FIYAT_VARSAYILAN fv ON fv.STOK_STOK_BIRIM = bb.STOK_STOK_BIRIM
WHERE ISNULL(bb.CARPAN, 1) <= 1 AND fv.FIYAT > 0
GROUP BY bb.STOK;
CREATE CLUSTERED INDEX i ON #fiyat (STOK);
IF OBJECT_ID('tempdb..#stok') IS NOT NULL DROP TABLE #stok;
SELECT ub.STOK, SUM(CAST(COALESCE(um.MIKTAR, ubar.MIKTAR) AS float)) AS MIKTAR
INTO #stok
FROM dbo.STOK_BARKOD_BIRIM ub
LEFT JOIN dbo.STOK_BARKOD ubar ON ubar.BARKOD = ub.BARKOD
LEFT JOIN dbo.STOK_MIKTAR_BARKODLU um ON um.BARKOD = ub.BARKOD
GROUP BY ub.STOK;
CREATE CLUSTERED INDEX i ON #stok (STOK);
"@

    # ---- 1) Ozet (son 90 gun) + urun bazinda donem ----
    try {
        Yaz "1) Donem ozeti..."
        Calistir @"
IF OBJECT_ID('tempdb..#ay') IS NOT NULL DROP TABLE #ay;
SELECT s.STOK, DATEADD(month, DATEDIFF(month, 0, s.GUN), 0) AS AY,
       SUM(s.MIKTAR) AS MIKTAR, SUM(s.TUTAR) AS TUTAR,
       SUM(CASE WHEN s.GUN >= DATEADD(day, -90, CAST(GETDATE() AS date)) THEN s.MIKTAR ELSE 0 END) AS M90,
       SUM(CASE WHEN s.GUN >= DATEADD(day, -90, CAST(GETDATE() AS date)) THEN s.TUTAR ELSE 0 END) AS T90,
       SUM(CASE WHEN s.GUN >= DATEADD(day, -90, CAST(GETDATE() AS date)) AND s.KASA = 1 THEN s.TUTAR ELSE 0 END) AS K90,
       SUM(CASE WHEN s.GUN >= DATEADD(day, -30, CAST(GETDATE() AS date)) THEN s.MIKTAR ELSE 0 END) AS M30,
       MAX(s.GUN) AS SON_SATIS,
       CAST(NULL AS float) AS MALIYET
INTO #ay FROM #sat s GROUP BY s.STOK, DATEADD(month, DATEDIFF(month, 0, s.GUN), 0);
UPDATE a SET MALIYET = COALESCE(
   (SELECT TOP 1 x.MALIYET FROM #alis x WHERE x.STOK = a.STOK AND x.TARIH < DATEADD(month, 1, a.AY) ORDER BY x.TARIH DESC, x.DID DESC),
   (SELECT TOP 1 x.MALIYET FROM #alis x WHERE x.STOK = a.STOK ORDER BY x.TARIH ASC, x.DID ASC))
FROM #ay a;
"@
        $oz = (Tablo @"
SELECT SUM(T90) AS CIRO, SUM(K90) AS KASA, SUM(CIRO_M) AS CIRO_M, SUM(MAL) AS MAL, COUNT(*) AS URUN FROM (
  SELECT STOK, SUM(T90) AS T90, SUM(K90) AS K90, SUM(CASE WHEN MALIYET IS NOT NULL THEN T90 ELSE 0 END) AS CIRO_M,
         SUM(CASE WHEN MALIYET IS NOT NULL THEN M90 * MALIYET ELSE 0 END) AS MAL
  FROM #ay GROUP BY STOK HAVING SUM(M90) > 0 AND SUM(T90) > 0) u
"@).Rows[0]
        $veri.ozet = [ordered]@{ ciro = D $oz.CIRO; kasa = D $oz.KASA; ciroMaliyetli = D $oz.CIRO_M; maliyet = D $oz.MAL; urun = [int]$oz.URUN }
        $aylar = @((Tablo @"
SELECT CONVERT(char(7), AY, 120) AS AY, SUM(TUTAR) AS CIRO, SUM(CASE WHEN MALIYET IS NOT NULL THEN TUTAR ELSE 0 END) AS CIRO_M,
       SUM(CASE WHEN MALIYET IS NOT NULL THEN MIKTAR * MALIYET ELSE 0 END) AS MAL
FROM #ay WHERE MIKTAR > 0 AND TUTAR > 0 GROUP BY AY ORDER BY AY
"@).Rows | ForEach-Object { ,@((M $_.AY), (D $_.CIRO), (D $_.CIRO_M), (D $_.MAL)) })
        $veri.aylar = $aylar
        # En cok kar getiren ve en cok ciro yapan dusuk marjli urunler
        $urunler = @((Tablo @"
SELECT TOP 400 k.KOD, k.AD, SUM(a.M90) AS M90, SUM(a.T90) AS T90, SUM(CASE WHEN a.MALIYET IS NOT NULL THEN a.M90 * a.MALIYET END) AS MAL
FROM #ay a JOIN #kdv k ON k.STOK = a.STOK GROUP BY k.KOD, k.AD HAVING SUM(a.T90) > 0 AND SUM(a.M90) > 0 ORDER BY SUM(a.T90) DESC
"@).Rows | ForEach-Object { ,@((M $_.KOD), (M $_.AD), (D $_.M90), (D $_.T90), (D $_.MAL)) })
        $veri.urunler = $urunler
    } catch { [void]$hatalar.Add("Ozet: " + $_.Exception.Message); Yaz "HATA ozet: $($_.Exception.Message)" }

    # ---- 2) Alisin altinda satilan ----
    try {
        Yaz "2) Alisin altinda satilanlar..."
        $veri.altinda = @((Tablo @"
SELECT TOP 200 k.KOD, k.AD, p.FIYAT / (1 + k.KDV / 100.0) AS SATIS, s.MALIYET AS ALIS, s.TARIH AS ALIS_TARIHI, s.CARI,
       ISNULL((SELECT SUM(x.MIKTAR) FROM #sat x WHERE x.STOK = k.STOK AND x.GUN >= DATEADD(day, -30, CAST(GETDATE() AS date))), 0) AS M30,
       st.MIKTAR AS STOK
FROM #kdv k JOIN #fiyat p ON p.STOK = k.STOK JOIN #son s ON s.STOK = k.STOK LEFT JOIN #stok st ON st.STOK = k.STOK
WHERE p.FIYAT / (1 + k.KDV / 100.0) < s.MALIYET * 0.999
ORDER BY (s.MALIYET - p.FIYAT / (1 + k.KDV / 100.0)) * ISNULL((SELECT SUM(x.MIKTAR) FROM #sat x WHERE x.STOK = k.STOK AND x.GUN >= DATEADD(day, -30, CAST(GETDATE() AS date))), 0) DESC
"@).Rows | ForEach-Object { ,@((M $_.KOD), (M $_.AD), (D $_.SATIS), (D $_.ALIS), $(if ($_.ALIS_TARIHI -is [DBNull]) { "" } else { ([datetime]$_.ALIS_TARIHI).ToString("dd.MM.yyyy") }), (M $_.CARI), (D $_.M30), (D $_.STOK)) })
    } catch { [void]$hatalar.Add("Alisin altinda: " + $_.Exception.Message); Yaz "HATA altinda: $($_.Exception.Message)" }

    # ---- 3) Alis artti, satis fiyati guncellenmedi ----
    try {
        Yaz "3) Fiyati guncellenmeyenler..."
        Calistir @"
IF OBJECT_ID('tempdb..#fdeg') IS NOT NULL DROP TABLE #fdeg;
SELECT ssb.STOK, MAX(dg.TARIH) AS SON_DEGISIM INTO #fdeg
FROM dbo.STOK_STOK_BIRIM_DEGISIM dg JOIN dbo.STOK_STOK_BIRIM ssb ON ssb.ID = dg.STOK_STOK_BIRIM
WHERE dg.FIYAT <> dg.ESKI_FIYAT GROUP BY ssb.STOK;
"@
        $veri.geride = @((Tablo @"
SELECT TOP 200 k.KOD, k.AD, p.FIYAT / (1 + k.KDV / 100.0) AS SATIS, s.ONCEKI, s.MALIYET AS ALIS, s.TARIH AS ALIS_TARIHI, fd.SON_DEGISIM, s.CARI,
       ISNULL((SELECT SUM(x.MIKTAR) FROM #sat x WHERE x.STOK = k.STOK AND x.GUN >= DATEADD(day, -30, CAST(GETDATE() AS date))), 0) AS M30
FROM #kdv k JOIN #fiyat p ON p.STOK = k.STOK JOIN #son s ON s.STOK = k.STOK LEFT JOIN #fdeg fd ON fd.STOK = k.STOK
WHERE s.ONCEKI > 0 AND s.MALIYET > s.ONCEKI * 1.03 AND (fd.SON_DEGISIM IS NULL OR fd.SON_DEGISIM < s.TARIH)
  AND p.FIYAT / (1 + k.KDV / 100.0) >= s.MALIYET * 0.999
ORDER BY (s.MALIYET - s.ONCEKI) * ISNULL((SELECT SUM(x.MIKTAR) FROM #sat x WHERE x.STOK = k.STOK AND x.GUN >= DATEADD(day, -30, CAST(GETDATE() AS date))), 0) DESC
"@).Rows | ForEach-Object { ,@((M $_.KOD), (M $_.AD), (D $_.SATIS), (D $_.ONCEKI), (D $_.ALIS), $(if ($_.ALIS_TARIHI -is [DBNull]) { "" } else { ([datetime]$_.ALIS_TARIHI).ToString("dd.MM.yyyy") }), $(if ($_.SON_DEGISIM -is [DBNull]) { "" } else { ([datetime]$_.SON_DEGISIM).ToString("dd.MM.yyyy") }), (M $_.CARI), (D $_.M30)) })
    } catch { [void]$hatalar.Add("Fiyati guncellenmeyen: " + $_.Exception.Message); Yaz "HATA geride: $($_.Exception.Message)" }

    # ---- 4) Satilmayan stok ----
    try {
        Yaz "4) Satilmayan stok..."
        $olu = Tablo @"
SELECT k.KOD, k.AD, st.MIKTAR, s.MALIYET, st.MIKTAR * s.MALIYET AS DEGER,
       (SELECT MAX(x.GUN) FROM #sat x WHERE x.STOK = k.STOK) AS SON_SATIS
FROM #stok st JOIN #kdv k ON k.STOK = st.STOK JOIN #son s ON s.STOK = k.STOK
WHERE st.MIKTAR > 0 AND NOT EXISTS (SELECT 1 FROM #sat x WHERE x.STOK = k.STOK AND x.GUN >= DATEADD(day, -90, CAST(GETDATE() AS date)) AND x.MIKTAR > 0)
"@
        $top = 0.0; foreach ($r in $olu.Rows) { if ($r.DEGER -isnot [DBNull]) { $top += [double]$r.DEGER } }
        $liste = @($olu.Rows | Sort-Object { -[double]$(if ($_.DEGER -is [DBNull]) { 0 } else { $_.DEGER }) } | Select-Object -First 150 | ForEach-Object {
            ,@((M $_.KOD), (M $_.AD), (D $_.MIKTAR), (D $_.MALIYET), (D $_.DEGER), $(if ($_.SON_SATIS -is [DBNull]) { "" } else { ([datetime]$_.SON_SATIS).ToString("dd.MM.yyyy") })) })
        $veri.olu = [ordered]@{ adet = $olu.Rows.Count; deger = [Math]::Round($top, 2); liste = $liste }
    } catch { [void]$hatalar.Add("Satilmayan stok: " + $_.Exception.Message); Yaz "HATA olu: $($_.Exception.Message)" }

    # ---- 5) Kasa iptalleri (son 30 gun) ----
    try {
        Yaz "5) Kasa iptalleri..."
        $ip = Tablo @"
SELECT PERSONEL, SUM(CASE WHEN SATIR_MI = 1 THEN 1 ELSE 0 END) AS SATIR, SUM(CASE WHEN SATIR_MI = 1 THEN CAST(TUTAR AS float) ELSE 0 END) AS SATIR_T,
       SUM(CASE WHEN SATIR_MI = 0 THEN 1 ELSE 0 END) AS FIS, SUM(CASE WHEN SATIR_MI = 0 THEN CAST(TUTAR AS float) ELSE 0 END) AS FIS_T
FROM dbo.FIS_POS_IPTAL WHERE TARIH >= DATEADD(day, -30, GETDATE()) GROUP BY PERSONEL
"@
        $fisSay = [int](Tablo "SELECT COUNT(*) AS N FROM dbo.FIS_POS WHERE KAPANIS_TARIHI >= DATEADD(day, -30, GETDATE())").Rows[0].N
        $saatler = @((Tablo "SELECT DATEPART(hour, TARIH) AS S, COUNT(*) AS N FROM dbo.FIS_POS_IPTAL WHERE TARIH >= DATEADD(day, -30, GETDATE()) GROUP BY DATEPART(hour, TARIH) ORDER BY S").Rows | ForEach-Object { ,@([int]$_.S, [int]$_.N) })
        $kisiler = @()
        foreach ($r in $ip.Rows) {
            $ad = ""
            if ($r.PERSONEL -isnot [DBNull]) {
                $id = [long]$r.PERSONEL
                try {
                    $t = Tablo "SELECT TOP 1 TABLO FROM dbo.SEQUNCES WHERE ID = $id"
                    if ($t.Rows.Count) {
                        $tablo = [string]$t.Rows[0].TABLO
                        $tk = @((Tablo "SELECT c.name FROM sys.columns c WHERE c.object_id = OBJECT_ID('dbo.$tablo')").Rows | ForEach-Object { [string]$_.name })
                        $ak = @("AD", "ADI", "AD_SOYAD", "ADSOYAD", "KULLANICI_ADI", "UNVAN") | Where-Object { $tk -contains $_ } | Select-Object -First 1
                        if ($ak) { $a = Tablo "SELECT TOP 1 CAST([$ak] AS nvarchar(200)) AS A FROM dbo.[$tablo] WHERE ID = $id"; if ($a.Rows.Count) { $ad = M $a.Rows[0].A } }
                    }
                } catch {}
                if (-not $ad) { $ad = "Kasiyer $id" }
            }
            $kisiler += ,@($ad, [int]$r.SATIR, (D $r.SATIR_T), [int]$r.FIS, (D $r.FIS_T))
        }
        $veri.iptal = [ordered]@{ fisSayisi = $fisSay; kisiler = $kisiler; saatler = $saatler }
    } catch { [void]$hatalar.Add("Kasa iptalleri: " + $_.Exception.Message); Yaz "HATA iptal: $($_.Exception.Message)" }

    # ---- 5b) Fiyat farki / iskonto belgeleri (tedarikci destegi) ----
    # Mal olmayan "fiyat farki" ve "iskonto" kartlarina yazilan belge satirlari. Urun karina katilmaz (hangi urune ait
    # oldugu bilinmez) ama sirketin karidir: aylik ve donem karina AYRI satir olarak eklenir, firma bazinda gosterilir.
    # Isaret: mali cikis yonundeki belge (bizim kestigimiz fiyat farki faturasi, alistan iade) = gelir;
    # giris yonundeki (tedarikcinin bize kestigi fiyat farki) = gider.
    try {
        Yaz "5b) Fiyat farki / iskonto belgeleri..."
        Calistir @"
IF OBJECT_ID('tempdb..#ff') IS NOT NULL DROP TABLE #ff;
SELECT CAST(f.FIS_TARIHI AS date) AS GUN, f.CARI, ISNULL(c.AD, '') AS CARI_AD, FT.AD AS TUR,
       -$g * CAST(ISNULL(d.TOPLAM_KDV_MATRAHI, 0) AS float) AS TUTAR
INTO #ff
FROM dbo.FIS f JOIN dbo.FIS_DETAY d ON d.FIS = f.ID JOIN dbo.FIS_TURU FT ON FT.ID = f.FIS_TURU JOIN dbo.STOK s ON s.ID = d.STOK
LEFT JOIN dbo.CARI c ON c.ID = f.CARI
WHERE f.FIS_TARIHI >= DATEADD(month, DATEDIFF(month, 0, GETDATE()) - 6, 0) AND ISNULL(f.AKTIF, 1) = 1 AND f.FIS_TURU <> 18 AND $g <> 0
  AND (s.AD LIKE N'%FIYAT FARK%' OR s.AD LIKE N'%F' + NCHAR(304) + N'YAT FARK%' OR s.AD LIKE N'%ISKONTO%' OR s.AD LIKE N'%' + NCHAR(304) + N'SKONTO%');
"@
        $ffAy = @((Tablo "SELECT CONVERT(char(7), DATEADD(month, DATEDIFF(month, 0, GUN), 0), 120) AS AY, SUM(TUTAR) AS T FROM #ff GROUP BY DATEADD(month, DATEDIFF(month, 0, GUN), 0) ORDER BY 1").Rows | ForEach-Object { ,@((M $_.AY), (D $_.T)) })
        $ff90 = (Tablo "SELECT SUM(TUTAR) AS T FROM #ff WHERE GUN >= DATEADD(day, -90, CAST(GETDATE() AS date))").Rows[0].T
        $ffCari = @((Tablo "SELECT TOP 20 CARI_AD, SUM(TUTAR) AS T, COUNT(*) AS N, MAX(GUN) AS SON FROM #ff GROUP BY CARI_AD HAVING ABS(SUM(TUTAR)) >= 1 ORDER BY ABS(SUM(TUTAR)) DESC").Rows |
            ForEach-Object { ,@((M $_.CARI_AD), (D $_.T), [int]$_.N, $(if ($_.SON -is [DBNull]) { "" } else { ([datetime]$_.SON).ToString("dd.MM.yyyy") })) })
        $veri.fiyatFarki = [ordered]@{ son90 = D $ff90; aylar = $ffAy; cariler = $ffCari }
    } catch { [void]$hatalar.Add("Fiyat farki: " + $_.Exception.Message); Yaz "HATA fiyat farki: $($_.Exception.Message)" }

    # ---- 6) Sermaye: para nerede bagli? (stok + musteri alacagi - tedarikci borcu) ----
    # Uc ayri parca (stok / hiz / cari): biri hata verirse digerleri yine raporda cikar.
    $veri.sermaye = [ordered]@{}
    $son90 = "DATEADD(day, -90, CAST(GETDATE() AS date))"
    try {
        Yaz "6a) Sermaye - stok..."
        Calistir @"
IF OBJECT_ID('tempdb..#sd') IS NOT NULL DROP TABLE #sd;
SELECT st.STOK, k.KOD, k.AD, st.MIKTAR, s.MALIYET, CAST(NULL AS date) AS SON_SATIS, CAST(0 AS float) AS M90
INTO #sd
FROM #stok st JOIN #kdv k ON k.STOK = st.STOK LEFT JOIN #son s ON s.STOK = st.STOK
WHERE st.MIKTAR IS NOT NULL AND st.MIKTAR <> 0;
UPDATE d SET SON_SATIS = x.SON, M90 = x.M90
FROM #sd d JOIN (SELECT STOK, MAX(CASE WHEN MIKTAR > 0 THEN GUN END) AS SON, SUM(CASE WHEN GUN >= $son90 THEN MIKTAR ELSE 0 END) AS M90 FROM #sat GROUP BY STOK) x ON x.STOK = d.STOK;
"@
        $sk = (Tablo @"
SELECT
  SUM(CASE WHEN MIKTAR > 0 AND MALIYET IS NOT NULL THEN MIKTAR * MALIYET ELSE 0 END) AS DEGER,
  SUM(CASE WHEN MIKTAR > 0 AND MALIYET IS NOT NULL AND SON_SATIS >= DATEADD(day, -30, CAST(GETDATE() AS date)) THEN MIKTAR * MALIYET ELSE 0 END) AS HIZLI,
  SUM(CASE WHEN MIKTAR > 0 AND MALIYET IS NOT NULL AND SON_SATIS < DATEADD(day, -30, CAST(GETDATE() AS date)) AND SON_SATIS >= $son90 THEN MIKTAR * MALIYET ELSE 0 END) AS YAVAS,
  SUM(CASE WHEN MIKTAR > 0 AND MALIYET IS NOT NULL AND (SON_SATIS IS NULL OR SON_SATIS < $son90) THEN MIKTAR * MALIYET ELSE 0 END) AS OLU,
  SUM(CASE WHEN MIKTAR > 0 THEN 1 ELSE 0 END) AS CESIT,
  SUM(CASE WHEN MIKTAR > 0 AND MALIYET IS NULL THEN 1 ELSE 0 END) AS MALIYETSIZ,
  SUM(CASE WHEN MIKTAR < 0 THEN 1 ELSE 0 END) AS EKSI
FROM #sd
"@).Rows[0]
        $stokBuyuk = @((Tablo @"
SELECT TOP 25 KOD, AD, MIKTAR, MALIYET, MIKTAR * MALIYET AS DEGER, M90, SON_SATIS
FROM #sd WHERE MIKTAR > 0 AND MALIYET IS NOT NULL ORDER BY MIKTAR * MALIYET DESC
"@).Rows | ForEach-Object { ,@((M $_.KOD), (M $_.AD), (D $_.MIKTAR), (D $_.MALIYET), (D $_.DEGER), (D $_.M90), (T $_.SON_SATIS)) })
        $veri.sermaye.stok = [ordered]@{ deger = D $sk.DEGER; hizli = D $sk.HIZLI; yavas = D $sk.YAVAS; olu = D $sk.OLU; cesit = I $sk.CESIT; maliyetsiz = I $sk.MALIYETSIZ; eksi = I $sk.EKSI; buyuk = $stokBuyuk }
    } catch { [void]$hatalar.Add("Sermaye (stok): " + $_.Exception.Message); Yaz "HATA sermaye stok: $($_.Exception.Message)" }

    try {
        Yaz "6b) Sermaye - satis/alis hizi..."
        # Satilan malin maliyeti (90 gun) ve firma satislari (KDV dahil) - gun hesaplari icin
        $smm = (Tablo "SELECT SUM(CASE WHEN MALIYET IS NOT NULL THEN M90 * MALIYET ELSE 0 END) AS SMM FROM #ay").Rows[0].SMM
        $firma = (Tablo "SELECT SUM(TUTAR * (1 + KDV / 100.0)) AS T FROM #sat WHERE KASA = 0 AND GUN >= $son90").Rows[0].T
        $alis90 = (Tablo @"
SELECT SUM(CAST(d.TOPLAM_KDV_MATRAHI AS float) * (1 + k.KDV / 100.0)) AS ALIS
FROM dbo.FIS f JOIN dbo.FIS_DETAY d ON d.FIS = f.ID JOIN dbo.FIS_TURU FT ON FT.ID = f.FIS_TURU JOIN #kdv k ON k.STOK = d.STOK
WHERE f.FIS_TURU IN (1, 5) AND ISNULL(f.AKTIF, 1) = 1 AND f.FIS_TARIHI >= DATEADD(day, -90, GETDATE()) AND $g <> 0 AND d.MIKTAR_FIS > 0
"@).Rows[0].ALIS
        $veri.sermaye.smm90 = D $smm; $veri.sermaye.firmaSatis90 = D $firma; $veri.sermaye.alis90 = D $alis90
    } catch { [void]$hatalar.Add("Sermaye (hiz): " + $_.Exception.Message); Yaz "HATA sermaye hiz: $($_.Exception.Message)" }

    try {
        Yaz "6c) Sermaye - cari alacak / borc..."
        # Cari bakiyeler: + cari bize borclu (alacagimiz), - biz cariye borcluyuz. Kasa (perakende) carisi haric.
        Calistir @"
IF OBJECT_ID('tempdb..#cb') IS NOT NULL DROP TABLE #cb;
SELECT c.ID, c.KOD, c.AD, CAST(SUM(b.BAKIYE) AS float) AS BAKIYE INTO #cb
FROM dbo.CARI_BAKIYELER b JOIN dbo.CARI c ON c.ID = b.ID
WHERE b.DOVIZ_AD = 'TRY' AND c.ID <> COALESCE((SELECT TOP 1 VARSAYILANCARI FROM dbo.FIRMASABITLERI), -1)
GROUP BY c.ID, c.KOD, c.AD HAVING ABS(SUM(b.BAKIYE)) >= 1;
IF OBJECT_ID('tempdb..#ch') IS NOT NULL DROP TABLE #ch;
SELECT f.CARI, MAX(f.FIS_TARIHI) AS SON INTO #ch FROM dbo.FIS f WHERE f.CARI IN (SELECT ID FROM #cb) AND ISNULL(f.AKTIF, 1) = 1 GROUP BY f.CARI;
"@
        $cs = (Tablo @"
SELECT SUM(CASE WHEN b.BAKIYE > 0 THEN b.BAKIYE ELSE 0 END) AS ALACAK, SUM(CASE WHEN b.BAKIYE > 0 THEN 1 ELSE 0 END) AS ALACAK_N,
       SUM(CASE WHEN b.BAKIYE < 0 THEN -b.BAKIYE ELSE 0 END) AS BORC, SUM(CASE WHEN b.BAKIYE < 0 THEN 1 ELSE 0 END) AS BORC_N,
       SUM(CASE WHEN b.BAKIYE > 0 AND (h.SON IS NULL OR h.SON < DATEADD(day, -180, GETDATE())) THEN b.BAKIYE ELSE 0 END) AS RISKLI,
       SUM(CASE WHEN b.BAKIYE > 0 AND (h.SON IS NULL OR h.SON < DATEADD(day, -180, GETDATE())) THEN 1 ELSE 0 END) AS RISKLI_N
FROM #cb b LEFT JOIN #ch h ON h.CARI = b.ID
"@).Rows[0]
        $veri.sermaye.alacaklar = @((Tablo "SELECT TOP 25 b.KOD, b.AD, b.BAKIYE, h.SON FROM #cb b LEFT JOIN #ch h ON h.CARI = b.ID WHERE b.BAKIYE > 0 ORDER BY b.BAKIYE DESC").Rows |
            ForEach-Object { ,@((M $_.KOD), (M $_.AD), (D $_.BAKIYE), (T $_.SON)) })
        $veri.sermaye.borclar = @((Tablo "SELECT TOP 25 b.KOD, b.AD, -b.BAKIYE AS BORC, h.SON FROM #cb b LEFT JOIN #ch h ON h.CARI = b.ID WHERE b.BAKIYE < 0 ORDER BY b.BAKIYE ASC").Rows |
            ForEach-Object { ,@((M $_.KOD), (M $_.AD), (D $_.BORC), (T $_.SON)) })
        $veri.sermaye.alacak = D $cs.ALACAK; $veri.sermaye.alacakN = I $cs.ALACAK_N; $veri.sermaye.riskli = D $cs.RISKLI; $veri.sermaye.riskliN = I $cs.RISKLI_N
        $veri.sermaye.borc = D $cs.BORC; $veri.sermaye.borcN = I $cs.BORC_N
    } catch { [void]$hatalar.Add("Sermaye (cari): " + $_.Exception.Message); Yaz "HATA sermaye cari: $($_.Exception.Message)" }

    # ---- 6d) Sermaye hareketi: her ay stoga ne girdi (alis), ne cikti (satilan malin maliyeti) ----
    # ALIS: alis ailesi belgeleri, KDV haric, alistan iade eksi. SMM: satilan miktar x o ayki son alis fiyati.
    # DIGER: fire, sayim farki, sarf gibi stok belgeleri (son alis fiyatiyla). Fark = stoga bagla(n)an para.
    try {
        Yaz "6d) Sermaye hareketi (aylik)..."
        $alisAile = "(f.FIS_TURU IN (1, 5, 7) OR FT.AD LIKE N'%Al' + NCHAR(305) + N'%' OR FT.AD LIKE N'%AL' + NCHAR(304) + N'%')"
        $alisAy = @{}
        foreach ($r in (Tablo @"
SELECT CONVERT(char(7), DATEADD(month, DATEDIFF(month, 0, f.FIS_TARIHI), 0), 120) AS AY,
       SUM($g * CAST(ISNULL(d.TOPLAM_KDV_MATRAHI, 0) AS float)) AS ALIS
FROM dbo.FIS f JOIN dbo.FIS_DETAY d ON d.FIS = f.ID JOIN dbo.FIS_TURU FT ON FT.ID = f.FIS_TURU JOIN #kdv k ON k.STOK = d.STOK
WHERE f.FIS_TARIHI >= DATEADD(month, DATEDIFF(month, 0, GETDATE()) - 6, 0) AND ISNULL(f.AKTIF, 1) = 1 AND f.FIS_TURU <> 18 AND $g <> 0
  AND $alisAile AND NOT $satisAile
GROUP BY DATEADD(month, DATEDIFF(month, 0, f.FIS_TARIHI), 0)
"@).Rows) { $alisAy[(M $r.AY)] = D $r.ALIS }
        $digerAy = @{}
        foreach ($r in (Tablo @"
SELECT CONVERT(char(7), DATEADD(month, DATEDIFF(month, 0, f.FIS_TARIHI), 0), 120) AS AY,
       SUM($g * CAST(d.MIKTAR_FIS AS float) * $carp * s.MALIYET) AS DIGER
FROM dbo.FIS f JOIN dbo.FIS_DETAY d ON d.FIS = f.ID JOIN dbo.FIS_TURU FT ON FT.ID = f.FIS_TURU JOIN #kdv k ON k.STOK = d.STOK JOIN #son s ON s.STOK = d.STOK
WHERE f.FIS_TARIHI >= DATEADD(month, DATEDIFF(month, 0, GETDATE()) - 6, 0) AND ISNULL(f.AKTIF, 1) = 1 AND f.FIS_TURU <> 18 AND $g <> 0
  AND NOT $alisAile AND NOT $satisAile
GROUP BY DATEADD(month, DATEDIFF(month, 0, f.FIS_TARIHI), 0)
"@).Rows) { $digerAy[(M $r.AY)] = D $r.DIGER }
        $smmAy = @{}
        foreach ($r in (Tablo "SELECT CONVERT(char(7), AY, 120) AS AY, SUM(CASE WHEN MALIYET IS NOT NULL THEN MIKTAR * MALIYET ELSE 0 END) AS SMM FROM #ay GROUP BY AY").Rows) { $smmAy[(M $r.AY)] = D $r.SMM }
        $ayListe = @(@($alisAy.Keys) + @($smmAy.Keys) + @($digerAy.Keys) | Sort-Object -Unique)
        $veri.sermayeAy = @($ayListe | ForEach-Object { ,@($_, $alisAy[$_], $smmAy[$_], $digerAy[$_]) })
    } catch { [void]$hatalar.Add("Sermaye hareketi: " + $_.Exception.Message); Yaz "HATA sermaye hareketi: $($_.Exception.Message)" }

    # ---- 7) Aylik incelemede kari en cok dusuren urunler (her ay ilk 8) ----
    try {
        Yaz "7) Aylarin incelemesi..."
        $veri.ayZarar = @((Tablo @"
SELECT AY, KOD, AD, MIKTAR, TUTAR, MAL FROM (
  SELECT CONVERT(char(7), a.AY, 120) AS AY, k.KOD, k.AD, a.MIKTAR, a.TUTAR, a.MIKTAR * a.MALIYET AS MAL,
         ROW_NUMBER() OVER (PARTITION BY a.AY ORDER BY a.MIKTAR * a.MALIYET - a.TUTAR DESC) AS R
  FROM #ay a JOIN #kdv k ON k.STOK = a.STOK
  WHERE a.MALIYET IS NOT NULL AND a.MIKTAR > 0 AND a.MIKTAR * a.MALIYET > a.TUTAR) x
WHERE R <= 8 ORDER BY AY, R
"@).Rows | ForEach-Object { ,@((M $_.AY), (M $_.KOD), (M $_.AD), (D $_.MIKTAR), (D $_.TUTAR), (D $_.MAL)) })
    } catch { [void]$hatalar.Add("Ay incelemesi: " + $_.Exception.Message); Yaz "HATA ay: $($_.Exception.Message)" }

    # ---- 8) Buyume plani icin veriler ----
    $veri.buyume = [ordered]@{}
    $s30 = "DATEADD(day, -30, CAST(GETDATE() AS date))"
    try {
        Yaz "8a) Buyume - tukenen cok satanlar..."
        $veri.buyume.tukenen = @((Tablo @"
SELECT TOP 60 k.KOD, k.AD, x.M30, x.T30, ISNULL(st.MIKTAR, 0) AS STOK, s.MALIYET
FROM (SELECT STOK, SUM(MIKTAR) AS M30, SUM(TUTAR) AS T30 FROM #sat WHERE GUN >= $s30 GROUP BY STOK HAVING SUM(MIKTAR) > 0 AND SUM(TUTAR) > 0) x
JOIN #kdv k ON k.STOK = x.STOK LEFT JOIN #stok st ON st.STOK = x.STOK LEFT JOIN #son s ON s.STOK = x.STOK
WHERE ISNULL(st.MIKTAR, 0) < x.M30 / 30.0 * 3
ORDER BY x.T30 DESC
"@).Rows | ForEach-Object { ,@((M $_.KOD), (M $_.AD), (D $_.M30), (D $_.T30), (D $_.STOK), (D $_.MALIYET)) })
    } catch { [void]$hatalar.Add("Buyume (tukenen): " + $_.Exception.Message); Yaz "HATA buyume tukenen: $($_.Exception.Message)" }
    try {
        Yaz "8b) Buyume - musteri trafigi..."
        $veri.buyume.fisAy = @((Tablo "SELECT CONVERT(char(7), DATEADD(month, DATEDIFF(month, 0, KAPANIS_TARIHI), 0), 120) AS AY, COUNT(*) AS N FROM dbo.FIS_POS WHERE KAPANIS_TARIHI >= DATEADD(month, DATEDIFF(month, 0, GETDATE()) - 6, 0) GROUP BY DATEADD(month, DATEDIFF(month, 0, KAPANIS_TARIHI), 0) ORDER BY 1").Rows |
            ForEach-Object { ,@((M $_.AY), (I $_.N)) })
        $veri.buyume.kasaAy = @((Tablo "SELECT CONVERT(char(7), DATEADD(month, DATEDIFF(month, 0, GUN), 0), 120) AS AY, SUM(TUTAR) AS T FROM #sat WHERE KASA = 1 GROUP BY DATEADD(month, DATEDIFF(month, 0, GUN), 0) ORDER BY 1").Rows |
            ForEach-Object { ,@((M $_.AY), (D $_.T)) })
        # 1900-01-01 pazartesi: (gun farki % 7) 0 = pazartesi ... 6 = pazar
        $veri.buyume.gun = @((Tablo "SELECT DATEDIFF(day, 0, KAPANIS_TARIHI) % 7 AS G, COUNT(*) AS N FROM dbo.FIS_POS WHERE KAPANIS_TARIHI >= DATEADD(day, -90, GETDATE()) GROUP BY DATEDIFF(day, 0, KAPANIS_TARIHI) % 7 ORDER BY 1").Rows |
            ForEach-Object { ,@((I $_.G), (I $_.N)) })
        $veri.buyume.saat = @((Tablo "SELECT DATEPART(hour, KAPANIS_TARIHI) AS S, COUNT(*) AS N FROM dbo.FIS_POS WHERE KAPANIS_TARIHI >= DATEADD(day, -90, GETDATE()) GROUP BY DATEPART(hour, KAPANIS_TARIHI) ORDER BY 1").Rows |
            ForEach-Object { ,@((I $_.S), (I $_.N)) })
    } catch { [void]$hatalar.Add("Buyume (trafik): " + $_.Exception.Message); Yaz "HATA buyume trafik: $($_.Exception.Message)" }
    try {
        Yaz "8c) Buyume - yukselen / dusen urunler..."
        Calistir @"
IF OBJECT_ID('tempdb..#ud') IS NOT NULL DROP TABLE #ud;
SELECT STOK, SUM(CASE WHEN GUN >= $s30 THEN TUTAR ELSE 0 END) AS T30,
       SUM(CASE WHEN GUN < $s30 AND GUN >= DATEADD(day, -90, CAST(GETDATE() AS date)) THEN TUTAR ELSE 0 END) / 2.0 AS ONCE
INTO #ud FROM #sat GROUP BY STOK;
"@
        $ud = "SELECT TOP 15 k.KOD, k.AD, u.T30, u.ONCE FROM #ud u JOIN #kdv k ON k.STOK = u.STOK WHERE u.T30 >= 0 AND u.ONCE >= 0 AND (u.T30 + u.ONCE) > 1000"
        $veri.buyume.yukselen = @((Tablo "$ud AND u.T30 > u.ONCE * 1.3 ORDER BY u.T30 - u.ONCE DESC").Rows | ForEach-Object { ,@((M $_.KOD), (M $_.AD), (D $_.T30), (D $_.ONCE)) })
        $veri.buyume.dusen = @((Tablo "$ud AND u.T30 < u.ONCE * 0.7 ORDER BY u.ONCE - u.T30 DESC").Rows | ForEach-Object { ,@((M $_.KOD), (M $_.AD), (D $_.T30), (D $_.ONCE)) })
        # Cironun %80'ini kac urun yapiyor (90 gun)
        $abc = (Tablo @"
SELECT COUNT(*) AS TUM, SUM(CASE WHEN KUM - T90 < TOPLAM * 0.8 THEN 1 ELSE 0 END) AS A FROM (
  SELECT T90, SUM(T90) OVER (ORDER BY T90 DESC ROWS UNBOUNDED PRECEDING) AS KUM, SUM(T90) OVER () AS TOPLAM
  FROM (SELECT STOK, SUM(T90) AS T90 FROM #ay GROUP BY STOK HAVING SUM(T90) > 0) u) x
"@).Rows[0]
        $veri.buyume.abc = [ordered]@{ tum = I $abc.TUM; a = I $abc.A }
    } catch { [void]$hatalar.Add("Buyume (urunler): " + $_.Exception.Message); Yaz "HATA buyume urun: $($_.Exception.Message)" }
    try {
        Yaz "8d) Buyume - firma musterileri..."
        $veri.buyume.firmalar = @((Tablo @"
SELECT TOP 20 c.KOD, c.AD, x.T30, x.ONCE, x.SON FROM (
  SELECT CARI, SUM(CASE WHEN GUN >= $s30 THEN TUTAR ELSE 0 END) AS T30,
         SUM(CASE WHEN GUN < $s30 AND GUN >= DATEADD(day, -120, CAST(GETDATE() AS date)) THEN TUTAR ELSE 0 END) / 3.0 AS ONCE, MAX(GUN) AS SON
  FROM #sat WHERE KASA = 0 AND CARI IS NOT NULL GROUP BY CARI) x
JOIN dbo.CARI c ON c.ID = x.CARI
WHERE x.ONCE >= 2000 AND x.T30 < x.ONCE * 0.6
ORDER BY x.ONCE - x.T30 DESC
"@).Rows | ForEach-Object { ,@((M $_.KOD), (M $_.AD), (D $_.T30), (D $_.ONCE), (T $_.SON)) })
        $fs = (Tablo "SELECT COUNT(DISTINCT CARI) AS N, SUM(TUTAR) AS T FROM #sat WHERE KASA = 0 AND CARI IS NOT NULL AND GUN >= $s30").Rows[0]
        $veri.buyume.firmaN = I $fs.N; $veri.buyume.firma30 = D $fs.T
    } catch { [void]$hatalar.Add("Buyume (firmalar): " + $_.Exception.Message); Yaz "HATA buyume firma: $($_.Exception.Message)" }

    # ---- 9) Oneriler (Karlilik -> Oneriler): dogru fiyatlandirma ve fis tutarini artirma ----
    # Kasa fisleri (FIS_POS'a bagli belgeler) son 60 gun: her fiste hangi urunler birlikte alinmis.
    $veri.oneri = [ordered]@{}
    try {
        Yaz "9a) Oneriler - kasa fisleri..."
        # Alisveris posetini hesaba katma: neredeyse her fiste var; eslestirmeleri, "musteri ceken" ve kasa onu listelerini
        # bozuyordu. Adinda POSET / TORBA gecen ve raf fiyati 3 TL'ye kadar olan ya da KASA / ALISVERIS / TASIMA poseti olan
        # kartlar. Cop poseti, buzdolabi poseti gibi gercek urunler (pahali ya da COP/BUZDOLABI/DONDURUCU gecen) kalir.
        Calistir @"
IF OBJECT_ID('tempdb..#poset') IS NOT NULL DROP TABLE #poset;
SELECT k.STOK INTO #poset FROM #kdv k LEFT JOIN #fiyat p ON p.STOK = k.STOK
WHERE (k.AD LIKE N'%PO' + NCHAR(350) + N'ET%' OR k.AD LIKE N'%POSET%' OR k.AD LIKE N'%TORBA%')
  AND NOT (k.AD LIKE N'%' + NCHAR(199) + NCHAR(214) + N'P%' OR k.AD LIKE N'%COP %' OR k.AD LIKE N'%COP PO%' OR k.AD LIKE N'%BUZDOLAB%' OR k.AD LIKE N'%DONDURUCU%'
           OR k.AD LIKE N'%K' + NCHAR(304) + N'L' + NCHAR(304) + N'TL%' OR k.AD LIKE N'%KILITLI%' OR k.AD LIKE N'%FIRIN%' OR k.AD LIKE N'%BEBEK%')
  AND (ISNULL(p.FIYAT, 0) <= 3 OR k.AD LIKE N'%KASA%' OR k.AD LIKE N'%ALI' + NCHAR(350) + N'VER%' OR k.AD LIKE N'%ALISVERIS%' OR k.AD LIKE N'%TA' + NCHAR(350) + N'IMA%' OR k.AD LIKE N'%TASIMA%');
CREATE CLUSTERED INDEX i ON #poset (STOK);
IF OBJECT_ID('tempdb..#fd') IS NOT NULL DROP TABLE #fd;
SELECT f.ID AS FIS, d.STOK,
       SUM(-$g * CAST(d.MIKTAR_FIS AS float) * $carp) AS MIKTAR,
       SUM(-$g * CASE WHEN ISNULL(d.TOPLAM_KDV_MATRAHI, 0) <> 0 THEN CAST(d.TOPLAM_KDV_MATRAHI AS float)
                     ELSE CAST(d.MIKTAR_FIS AS float) * CAST(ISNULL(d.FIYAT, 0) AS float) / (1 + k.KDV / 100.0) END) AS TUTAR
INTO #fd
FROM dbo.FIS f JOIN dbo.FIS_DETAY d ON d.FIS = f.ID JOIN dbo.FIS_TURU FT ON FT.ID = f.FIS_TURU JOIN #kdv k ON k.STOK = d.STOK
WHERE f.FIS_TARIHI >= DATEADD(day, -60, CAST(GETDATE() AS date)) AND ISNULL(f.AKTIF, 1) = 1 AND f.FIS_TURU <> 18 AND $satisAile AND $g <> 0
  AND EXISTS (SELECT 1 FROM dbo.FIS_POS p WHERE p.FIS = f.ID) AND NOT EXISTS (SELECT 1 FROM #poset ps WHERE ps.STOK = d.STOK)
GROUP BY f.ID, d.STOK HAVING SUM(-$g * CAST(d.MIKTAR_FIS AS float)) > 0;
CREATE CLUSTERED INDEX i ON #fd (FIS, STOK);
IF OBJECT_ID('tempdb..#fs') IS NOT NULL DROP TABLE #fs;
SELECT FIS, COUNT(*) AS KALEM, SUM(TUTAR) AS TUTAR INTO #fs FROM #fd GROUP BY FIS;
IF OBJECT_ID('tempdb..#pen') IS NOT NULL DROP TABLE #pen;
SELECT STOK, COUNT(*) AS FISN, SUM(MIKTAR) AS M60, SUM(TUTAR) AS T60 INTO #pen FROM #fd GROUP BY STOK;
CREATE CLUSTERED INDEX i ON #pen (STOK);
"@
        $fo = (Tablo "SELECT COUNT(*) AS N, AVG(TUTAR) AS ORT, AVG(CAST(KALEM AS float)) AS KALEM, SUM(CASE WHEN KALEM = 1 THEN 1 ELSE 0 END) AS TEK FROM #fs").Rows[0]
        if ((D $fo.KALEM) -gt 150) { throw "Kasa belgeleri fis fis degil (belge basina $(D $fo.KALEM) kalem) - sepet incelemesi yapilamadi" }
        $veri.oneri.poset = @((Tablo "SELECT TOP 10 k.AD FROM #poset ps JOIN #kdv k ON k.STOK = ps.STOK ORDER BY k.AD").Rows | ForEach-Object { M $_.AD })
        $veri.oneri.fis = [ordered]@{ n = I $fo.N; ort = D $fo.ORT; kalem = D $fo.KALEM; tek = I $fo.TEK; gun = 60 }
        $veri.oneri.dagilim = @((Tablo @"
SELECT CASE WHEN KALEM = 1 THEN '1' WHEN KALEM = 2 THEN '2' WHEN KALEM <= 4 THEN '3-4' WHEN KALEM <= 9 THEN '5-9' ELSE '10+' END AS K,
       COUNT(*) AS N, AVG(TUTAR) AS ORT, SUM(TUTAR) AS TOP
FROM #fs GROUP BY CASE WHEN KALEM = 1 THEN '1' WHEN KALEM = 2 THEN '2' WHEN KALEM <= 4 THEN '3-4' WHEN KALEM <= 9 THEN '5-9' ELSE '10+' END
"@).Rows | ForEach-Object { ,@((M $_.K), (I $_.N), (D $_.ORT), (D $_.TOP)) })
    } catch { [void]$hatalar.Add("Oneriler (fis): " + $_.Exception.Message); Yaz "HATA oneri fis: $($_.Exception.Message)" }

    try {
        Yaz "9b) Oneriler - fiyatlandirma..."
        # Urun grubu (ERP STOK_GRUP) ve gruptaki satilan urunlerin ortanca marji: hedef fiyat icin olcu.
        Calistir @"
IF OBJECT_ID('tempdb..#fu') IS NOT NULL DROP TABLE #fu;
SELECT k.STOK, k.KOD, k.AD, ISNULL(g.AD, '') AS GRUP, ISNULL(s2.STOK_GRUP, 0) AS GID, k.KDV, p.FIYAT, s.MALIYET AS ALIS,
       (p.FIYAT / (1 + k.KDV / 100.0) - s.MALIYET) / NULLIF(p.FIYAT / (1 + k.KDV / 100.0), 0) AS MARJ,
       ISNULL(pn.FISN, 0) AS FISN,
       ISNULL((SELECT SUM(x.MIKTAR) FROM #sat x WHERE x.STOK = k.STOK AND x.GUN >= DATEADD(day, -30, CAST(GETDATE() AS date))), 0) AS M30,
       CAST(0 AS float) AS GMARJ, 0 AS SIRA
INTO #fu
FROM #kdv k JOIN #fiyat p ON p.STOK = k.STOK JOIN #son s ON s.STOK = k.STOK JOIN dbo.STOK s2 ON s2.ID = k.STOK
LEFT JOIN dbo.STOK_GRUP g ON g.ID = s2.STOK_GRUP LEFT JOIN #pen pn ON pn.STOK = k.STOK
WHERE s.MALIYET > 0 AND p.FIYAT > 0;
DELETE FROM #fu WHERE M30 <= 0 OR STOK IN (SELECT STOK FROM #poset);
UPDATE f SET GMARJ = x.GM FROM #fu f JOIN (SELECT DISTINCT GID, PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY MARJ) OVER (PARTITION BY GID) AS GM FROM #fu WHERE MARJ BETWEEN -0.5 AND 0.9) x ON x.GID = f.GID;
UPDATE f SET SIRA = x.R FROM #fu f JOIN (SELECT STOK, ROW_NUMBER() OVER (ORDER BY FISN DESC, M30 DESC) AS R FROM #fu) x ON x.STOK = f.STOK;
"@
        $alan = "KOD, AD, GRUP, KDV, FIYAT, ALIS, MARJ, GMARJ, FISN, M30, SIRA"
        $sat = { param($r) ,@((M $r.KOD), (M $r.AD), (M $r.GRUP), (D $r.KDV), (D $r.FIYAT), (D $r.ALIS), [Math]::Round([double]$(if ($r.MARJ -is [DBNull]) { 0 } else { $r.MARJ }), 4), [Math]::Round([double]$(if ($r.GMARJ -is [DBNull]) { 0 } else { $r.GMARJ }), 4), (I $r.FISN), (D $r.M30), (I $r.SIRA)) }
        # Musteri ceken urunler: en cok fiste gecen 150 urun (fiyati herkesin bildigi urunler)
        $veri.oneri.kvi = @((Tablo "SELECT TOP 150 $alan FROM #fu WHERE FISN > 0 ORDER BY SIRA").Rows | ForEach-Object { & $sat $_ })
        # Kar firsati: cok fiste gecmeyen (ilk 300 disi), marji grubunun belirgin altinda kalan urunler
        $veri.oneri.firsat = @((Tablo "SELECT TOP 120 $alan FROM #fu WHERE SIRA > 300 AND M30 >= 3 AND MARJ >= 0 AND MARJ < GMARJ - 0.05 AND MARJ < 0.25 ORDER BY M30 * ALIS * (GMARJ - MARJ) DESC").Rows | ForEach-Object { & $sat $_ })
        # One cikarilacaklar: marji grubunun ustunde, az fiste gecen urunler (gorunur yere konursa kar getirir)
        $veri.oneri.oneCikar = @((Tablo "SELECT TOP 40 $alan FROM #fu WHERE SIRA > 300 AND MARJ >= GMARJ + 0.05 AND MARJ < 0.8 AND M30 >= 2 ORDER BY M30 * FIYAT / (1 + KDV / 100.0) * MARJ DESC").Rows | ForEach-Object { & $sat $_ })
        # Kasa onu adaylari: ucuz (KDV dahil 40 TL'ye kadar), marji yuksek, sik alinan, fiste 1-2 adet
        $veri.oneri.kasaOnu = @((Tablo @"
SELECT TOP 30 $alan FROM #fu f
WHERE f.FIYAT <= 40 AND f.MARJ >= 0.25 AND f.FISN >= 20
  AND (SELECT AVG(x.MIKTAR) FROM #fd x WHERE x.STOK = f.STOK) <= 2.5
ORDER BY f.FISN * f.MARJ DESC
"@).Rows | ForEach-Object { & $sat $_ })
        # Fiyat sonu: kurusu ,90 / ,95 / ,99 / ,50 / ,00 / ,25 / ,75 olmayan cok satanlar
        $veri.oneri.kurus = @((Tablo @"
SELECT TOP 40 $alan FROM #fu
WHERE CAST(ROUND(FIYAT * 100, 0) AS int) % 100 NOT IN (0, 25, 50, 75, 90, 95, 99) AND FIYAT >= 5
ORDER BY M30 DESC
"@).Rows | ForEach-Object { & $sat $_ })
        $veri.oneri.kurusN = I (Tablo "SELECT COUNT(*) AS N FROM #fu WHERE CAST(ROUND(FIYAT * 100, 0) AS int) % 100 NOT IN (0, 25, 50, 75, 90, 95, 99) AND FIYAT >= 5").Rows[0].N
    } catch { [void]$hatalar.Add("Oneriler (fiyat): " + $_.Exception.Message); Yaz "HATA oneri fiyat: $($_.Exception.Message)" }

    try {
        Yaz "9c) Oneriler - birlikte alinanlar..."
        $nf = I (Tablo "SELECT COUNT(*) AS N FROM #fs").Rows[0].N
        if ($nf -gt 0) {
            Calistir @"
IF OBJECT_ID('tempdb..#top') IS NOT NULL DROP TABLE #top;
SELECT TOP 400 STOK, FISN INTO #top FROM #pen ORDER BY FISN DESC;
CREATE CLUSTERED INDEX i ON #top (STOK);
"@
            $veri.oneri.ciftler = @((Tablo @"
SELECT TOP 150 ka.KOD AS AK, ka.AD AS AA, kb.KOD AS BK, kb.AD AS BA, x.N, ta.FISN AS NA, tb.FISN AS NB,
       CAST(x.N AS float) * $nf / (CAST(ta.FISN AS float) * tb.FISN) AS LIFT
FROM (SELECT a.STOK AS A, b.STOK AS B, COUNT(*) AS N FROM #fd a JOIN #fd b ON b.FIS = a.FIS AND b.STOK > a.STOK
      JOIN #top t1 ON t1.STOK = a.STOK JOIN #top t2 ON t2.STOK = b.STOK GROUP BY a.STOK, b.STOK HAVING COUNT(*) >= 12) x
JOIN #top ta ON ta.STOK = x.A JOIN #top tb ON tb.STOK = x.B JOIN #kdv ka ON ka.STOK = x.A JOIN #kdv kb ON kb.STOK = x.B
WHERE CAST(x.N AS float) * $nf / (CAST(ta.FISN AS float) * tb.FISN) >= 1.5
ORDER BY x.N * LOG(CAST(x.N AS float) * $nf / (CAST(ta.FISN AS float) * tb.FISN)) DESC
"@ 900).Rows | ForEach-Object { ,@((M $_.AK), (M $_.AA), (M $_.BK), (M $_.BA), (I $_.N), (I $_.NA), (I $_.NB), [Math]::Round([double]$_.LIFT, 2)) })
        }
    } catch { [void]$hatalar.Add("Oneriler (birlikte alinanlar): " + $_.Exception.Message); Yaz "HATA oneri cift: $($_.Exception.Message)" }

} catch {
    [void]$hatalar.Add("Genel: " + $_.Exception.Message); Yaz "HATA: $($_.Exception.Message)"
} finally { if ($bag) { try { $bag.Close() } catch {} } }

$veri.hatalar = @($hatalar)
try {
    $json = $veri | ConvertTo-Json -Depth 8 -Compress
    $json = $json.Replace("</", "<\/")
    $html = [System.IO.File]::ReadAllText($Sablon, [System.Text.Encoding]::UTF8)
    $html = $html.Replace("/*VERI*/null", $json)
    [System.IO.File]::WriteAllText($Cikti, $html, (New-Object System.Text.UTF8Encoding($true)))
    Yaz "RAPOR HAZIR: $Cikti"
    if (-not $Gorev) { try { Start-Process $Cikti } catch {} }
} catch { Yaz "HATA: rapor yazilamadi: $($_.Exception.Message)" }
# KRT Saha'ya gonder (uygulamada Karlilik -> Saglik)
if (DbAnahtar) {
    try {
        $govde = '{"p_veri":' + ($veri | ConvertTo-Json -Depth 8 -Compress) + '}'
        $r = DbCagir "saglik_rapor_yaz" $govde 120
        if ($r.status -eq "ok") { Yaz "KRT Saha'ya gonderildi (uygulamada Karlilik -> Saglik)"; Nabiz ("OK: rapor gonderildi" + $(if ($hatalar.Count) { " (" + $hatalar.Count + " bolum hatali)" } else { "" })) }
        else { Yaz "KRT Saha'ya gonderilemedi: $($r.message)"; Nabiz ("HATA: " + $r.message) }
    } catch { Yaz "KRT Saha'ya gonderilemedi: $($_.Exception.Message)"; Nabiz ("HATA: " + $_.Exception.Message) }
} else { Yaz "Not: db-anahtar.txt yok, rapor yalniz bu bilgisayarda kaldi." }
if ($hatalar.Count) { Yaz "Uyari: $($hatalar.Count) bolum hesaplanamadi (raporun sonunda yazar)." }
if (-not $Gorev) { Read-Host "Kapatmak icin Enter" }
