# =====================================================================
#  MK Saha - ERP12 KESIF: irsaliyeler (alis 5, satis 6, alistan iade 7, satistan iade 8)
#  ERP12'ye HICBIR SEY YAZMAZ, sadece okur. Sonuc: C:\Scripts\kesif-irsaliye.txt
#  Her tur icin ERP'nin KENDI actigi son irsaliye: baslik, ilk satir, sayac kayitlari,
#  o fise bagli baska tablolar, numara serileri, trigger'lar ve zorunlu sutunlar.
# =====================================================================
$SqlServer = "SERVER\ERP12"
$Cikti     = "C:\Scripts\kesif-irsaliye.txt"
Import-Module SqlServer -ErrorAction SilentlyContinue
$sb = New-Object System.Text.StringBuilder
function Yaz($m) { [void]$sb.AppendLine([string]$m); Write-Host $m }
function Sor($db, $q) { try { return @(Invoke-Sqlcmd -ServerInstance $SqlServer -Database $db -Query $q -QueryTimeout 180 -ErrorAction Stop) } catch { Yaz "  HATA: $($_.Exception.Message)"; return @() } }
function Dok($satirlar) { foreach ($r in $satirlar) { $p = @(); foreach ($c in $r.Table.Columns) { $v = $r[$c.ColumnName]; if ($v -isnot [DBNull] -and [string]$v -ne '') { $p += "$($c.ColumnName)=$v" } }; Yaz ("  " + ($p -join " | ")); Yaz "" } }
$dbler = @(Sor "master" "SELECT name FROM sys.databases WHERE name LIKE 'ERP12[0-9][0-9][0-9][0-9]' AND state = 0 ORDER BY name DESC")
$db = $null
foreach ($d in $dbler) { $n = @(Sor ([string]$d.name) "SELECT COUNT(*) AS n FROM dbo.FIS WHERE FIS_TARIHI >= DATEADD(day, -7, GETDATE())"); if ($n.Count -and [int]$n[0].n -gt 0) { $db = [string]$d.name; break } }
if (-not $db) { $db = [string]$dbler[0].name }
Yaz "KESIF-IRSALIYE $(Get-Date -Format 'yyyy-MM-dd HH:mm')  veri tabani: $db"

Yaz ""; Yaz "== 0) FIS / FIS_DETAY trigger'lari ve tablolari degistiren prosedurler =="
Dok (Sor $db "SELECT tr.name AS TRIGGER_ADI, OBJECT_NAME(tr.parent_id) AS TABLO, tr.is_disabled FROM sys.triggers tr WHERE OBJECT_NAME(tr.parent_id) IN ('FIS','FIS_DETAY','STOK','CARI')")
Yaz ""; Yaz "== 0b) Adinda MIKTAR / BAKIYE / ENVANTER / LOKASYON_STOK gecen tablolar (stok toplami tutuluyor mu) =="
Dok (Sor $db "SELECT t.name AS TABLO, SUM(p.rows) AS SATIR FROM sys.tables t JOIN sys.partitions p ON p.object_id = t.object_id AND p.index_id IN (0,1) WHERE t.name LIKE '%MIKTAR%' OR t.name LIKE '%BAKIYE%' OR t.name LIKE '%ENVANTER%' OR t.name LIKE '%LOKASYON[_]STOK%' OR t.name LIKE '%STOK[_]DURUM%' GROUP BY t.name")
Yaz ""; Yaz "== 0c) FIRMASABITLERI e-belge alanlari =="
Dok (Sor $db "SELECT * FROM dbo.FIRMASABITLERI")

foreach ($tur in 5, 6, 7, 8) {
    Yaz ""; Yaz "################ FIS_TURU $tur ################"
    Yaz "-- son 8 belge numarasi ve kim acti (MOBIL_MI, FIS_BASIM_TIPI)"
    Dok (Sor $db "SELECT TOP 8 f.ID, f.BELGENO, f.FIS_TARIHI, f.MOBIL_MI, f.FIS_BASIM_TIPI, f.E_FATURA_TIPI, q.KOD_PC FROM dbo.FIS f LEFT JOIN dbo.SEQUNCES q ON q.ID = f.ID WHERE f.FIS_TURU = $tur AND f.AKTIF = 1 ORDER BY f.ID DESC")
    $son = @(Sor $db "SELECT TOP 1 ID FROM dbo.FIS WHERE FIS_TURU = $tur AND AKTIF = 1 AND ISNULL(MOBIL_MI, 0) = 0 ORDER BY ID DESC")
    if ($son.Count -eq 0) { $son = @(Sor $db "SELECT TOP 1 ID FROM dbo.FIS WHERE FIS_TURU = $tur AND AKTIF = 1 ORDER BY ID DESC") }
    if ($son.Count -eq 0) { Yaz "  bu turde belge yok"; continue }
    $id = [long]$son[0].ID
    Yaz "-- ornek FIS $id (tum dolu alanlar)"; Dok (Sor $db "SELECT * FROM dbo.FIS WHERE ID = $id")
    Yaz "-- ilk satiri"; Dok (Sor $db "SELECT TOP 1 * FROM dbo.FIS_DETAY WHERE FIS = $id ORDER BY ID")
    Yaz "-- SEQUNCES"; Dok (Sor $db "SELECT q.* FROM dbo.SEQUNCES q WHERE q.ID = $id OR q.ID IN (SELECT ID FROM dbo.FIS_DETAY WHERE FIS = $id)")
    Yaz "-- bu fise bagli diger tablolar (sutun adi FIS)"
    $aday = @(Sor $db "SELECT t.name AS TABLO FROM sys.columns c JOIN sys.tables t ON t.object_id = c.object_id WHERE c.name = 'FIS' AND t.name NOT IN ('FIS_DETAY','FIS')")
    foreach ($a in $aday) { $t = [string]$a.TABLO; $s = @(Sor $db "SELECT TOP 3 * FROM dbo.[$t] WHERE FIS = $id"); if ($s.Count -gt 0) { Yaz "   [$t]"; Dok $s } }
}

Yaz ""; Yaz "== 9) FIS ve FIS_DETAY: bos olamayan sutunlar ve varsayilanlar =="
Dok (Sor $db "SELECT TABLE_NAME, COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH AS UZ, COLUMN_DEFAULT AS VARSAYILAN FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME IN ('FIS','FIS_DETAY') AND IS_NULLABLE = 'NO' ORDER BY TABLE_NAME, ORDINAL_POSITION")
Yaz ""; Yaz "== 10) Belge numarasi serileri (KOD_BELGE) irsaliye turleri =="
Dok (Sor $db "IF OBJECT_ID('dbo.KOD_BELGE') IS NOT NULL SELECT * FROM dbo.KOD_BELGE WHERE FK_FIS_TURU IN (5,6,7,8)")

[System.IO.File]::WriteAllText($Cikti, $sb.ToString(), [System.Text.Encoding]::UTF8)
Write-Host ""; Write-Host "Bitti. Sonuc: $Cikti  -> bu dosyayi gonder."
Read-Host "Kapatmak icin Enter"
