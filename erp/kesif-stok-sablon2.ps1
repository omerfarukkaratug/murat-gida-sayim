# =====================================================================
#  MK Saha - ERP12 KESIF 2: sablon stok kartinin barkod / fiyat / sayac kayitlari.
#  ERP12'ye HICBIR SEY YAZMAZ, sadece okur. Sonuc: C:\Scripts\kesif-stok-sablon2.txt
# =====================================================================
$SqlServer = "SERVER\ERP12"
$Cikti     = "C:\Scripts\kesif-stok-sablon2.txt"
Import-Module SqlServer -ErrorAction SilentlyContinue
$sb = New-Object System.Text.StringBuilder
function Yaz($m) { [void]$sb.AppendLine([string]$m); Write-Host $m }
function Sor($db, $q) { try { return @(Invoke-Sqlcmd -ServerInstance $SqlServer -Database $db -Query $q -QueryTimeout 120 -MaxCharLength 20000 -ErrorAction Stop) } catch { Yaz "  HATA: $($_.Exception.Message)"; return @() } }
function Dok($satirlar) { foreach ($r in $satirlar) { $p = @(); foreach ($c in $r.Table.Columns) { $v = $r[$c.ColumnName]; if ($v -isnot [DBNull] -and [string]$v -ne '') { $p += "$($c.ColumnName)=$v" } }; Yaz ("  " + ($p -join " | ")); Yaz "" } }
$dbler = @(Sor "master" "SELECT name FROM sys.databases WHERE name LIKE 'ERP12[0-9][0-9][0-9][0-9]' AND state = 0 ORDER BY name DESC")
$db = $null
foreach ($d in $dbler) { $n = @(Sor ([string]$d.name) "SELECT COUNT(*) AS n FROM dbo.FIS WHERE FIS_TARIHI >= DATEADD(day, -7, GETDATE())"); if ($n.Count -and [int]$n[0].n -gt 0) { $db = [string]$d.name; break } }
if (-not $db) { $db = [string]$dbler[0].name }
$s = @(Sor $db "SELECT TOP 1 STOK FROM dbo.STOK_BARKOD_BIRIM WHERE BARKOD IN ('MKSABLON', '99999001')")
if ($s.Count -eq 0) { Yaz "Sablon kart bulunamadi."; [System.IO.File]::WriteAllText($Cikti, $sb.ToString(), [System.Text.Encoding]::UTF8); Read-Host "Enter"; exit 1 }
$id = [long]$s[0].STOK
Yaz "KESIF-STOK-SABLON2 $(Get-Date -Format 'yyyy-MM-dd HH:mm')  veri tabani: $db  sablon STOK ID: $id"

Yaz ""; Yaz "== 1) STOK_BARKOD_BIRIM tablo mu gorunum mu? Gorunumse tanimi =="
Dok (Sor $db "SELECT o.name, o.type_desc FROM sys.objects o WHERE o.name IN ('STOK_BARKOD_BIRIM','STOK_BARKOD','STOK_STOK_BIRIM','STOK_STOK_BIRIM_FIYAT','SEQUNCES')")
Yaz (Sor $db "SELECT OBJECT_DEFINITION(OBJECT_ID('dbo.STOK_BARKOD_BIRIM')) AS T" | ForEach-Object { $_.T })

Yaz ""; Yaz "== 2) Sablonun STOK_BARKOD satirlari =="
Dok (Sor $db "SELECT b.* FROM dbo.STOK_BARKOD b WHERE b.ID BETWEEN $id AND $($id + 10) OR b.BARKOD IN ('MKSABLON','99999001')")

Yaz ""; Yaz "== 3) Sutunlar: STOK_BARKOD, STOK_STOK_BIRIM, STOK_STOK_BIRIM_FIYAT, SEQUNCES =="
Dok (Sor $db "SELECT TABLE_NAME, COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH AS UZ, IS_NULLABLE AS BOS, COLUMN_DEFAULT AS VARSAYILAN FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME IN ('STOK_BARKOD','STOK_STOK_BIRIM','STOK_STOK_BIRIM_FIYAT','SEQUNCES') ORDER BY TABLE_NAME, ORDINAL_POSITION")

Yaz ""; Yaz "== 4) Sablonun SEQUNCES kayitlari (tum alanlar) =="
Dok (Sor $db "SELECT * FROM dbo.SEQUNCES WHERE ID BETWEEN $id AND $($id + 6)")

Yaz ""; Yaz "== 5) STOK_STOK_BIRIM ve FIYAT satirlarini kullanan baska tablolar (sutun adi STOK_STOK_BIRIM) =="
Dok (Sor $db "SELECT t.name AS TABLO, c.name AS SUTUN FROM sys.columns c JOIN sys.tables t ON t.object_id = c.object_id WHERE c.name IN ('STOK_STOK_BIRIM','FK_STOK_STOK_BIRIM','STOK_BARKOD')")

Yaz ""; Yaz "== 6) KARSILASTIRMA: ERP'nin son acilan 2 normal kartinin (sablon disi) bagli satir sayilari =="
$son = @(Sor $db "SELECT TOP 2 ID, KOD, AD FROM dbo.STOK WHERE ID < $id ORDER BY ID DESC")
foreach ($k in $son) {
    $kid = [long]$k.ID
    Yaz "-- $($k.KOD) $($k.AD) (ID $kid)"
    Dok (Sor $db "SELECT 'STOK_STOK_BIRIM' AS T, COUNT(*) AS N FROM dbo.STOK_STOK_BIRIM WHERE STOK = $kid UNION ALL SELECT 'FIYAT', COUNT(*) FROM dbo.STOK_STOK_BIRIM_FIYAT f JOIN dbo.STOK_STOK_BIRIM u ON u.ID = f.STOK_STOK_BIRIM WHERE u.STOK = $kid UNION ALL SELECT 'SEQUNCES', COUNT(*) FROM dbo.SEQUNCES WHERE ID BETWEEN $kid AND $($kid + 6)")
    Dok (Sor $db "SELECT * FROM dbo.SEQUNCES WHERE ID BETWEEN $kid AND $($kid + 6)")
}

Yaz ""; Yaz "== 7) STOK_VERGI 1019 ve STOK_GRUP 438357 nedir =="
Dok (Sor $db "SELECT * FROM dbo.STOK_VERGI WHERE ID = 1019")
Dok (Sor $db "IF OBJECT_ID('dbo.STOK_GRUP') IS NOT NULL SELECT * FROM dbo.STOK_GRUP WHERE ID = 438357")
Yaz ""; Yaz "== 8) Bizim siparislerimizin SEQUNCES kaydi var mi (MK SAHA)? =="
Dok (Sor $db "SELECT TOP 3 s.ID, s.BELGENO, q.TABLO, q.KOD_PC FROM dbo.SIPARIS s LEFT JOIN dbo.SEQUNCES q ON q.ID = s.ID WHERE s.BELGENO LIKE 'MK SAHA%' ORDER BY s.ID DESC")
Dok (Sor $db "SELECT TOP 3 s.ID, s.BELGENO, q.TABLO, q.KOD_PC FROM dbo.SIPARIS s LEFT JOIN dbo.SEQUNCES q ON q.ID = s.ID WHERE s.BELGENO NOT LIKE 'MK SAHA%' ORDER BY s.ID DESC")

[System.IO.File]::WriteAllText($Cikti, $sb.ToString(), [System.Text.Encoding]::UTF8)
Write-Host ""; Write-Host "Bitti. Sonuc: $Cikti  -> bu dosyayi gonder."
Read-Host "Kapatmak icin Enter"
