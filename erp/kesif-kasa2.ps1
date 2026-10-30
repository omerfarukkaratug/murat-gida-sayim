# =====================================================================
#  MK Saha - ERP12 KESIF KASA 2: kasalar yeni kartlari SEQUNCES_DEGISIKLIK (degisiklik kaydi)
#  tablosundan aliyor olmali. ERP'nin elle acilan bir kart icin bu tabloya ne yazdigini gosterir.
#  ERP12'ye HICBIR SEY YAZMAZ, sadece okur. Sonuc: C:\Scripts\kesif-kasa2.txt
# =====================================================================
$SqlServer = "SERVER\ERP12"
$Cikti     = "C:\Scripts\kesif-kasa2.txt"
Import-Module SqlServer -ErrorAction SilentlyContinue
$sb = New-Object System.Text.StringBuilder
function Yaz($m) { [void]$sb.AppendLine([string]$m); Write-Host $m }
function Kaydet { try { [System.IO.File]::WriteAllText($Cikti, $sb.ToString(), [System.Text.Encoding]::UTF8) } catch {} }
function Sor($db, $q, $sn = 300) { try { return @(Invoke-Sqlcmd -ServerInstance $SqlServer -Database $db -Query $q -QueryTimeout $sn -MaxCharLength 20000 -ErrorAction Stop) } catch { Yaz "  HATA: $($_.Exception.Message)"; return @() } }
function Dok($satirlar) { foreach ($r in $satirlar) { $p = @(); foreach ($c in $r.Table.Columns) { $v = $r[$c.ColumnName]; if ($v -isnot [DBNull] -and [string]$v -ne '') { $p += "$($c.ColumnName)=$v" } }; Yaz ("  " + ($p -join " | ")) } }

$dbler = @(Sor "master" "SELECT name FROM sys.databases WHERE name LIKE 'ERP12[0-9][0-9][0-9][0-9]' AND state = 0 ORDER BY name DESC")
$db = $null
foreach ($d in $dbler) { $n = @(Sor ([string]$d.name) "SELECT COUNT(*) AS n FROM dbo.FIS WITH (NOLOCK) WHERE FIS_TARIHI >= DATEADD(day, -7, GETDATE())"); if ($n.Count -and [int]$n[0].n -gt 0) { $db = [string]$d.name; break } }
if (-not $db) { $db = [string]$dbler[0].name }
Yaz "KESIF-KASA2 $(Get-Date -Format 'yyyy-MM-dd HH:mm')  veri tabani: $db"

Yaz ""; Yaz "== 1) SEQUNCES_DEGISIKLIK sutunlari =="
Dok (Sor $db "SELECT c.name AS SUTUN, y.name AS TIP, c.max_length AS UZ, c.is_nullable AS BOS, c.is_identity AS KIMLIK, OBJECT_DEFINITION(c.default_object_id) AS VARSAYILAN FROM sys.columns c JOIN sys.types y ON y.user_type_id = c.user_type_id WHERE c.object_id = OBJECT_ID('dbo.SEQUNCES_DEGISIKLIK') ORDER BY c.column_id")
Dok (Sor $db "SELECT i.name AS INDEKS, i.type_desc, (SELECT STUFF((SELECT ',' + COL_NAME(ic.object_id, ic.column_id) FROM sys.index_columns ic WHERE ic.object_id = i.object_id AND ic.index_id = i.index_id FOR XML PATH('')), 1, 1, '')) AS SUTUNLAR FROM sys.indexes i WHERE i.object_id = OBJECT_ID('dbo.SEQUNCES_DEGISIKLIK')")
Yaz "-- Tetikleyiciler (SEQUNCES / SEQUNCES_DEGISIKLIK)"
Dok (Sor $db "SELECT tr.name AS TRIGGER_ADI, OBJECT_NAME(tr.parent_id) AS TABLO, LEFT(OBJECT_DEFINITION(tr.object_id), 3000) AS TANIM FROM sys.triggers tr WHERE OBJECT_NAME(tr.parent_id) IN ('SEQUNCES','SEQUNCES_DEGISIKLIK')")
Yaz "-- ID nereden geliyor (sequence)?"
Dok (Sor $db "SELECT name, CAST(current_value AS bigint) AS SIMDIKI FROM sys.sequences")
Dok (Sor $db "SELECT MAX(ID) AS EN_BUYUK_ID, COUNT(*) AS SATIR FROM dbo.SEQUNCES_DEGISIKLIK WITH (NOLOCK)")
Kaydet

# Kartlar: elle acilmis son normal kart + son 3 MKS karti
$normal = @(Sor $db "SELECT TOP 2 ID, KOD, AD FROM dbo.STOK WITH (NOLOCK) WHERE KOD NOT LIKE 'MKS-%' ORDER BY ID DESC")
$mks = @(Sor $db "SELECT TOP 2 ID, KOD, AD FROM dbo.STOK WITH (NOLOCK) WHERE KOD LIKE 'MKS-%' ORDER BY ID DESC")
foreach ($k in @($normal + $mks)) {
    $sid = [long]$k.ID
    Yaz ""; Yaz "== KART $($k.KOD) $($k.AD) (STOK ID $sid) =="
    $ids = @($sid)
    $ids += @(Sor $db "SELECT ID FROM dbo.STOK_STOK_BIRIM WITH (NOLOCK) WHERE STOK = $sid" | ForEach-Object { [long]$_.ID })
    $bir = ($ids | Select-Object -Skip 1) -join ","
    if ($bir) {
        $ids += @(Sor $db "SELECT ID FROM dbo.STOK_STOK_BIRIM_FIYAT WITH (NOLOCK) WHERE STOK_STOK_BIRIM IN ($bir)" | ForEach-Object { [long]$_.ID })
        $ids += @(Sor $db "SELECT ID FROM dbo.STOK_BARKOD WITH (NOLOCK) WHERE STOK_STOK_BIRIM IN ($bir)" | ForEach-Object { [long]$_.ID })
    }
    Yaz "  ilgili kimlikler: $($ids -join ', ')"
    Yaz "  -- SEQUNCES"
    Dok (Sor $db "SELECT * FROM dbo.SEQUNCES WITH (NOLOCK) WHERE ID IN ($($ids -join ','))")
    Yaz "  -- SEQUNCES_DEGISIKLIK (tum alanlar)"
    Dok (Sor $db "SELECT * FROM dbo.SEQUNCES_DEGISIKLIK WITH (NOLOCK) WHERE SEQUNCES IN ($($ids -join ',')) ORDER BY ID")
    Kaydet
}

Yaz ""; Yaz "== 3) Son 1 gunde ISLEM / TABLO dagilimi (kasaya giden degisiklikler) =="
Dok (Sor $db "SELECT ISLEM, TABLO, KOD_PC, COUNT(*) AS N FROM dbo.SEQUNCES_DEGISIKLIK WITH (NOLOCK) WHERE TARIH >= DATEADD(day, -1, GETDATE()) GROUP BY ISLEM, TABLO, KOD_PC ORDER BY N DESC")
Yaz ""; Yaz "== 4) Son 15 satir (KOD_PC = ERP bilgisayari, kasa disi) =="
$erpPc = @(Sor $db "SELECT TOP 1 KOD_PC FROM dbo.SEQUNCES WITH (NOLOCK) WHERE ID = (SELECT TOP 1 STOK FROM dbo.STOK_BARKOD_BIRIM WITH (NOLOCK) WHERE BARKOD IN ('MKSABLON','99999001'))")
if ($erpPc.Count) { Dok (Sor $db "SELECT TOP 15 * FROM dbo.SEQUNCES_DEGISIKLIK WITH (NOLOCK) WHERE KOD_PC = $($erpPc[0].KOD_PC) ORDER BY ID DESC") }
Yaz ""; Yaz "== 5) Kasalarin en son aldigi degisiklik (varsa kasa bazinda takip tablolari) =="
Dok (Sor $db "SELECT t.name AS TABLO, c.name AS SUTUN FROM sys.columns c JOIN sys.tables t ON t.object_id = c.object_id WHERE c.name LIKE '%SON%' AND (t.name LIKE '%POS%' OR t.name LIKE '%SEQ%' OR t.name LIKE '%PC%' OR t.name LIKE '%KASA%')")
Dok (Sor $db "IF OBJECT_ID('dbo.PC_AD') IS NOT NULL SELECT * FROM dbo.PC_AD WITH (NOLOCK) WHERE ID IN (696123, 696195, 696199)")

Kaydet
Write-Host ""; Write-Host "Bitti. Sonuc: $Cikti  -> bu dosyayi gonder."
Read-Host "Kapatmak icin Enter"
