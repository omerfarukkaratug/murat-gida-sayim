# =====================================================================
#  KRT Saha - AY INCELEME: "Bu ayin kari neden bu kadar dusuk?" (ornek: Temmuz 2026, marj -%0,5)
#  Saglik raporuyla AYNI hesabi yapar (satis, maliyet = o ay gecerli son net alis, koli carpani) ve
#  o ay kari en cok dusuren urunleri bulur. Her urun icin:
#    - maliyetin geldigi ALIS satirlari (belge no, firma, miktar, carpan, tutar, hesaplanan birim maliyet)
#    - o ayin en buyuk SATIS satirlari (kasa / firma, miktar, tutar)
#  Boylece yanlis girilmis alis fiyati (koli fiyati adete yazilmis gibi) ya da yanlis satis miktari gorulur.
#  ERP12'ye HICBIR SEY YAZMAZ, sadece okur. Sonuc ekranda ve C:\Scripts\kesif-ay.txt
# =====================================================================
$SqlServer = "SERVER\ERP12"
$Cikti     = "C:\Scripts\kesif-ay.txt"
$sb = New-Object System.Text.StringBuilder
function Yaz($m) { [void]$sb.AppendLine([string]$m); Write-Host $m }
function Kaydet { try { [System.IO.File]::WriteAllText($Cikti, $sb.ToString(), [System.Text.Encoding]::UTF8) } catch {} }
$bag = $null
function Tablo($sql, $sn = 600) { $cmd = $bag.CreateCommand(); $cmd.CommandText = $sql; $cmd.CommandTimeout = $sn; $da = New-Object System.Data.SqlClient.SqlDataAdapter($cmd); $dt = New-Object System.Data.DataTable; [void]$da.Fill($dt); return ,$dt }
function Calistir($sql, $sn = 600) { $cmd = $bag.CreateCommand(); $cmd.CommandText = $sql; $cmd.CommandTimeout = $sn; [void]$cmd.ExecuteNonQuery() }
$tr = [Globalization.CultureInfo]::GetCultureInfo("tr-TR")
function P($v, $o = 2) { if ($v -is [DBNull] -or $v -eq $null) { return "-" }; return ([double]$v).ToString("N$o", $tr) }
function T($v) { if ($v -is [DBNull] -or $v -eq $null) { return "" }; return ([datetime]$v).ToString("dd.MM.yyyy") }
function M($v) { if ($v -is [DBNull] -or $v -eq $null) { return "" }; return ([string]$v).Trim() }

try {
    $ayGir = (Read-Host "Hangi ay? (YYYY-AA, bos: 2026-07)").Trim(); if (-not $ayGir) { $ayGir = "2026-07" }
    if ($ayGir -notmatch '^\d{4}-\d{2}$') { throw "Ay YYYY-AA biciminde olmali (ornek 2026-07)." }
    $ay = $ayGir.Replace("-", "") + "01"   # YYYYAAGG: SQL Server dil ayarindan bagimsiz
    $bag = New-Object System.Data.SqlClient.SqlConnection("Server=$SqlServer;Database=master;Integrated Security=SSPI;"); $bag.Open()
    $dbler = Tablo "SELECT name FROM sys.databases WHERE name LIKE 'ERP12[0-9][0-9][0-9][0-9]' AND state = 0 ORDER BY name DESC"
    $db = $null
    foreach ($d in $dbler.Rows) { $n = (Tablo ("SELECT COUNT(*) AS n FROM [" + $d.name + "].dbo.FIS WITH (NOLOCK) WHERE FIS_TARIHI >= DATEADD(day, -7, GETDATE())")).Rows[0].n; if ([int]$n -gt 0) { $db = [string]$d.name; break } }
    if (-not $db) { throw "ERP12 veri tabani bulunamadi." }
    $bag.ChangeDatabase($db); Calistir "SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED"
    Yaz "AY INCELEME $ayGir  ($(Get-Date -Format 'yyyy-MM-dd HH:mm'), $db)"

    $satisAile = "(FT.AD LIKE N'%Sat' + NCHAR(305) + NCHAR(351) + N'%' OR FT.AD LIKE N'%SATI' + NCHAR(350) + N'%' OR f.FIS_TURU IN (11, 12, 35, 36))"
    $kasaMi = "(ISNULL(f.CARI, 0) = COALESCE((SELECT TOP 1 VARSAYILANCARI FROM dbo.FIRMASABITLERI), -1) OR (f.CARI IS NULL AND f.FIS_TURU IN (11, 12, 35, 36)) OR f.FIS_TURU = 11)"
    $g = "(CASE WHEN f.FIS_TURU IN (5, 6, 7, 8, 36) AND ISNULL(d.FATRALANDIRILMIS_IRSALIYEMI, 0) = 1 THEN 0 ELSE FT.GIRIS END)"
    $carp = "(CASE WHEN ISNULL(d.CARPAN, 0) > 0.0001 AND ISNULL(d.CARPAN, 0) < 100000 THEN CAST(d.CARPAN AS float) ELSE 1 END)"
    Yaz "Satislar ve alislar okunuyor..."
    Calistir @"
IF OBJECT_ID('tempdb..#kdv') IS NOT NULL DROP TABLE #kdv;
SELECT s.ID AS STOK, CAST(ISNULL(v.KDV_PAREKENDE, 0) AS float) AS KDV, s.KOD, s.AD INTO #kdv FROM dbo.STOK s LEFT JOIN dbo.STOK_VERGI v ON v.ID = s.STOK_VERGI
WHERE NOT (s.AD LIKE N'%FIYAT FARK%' OR s.AD LIKE N'%F' + NCHAR(304) + N'YAT FARK%' OR s.AD LIKE N'%ISKONTO%' OR s.AD LIKE N'%' + NCHAR(304) + N'SKONTO%'
           OR s.AD LIKE N'%NAKL%YE%' OR s.AD LIKE N'%NAVLUN%' OR s.AD LIKE N'%KARGO BEDEL%');
CREATE CLUSTERED INDEX i ON #kdv (STOK);
IF OBJECT_ID('tempdb..#sat') IS NOT NULL DROP TABLE #sat;
SELECT d.STOK, d.ID AS DID, f.ID AS FID, f.FIS_TARIHI AS TARIH, CASE WHEN $kasaMi THEN 1 ELSE 0 END AS KASA, FT.AD AS TUR, f.CARI,
       -$g * CAST(d.MIKTAR_FIS AS float) * $carp AS MIKTAR, CAST(d.MIKTAR_FIS AS float) AS MIKTAR_FIS, $carp AS CARPAN,
       -$g * CASE WHEN ISNULL(d.TOPLAM_KDV_MATRAHI, 0) <> 0 THEN CAST(d.TOPLAM_KDV_MATRAHI AS float)
                  ELSE CAST(d.MIKTAR_FIS AS float) * CAST(ISNULL(d.FIYAT, 0) AS float) / (1 + k.KDV / 100.0) END AS TUTAR
INTO #sat
FROM dbo.FIS f JOIN dbo.FIS_DETAY d ON d.FIS = f.ID JOIN dbo.FIS_TURU FT ON FT.ID = f.FIS_TURU JOIN #kdv k ON k.STOK = d.STOK
WHERE f.FIS_TARIHI >= '$ay' AND f.FIS_TARIHI < DATEADD(month, 1, '$ay')
  AND ISNULL(f.AKTIF, 1) = 1 AND f.FIS_TURU <> 18 AND $satisAile AND $g <> 0;
IF OBJECT_ID('tempdb..#alis') IS NOT NULL DROP TABLE #alis;
SELECT d.STOK, f.FIS_TARIHI AS TARIH, d.ID AS DID, f.ID AS FID, CAST(d.TOPLAM_KDV_MATRAHI AS float) / (CAST(d.MIKTAR_FIS AS float) * $carp) AS MALIYET,
       CAST(d.MIKTAR_FIS AS float) AS MIKTAR_FIS, $carp AS CARPAN, CAST(d.TOPLAM_KDV_MATRAHI AS float) AS TUTAR, ISNULL(c.AD, '') AS CARI, f.FIS_TURU
INTO #alis
FROM dbo.FIS f JOIN dbo.FIS_DETAY d ON d.FIS = f.ID LEFT JOIN dbo.CARI c ON c.ID = f.CARI JOIN #kdv k ON k.STOK = d.STOK
WHERE f.FIS_TURU IN (1, 5) AND ISNULL(f.AKTIF, 1) = 1 AND d.MIKTAR_FIS > 0 AND ISNULL(d.TOPLAM_KDV_MATRAHI, 0) > 0;
IF OBJECT_ID('tempdb..#ort') IS NOT NULL DROP TABLE #ort;
SELECT STOK, AVG(MALIYET) AS ORT INTO #ort FROM #alis GROUP BY STOK;
DELETE a FROM #alis a JOIN #ort o ON o.STOK = a.STOK WHERE a.MALIYET < o.ORT * 0.2;
CREATE CLUSTERED INDEX i ON #alis (STOK, TARIH);
IF OBJECT_ID('tempdb..#u') IS NOT NULL DROP TABLE #u;
SELECT s.STOK, SUM(s.MIKTAR) AS MIKTAR, SUM(s.TUTAR) AS TUTAR, SUM(CASE WHEN s.KASA = 1 THEN s.MIKTAR ELSE 0 END) AS KASA_M, CAST(NULL AS float) AS MALIYET, CAST(NULL AS bigint) AS MDID
INTO #u FROM #sat s GROUP BY s.STOK;
UPDATE u SET MDID = COALESCE(
   (SELECT TOP 1 x.DID FROM #alis x WHERE x.STOK = u.STOK AND x.TARIH < DATEADD(month, 1, '$ay') ORDER BY x.TARIH DESC, x.DID DESC),
   (SELECT TOP 1 x.DID FROM #alis x WHERE x.STOK = u.STOK ORDER BY x.TARIH ASC, x.DID ASC)) FROM #u u;
UPDATE u SET MALIYET = (SELECT TOP 1 x.MALIYET FROM #alis x WHERE x.DID = u.MDID) FROM #u u;
"@
    $oz = (Tablo "SELECT SUM(TUTAR) AS CIRO, SUM(CASE WHEN MALIYET IS NOT NULL THEN TUTAR ELSE 0 END) AS CIRO_M, SUM(CASE WHEN MALIYET IS NOT NULL THEN MIKTAR * MALIYET ELSE 0 END) AS MAL FROM #u WHERE MIKTAR > 0 AND TUTAR > 0").Rows[0]
    $kar = [double]$oz.CIRO_M - [double]$oz.MAL
    Yaz ""; Yaz ("AY TOPLAMI: satis {0} TL, maliyetli satis {1} TL, maliyet {2} TL, brut kar {3} TL, marj %{4}" -f (P $oz.CIRO 0), (P $oz.CIRO_M 0), (P $oz.MAL 0), (P $kar 0), (P ($kar / [Math]::Max(1, [double]$oz.CIRO_M) * 100) 1))
    $kotu = Tablo @"
SELECT TOP 15 u.STOK, k.KOD, k.AD, u.MIKTAR, u.KASA_M, u.TUTAR, u.MALIYET, u.MIKTAR * u.MALIYET AS MAL, u.MIKTAR * u.MALIYET - u.TUTAR AS ZARAR, u.TUTAR / NULLIF(u.MIKTAR, 0) AS ORT_SATIS
FROM #u u JOIN #kdv k ON k.STOK = u.STOK WHERE u.MALIYET IS NOT NULL AND u.MIKTAR > 0 AND u.TUTAR > 0 AND u.MIKTAR * u.MALIYET > u.TUTAR
ORDER BY u.MIKTAR * u.MALIYET - u.TUTAR DESC
"@
    $topZarar = 0.0; foreach ($r in $kotu.Rows) { $topZarar += [double]$r.ZARAR }
    Yaz ("En cok zarar yazan 15 urunun toplam zarari: {0} TL  (bunlar duzeltilirse kar {1} TL, marj %{2} olurdu)" -f (P $topZarar 0), (P ($kar + $topZarar) 0), (P (($kar + $topZarar) / [Math]::Max(1, [double]$oz.CIRO_M) * 100) 1))
    Kaydet
    $i = 0
    foreach ($r in $kotu.Rows) {
        $i++
        Yaz ""; Yaz ("===== {0}) {1}  {2} =====" -f $i, (M $r.KOD), (M $r.AD))
        Yaz ("  Ayda satilan {0} (kasada {1}), satis {2} TL -> ortalama satis {3} TL/adet (KDV haric)" -f (P $r.MIKTAR 2), (P $r.KASA_M 2), (P $r.TUTAR 0), (P $r.ORT_SATIS 2))
        Yaz ("  Hesaba giren maliyet {0} TL/adet -> maliyet {1} TL, ZARAR {2} TL" -f (P $r.MALIYET 2), (P $r.MAL 0), (P $r.ZARAR 0))
        Yaz "  -- Alislar (son 4, ay sonuna kadar; * = maliyet buradan):"
        $al = Tablo ("SELECT TOP 4 a.DID, a.TARIH, f.BELGENO, a.CARI, a.FIS_TURU, a.MIKTAR_FIS, a.CARPAN, a.TUTAR, a.MALIYET FROM #alis a LEFT JOIN dbo.FIS f ON f.ID = a.FID WHERE a.STOK = " + $r.STOK + " AND a.TARIH < DATEADD(month, 1, '$ay') ORDER BY a.TARIH DESC, a.DID DESC")
        if ($al.Rows.Count -eq 0) { $al = Tablo ("SELECT TOP 2 a.DID, a.TARIH, f.BELGENO, a.CARI, a.FIS_TURU, a.MIKTAR_FIS, a.CARPAN, a.TUTAR, a.MALIYET FROM #alis a LEFT JOIN dbo.FIS f ON f.ID = a.FID WHERE a.STOK = " + $r.STOK + " ORDER BY a.TARIH ASC") }
        $mdid = (Tablo ("SELECT MDID FROM #u WHERE STOK = " + $r.STOK)).Rows[0].MDID
        foreach ($a in $al.Rows) {
            $isa = if ([long]$a.DID -eq [long]$mdid) { "*" } else { " " }
            Yaz ("   {0} {1}  belge {2}  {3}  miktar {4} x carpan {5}  tutar {6} TL  => {7} TL/adet" -f $isa, (T $a.TARIH), (M $a.BELGENO), (M $a.CARI), (P $a.MIKTAR_FIS 2), (P $a.CARPAN 0), (P $a.TUTAR 2), (P $a.MALIYET 2))
        }
        Yaz "  -- O ayin en buyuk satislari:"
        $st = Tablo ("SELECT TOP 4 s.TARIH, f.BELGENO, s.TUR, s.KASA, ISNULL(c.AD, '') AS CARI, s.MIKTAR_FIS, s.CARPAN, s.MIKTAR, s.TUTAR FROM #sat s LEFT JOIN dbo.FIS f ON f.ID = s.FID LEFT JOIN dbo.CARI c ON c.ID = s.CARI WHERE s.STOK = " + $r.STOK + " ORDER BY ABS(s.MIKTAR) DESC")
        foreach ($s in $st.Rows) {
            Yaz ("     {0}  {1}  {2}  {3}  miktar {4} x carpan {5} = {6}  tutar {7} TL" -f (T $s.TARIH), (M $s.BELGENO), (M $s.TUR), $(if ([int]$s.KASA -eq 1) { "KASA" } else { (M $s.CARI) }), (P $s.MIKTAR_FIS 2), (P $s.CARPAN 0), (P $s.MIKTAR 2), (P $s.TUTAR 2))
        }
        Kaydet
    }
    Yaz ""; Yaz "Okuma: '*' isaretli alisin TL/adet maliyeti satis fiyatindan cok yuksekse, o alis satirinda miktar ya da carpan"
    Yaz "yanlis girilmistir (ornek: 24'lu koli 1 adet gibi). Satis miktari anormal buyukse satis belgesinde hata vardir."
} catch { Yaz "HATA: $($_.Exception.Message)" }
finally { if ($bag) { try { $bag.Close() } catch {} } }
Kaydet
Write-Host ""; Write-Host "Bitti. Ekranin fotografini ya da $Cikti dosyasini gonderin."
Read-Host "Kapatmak icin Enter"
