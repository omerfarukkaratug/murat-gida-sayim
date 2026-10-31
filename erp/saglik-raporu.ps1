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
# =====================================================================
param(
    [string]$SqlServer = "SERVER\ERP12",
    [string]$Database = "",
    [double]$AylikEnflasyon = 2.0,     # satilmayan stokta bekleyen paranin aylik deger kaybi (%)
    [string]$Cikti = ""
)
$Klasor = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $Cikti) { $Cikti = Join-Path $Klasor "magaza-saglik-raporu.html" }
$Sablon = Join-Path $Klasor "saglik-sablon.html"
$Log = Join-Path $Klasor "saglik-raporu-log.txt"
function Yaz($m) { $s = "$(Get-Date -Format 'HH:mm:ss') $m"; Write-Host $s; try { Add-Content -Path $Log -Value $s } catch {} }
$Inv = [Globalization.CultureInfo]::InvariantCulture

$bag = $null
function Tablo($sql, $sn = 600) {
    $cmd = $bag.CreateCommand(); $cmd.CommandText = $sql; $cmd.CommandTimeout = $sn
    $da = New-Object System.Data.SqlClient.SqlDataAdapter($cmd); $dt = New-Object System.Data.DataTable; [void]$da.Fill($dt); return ,$dt
}
function Calistir($sql, $sn = 600) { $cmd = $bag.CreateCommand(); $cmd.CommandText = $sql; $cmd.CommandTimeout = $sn; [void]$cmd.ExecuteNonQuery() }
function D($v) { if ($v -is [DBNull] -or $v -eq $null) { return $null }; return [Math]::Round([double]$v, 2) }
function M($v) { if ($v -is [DBNull] -or $v -eq $null) { return "" }; return ([string]$v).Trim() }

$veri = [ordered]@{ surum = "1"; olusturma = (Get-Date).ToString("yyyy-MM-dd HH:mm"); firma = ""; veritabani = ""; enflasyon = $AylikEnflasyon; hatalar = @() }
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
    Calistir @"
IF OBJECT_ID('tempdb..#kdv') IS NOT NULL DROP TABLE #kdv;
SELECT s.ID AS STOK, CAST(ISNULL(v.KDV_PAREKENDE, 0) AS float) AS KDV, s.KOD, s.AD INTO #kdv FROM dbo.STOK s LEFT JOIN dbo.STOK_VERGI v ON v.ID = s.STOK_VERGI;
CREATE CLUSTERED INDEX i ON #kdv (STOK);
IF OBJECT_ID('tempdb..#sat') IS NOT NULL DROP TABLE #sat;
SELECT d.STOK, CAST(f.FIS_TARIHI AS date) AS GUN,
       CASE WHEN $kasaMi THEN 1 ELSE 0 END AS KASA,
       -$g * CAST(d.MIKTAR_FIS AS float) AS MIKTAR,
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
SELECT d.STOK, f.FIS_TARIHI AS TARIH, d.ID AS DID, CAST(d.TOPLAM_KDV_MATRAHI AS float) / CAST(d.MIKTAR_FIS AS float) AS MALIYET, ISNULL(c.AD, '') AS CARI
INTO #alis
FROM dbo.FIS f JOIN dbo.FIS_DETAY d ON d.FIS = f.ID LEFT JOIN dbo.CARI c ON c.ID = f.CARI
WHERE f.FIS_TURU IN (1, 5) AND ISNULL(f.AKTIF, 1) = 1 AND d.MIKTAR_FIS > 0 AND ISNULL(d.TOPLAM_KDV_MATRAHI, 0) > 0;
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
SELECT SUM(T90) AS CIRO, SUM(K90) AS KASA, SUM(CASE WHEN MALIYET IS NOT NULL THEN T90 ELSE 0 END) AS CIRO_M,
       SUM(CASE WHEN MALIYET IS NOT NULL THEN M90 * MALIYET ELSE 0 END) AS MAL,
       COUNT(DISTINCT CASE WHEN M90 <> 0 THEN STOK END) AS URUN
FROM #ay
"@).Rows[0]
        $veri.ozet = [ordered]@{ ciro = D $oz.CIRO; kasa = D $oz.KASA; ciroMaliyetli = D $oz.CIRO_M; maliyet = D $oz.MAL; urun = [int]$oz.URUN }
        $aylar = @((Tablo @"
SELECT CONVERT(char(7), AY, 120) AS AY, SUM(TUTAR) AS CIRO, SUM(CASE WHEN MALIYET IS NOT NULL THEN TUTAR ELSE 0 END) AS CIRO_M,
       SUM(CASE WHEN MALIYET IS NOT NULL THEN MIKTAR * MALIYET ELSE 0 END) AS MAL
FROM #ay GROUP BY AY ORDER BY AY
"@).Rows | ForEach-Object { ,@((M $_.AY), (D $_.CIRO), (D $_.CIRO_M), (D $_.MAL)) })
        $veri.aylar = $aylar
        # En cok kar getiren ve en cok ciro yapan dusuk marjli urunler
        $urunler = @((Tablo @"
SELECT TOP 400 k.KOD, k.AD, SUM(a.M90) AS M90, SUM(a.T90) AS T90, SUM(CASE WHEN a.MALIYET IS NOT NULL THEN a.M90 * a.MALIYET END) AS MAL
FROM #ay a JOIN #kdv k ON k.STOK = a.STOK GROUP BY k.KOD, k.AD HAVING SUM(a.T90) > 0 ORDER BY SUM(a.T90) DESC
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
    try { Start-Process $Cikti } catch {}
} catch { Yaz "HATA: rapor yazilamadi: $($_.Exception.Message)" }
if ($hatalar.Count) { Yaz "Uyari: $($hatalar.Count) bolum hesaplanamadi (raporun sonunda yazar)." }
Read-Host "Kapatmak icin Enter"
