# =====================================================================
#  Murat Gida - ERP12 KESIF: alistan iade irsaliyeleri nerede, nasil "bekliyor"?
#  ERP12'ye HICBIR SEY YAZMAZ, sadece okur. Internete hicbir sey gondermez.
#  Sonuc: C:\Scripts\kesif-iade.txt  (bu dosyayi Claude'a gonder)
#  Icinde: fis turleri, son 1 yilda tur basina fis sayisi, FIS tablosunun
#  sutunlari ve adinda IADE gecen turlerden birkac ornek fis (cari ADI ile).
# =====================================================================
$SqlServer = "SERVER\ERP12"
$Cikti     = "C:\Scripts\kesif-iade.txt"
Import-Module SqlServer -ErrorAction SilentlyContinue
$sb = New-Object System.Text.StringBuilder
function Yaz($m) { [void]$sb.AppendLine([string]$m); Write-Host $m }
function Sor($db, $q) { try { return @(Invoke-Sqlcmd -ServerInstance $SqlServer -Database $db -Query $q -QueryTimeout 120 -ErrorAction Stop) } catch { Yaz "  HATA: $($_.Exception.Message)"; return @() } }
function Dok($satirlar) {
    foreach ($r in $satirlar) {
        $p = @(); foreach ($c in $r.Table.Columns) { $v = $r[$c.ColumnName]; if ($v -isnot [DBNull] -and [string]$v -ne '') { $p += "$($c.ColumnName)=$v" } }
        Yaz ("  " + ($p -join " | "))
    }
}
$dbler = @(Sor "master" "SELECT name FROM sys.databases WHERE name LIKE 'ERP12[0-9][0-9][0-9][0-9]' AND state = 0 ORDER BY name DESC")
if ($dbler.Count -eq 0) { Write-Host "ERP12 veri tabani bulunamadi."; Read-Host "Enter"; exit 1 }
$db = [string]$dbler[0].name
Yaz "KESIF-IADE $(Get-Date -Format 'yyyy-MM-dd HH:mm')  veri tabani: $db"

Yaz ""; Yaz "== 1) ADINDA FIS_TUR / BELGE_TUR / IRSALIYE / IADE gecen tablolar =="
$tl = @(Sor $db @"
SELECT t.name AS ad, SUM(p.rows) AS satir
FROM sys.tables t JOIN sys.partitions p ON p.object_id = t.object_id AND p.index_id IN (0,1)
WHERE t.name LIKE '%FIS[_]TUR%' OR t.name LIKE '%BELGE[_]TUR%' OR t.name LIKE '%IRSALIYE%' OR t.name LIKE '%IADE%' OR t.name LIKE '%FIS[_]DURUM%'
GROUP BY t.name ORDER BY t.name
"@)
foreach ($t in $tl) {
    $kol = @(Sor $db "SELECT COLUMN_NAME AS c FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = '$($t.ad)' ORDER BY ORDINAL_POSITION")
    Yaz ("  $($t.ad)  [$($t.satir) satir]: " + (($kol | ForEach-Object { [string]$_.c }) -join ", "))
    if ([long]$t.satir -gt 0 -and [long]$t.satir -le 60) { Dok (@(Sor $db "SELECT * FROM dbo.[$($t.ad)]")) }
}

Yaz ""; Yaz "== 2) SON 1 YILDA fis turu basina fis sayisi =="
Dok (@(Sor $db "SELECT FIS_TURU, COUNT(*) AS adet, MIN(FIS_TARIHI) AS ilk, MAX(FIS_TARIHI) AS son FROM dbo.FIS WHERE FIS_TARIHI >= DATEADD(day, -365, GETDATE()) GROUP BY FIS_TURU ORDER BY FIS_TURU"))

Yaz ""; Yaz "== 3) FIS tablosunun sutunlari =="
$fk = @(Sor $db "SELECT COLUMN_NAME AS c, DATA_TYPE AS d FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'FIS' ORDER BY ORDINAL_POSITION")
Yaz ("  " + (($fk | ForEach-Object { "$($_.c):$($_.d)" }) -join ", "))

Yaz ""; Yaz "== 4) Kasa (11) ve alis/satis (1,2,5,6,12) DISINDAKI turlerden ornek fisler (tur basina en yeni 3) =="
$turler = @(Sor $db "SELECT DISTINCT FIS_TURU FROM dbo.FIS WHERE FIS_TARIHI >= DATEADD(day, -365, GETDATE()) AND FIS_TURU NOT IN (1, 2, 5, 6, 11, 12) ORDER BY FIS_TURU")
foreach ($t in $turler) {
    $tur = [int]$t.FIS_TURU
    Yaz "  -- FIS_TURU = $tur"
    $fisler = @(Sor $db "SELECT TOP 3 f.*, c.AD AS CARI_ADI FROM dbo.FIS f LEFT JOIN dbo.CARI c ON c.ID = f.CARI WHERE f.FIS_TURU = $tur ORDER BY f.FIS_TARIHI DESC")
    Dok $fisler
    if ($fisler.Count -gt 0) {
        Yaz "     .. ilk fisin satirlari (en cok 4):"
        Dok (@(Sor $db "SELECT TOP 4 d.STOK, d.BARKOD, d.MIKTAR_FIS, d.MIKTAR_GIRIS, d.MIKTAR_CIKIS, d.DAHIL_FIYAT, d.FATRALANDIRILMIS_IRSALIYEMI, d.FIS_DETAY_SATIR_TURU, d.BAGLI_SATIR, d.SATIR FROM dbo.FIS_DETAY d WHERE d.FIS = '$($fisler[0].ID)'"))
    }
}

Yaz ""; Yaz "== 5) Alis turlerinden (1, 5) birer ornek (karsilastirma) =="
foreach ($tur in @(1, 5)) { Yaz "  -- FIS_TURU = $tur"; Dok (@(Sor $db "SELECT TOP 1 f.*, c.AD AS CARI_ADI FROM dbo.FIS f LEFT JOIN dbo.CARI c ON c.ID = f.CARI WHERE f.FIS_TURU = $tur ORDER BY f.FIS_TARIHI DESC")) }

[System.IO.File]::WriteAllText($Cikti, $sb.ToString(), [System.Text.Encoding]::UTF8)
Write-Host ""; Write-Host "Bitti. Dosya: $Cikti"
Read-Host "Kapatmak icin Enter"
