# =====================================================================
#  KRT Saha - Saglik raporu KONTROL: Nisan / Agustos gibi tuhaf aylarin sebebi.
#  ERP12'yi YALNIZ OKUR. Sonuc: C:\Scripts\kesif-saglik.txt
#   1) Ay x belge turu: satir sayisi, ciro (KDV haric), maliyet, kar
#   2) Her ayda en cok zarar ve en cok kar yazan 15 urun (miktar, ciro, maliyet)
#   3) Maliyeti satis fiyatina gore cok tuhaf olan urunler (alis/satis orani)
# =====================================================================
$SqlServer = "SERVER\ERP12"
$Cikti = "C:\Scripts\kesif-saglik.txt"
$sb = New-Object System.Text.StringBuilder
function Yaz($m) { [void]$sb.AppendLine([string]$m); Write-Host $m }
$bag = New-Object System.Data.SqlClient.SqlConnection("Server=$SqlServer;Database=master;Integrated Security=SSPI;")
function Tablo($sql) { $c = $bag.CreateCommand(); $c.CommandText = $sql; $c.CommandTimeout = 900; $da = New-Object System.Data.SqlClient.SqlDataAdapter($c); $dt = New-Object System.Data.DataTable; [void]$da.Fill($dt); return ,$dt }
function Calistir($sql) { $c = $bag.CreateCommand(); $c.CommandText = $sql; $c.CommandTimeout = 900; [void]$c.ExecuteNonQuery() }
function Dok($dt) { foreach ($r in $dt.Rows) { $p = @(); foreach ($k in $dt.Columns) { $v = $r[$k.ColumnName]; if ($v -is [double]) { $v = [Math]::Round($v, 2) }; $p += "$($k.ColumnName)=$v" }; Yaz ("  " + ($p -join " | ")) } }
try {
    $bag.Open()
    $db = $null
    foreach ($d in (Tablo "SELECT name FROM sys.databases WHERE name LIKE 'ERP12[0-9][0-9][0-9][0-9]' AND state = 0 ORDER BY name DESC").Rows) {
        if ([int](Tablo ("SELECT COUNT(*) AS n FROM [" + $d.name + "].dbo.FIS WITH (NOLOCK) WHERE FIS_TARIHI >= DATEADD(day, -7, GETDATE())")).Rows[0].n -gt 0) { $db = [string]$d.name; break }
    }
    $bag.ChangeDatabase($db); Calistir "SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED"
    Yaz "KESIF-SAGLIK $(Get-Date -Format 'yyyy-MM-dd HH:mm') veri tabani: $db"
    $aile = "(FT.AD LIKE N'%Sat' + NCHAR(305) + NCHAR(351) + N'%' OR FT.AD LIKE N'%SATI' + NCHAR(350) + N'%' OR f.FIS_TURU IN (11, 12, 35, 36))"
    $g = "(CASE WHEN f.FIS_TURU IN (5, 6, 7, 8, 36) AND ISNULL(d.FATRALANDIRILMIS_IRSALIYEMI, 0) = 1 THEN 0 ELSE FT.GIRIS END)"
    Calistir @"
IF OBJECT_ID('tempdb..#kdv') IS NOT NULL DROP TABLE #kdv;
SELECT s.ID AS STOK, CAST(ISNULL(v.KDV_PAREKENDE, 0) AS float) AS KDV, s.KOD, s.AD INTO #kdv FROM dbo.STOK s LEFT JOIN dbo.STOK_VERGI v ON v.ID = s.STOK_VERGI;
CREATE CLUSTERED INDEX i ON #kdv (STOK);
IF OBJECT_ID('tempdb..#sat') IS NOT NULL DROP TABLE #sat;
SELECT d.STOK, DATEADD(month, DATEDIFF(month, 0, f.FIS_TARIHI), 0) AS AY, f.FIS_TURU, FT.AD AS TUR, d.ID AS DID, f.ID AS FID,
       -$g * CAST(d.MIKTAR_FIS AS float) AS MIKTAR,
       CAST(ISNULL(d.TOPLAM_KDV_MATRAHI, 0) AS float) AS MATRAH, CAST(d.MIKTAR_FIS AS float) * CAST(ISNULL(d.FIYAT, 0) AS float) / (1 + k.KDV / 100.0) AS BRUT,
       -$g * CASE WHEN ISNULL(d.TOPLAM_KDV_MATRAHI, 0) <> 0 THEN CAST(d.TOPLAM_KDV_MATRAHI AS float)
                  ELSE CAST(d.MIKTAR_FIS AS float) * CAST(ISNULL(d.FIYAT, 0) AS float) / (1 + k.KDV / 100.0) END AS TUTAR
INTO #sat
FROM dbo.FIS f JOIN dbo.FIS_DETAY d ON d.FIS = f.ID JOIN dbo.FIS_TURU FT ON FT.ID = f.FIS_TURU JOIN #kdv k ON k.STOK = d.STOK
WHERE f.FIS_TARIHI >= DATEADD(month, DATEDIFF(month, 0, GETDATE()) - 6, 0) AND ISNULL(f.AKTIF, 1) = 1 AND f.FIS_TURU <> 18 AND $aile AND $g <> 0;
IF OBJECT_ID('tempdb..#alis') IS NOT NULL DROP TABLE #alis;
SELECT d.STOK, f.FIS_TARIHI AS TARIH, d.ID AS DID, CAST(d.TOPLAM_KDV_MATRAHI AS float) / CAST(d.MIKTAR_FIS AS float) AS MALIYET
INTO #alis FROM dbo.FIS f JOIN dbo.FIS_DETAY d ON d.FIS = f.ID
WHERE f.FIS_TURU IN (1, 5) AND ISNULL(f.AKTIF, 1) = 1 AND d.MIKTAR_FIS > 0 AND ISNULL(d.TOPLAM_KDV_MATRAHI, 0) > 0;
CREATE CLUSTERED INDEX i ON #alis (STOK, TARIH);
IF OBJECT_ID('tempdb..#ay') IS NOT NULL DROP TABLE #ay;
SELECT STOK, AY, SUM(MIKTAR) AS MIKTAR, SUM(TUTAR) AS TUTAR, CAST(NULL AS float) AS MALIYET INTO #ay FROM #sat GROUP BY STOK, AY;
UPDATE a SET MALIYET = COALESCE(
   (SELECT TOP 1 x.MALIYET FROM #alis x WHERE x.STOK = a.STOK AND x.TARIH < DATEADD(month, 1, a.AY) ORDER BY x.TARIH DESC, x.DID DESC),
   (SELECT TOP 1 x.MALIYET FROM #alis x WHERE x.STOK = a.STOK ORDER BY x.TARIH ASC, x.DID ASC)) FROM #ay a;
"@
    Yaz ""; Yaz "== 1) Ay x belge turu =="
    Dok (Tablo @"
SELECT CONVERT(char(7), s.AY, 120) AS AY, s.FIS_TURU, MAX(s.TUR) AS TUR, COUNT(*) AS SATIR, COUNT(DISTINCT s.FID) AS FIS,
       SUM(s.TUTAR) AS CIRO, SUM(CASE WHEN s.MATRAH = 0 THEN 1 ELSE 0 END) AS MATRAHSIZ, SUM(s.BRUT * SIGN(s.MIKTAR)) AS BRUT_CIRO,
       SUM(s.MIKTAR * a.MALIYET) AS MALIYET
FROM #sat s JOIN #ay a ON a.STOK = s.STOK AND a.AY = s.AY
GROUP BY s.AY, s.FIS_TURU ORDER BY s.AY, s.FIS_TURU
"@)
    foreach ($ay in @((Tablo "SELECT DISTINCT CONVERT(char(7), AY, 120) AS AY FROM #ay ORDER BY 1").Rows | ForEach-Object { [string]$_.AY })) {
        Yaz ""; Yaz "== 2) $ay : en cok ZARAR yazan 15 urun =="
        Dok (Tablo "SELECT TOP 15 k.KOD, k.AD, a.MIKTAR, a.TUTAR AS CIRO, a.MALIYET AS BIRIM_MALIYET, a.TUTAR / NULLIF(a.MIKTAR, 0) AS BIRIM_SATIS, a.TUTAR - a.MIKTAR * a.MALIYET AS KAR FROM #ay a JOIN #kdv k ON k.STOK = a.STOK WHERE CONVERT(char(7), a.AY, 120) = '$ay' AND a.MALIYET IS NOT NULL ORDER BY a.TUTAR - a.MIKTAR * a.MALIYET ASC")
        Yaz "== 2) $ay : en cok KAR yazan 15 urun =="
        Dok (Tablo "SELECT TOP 15 k.KOD, k.AD, a.MIKTAR, a.TUTAR AS CIRO, a.MALIYET AS BIRIM_MALIYET, a.TUTAR / NULLIF(a.MIKTAR, 0) AS BIRIM_SATIS, a.TUTAR - a.MIKTAR * a.MALIYET AS KAR FROM #ay a JOIN #kdv k ON k.STOK = a.STOK WHERE CONVERT(char(7), a.AY, 120) = '$ay' AND a.MALIYET IS NOT NULL ORDER BY a.TUTAR - a.MIKTAR * a.MALIYET DESC")
    }
    Yaz ""; Yaz "== 3) Birim maliyet / birim satis orani 3'ten buyuk ya da 0,2'den kucuk (ciroya gore ilk 30) =="
    Dok (Tablo "SELECT TOP 30 CONVERT(char(7), a.AY, 120) AS AY, k.KOD, k.AD, a.MIKTAR, a.TUTAR, a.MALIYET AS BIRIM_MALIYET, a.TUTAR / NULLIF(a.MIKTAR, 0) AS BIRIM_SATIS FROM #ay a JOIN #kdv k ON k.STOK = a.STOK WHERE a.MALIYET IS NOT NULL AND a.MIKTAR > 0 AND a.TUTAR > 0 AND (a.MALIYET / (a.TUTAR / a.MIKTAR) > 3 OR a.MALIYET / (a.TUTAR / a.MIKTAR) < 0.2) ORDER BY ABS(a.TUTAR - a.MIKTAR * a.MALIYET) DESC")
} catch { Yaz "HATA: $($_.Exception.Message)" } finally { try { $bag.Close() } catch {} }
[System.IO.File]::WriteAllText($Cikti, $sb.ToString(), [System.Text.Encoding]::UTF8)
Write-Host ""; Write-Host "Bitti: $Cikti -> bu dosyayi gonder"
Read-Host "Kapatmak icin Enter"
