# =====================================================================
#  Murat Gida - ERP12 KESIF: CARI HAREKETLERI nerede tutuluyor?
#  ERP12'ye HICBIR SEY YAZMAZ, sadece okur (SELECT). Internete hicbir sey gondermez.
#  Sonuc: C:\Scripts\kesif-cari.txt  (Not Defteri'nde acilir; Claude'a yapistir)
#  Icinde:
#   1) CARI_BAKIYELER'in tanimi (bakiye hangi tablodan hesaplaniyor - asil ipucu)
#   2) Adinda CARI / HAREKET / TAHSIL / ODEME / KASA / BANKA / CEK / SENET / DEKONT /
#      VIRMAN / MAKBUZ / MAHSUP gecen dolu tablolar ve gorunumler + sutunlari
#   3) BORC / ALACAK sutunu olan dolu tablolar
#   4) En hareketli bir carinin son 8 hareketi (aday tablolardan)
# =====================================================================
$SqlServer = "SERVER\ERP12"
$Cikti     = "C:\Scripts\kesif-cari.txt"
Import-Module SqlServer -ErrorAction SilentlyContinue
$sb = New-Object System.Text.StringBuilder
function Yaz($m) { [void]$sb.AppendLine([string]$m); Write-Host $m }
function Sor($db, $q) { try { return @(Invoke-Sqlcmd -ServerInstance $SqlServer -Database $db -Query $q -QueryTimeout 120 -MaxCharLength 20000 -ErrorAction Stop) } catch { Yaz "  HATA: $($_.Exception.Message)"; return @() } }
function Dok($satirlar) {
    foreach ($r in $satirlar) {
        $p = @(); foreach ($c in $r.Table.Columns) { $v = $r[$c.ColumnName]; if ($v -isnot [DBNull] -and [string]$v -ne '') { $p += "$($c.ColumnName)=$v" } }
        Yaz ("  " + ($p -join " | "))
    }
}
$dbler = @(Sor "master" "SELECT name FROM sys.databases WHERE name LIKE 'ERP12[0-9][0-9][0-9][0-9]' AND state = 0 ORDER BY name DESC")
if ($dbler.Count -eq 0) { Write-Host "ERP12 veri tabani bulunamadi."; Read-Host "Enter"; exit 1 }
$db = [string]$dbler[0].name
Yaz "KESIF-CARI $(Get-Date -Format 'yyyy-MM-dd HH:mm')  veri tabani: $db  (diger yillar: $((@($dbler | ForEach-Object { [string]$_.name }) -join ', ')))"

Yaz ""; Yaz "== 1) CARI_BAKIYELER ve adinda CARI gecen GORUNUMLERIN tanimi =="
$gor = @(Sor $db "SELECT o.name AS ad, m.definition AS tanim FROM sys.views o JOIN sys.sql_modules m ON m.object_id = o.object_id WHERE o.name LIKE '%CARI%' OR o.name LIKE '%HESAP%' OR o.name LIKE '%BAKIYE%' ORDER BY o.name")
foreach ($g in $gor) { Yaz "  ---- GORUNUM $($g.ad) ----"; Yaz ([string]$g.tanim) }
if ($gor.Count -eq 0) { Yaz "  (gorunum yok; CARI_BAKIYELER tablo olabilir)" }
$fn = @(Sor $db "SELECT o.name AS ad, o.type_desc AS tur, m.definition AS tanim FROM sys.objects o JOIN sys.sql_modules m ON m.object_id = o.object_id WHERE o.type IN ('FN','IF','TF','P') AND (o.name LIKE '%CARI%BAKIYE%' OR o.name LIKE '%CARI%HAREKET%' OR o.name LIKE '%EKSTRE%') ORDER BY o.name")
foreach ($g in $fn) { Yaz "  ---- $($g.tur) $($g.ad) ----"; Yaz ([string]$g.tanim) }

Yaz ""; Yaz "== 2) Aday tablolar (dolu olanlar) ve sutunlari =="
$tl = @(Sor $db @"
SELECT t.name AS ad, SUM(p.rows) AS satir
FROM sys.tables t JOIN sys.partitions p ON p.object_id = t.object_id AND p.index_id IN (0,1)
WHERE t.name LIKE '%CARI%' OR t.name LIKE '%HAREKET%' OR t.name LIKE '%TAHSIL%' OR t.name LIKE '%ODEME%' OR t.name LIKE '%KASA%'
   OR t.name LIKE '%BANKA%' OR t.name LIKE '%CEK%' OR t.name LIKE '%SENET%' OR t.name LIKE '%DEKONT%' OR t.name LIKE '%VIRMAN%'
   OR t.name LIKE '%MAKBUZ%' OR t.name LIKE '%MAHSUP%' OR t.name LIKE '%EKSTRE%' OR t.name LIKE '%FATURA%'
GROUP BY t.name HAVING SUM(p.rows) > 0 ORDER BY t.name
"@)
foreach ($t in $tl) {
    $kol = @(Sor $db "SELECT COLUMN_NAME AS c, DATA_TYPE AS d FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = '$($t.ad)' ORDER BY ORDINAL_POSITION")
    Yaz ("  $($t.ad)  [$($t.satir) satir]: " + (($kol | ForEach-Object { "$($_.c):$($_.d)" }) -join ", "))
    if ([long]$t.satir -le 40) { Dok (@(Sor $db "SELECT * FROM dbo.[$($t.ad)]")) }
}

Yaz ""; Yaz "== 3) BORC / ALACAK sutunu olan dolu tablolar =="
$ba = @(Sor $db @"
SELECT c.TABLE_NAME AS t, c.COLUMN_NAME AS c, x.satir
FROM INFORMATION_SCHEMA.COLUMNS c
JOIN (SELECT t.name, SUM(p.rows) AS satir FROM sys.tables t JOIN sys.partitions p ON p.object_id = t.object_id AND p.index_id IN (0,1) GROUP BY t.name) x ON x.name = c.TABLE_NAME
WHERE x.satir > 0 AND (c.COLUMN_NAME LIKE '%BORC%' OR c.COLUMN_NAME LIKE '%ALACAK%')
ORDER BY c.TABLE_NAME, c.ORDINAL_POSITION
"@)
foreach ($r in $ba) { Yaz "  $($r.t).$($r.c)  [$($r.satir) satir]" }

Yaz ""; Yaz "== 4) Ornek: en buyuk bakiyeli 1 cari ve aday tablolardaki son 8 hareketi =="
$c1 = @(Sor $db "SELECT TOP 1 c.ID, c.KOD, c.AD, b.BAKIYE FROM dbo.CARI_BAKIYELER b JOIN dbo.CARI c ON c.ID = b.ID ORDER BY ABS(b.BAKIYE) DESC")
if ($c1.Count -gt 0) {
    $cid = $c1[0].ID
    Yaz "  Cari: ID=$cid KOD=$($c1[0].KOD) AD=$($c1[0].AD) BAKIYE=$($c1[0].BAKIYE)"
    $adaylar = @($tl | ForEach-Object { [string]$_.ad } | Where-Object { $_ -ne 'CARI' })
    foreach ($t in $adaylar) {
        $kolAd = @((Sor $db "SELECT COLUMN_NAME AS c FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = '$t'") | ForEach-Object { [string]$_.c })
        $ck = @('CARI', 'FK_CARI', 'CARI_ID', 'CARI_HESAP') | Where-Object { $kolAd -contains $_ } | Select-Object -First 1
        if (-not $ck) { continue }
        $sk = @('TARIH', 'ISLEM_TARIHI', 'FIS_TARIHI', 'BELGE_TARIHI', 'KAYIT_TARIHI', 'ID') | Where-Object { $kolAd -contains $_ } | Select-Object -First 1
        $say = @(Sor $db "SELECT COUNT(*) AS n FROM dbo.[$t] WHERE [$ck] = '$cid'")
        if ($say.Count -eq 0 -or [long]$say[0].n -eq 0) { continue }
        Yaz "  -- $t  ($ck = cari, $($say[0].n) satir, siralama: $sk)"
        Dok (@(Sor $db "SELECT TOP 8 * FROM dbo.[$t] WHERE [$ck] = '$cid' ORDER BY [$sk] DESC"))
    }
}

Yaz ""; Yaz "== 5) Tur / tip tablolari (hareket turlerinin adlari) =="
$tt = @(Sor $db @"
SELECT t.name AS ad, SUM(p.rows) AS satir
FROM sys.tables t JOIN sys.partitions p ON p.object_id = t.object_id AND p.index_id IN (0,1)
WHERE (t.name LIKE '%TUR%' OR t.name LIKE '%TIP%') AND (t.name LIKE '%CARI%' OR t.name LIKE '%HAREKET%' OR t.name LIKE '%ISLEM%' OR t.name LIKE '%BELGE%' OR t.name LIKE '%FIS%')
GROUP BY t.name HAVING SUM(p.rows) BETWEEN 1 AND 80 ORDER BY t.name
"@)
foreach ($t in $tt) { Yaz "  -- $($t.ad)"; Dok (@(Sor $db "SELECT * FROM dbo.[$($t.ad)]")) }

[System.IO.File]::WriteAllText($Cikti, $sb.ToString(), [System.Text.Encoding]::UTF8)
Write-Host ""; Write-Host "Bitti. Sonuc Not Defteri'nde aciliyor: hepsini sec (Ctrl+A), kopyala (Ctrl+C), Claude'a yapistir."
try { Start-Process notepad.exe -ArgumentList $Cikti } catch {}
Read-Host "Kapatmak icin Enter"
