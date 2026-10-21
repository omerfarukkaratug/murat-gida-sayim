# =====================================================================
#  MK Saha - ERP12 KESIF: irsaliye + fatura ayni mal iki kez mi sayiliyor?
#  ERP12'ye HICBIR SEY YAZMAZ, sadece okur. Internete hicbir sey gondermez.
#  Sonuc: C:\Scripts\kesif-cift.txt  (bu dosyayi Claude'a gonder)
#  Ornek urun: NESQUIK MISIR GEVREGI 1 KG (8690632048680), belge NSP2026000011040
#  Icinde: o belgelerin FIS ve FIS_DETAY satirlarinin TUM dolu alanlari,
#  irsaliye-fatura baglantisi olabilecek sutunlar ve ERP'nin stok hareket tablolari.
# =====================================================================
$SqlServer = "SERVER\ERP12"
$Barkod    = "8690632048680"
$BelgeNo   = "NSP2026000011040"
$Cikti     = "C:\Scripts\kesif-cift.txt"
Import-Module SqlServer -ErrorAction SilentlyContinue
$sb = New-Object System.Text.StringBuilder
function Yaz($m) { [void]$sb.AppendLine([string]$m); Write-Host $m }
function Sor($db, $q) { try { return @(Invoke-Sqlcmd -ServerInstance $SqlServer -Database $db -Query $q -QueryTimeout 120 -ErrorAction Stop) } catch { Yaz "  HATA: $($_.Exception.Message)"; return @() } }
function Dok($satirlar) {
    foreach ($r in $satirlar) {
        $p = @(); foreach ($c in $r.Table.Columns) { $v = $r[$c.ColumnName]; if ($v -isnot [DBNull] -and [string]$v -ne '') { $p += "$($c.ColumnName)=$v" } }
        Yaz ("  " + ($p -join " | ")); Yaz ""
    }
}
$dbler = @(Sor "master" "SELECT name FROM sys.databases WHERE name LIKE 'ERP12[0-9][0-9][0-9][0-9]' AND state = 0 ORDER BY name DESC")
if ($dbler.Count -eq 0) { Write-Host "ERP12 veri tabani bulunamadi."; Read-Host "Enter"; exit 1 }
$db = $null
foreach ($d in $dbler) { $n = @(Sor ([string]$d.name) "SELECT COUNT(*) AS n FROM dbo.FIS WHERE FIS_TARIHI >= DATEADD(day, -7, GETDATE())"); if ($n.Count -and [int]$n[0].n -gt 0) { $db = [string]$d.name; break } }
if (-not $db) { $db = [string]$dbler[0].name }
Yaz "KESIF-CIFT $(Get-Date -Format 'yyyy-MM-dd HH:mm')  veri tabani: $db  barkod: $Barkod  belge: $BelgeNo"

Yaz ""; Yaz "== 1) Bu barkodun son 60 gundeki alis satirlari (FIS + FIS_TURU + FIS_DETAY ozet) =="
Dok (Sor $db @"
SELECT TOP 20 f.ID AS FIS_ID, f.FIS_TURU, FT.AD AS TUR_AD, FT.GIRIS AS TUR_GIRIS, f.BELGENO, f.FIS_TARIHI, f.AKTIF,
       d.ID AS DETAY_ID, d.MIKTAR_FIS, d.MIKTAR_GIRIS, d.MIKTAR_CIKIS, d.FATRALANDIRILMIS_IRSALIYEMI, d.BAGLI_SATIR, d.FIS_DETAY_SATIR_TURU
FROM dbo.FIS_DETAY d JOIN dbo.FIS f ON f.ID = d.FIS LEFT JOIN dbo.FIS_TURU FT ON FT.ID = f.FIS_TURU
JOIN dbo.STOK_BARKOD_BIRIM bb ON bb.STOK = d.STOK
WHERE bb.BARKOD = '$Barkod' AND f.FIS_TARIHI >= DATEADD(day, -60, GETDATE()) AND f.FIS_TURU IN (1, 5)
ORDER BY f.FIS_TARIHI DESC
"@)

Yaz ""; Yaz "== 2) Bu belge numarali FIS kayitlarinin TUM dolu alanlari =="
Dok (Sor $db "SELECT * FROM dbo.FIS WHERE BELGENO = '$BelgeNo'")

Yaz ""; Yaz "== 3) O belgelerde bu urunun FIS_DETAY satirlarinin TUM dolu alanlari =="
Dok (Sor $db "SELECT d.* FROM dbo.FIS_DETAY d JOIN dbo.FIS f ON f.ID = d.FIS JOIN dbo.STOK_BARKOD_BIRIM bb ON bb.STOK = d.STOK WHERE f.BELGENO = '$BelgeNo' AND bb.BARKOD = '$Barkod'")

Yaz ""; Yaz "== 4) FIS / FIS_DETAY'da baglanti olabilecek sutunlar =="
Dok (Sor $db "SELECT t.name AS TABLO, c.name AS SUTUN FROM sys.columns c JOIN sys.tables t ON t.object_id = c.object_id WHERE t.name IN ('FIS','FIS_DETAY') AND (c.name LIKE '%IRSALIYE%' OR c.name LIKE '%FATURA%' OR c.name LIKE '%FATRA%' OR c.name LIKE '%BAGLI%' OR c.name LIKE '%KAYNAK%' OR c.name LIKE '%GIRIS%' OR c.name LIKE '%CIKIS%' OR c.name LIKE '%STOK_ETKI%') ORDER BY t.name, c.name")

Yaz ""; Yaz "== 5) Adinda STOK ve HAREKET gecen tablolar (satir sayisi) =="
Dok (Sor $db "SELECT t.name AS TABLO, SUM(p.rows) AS SATIR FROM sys.tables t JOIN sys.partitions p ON p.object_id = t.object_id AND p.index_id IN (0,1) WHERE t.name LIKE '%HAREKET%' OR t.name LIKE '%STOK[_]MIKTAR%' OR t.name LIKE '%BAKIYE%' GROUP BY t.name ORDER BY t.name")

Yaz ""; Yaz "== 6) FIS_TURU listesi =="
Dok (Sor $db "SELECT ID, AD, GIRIS FROM dbo.FIS_TURU ORDER BY ID")

[System.IO.File]::WriteAllText($Cikti, $sb.ToString(), [System.Text.Encoding]::UTF8)
Write-Host ""; Write-Host "Bitti. Sonuc: $Cikti  -> bu dosyayi gonder."
Read-Host "Kapatmak icin Enter"
