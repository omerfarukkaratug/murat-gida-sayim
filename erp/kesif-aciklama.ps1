# =====================================================================
#  MK Saha - ERP12 KESIF: siparis aciklamasi nereye, ne kadar uzun yazilabilir?
#  ERP12'ye HICBIR SEY YAZMAZ, sadece okur. Sonuc: C:\Scripts\kesif-aciklama.txt
# =====================================================================
$SqlServer = "SERVER\ERP12"
$Cikti     = "C:\Scripts\kesif-aciklama.txt"
Import-Module SqlServer -ErrorAction SilentlyContinue
$sb = New-Object System.Text.StringBuilder
function Yaz($m) { [void]$sb.AppendLine([string]$m); Write-Host $m }
function Sor($db, $q) { try { return @(Invoke-Sqlcmd -ServerInstance $SqlServer -Database $db -Query $q -QueryTimeout 120 -ErrorAction Stop) } catch { Yaz "  HATA: $($_.Exception.Message)"; return @() } }
function Dok($satirlar) { foreach ($r in $satirlar) { $p = @(); foreach ($c in $r.Table.Columns) { $v = $r[$c.ColumnName]; if ($v -isnot [DBNull] -and [string]$v -ne '') { $p += "$($c.ColumnName)=$v" } }; Yaz ("  " + ($p -join " | ")) } }
$dbler = @(Sor "master" "SELECT name FROM sys.databases WHERE name LIKE 'ERP12[0-9][0-9][0-9][0-9]' AND state = 0 ORDER BY name DESC")
$db = $null
foreach ($d in $dbler) { $n = @(Sor ([string]$d.name) "SELECT COUNT(*) AS n FROM dbo.FIS WHERE FIS_TARIHI >= DATEADD(day, -7, GETDATE())"); if ($n.Count -and [int]$n[0].n -gt 0) { $db = [string]$d.name; break } }
if (-not $db) { $db = [string]$dbler[0].name }
Yaz "KESIF-ACIKLAMA $(Get-Date -Format 'yyyy-MM-dd HH:mm')  veri tabani: $db"
Yaz ""; Yaz "== 1) Adinda SIPARIS gecen tablolar (satir sayisi) =="
Dok (Sor $db "SELECT t.name AS TABLO, SUM(p.rows) AS SATIR FROM sys.tables t JOIN sys.partitions p ON p.object_id = t.object_id AND p.index_id IN (0,1) WHERE t.name LIKE '%SIPARIS%' GROUP BY t.name ORDER BY t.name")
Yaz ""; Yaz "== 2) Bu tablolarda metin sutunlari ve uzunluklari =="
Dok (Sor $db "SELECT TABLE_NAME, COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME LIKE '%SIPARIS%' AND DATA_TYPE IN ('varchar','nvarchar','text','ntext','char','nchar') ORDER BY TABLE_NAME, COLUMN_NAME")
Yaz ""; Yaz "== 3) Elle girilmis (MK SAHA olmayan) son 5 siparisin dolu metin alanlari =="
Dok (Sor $db "SELECT TOP 5 ID, BELGENO, ACIKLAMA, KARSI_SIPARIS_NO FROM dbo.SIPARIS WHERE BELGENO NOT LIKE 'MK SAHA%' ORDER BY ID DESC")
Yaz ""; Yaz "== 4) SIPARIS_EKTABLOLAR ornek (varsa) =="
Dok (Sor $db "IF OBJECT_ID('dbo.SIPARIS_EKTABLOLAR') IS NOT NULL SELECT TOP 3 * FROM dbo.SIPARIS_EKTABLOLAR ORDER BY 1 DESC")
[System.IO.File]::WriteAllText($Cikti, $sb.ToString(), [System.Text.Encoding]::UTF8)
Write-Host ""; Write-Host "Bitti. Sonuc: $Cikti  -> bu dosyayi gonder."
Read-Host "Kapatmak icin Enter"
