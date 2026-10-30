# =====================================================================
#  MK Saha - ERP12 KESIF + ON RAPOR: kasa iptalleri, indirimler, yetkili islemleri
#  Kasiyer / kasa / saat bazinda son 30 gun ozeti ve 12 aylik egilim.
#  ERP12'ye HICBIR SEY YAZMAZ, sadece okur. Sonuc: C:\Scripts\kesif-iptal.txt
# =====================================================================
$SqlServer = "SERVER\ERP12"
$Cikti     = "C:\Scripts\kesif-iptal.txt"
Import-Module SqlServer -ErrorAction SilentlyContinue
$sb = New-Object System.Text.StringBuilder
function Yaz($m) { [void]$sb.AppendLine([string]$m); Write-Host $m }
function Kaydet { try { [System.IO.File]::WriteAllText($Cikti, $sb.ToString(), [System.Text.Encoding]::UTF8) } catch {} }
function Sor($db, $q, $sn = 300) { try { return @(Invoke-Sqlcmd -ServerInstance $SqlServer -Database $db -Query $q -QueryTimeout $sn -MaxCharLength 20000 -ErrorAction Stop) } catch { Yaz "  HATA: $($_.Exception.Message)"; return @() } }
function Dok($satirlar) { foreach ($r in $satirlar) { $p = @(); foreach ($c in $r.Table.Columns) { $v = $r[$c.ColumnName]; if ($v -isnot [DBNull] -and [string]$v -ne '') { $p += "$($c.ColumnName)=$v" } }; Yaz ("  " + ($p -join " | ")) } }
function Sutunlar($db, $t) { return @(Sor $db "SELECT c.name FROM sys.columns c WHERE c.object_id = OBJECT_ID('dbo.$t') ORDER BY c.column_id" | ForEach-Object { [string]$_.name }) }

$dbler = @(Sor "master" "SELECT name FROM sys.databases WHERE name LIKE 'ERP12[0-9][0-9][0-9][0-9]' AND state = 0 ORDER BY name DESC")
$db = $null
foreach ($d in $dbler) { $n = @(Sor ([string]$d.name) "SELECT COUNT(*) AS n FROM dbo.FIS WITH (NOLOCK) WHERE FIS_TARIHI >= DATEADD(day, -7, GETDATE())"); if ($n.Count -and [int]$n[0].n -gt 0) { $db = [string]$d.name; break } }
if (-not $db) { $db = [string]$dbler[0].name }
Yaz "KESIF-IPTAL $(Get-Date -Format 'yyyy-MM-dd HH:mm')  veri tabani: $db"

Yaz ""; Yaz "== 1) Sutunlar =="
foreach ($t in @("FIS_POS", "FIS_POS_IPTAL", "FIS_POS_IPTAL_DETAY", "FIS_POS_YETKILI_ISLEMLERI", "FIS", "IPTAL_SEBEBI", "POS_IPTAL_SEBEBI")) {
    $c = Sutunlar $db $t; if ($c.Count) { Yaz "-- $t : $($c -join ', ')" }
}
$fisKol = Sutunlar $db "FIS"
Yaz "-- FIS icinde personel / kullanici olabilecek sutunlar: $(($fisKol | Where-Object { $_ -match 'PERSONEL|KULLANICI|KASIYER|SATICI|GARSON|PC' }) -join ', ')"
Kaydet

Yaz ""; Yaz "== 2) Kisi kimlikleri hangi tabloda (SEQUNCES) ve adlari =="
$kisiler = @(Sor $db "SELECT DISTINCT TOP 40 K FROM (SELECT PERSONEL AS K FROM dbo.FIS_POS_IPTAL WITH (NOLOCK) WHERE TARIH >= DATEADD(day, -60, GETDATE()) UNION SELECT KULLANICI FROM dbo.FIS_POS_YETKILI_ISLEMLERI WITH (NOLOCK) WHERE TARIH >= DATEADD(day, -60, GETDATE()) UNION SELECT YETKILI_KULLANICI FROM dbo.FIS_POS_YETKILI_ISLEMLERI WITH (NOLOCK) WHERE TARIH >= DATEADD(day, -60, GETDATE())) x WHERE K IS NOT NULL AND K > 0")
foreach ($k in $kisiler) {
    $id = [long]$k.K
    $t = @(Sor $db "SELECT TABLO FROM dbo.SEQUNCES WITH (NOLOCK) WHERE ID = $id")
    $tablo = if ($t.Count) { [string]$t[0].TABLO } else { "" }
    $ad = ""
    if ($tablo) {
        $tk = Sutunlar $db $tablo
        $adk = @($tk | Where-Object { $_ -in @("AD", "ADI", "AD_SOYAD", "UNVAN", "KULLANICI_ADI", "ISIM", "KOD") })
        if ($adk.Count) { $r = @(Sor $db ("SELECT " + (($adk | ForEach-Object { "CAST([$_] AS nvarchar(200)) AS [$_]" }) -join ", ") + " FROM dbo.[$tablo] WITH (NOLOCK) WHERE ID = $id")); if ($r.Count) { $ad = (($adk | ForEach-Object { [string]$r[0][$_] }) | Where-Object { $_ }) -join " / " } }
    }
    Yaz "  $id -> tablo $tablo : $ad"
}
Kaydet

Yaz ""; Yaz "== 3) Ornek satirlar (son 5) =="
Yaz "-- FIS_POS_IPTAL"; Dok (Sor $db "SELECT TOP 5 * FROM dbo.FIS_POS_IPTAL WITH (NOLOCK) ORDER BY ID DESC")
Yaz "-- FIS_POS_YETKILI_ISLEMLERI"; Dok (Sor $db "SELECT TOP 5 * FROM dbo.FIS_POS_YETKILI_ISLEMLERI WITH (NOLOCK) ORDER BY ID DESC")
Yaz "-- FIS_POS"; Dok (Sor $db "SELECT TOP 3 * FROM dbo.FIS_POS WITH (NOLOCK) ORDER BY ID DESC")
$sonFis = @(Sor $db "SELECT TOP 1 FIS FROM dbo.FIS_POS WITH (NOLOCK) ORDER BY ID DESC")
if ($sonFis.Count) { Yaz "-- O kasa fisinin FIS satiri"; Dok (Sor $db "SELECT TOP 1 * FROM dbo.FIS WITH (NOLOCK) WHERE ID = $($sonFis[0].FIS)") }
Kaydet

Yaz ""; Yaz "== 4) SON 30 GUN: iptaller kisi + kasa bazinda (SATIR_MI=1 satir iptali, 0 fis iptali) =="
Dok (Sor $db "SELECT PERSONEL, PC_ID, SATIR_MI, COUNT(*) AS ADET, CAST(SUM(TUTAR) AS decimal(18,2)) AS TUTAR, CAST(SUM(ODENEN_TUTAR) AS decimal(18,2)) AS ODENEN FROM dbo.FIS_POS_IPTAL WITH (NOLOCK) WHERE TARIH >= DATEADD(day, -30, GETDATE()) GROUP BY PERSONEL, PC_ID, SATIR_MI ORDER BY PERSONEL, PC_ID, SATIR_MI")
Yaz ""; Yaz "-- Iptal sebepleri (son 30 gun)"
Dok (Sor $db "SELECT IPTAL_SEBEBI, SATIR_MI, COUNT(*) AS ADET FROM dbo.FIS_POS_IPTAL WITH (NOLOCK) WHERE TARIH >= DATEADD(day, -30, GETDATE()) GROUP BY IPTAL_SEBEBI, SATIR_MI ORDER BY ADET DESC")
Yaz ""; Yaz "== 5) SON 30 GUN: yetkili islemleri (indirim, satir iptal, fiyat degistirme...) kisi bazinda =="
Dok (Sor $db "SELECT LEFT(POS_YETKI_SORUSU, 60) AS ISLEM, KULLANICI, YETKILI_KULLANICI, COUNT(*) AS ADET FROM dbo.FIS_POS_YETKILI_ISLEMLERI WITH (NOLOCK) WHERE TARIH >= DATEADD(day, -30, GETDATE()) GROUP BY LEFT(POS_YETKI_SORUSU, 60), KULLANICI, YETKILI_KULLANICI ORDER BY ADET DESC")
Yaz ""; Yaz "== 6) SON 30 GUN: kasa fisi sayisi ve ciro (kasa bazinda) =="
Dok (Sor $db "SELECT p.PC_ID, COUNT(*) AS FIS_ADET, CAST(SUM(f.GENELTOPLAM) AS decimal(18,2)) AS CIRO FROM dbo.FIS_POS p WITH (NOLOCK) JOIN dbo.FIS f WITH (NOLOCK) ON f.ID = p.FIS WHERE p.KAPANIS_TARIHI >= DATEADD(day, -30, GETDATE()) GROUP BY p.PC_ID")
Kaydet

Yaz ""; Yaz "== 7) SON 30 GUN: iptallerin saate gore dagilimi =="
Dok (Sor $db "SELECT DATEPART(hour, TARIH) AS SAAT, SUM(CASE WHEN SATIR_MI = 1 THEN 1 ELSE 0 END) AS SATIR_IPTAL, SUM(CASE WHEN SATIR_MI = 0 THEN 1 ELSE 0 END) AS FIS_IPTAL, CAST(SUM(TUTAR) AS decimal(18,2)) AS TUTAR FROM dbo.FIS_POS_IPTAL WITH (NOLOCK) WHERE TARIH >= DATEADD(day, -30, GETDATE()) GROUP BY DATEPART(hour, TARIH) ORDER BY SAAT")
Yaz ""; Yaz "== 8) SON 30 GUN: en cok iptal edilen urunler =="
Dok (Sor $db "SELECT TOP 20 d.BARKOD, d.STOK, COUNT(*) AS ADET, CAST(SUM(d.MIKTAR) AS decimal(18,3)) AS MIKTAR, CAST(SUM(d.MIKTAR * d.FIYAT) AS decimal(18,2)) AS TUTAR FROM dbo.FIS_POS_IPTAL_DETAY d WITH (NOLOCK) JOIN dbo.FIS_POS_IPTAL i WITH (NOLOCK) ON i.ID = d.FIS_POS_IPTAL WHERE i.TARIH >= DATEADD(day, -30, GETDATE()) GROUP BY d.BARKOD, d.STOK ORDER BY TUTAR DESC")
Yaz ""; Yaz "== 9) 12 AYLIK EGILIM: ay bazinda kasa fisi ve iptal sayisi =="
Dok (Sor $db "SELECT CONVERT(char(7), TARIH, 120) AS AY, SUM(CASE WHEN SATIR_MI = 1 THEN 1 ELSE 0 END) AS SATIR_IPTAL, SUM(CASE WHEN SATIR_MI = 0 THEN 1 ELSE 0 END) AS FIS_IPTAL, CAST(SUM(TUTAR) AS decimal(18,2)) AS TUTAR FROM dbo.FIS_POS_IPTAL WITH (NOLOCK) WHERE TARIH >= DATEADD(month, -12, GETDATE()) GROUP BY CONVERT(char(7), TARIH, 120) ORDER BY AY")
Dok (Sor $db "SELECT CONVERT(char(7), KAPANIS_TARIHI, 120) AS AY, COUNT(*) AS KASA_FISI FROM dbo.FIS_POS WITH (NOLOCK) WHERE KAPANIS_TARIHI >= DATEADD(month, -12, GETDATE()) GROUP BY CONVERT(char(7), KAPANIS_TARIHI, 120) ORDER BY AY")
Yaz ""; Yaz "== 10) Ayni fiste cok satir iptali (son 30 gun, en cok 15) =="
Dok (Sor $db "SELECT TOP 15 i.POS_GECICI, MIN(i.TARIH) AS ILK, i.PERSONEL, i.PC_ID, COUNT(*) AS SATIR_IPTAL, CAST(SUM(i.TUTAR) AS decimal(18,2)) AS TUTAR FROM dbo.FIS_POS_IPTAL i WITH (NOLOCK) WHERE i.TARIH >= DATEADD(day, -30, GETDATE()) AND i.SATIR_MI = 1 GROUP BY i.POS_GECICI, i.PERSONEL, i.PC_ID ORDER BY SATIR_IPTAL DESC")

Kaydet
Write-Host ""; Write-Host "Bitti. Sonuc: $Cikti  -> bu dosyayi gonder."
Read-Host "Kapatmak icin Enter"
