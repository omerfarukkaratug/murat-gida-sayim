# =====================================================================
#  Murat Gida - ERP12 KESIF: miktar indirimi / toptan fiyat nerede duruyor?
#  ERP12'ye HICBIR SEY YAZMAZ, sadece okur. Internete hicbir sey gondermez.
#  Sonuc: C:\Scripts\kesif-koli.txt  (bu dosyayi Claude'a gonder)
#  Icinde: fiyatla ilgili tablo ADLARI ve SUTUNLARI ile sorulan TEK urunun
#  fiyat satirlari vardir. Sifre, anahtar, musteri bilgisi YOKTUR.
# =====================================================================
$SqlServer = "SERVER\ERP12"
$Cikti     = "C:\Scripts\kesif-koli.txt"
$Barkod    = Read-Host "Kasada miktar girince indirim uygulanan bir urunun TEKLI barkodunu yaz (orn. Dimes 200 ml)"
$Barkod    = $Barkod.Trim()

Import-Module SqlServer -ErrorAction SilentlyContinue
$sb = New-Object System.Text.StringBuilder
function Yaz($m) { [void]$sb.AppendLine([string]$m); Write-Host $m }
function Sor($db, $q) { try { return @(Invoke-Sqlcmd -ServerInstance $SqlServer -Database $db -Query $q -QueryTimeout 120 -ErrorAction Stop) } catch { Yaz "  HATA: $($_.Exception.Message)"; return @() } }
function Dok($satirlar) {
    foreach ($r in $satirlar) {
        $p = @(); foreach ($c in $r.Table.Columns) { $v = $r[$c.ColumnName]; if ($v -isnot [DBNull]) { $p += "$($c.ColumnName)=$v" } }
        Yaz ("  " + ($p -join " | "))
    }
}

$dbler = Sor "master" "SELECT name FROM sys.databases WHERE name LIKE 'ERP12[0-9][0-9][0-9][0-9]' AND state = 0 ORDER BY name DESC"
if ($dbler.Count -eq 0) { Write-Host "ERP12 veri tabani bulunamadi."; Read-Host "Enter"; exit 1 }
$db = [string]$dbler[0].name
Yaz "KESIF $(Get-Date -Format 'yyyy-MM-dd HH:mm')  veri tabani: $db  barkod: $Barkod"

Yaz ""; Yaz "== 1) FIYAT LISTELERI (STOK_FIYAT_AD) =="
Dok (Sor $db "SELECT TOP 40 * FROM dbo.STOK_FIYAT_AD")

Yaz ""; Yaz "== 2) ADINDA fiyat / kampanya / iskonto / indirim / promosyon / miktar gecen tablolar =="
$tablolar = Sor $db @"
SELECT t.name AS ad, SUM(p.rows) AS satir
FROM sys.tables t JOIN sys.partitions p ON p.object_id = t.object_id AND p.index_id IN (0,1)
WHERE t.name LIKE '%FIYAT%' OR t.name LIKE '%KAMPANYA%' OR t.name LIKE '%ISKONTO%' OR t.name LIKE '%INDIRIM%'
   OR t.name LIKE '%PROMOSYON%' OR t.name LIKE '%MIKTAR%' OR t.name LIKE '%TOPTAN%' OR t.name LIKE '%KADEME%'
GROUP BY t.name ORDER BY t.name
"@
foreach ($t in $tablolar) {
    $kol = Sor $db "SELECT COLUMN_NAME AS c, DATA_TYPE AS d FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = '$($t.ad)' ORDER BY ORDINAL_POSITION"
    Yaz ("  $($t.ad)  [$($t.satir) satir]: " + (($kol | ForEach-Object { "$($_.c):$($_.d)" }) -join ", "))
}

Yaz ""; Yaz "== 3) URUN: $Barkod =="
if ($Barkod -notmatch '^[0-9A-Za-z]{4,20}$') { Yaz "  Barkod gecersiz, bu bolum atlandi." }
else {
    $u = Sor $db "SELECT bb.BARKOD, bb.STOK, bb.STOK_STOK_BIRIM, bb.STOK_BIRIM, bb.CARPAN, s.KOD FROM dbo.STOK_BARKOD_BIRIM bb LEFT JOIN dbo.STOK s ON s.ID = bb.STOK WHERE bb.BARKOD = '$Barkod'"
    Dok $u
    if ($u.Count -gt 0) {
        $stok = $u[0].STOK
        Yaz "  -- ayni urunun butun barkod/birimleri:"
        $hepsi = Sor $db "SELECT bb.BARKOD, bb.STOK_STOK_BIRIM, bb.CARPAN, sb.AD AS Birim, f.FIYAT FROM dbo.STOK_BARKOD_BIRIM bb LEFT JOIN dbo.STOK_BIRIM sb ON sb.ID = bb.STOK_BIRIM LEFT JOIN dbo.STOK_BARKOD_FIYAT_VARSAYILAN f ON f.STOK_STOK_BIRIM = bb.STOK_STOK_BIRIM WHERE bb.STOK = '$stok'"
        Dok $hepsi
        $ssbler = @($hepsi | ForEach-Object { "'" + [string]$_.STOK_STOK_BIRIM + "'" } | Select-Object -Unique) -join ","
        foreach ($t in $tablolar) {
            $kolAd = @((Sor $db "SELECT COLUMN_NAME AS c FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = '$($t.ad)'") | ForEach-Object { [string]$_.c })
            $kosul = $null
            if ($kolAd -contains 'STOK_STOK_BIRIM' -and $ssbler) { $kosul = "STOK_STOK_BIRIM IN ($ssbler)" }
            elseif ($kolAd -contains 'STOK') { $kosul = "STOK = '$stok'" }
            if (-not $kosul) { continue }
            $r = Sor $db "SELECT TOP 15 * FROM dbo.[$($t.ad)] WHERE $kosul"
            if ($r.Count -gt 0) { Yaz "  -- $($t.ad) ($($r.Count) satir):"; Dok $r }
        }
    } else { Yaz "  Bu barkod STOK_BARKOD_BIRIM'de yok." }
}
[System.IO.File]::WriteAllText($Cikti, $sb.ToString(), [System.Text.Encoding]::UTF8)
Write-Host ""; Write-Host "Bitti. Dosya: $Cikti"
Read-Host "Kapatmak icin Enter"
