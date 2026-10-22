# =====================================================================
#  MK Saha - ERP12 KESIF: "LS FTRS-000008ISP2026000001065" nereden geldi?
#  ERP12'ye HICBIR SEY YAZMAZ, sadece okur. Sonuc: C:\Scripts\kesif-ftrs.txt
# =====================================================================
$SqlServer = "SERVER\ERP12"
$Cikti     = "C:\Scripts\kesif-ftrs.txt"
Import-Module SqlServer -ErrorAction SilentlyContinue
$sb = New-Object System.Text.StringBuilder
function Yaz($m) { [void]$sb.AppendLine([string]$m); Write-Host $m }
function Sor($db, $q) { try { return @(Invoke-Sqlcmd -ServerInstance $SqlServer -Database $db -Query $q -QueryTimeout 300 -ErrorAction Stop) } catch { Yaz "  HATA: $($_.Exception.Message)"; return @() } }
function Dok($satirlar) { foreach ($r in $satirlar) { $p = @(); foreach ($c in $r.Table.Columns) { $v = $r[$c.ColumnName]; if ($v -isnot [DBNull] -and [string]$v -ne '') { $p += "$($c.ColumnName)=$v" } }; Yaz ("  " + ($p -join " | ")); Yaz "" } }
$db = "ERP122025"
Yaz "KESIF-FTRS $(Get-Date -Format 'yyyy-MM-dd HH:mm')  veri tabani: $db"
Yaz ""; Yaz "== 1) Belge no'sunda ISP2026000001065 ya da LS FTRS gecen fisler =="
Dok (Sor $db "SELECT TOP 20 f.ID, f.FIS_TURU, f.BELGENO, f.FIS_TARIHI, f.ISLEM_TARIHI, f.CARI, c.AD AS CARI_AD, f.MOBIL_MI, f.AKTIF FROM dbo.FIS f LEFT JOIN dbo.CARI c ON c.ID = f.CARI WHERE f.BELGENO LIKE '%ISP2026000001065%' OR f.BELGENO LIKE 'LS FTRS%' ORDER BY f.ID DESC")
Yaz ""; Yaz "== 2) Bu bilgisayarlarin alis faturasi seri tanimlari (KOD_BELGE, FIS_TURU 1) =="
Dok (Sor $db "SELECT * FROM dbo.KOD_BELGE WHERE FK_FIS_TURU = 1")
Yaz ""; Yaz "== 3) ISP2026000001065 baska hangi tablolarda geciyor (metin sutunlari, e-belge tablolari dahil) =="
$kol = @(Sor $db "SELECT t.name AS T, c.name AS C FROM sys.columns c JOIN sys.tables t ON t.object_id = c.object_id JOIN sys.types y ON y.user_type_id = c.user_type_id WHERE y.name IN ('nvarchar','varchar','nchar','char') AND c.max_length BETWEEN 16 AND 400 AND (t.name LIKE '%FIS%' OR t.name LIKE '%FATURA%' OR t.name LIKE '%BELGE%' OR t.name LIKE '%IRSALIYE%' OR t.name LIKE '%GELEN%' OR t.name LIKE 'E[_]%')")
foreach ($k in $kol) {
    $t = [string]$k.T; $c = [string]$k.C
    $s = @(Sor $db "SELECT TOP 3 * FROM dbo.[$t] WHERE [$c] LIKE '%ISP2026000001065%'")
    if ($s.Count -gt 0) { Yaz "-- $t.$c"; Dok $s }
}
Yaz ""; Yaz "== 4) Yilmaz Erkabak carisinin son 10 alis fatura / irsaliyesi =="
Dok (Sor $db "SELECT TOP 10 f.ID, f.FIS_TURU, f.BELGENO, f.FIS_TARIHI, f.MOBIL_MI, f.AKTIF FROM dbo.FIS f JOIN dbo.CARI c ON c.ID = f.CARI WHERE c.AD LIKE '%ERKABAK%' AND f.FIS_TURU IN (1, 5) ORDER BY f.ID DESC")
[System.IO.File]::WriteAllText($Cikti, $sb.ToString(), [System.Text.Encoding]::UTF8)
Write-Host ""; Write-Host "Bitti. Sonuc: $Cikti  -> bu dosyayi gonder."
Read-Host "Kapatmak icin Enter"
