# =====================================================================
#  Murat Gida - ERP12 KESIF: bir urunun kasa promosyonu neden afise gelmiyor?
#  ERP12'ye HICBIR SEY YAZMAZ, sadece okur. Internete hicbir sey gondermez.
#  Sonuc: C:\Scripts\kesif-promo.txt  (bu dosyayi Claude'a gonder)
#  Icinde: adinda aranan soz gecen urunler ve bu urunlere (kendisine, grubuna,
#  markasina) bagli POS_PROMASYON satirlari, bir de aktif promosyonlarin turlere gore sayisi.
# =====================================================================
$SqlServer = "SERVER\ERP12"
$Cikti     = "C:\Scripts\kesif-promo.txt"
$Aranan    = "BEYPAZAR"          # urun adinda aranacak soz (buyuk harf, Turkce karaktersiz)
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
Yaz "KESIF-PROMO $(Get-Date -Format 'yyyy-MM-dd HH:mm')  veri tabani: $db  aranan: $Aranan"

$urunSorgu = @"
SELECT DISTINCT bb.STOK AS StokId, s.STOK_GRUP AS Grup, s.STOK_MARKA AS Marka
FROM dbo.STOK_BARKOD_BIRIM bb
LEFT JOIN dbo.STOK_BARKOD_W w ON w.ID = bb.BARKOD
LEFT JOIN dbo.STOK s ON s.ID = bb.STOK
WHERE UPPER(w.AD) LIKE '%$Aranan%'
"@

Yaz ""; Yaz "== 1) POS_PROMASYON sutunlari =="
Yaz ("  " + ((@(Sor $db "SELECT COLUMN_NAME AS c FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'POS_PROMASYON' ORDER BY ORDINAL_POSITION") | ForEach-Object { [string]$_.c }) -join ", "))

Yaz ""; Yaz "== 2) Adinda '$Aranan' gecen urunler (barkod, carpan, fiyat, grup, marka) =="
Dok (@(Sor $db @"
SELECT TOP 80 bb.STOK AS StokId, s.KOD AS StokKodu, w.AD AS Ad, bb.BARKOD AS Barkod, bb.CARPAN AS Carpan, f.FIYAT AS Fiyat, s.STOK_GRUP AS Grup, s.STOK_MARKA AS Marka
FROM dbo.STOK_BARKOD_BIRIM bb
LEFT JOIN dbo.STOK_BARKOD_W w ON w.ID = bb.BARKOD
LEFT JOIN dbo.STOK_BARKOD_FIYAT_VARSAYILAN f ON f.STOK_STOK_BIRIM = bb.STOK_STOK_BIRIM
LEFT JOIN dbo.STOK s ON s.ID = bb.STOK
WHERE UPPER(w.AD) LIKE '%$Aranan%'
ORDER BY w.AD, bb.CARPAN
"@))

Yaz ""; Yaz "== 3) Bu urunlere bagli POS_PROMASYON satirlari (urun / grup / marka; aktif olsun olmasin) =="
Dok (@(Sor $db @"
;WITH u AS ($urunSorgu)
SELECT p.*
FROM dbo.POS_PROMASYON p
WHERE p.FK_H_STOK IN (SELECT StokId FROM u) OR p.FK_P_STOK IN (SELECT StokId FROM u)
   OR p.H_GRUP IN (SELECT Grup FROM u WHERE Grup IS NOT NULL) OR p.P_GRUP IN (SELECT Grup FROM u WHERE Grup IS NOT NULL)
   OR p.H_MARKA IN (SELECT Marka FROM u WHERE Marka IS NOT NULL) OR p.P_MARKA IN (SELECT Marka FROM u WHERE Marka IS NOT NULL)
ORDER BY p.BITIS_TARIHI DESC
"@))

Yaz ""; Yaz "== 4) Aktif ve tarihi gecerli promosyonlar, ture gore sayi =="
Dok (@(Sor $db @"
SELECT INDIRIMMI, CASE WHEN ADET = P_ADET THEN 'ADET=P_ADET' ELSE 'ADET<>P_ADET' END AS AdetDurumu,
       CASE WHEN FIYAT > 0 AND FIYAT < 100 THEN 'FIYAT 0-100' WHEN FIYAT >= 100 THEN 'FIYAT>=100' ELSE 'FIYAT<=0' END AS FiyatDurumu,
       CASE WHEN ISNULL(FK_P_STOK, 0) = ISNULL(FK_H_STOK, 0) AND ISNULL(P_GRUP, 0) = ISNULL(H_GRUP, 0) AND ISNULL(P_MARKA, 0) = ISNULL(H_MARKA, 0) THEN 'hedef=tetik' ELSE 'hedef<>tetik' END AS Hedef,
       COUNT(*) AS Adet
FROM dbo.POS_PROMASYON
WHERE AKTIF = 1 AND BASLANGIC_TARIHI <= GETDATE() AND BITIS_TARIHI >= GETDATE()
GROUP BY INDIRIMMI, CASE WHEN ADET = P_ADET THEN 'ADET=P_ADET' ELSE 'ADET<>P_ADET' END,
       CASE WHEN FIYAT > 0 AND FIYAT < 100 THEN 'FIYAT 0-100' WHEN FIYAT >= 100 THEN 'FIYAT>=100' ELSE 'FIYAT<=0' END,
       CASE WHEN ISNULL(FK_P_STOK, 0) = ISNULL(FK_H_STOK, 0) AND ISNULL(P_GRUP, 0) = ISNULL(H_GRUP, 0) AND ISNULL(P_MARKA, 0) = ISNULL(H_MARKA, 0) THEN 'hedef=tetik' ELSE 'hedef<>tetik' END
ORDER BY Adet DESC
"@))

[System.IO.File]::WriteAllText($Cikti, $sb.ToString(), [System.Text.Encoding]::UTF8)
Write-Host ""; Write-Host "Bitti. Sonuc Not Defteri'nde aciliyor: hepsini sec (Ctrl+A), kopyala (Ctrl+C), Claude'a yapistir."
try { Start-Process notepad.exe -ArgumentList $Cikti } catch {}
Read-Host "Kapatmak icin Enter"
