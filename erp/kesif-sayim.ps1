# =====================================================================
#  KRT Saha - ERP12 KESIF: SAYIM bolumu nasil calisiyor?
#  23 Kasim bolum bolum sayimi icin: ERP12'nin sayim belgesi sayilani stoga EKLIYOR mu, stogu sayilana
#  ESITLIYOR mu, "sifirlama" ne yapiyor, hangi fisleri uretiyor? Ve urun gruplari (bolumler) neler?
#   1) Adinda SAYIM gecen tablolar ve kolonlari
#   2) SAYIM basliklari (son 20) ve her birinin satir sayisi / tarih araligi
#   3) Sayim gunlerinde olusan fisler (fis turu bazinda) - sayim hangi fisi uretmis
#   4) Ornek urun: son sayimdaki sayilan miktar, sayimdan onceki ve sonraki stok hareketleri
#   5) Urun gruplari (STOK_GRUP agaci): urun sayisi, stoktaki urun, stok miktari ve degeri
#   6) Depolar / lokasyonlar
#  ERP12'ye HICBIR SEY YAZMAZ, sadece okur. Sonuc ekranda ve C:\Scripts\kesif-sayim.txt
# =====================================================================
$SqlServer = "SERVER\ERP12"
$Cikti     = "C:\Scripts\kesif-sayim.txt"
Import-Module SqlServer -ErrorAction SilentlyContinue
$sb = New-Object System.Text.StringBuilder
function Yaz($m) { [void]$sb.AppendLine([string]$m); Write-Host $m }
function Kaydet { try { [System.IO.File]::WriteAllText($Cikti, $sb.ToString(), [System.Text.Encoding]::UTF8) } catch {} }
function Sor($db, $q, $sn = 300) { try { return @(Invoke-Sqlcmd -ServerInstance $SqlServer -Database $db -Query $q -QueryTimeout $sn -MaxCharLength 4000 -ErrorAction Stop) } catch { Yaz "  HATA: $($_.Exception.Message)"; return @() } }
function Deger($v) { if ($v -is [DBNull]) { return "NULL" } elseif ($v -is [byte[]]) { return "0x.." } elseif ($v -is [datetime]) { return $v.ToString("yyyy-MM-dd HH:mm") } else { $s = [string]$v; if ($s.Length -gt 60) { $s = $s.Substring(0, 60) + ".." }; return $s } }
function Dok($satirlar, $on) { foreach ($r in $satirlar) { $p = @(); foreach ($c in $r.Table.Columns) { $p += "$($c.ColumnName)=$(Deger $r[$c.ColumnName])" }; Yaz ("  $on" + ($p -join " | ")) } }
function Kolonlar($db, $t) { return @(Sor $db "SELECT c.name FROM sys.columns c WHERE c.object_id = OBJECT_ID('dbo.$t') ORDER BY c.column_id" | ForEach-Object { [string]$_.name }) }

$dbler = @(Sor "master" "SELECT name FROM sys.databases WHERE name LIKE 'ERP12[0-9][0-9][0-9][0-9]' AND state = 0 ORDER BY name DESC")
$db = $null
foreach ($d in $dbler) { $n = @(Sor ([string]$d.name) "SELECT COUNT(*) AS n FROM dbo.FIS WITH (NOLOCK) WHERE FIS_TARIHI >= DATEADD(day, -7, GETDATE())"); if ($n.Count -and [int]$n[0].n -gt 0) { $db = [string]$d.name; break } }
if (-not $db) { $db = [string]$dbler[0].name }
Yaz "KESIF-SAYIM $(Get-Date -Format 'yyyy-MM-dd HH:mm')  veri tabani: $db  (tum yil veri tabanlari: $(($dbler | ForEach-Object { $_.name }) -join ', '))"

Yaz ""; Yaz "== 1) Adinda SAYIM gecen tablolar / gorunumler / prosedurler =="
foreach ($t in (Sor $db "SELECT o.name, o.type_desc, (SELECT SUM(p.rows) FROM sys.partitions p WHERE p.object_id = o.object_id AND p.index_id IN (0, 1)) AS SATIR FROM sys.objects o WHERE o.name LIKE '%SAYIM%' AND o.type IN ('U', 'V', 'P', 'FN', 'TF', 'TR') ORDER BY o.type, o.name")) {
    $k = if ($t.type_desc -match 'TABLE|VIEW') { " : " + ((Kolonlar $db $t.name) -join ', ') } else { "" }
    Yaz ("  [{0}] {1} ({2} satir){3}" -f $t.type_desc, $t.name, (Deger $t.SATIR), $k)
}
Yaz "  -- SAYIM'a baska tablolarda bagli kolonlar:"
Dok (Sor $db "SELECT t.name AS TABLO, c.name AS KOLON FROM sys.columns c JOIN sys.tables t ON t.object_id = c.object_id WHERE c.name LIKE '%SAYIM%' AND t.name NOT LIKE '%SAYIM%' ORDER BY t.name") "    "
Kaydet

Yaz ""; Yaz "== 2) SAYIM basliklari (son 20) =="
Dok (Sor $db "SELECT TOP 20 * FROM dbo.SAYIM WITH (NOLOCK) ORDER BY ID DESC") "  "
Yaz "  -- her sayimin satir sayisi, urun sayisi, toplam miktar, satir tarih araligi:"
Dok (Sor $db "SELECT SAYIM, COUNT(*) AS SATIR, COUNT(DISTINCT STOK) AS URUN, SUM(CAST(MIKTAR AS float)) AS MIKTAR, MIN(TARIH) AS ILK, MAX(TARIH) AS SON FROM dbo.SAYIM_DETAY WITH (NOLOCK) GROUP BY SAYIM ORDER BY SAYIM DESC") "  "
Kaydet

Yaz ""; Yaz "== 3) Sayim gunlerinde (+/- 3 gun) olusan fisler, fis turu bazinda =="
$gunler = @(Sor $db "SELECT DISTINCT CAST(TARIH AS date) AS G FROM dbo.SAYIM_DETAY WITH (NOLOCK) WHERE TARIH IS NOT NULL" | ForEach-Object { ([datetime]$_.G).ToString("yyyy-MM-dd") })
Yaz "  sayim satiri olan gunler: $($gunler -join ', ')"
if ($gunler.Count) {
    $ilk = $gunler | Sort-Object | Select-Object -First 1; $son = $gunler | Sort-Object | Select-Object -Last 1
    Dok (Sor $db @"
SELECT CAST(f.FIS_TARIHI AS date) AS GUN, f.FIS_TURU, FT.AD AS TUR, FT.GIRIS, COUNT(DISTINCT f.ID) AS FIS, COUNT(*) AS SATIR, SUM(CAST(d.MIKTAR_FIS AS float)) AS MIKTAR
FROM dbo.FIS f WITH (NOLOCK) JOIN dbo.FIS_DETAY d WITH (NOLOCK) ON d.FIS = f.ID JOIN dbo.FIS_TURU FT ON FT.ID = f.FIS_TURU
WHERE f.FIS_TARIHI >= DATEADD(day, -3, '$ilk') AND f.FIS_TARIHI < DATEADD(day, 4, '$son')
  AND (FT.AD NOT LIKE N'%Sat' + NCHAR(305) + NCHAR(351) + N'%' OR FT.AD LIKE N'%SAYIM%') AND f.FIS_TURU NOT IN (11, 12, 35, 36)
GROUP BY CAST(f.FIS_TARIHI AS date), f.FIS_TURU, FT.AD, FT.GIRIS ORDER BY GUN, f.FIS_TURU
"@) "  "
}
Yaz "  -- butun fis turleri (ID, AD, GIRIS):"
Dok (Sor $db "SELECT ID, AD, GIRIS FROM dbo.FIS_TURU ORDER BY ID") "    "
Kaydet

Yaz ""; Yaz "== 4) Ornek urunler: son sayimda sayilan ile stok hareketleri =="
$son = @(Sor $db "SELECT TOP 1 SAYIM FROM dbo.SAYIM_DETAY WITH (NOLOCK) GROUP BY SAYIM ORDER BY MAX(TARIH) DESC")
if ($son.Count) {
    $sid = [long]$son[0].SAYIM
    $ornek = @(Sor $db "SELECT TOP 3 d.STOK, MAX(d.KOD) AS KOD, SUM(CAST(d.MIKTAR AS float) * ISNULL(d.CARPAN, 1)) AS SAYILAN, MAX(d.TARIH) AS T FROM dbo.SAYIM_DETAY d WITH (NOLOCK) WHERE d.SAYIM = $sid GROUP BY d.STOK HAVING SUM(CAST(d.MIKTAR AS float)) > 5 ORDER BY NEWID()")
    foreach ($o in $ornek) {
        Yaz "  -- STOK $($o.STOK) $($o.KOD): sayimda sayilan $($o.SAYILAN) (son okutma $(Deger $o.T))"
        Dok (Sor $db @"
SELECT TOP 25 f.ID, f.FIS_TARIHI, f.FIS_TURU, FT.AD AS TUR, FT.GIRIS, f.BELGENO, CAST(d.MIKTAR_FIS AS float) AS MIKTAR, d.CARPAN, ISNULL(f.AKTIF, 1) AS AKTIF
FROM dbo.FIS f WITH (NOLOCK) JOIN dbo.FIS_DETAY d WITH (NOLOCK) ON d.FIS = f.ID JOIN dbo.FIS_TURU FT ON FT.ID = f.FIS_TURU
WHERE d.STOK = $($o.STOK) AND f.FIS_TARIHI >= DATEADD(day, -5, '$(([datetime]$o.T).ToString("yyyy-MM-dd"))') AND f.FIS_TARIHI < DATEADD(day, 6, '$(([datetime]$o.T).ToString("yyyy-MM-dd"))')
  AND f.FIS_TURU NOT IN (11, 12, 35, 36)
ORDER BY f.FIS_TARIHI, f.ID
"@) "    "
    }
}
Kaydet

Yaz ""; Yaz "== 5) Urun gruplari (STOK_GRUP): bolum bolum sayim icin =="
Dok (Sor $db @"
WITH st AS (SELECT ub.STOK, SUM(CAST(COALESCE(um.MIKTAR, ubar.MIKTAR) AS float)) AS M FROM dbo.STOK_BARKOD_BIRIM ub
            LEFT JOIN dbo.STOK_BARKOD ubar ON ubar.BARKOD = ub.BARKOD LEFT JOIN dbo.STOK_MIKTAR_BARKODLU um ON um.BARKOD = ub.BARKOD GROUP BY ub.STOK)
SELECT g.ID, g.USTID, ISNULL(u.AD, '') AS UST, g.AD, ISNULL(g.AKTIF, 1) AS AKTIF,
       (SELECT COUNT(*) FROM dbo.STOK s WHERE s.STOK_GRUP = g.ID) AS URUN,
       (SELECT COUNT(*) FROM dbo.STOK s JOIN st ON st.STOK = s.ID WHERE s.STOK_GRUP = g.ID AND st.M > 0) AS STOKTA,
       (SELECT COUNT(*) FROM dbo.STOK s JOIN st ON st.STOK = s.ID WHERE s.STOK_GRUP = g.ID AND st.M < 0) AS EKSI,
       (SELECT SUM(CASE WHEN st.M > 0 THEN st.M ELSE 0 END) FROM dbo.STOK s JOIN st ON st.STOK = s.ID WHERE s.STOK_GRUP = g.ID) AS MIKTAR,
       (SELECT SUM(CASE WHEN st.M > 0 THEN st.M * ISNULL(s.SON_ALIS_FIYAT, 0) ELSE 0 END) FROM dbo.STOK s JOIN st ON st.STOK = s.ID WHERE s.STOK_GRUP = g.ID) AS DEGER
FROM dbo.STOK_GRUP g LEFT JOIN dbo.STOK_GRUP u ON u.ID = g.USTID ORDER BY ISNULL(u.AD, g.AD), g.AD
"@) "  "
Yaz "  -- grubu olmayan urunler:"
Dok (Sor $db "SELECT COUNT(*) AS URUN FROM dbo.STOK s WHERE s.STOK_GRUP IS NULL OR s.STOK_GRUP = 0 OR NOT EXISTS (SELECT 1 FROM dbo.STOK_GRUP g WHERE g.ID = s.STOK_GRUP)") "    "
Kaydet

Yaz ""; Yaz "== 6) Depolar / lokasyonlar =="
foreach ($t in (Sor $db "SELECT name FROM sys.tables WHERE name IN ('LOKASYON', 'DEPO', 'STOK_DEPO', 'STOK_LOKASYON', 'TR_LOKASYON') OR name LIKE 'LOKASYON%' OR name LIKE 'DEPO%' ORDER BY name")) {
    Yaz "  -- $($t.name): $((Kolonlar $db $t.name) -join ', ')"
    Dok (Sor $db "SELECT TOP 10 * FROM dbo.[$($t.name)] WITH (NOLOCK)") "    "
}
Kaydet
Write-Host ""; Write-Host "Bitti. $Cikti dosyasini gonderin."
Read-Host "Kapatmak icin Enter"
