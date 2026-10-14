# =====================================================================
#  Murat Gida - ERP12 KESIF: bir urunun stoga NEREDEN girdigi
#  ERP12'ye HICBIR SEY YAZMAZ, sadece okur (SELECT). Internete hicbir sey gondermez.
#  Sorar: barkod (ya da stok kodu). Sonuc: C:\Scripts\kesif-urun.txt (Claude'a gonder)
#  Icinde, TUM ERP12 yil veri tabanlarinda:
#   1) Bu barkoda / stok koduna bagli stok kartlari (ID, KOD, AD)
#   2) Bu kartlarin ya da barkodun gectigi TUM fis satirlari (tur adi, GIRIS, tarih, belge, cari, miktar)
#   3) STOK sutunu olan diger dolu tablolarda bu kartlarin kac satiri var (transfer, sayim, devir, uretim...)
# =====================================================================
$SqlServer = "SERVER\ERP12"
$Cikti     = "C:\Scripts\kesif-urun.txt"
Import-Module SqlServer -ErrorAction SilentlyContinue
$sb = New-Object System.Text.StringBuilder
function Yaz($m) { [void]$sb.AppendLine([string]$m); Write-Host $m }
function Sor($db, $q) { try { return @(Invoke-Sqlcmd -ServerInstance $SqlServer -Database $db -Query $q -QueryTimeout 180 -MaxCharLength 20000 -ErrorAction Stop) } catch { Yaz "  HATA: $($_.Exception.Message)"; return @() } }
function Dok($satirlar) {
    foreach ($r in $satirlar) {
        $p = @(); foreach ($c in $r.Table.Columns) { $v = $r[$c.ColumnName]; if ($v -isnot [DBNull] -and [string]$v -ne '') { $p += "$($c.ColumnName)=$v" } }
        Yaz ("  " + ($p -join " | "))
    }
}
$aranan = Read-Host "Barkod ya da stok kodu (bos: 8695122005891)"
if (-not $aranan) { $aranan = "8695122005891" }
$aranan = $aranan.Trim().Replace("'", "")
$dbler = @(Sor "master" "SELECT name FROM sys.databases WHERE name LIKE 'ERP12%' AND state = 0 ORDER BY name DESC")
Yaz "KESIF-URUN $(Get-Date -Format 'yyyy-MM-dd HH:mm')  aranan: $aranan  veri tabanlari: $((@($dbler | ForEach-Object { [string]$_.name }) -join ', '))"

foreach ($d in $dbler) {
    $db = [string]$d.name
    Yaz ""; Yaz "################ $db ################"
    Yaz "== 1) Stok kartlari =="
    $kart = @(Sor $db @"
SELECT DISTINCT s.ID, s.KOD, w.AD
FROM dbo.STOK s
LEFT JOIN dbo.STOK_BARKOD_BIRIM bb ON bb.STOK = s.ID
LEFT JOIN dbo.STOK_BARKOD_W w ON w.ID = bb.BARKOD
WHERE s.KOD = '$aranan' OR bb.BARKOD = '$aranan'
"@)
    if ($kart.Count -eq 0) {
        Yaz "  (bu veri tabaninda kart bulunamadi)"
    }
    Dok $kart
    $idler = @($kart | ForEach-Object { [string]$_.ID } | Where-Object { $_ } | Select-Object -Unique)
    $idList = if ($idler.Count) { $idler -join "," } else { "-1" }

    Yaz "== 2) Fis satirlari (tum turler) =="
    $kol = @(Sor $db "SELECT COLUMN_NAME AS c FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'FIS_DETAY'") | ForEach-Object { [string]$_.c }
    $mk = @("MIKTAR_FIS", "MIKTAR", "ADET") | Where-Object { $kol -contains $_ } | Select-Object -First 1
    Dok (@(Sor $db @"
SELECT TOP 60 f.ID AS FisId, f.FIS_TURU AS Tur, FT.AD AS TurAd, FT.GIRIS AS Giris, CONVERT(char(16), f.FIS_TARIHI, 120) AS Tarih,
       f.BELGENO AS Belge, C.KOD AS CariKod, C.AD AS Cari, d.STOK AS StokId, s.KOD AS StokKod, d.BARKOD AS Barkod, d.$mk AS Miktar
FROM dbo.FIS f JOIN dbo.FIS_DETAY d ON d.FIS = f.ID
LEFT JOIN dbo.FIS_TURU FT ON FT.ID = f.FIS_TURU
LEFT JOIN dbo.CARI C ON C.ID = f.CARI
LEFT JOIN dbo.STOK s ON s.ID = d.STOK
WHERE d.STOK IN ($idList) OR d.BARKOD = '$aranan'
ORDER BY f.FIS_TARIHI DESC
"@))

    Yaz "== 3) STOK sutunu olan diger dolu tablolarda bu kart(lar) =="
    if ($idler.Count) {
        $tablolar = @(Sor $db @"
SELECT c.TABLE_NAME AS t, c.COLUMN_NAME AS c
FROM INFORMATION_SCHEMA.COLUMNS c JOIN INFORMATION_SCHEMA.TABLES x ON x.TABLE_NAME = c.TABLE_NAME AND x.TABLE_TYPE = 'BASE TABLE'
WHERE c.COLUMN_NAME IN ('STOK', 'STOK_ID', 'FK_STOK') AND c.TABLE_NAME NOT IN ('FIS_DETAY', 'STOK_BARKOD_BIRIM')
"@)
        foreach ($t in $tablolar) {
            $n = @(Sor $db "SELECT COUNT(*) AS n FROM dbo.[$($t.t)] WHERE [$($t.c)] IN ($idList)")
            if ($n.Count -and [long]$n[0].n -gt 0) {
                Yaz "  $($t.t).$($t.c): $($n[0].n) satir"
                Dok (@(Sor $db "SELECT TOP 5 * FROM dbo.[$($t.t)] WHERE [$($t.c)] IN ($idList)"))
            }
        }
    }
}
Set-Content -Path $Cikti -Value $sb.ToString() -Encoding UTF8
Write-Host ""; Write-Host "Bitti: $Cikti  (Not Defteri'nde ac, Claude'a gonder)"
