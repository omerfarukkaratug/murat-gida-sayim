# =====================================================================
#  MK Saha - ERP12 KESIF: ERP yeni bir STOK KARTI acarken hangi tablolara ne yaziyor?
#  ERP12'ye HICBIR SEY YAZMAZ, sadece okur. Internete hicbir sey gondermez.
#  Once ERP'de elle bir SABLON stok karti acin (barkod asagida), sonra bunu calistirin.
#  Sonuc: C:\Scripts\kesif-stok-sablon.txt  (bu dosyayi Claude'a gonder)
# =====================================================================
$SqlServer = "SERVER\ERP12"
$Barkod    = "MKSABLON"   # ERP harf kabul etmezse karti 99999001 barkoduyla acin; o da aranir
$Cikti     = "C:\Scripts\kesif-stok-sablon.txt"
Import-Module SqlServer -ErrorAction SilentlyContinue
$sb = New-Object System.Text.StringBuilder
function Yaz($m) { [void]$sb.AppendLine([string]$m); Write-Host $m }
function Sor($db, $q) { try { return @(Invoke-Sqlcmd -ServerInstance $SqlServer -Database $db -Query $q -QueryTimeout 120 -ErrorAction Stop) } catch { Yaz "  HATA: $($_.Exception.Message)"; return @() } }
function Dok($satirlar) { foreach ($r in $satirlar) { $p = @(); foreach ($c in $r.Table.Columns) { $v = $r[$c.ColumnName]; if ($v -isnot [DBNull] -and [string]$v -ne '') { $p += "$($c.ColumnName)=$v" } }; Yaz ("  " + ($p -join " | ")); Yaz "" } }
$dbler = @(Sor "master" "SELECT name FROM sys.databases WHERE name LIKE 'ERP12[0-9][0-9][0-9][0-9]' AND state = 0 ORDER BY name DESC")
$db = $null
foreach ($d in $dbler) { $n = @(Sor ([string]$d.name) "SELECT COUNT(*) AS n FROM dbo.FIS WHERE FIS_TARIHI >= DATEADD(day, -7, GETDATE())"); if ($n.Count -and [int]$n[0].n -gt 0) { $db = [string]$d.name; break } }
if (-not $db) { $db = [string]$dbler[0].name }
Yaz "KESIF-STOK-SABLON $(Get-Date -Format 'yyyy-MM-dd HH:mm')  veri tabani: $db  barkod: $Barkod"

$bb = @(Sor $db "SELECT TOP 1 * FROM dbo.STOK_BARKOD_BIRIM WHERE BARKOD IN ('$Barkod', '99999001') ORDER BY CASE WHEN BARKOD = '$Barkod' THEN 0 ELSE 1 END")
if ($bb.Count -eq 0) { Yaz "BU BARKODLA STOK KARTI BULUNAMADI. ERP'de once sablon karti acin (barkod $Barkod ya da 99999001)."; [System.IO.File]::WriteAllText($Cikti, $sb.ToString(), [System.Text.Encoding]::UTF8); Read-Host "Enter"; exit 1 }
$stokId = [long]$bb[0].STOK
Yaz "STOK ID: $stokId"

Yaz ""; Yaz "== 1) STOK satiri (tum dolu alanlar) =="
Dok (Sor $db "SELECT * FROM dbo.STOK WHERE ID = $stokId")
Yaz ""; Yaz "== 2) STOK tablosunun TUM sutunlari (tip, bos olabilir mi, varsayilan) =="
Dok (Sor $db "SELECT c.COLUMN_NAME, c.DATA_TYPE, c.CHARACTER_MAXIMUM_LENGTH AS UZ, c.IS_NULLABLE AS BOS, c.COLUMN_DEFAULT AS VARSAYILAN FROM INFORMATION_SCHEMA.COLUMNS c WHERE c.TABLE_NAME = 'STOK' ORDER BY c.ORDINAL_POSITION")

Yaz ""; Yaz "== 3) Bu stoga bagli satirlar: adinda STOK gecen sayi sutunlari = $stokId olan her tablo =="
$aday = @(Sor $db "SELECT t.name AS TABLO, c.name AS SUTUN FROM sys.columns c JOIN sys.tables t ON t.object_id = c.object_id JOIN sys.types y ON y.user_type_id = c.user_type_id WHERE y.name IN ('int','bigint') AND (c.name = 'STOK' OR c.name LIKE 'FK[_]STOK' OR c.name = 'STOK_ID' OR c.name = 'FK_STOK_KARTI') AND t.name <> 'STOK' ORDER BY t.name")
foreach ($a in $aday) {
    $t = [string]$a.TABLO; $c = [string]$a.SUTUN
    $s = @(Sor $db "SELECT TOP 20 * FROM dbo.[$t] WHERE [$c] = $stokId")
    if ($s.Count -gt 0) { Yaz "-- $t ($c) : $($s.Count) satir"; Dok $s }
}

Yaz ""; Yaz "== 4) Bu stogun ID'sinden HEMEN ONCE / SONRA alinan ID'ler hangi tablolarda (ayni anda yazilan kayitlar) =="
$tablolar = @(Sor $db "SELECT t.name AS TABLO FROM sys.tables t JOIN sys.columns c ON c.object_id = t.object_id AND c.name = 'ID' JOIN sys.types y ON y.user_type_id = c.user_type_id WHERE y.name IN ('int','bigint')")
foreach ($tt in $tablolar) {
    $t = [string]$tt.TABLO
    $s = @(Sor $db "SELECT TOP 10 * FROM dbo.[$t] WHERE ID BETWEEN $($stokId - 5) AND $($stokId + 15) ORDER BY ID")
    if ($s.Count -gt 0) { Yaz "-- $t : $($s.Count) satir"; Dok $s }
}

Yaz ""; Yaz "== 5) STOK tablosundaki trigger'lar =="
Dok (Sor $db "SELECT tr.name AS TRIGGER_ADI, OBJECT_NAME(tr.parent_id) AS TABLO FROM sys.triggers tr WHERE OBJECT_NAME(tr.parent_id) IN ('STOK','STOK_BARKOD_BIRIM','STOK_BIRIM')")

[System.IO.File]::WriteAllText($Cikti, $sb.ToString(), [System.Text.Encoding]::UTF8)
Write-Host ""; Write-Host "Bitti. Sonuc: $Cikti  -> bu dosyayi gonder."
Read-Host "Kapatmak icin Enter"
