# =====================================================================
#  MK Saha - ERP12 KESIF KASA 3: "Deftere gonderildi ama kasa yine okumuyor"
#  Kasada OKUNAN, ERP'de elle acilmis son kart ile OKUNMAYAN MKS kartini KISA ve yan yana gosterir:
#   1) kart / birim / barkod / fiyat satirlarinda FARKLI olan alanlar
#   2) her ikisinin degisiklik defteri (SEQUNCES_DEGISIKLIK) satirlari - tum alanlar
#   3) SEQUNCES satirlari
#   4) kasanin okudugu barkod gorunumu (STOK_BARKOD_BIRIM) ve fiyat satirlari
#  ERP12'ye HICBIR SEY YAZMAZ, sadece okur. Sonuc ekranda ve C:\Scripts\kesif-kasa3.txt
# =====================================================================
$SqlServer = "SERVER\ERP12"
$Cikti     = "C:\Scripts\kesif-kasa3.txt"
Import-Module SqlServer -ErrorAction SilentlyContinue
$sb = New-Object System.Text.StringBuilder
function Yaz($m) { [void]$sb.AppendLine([string]$m); Write-Host $m }
function Kaydet { try { [System.IO.File]::WriteAllText($Cikti, $sb.ToString(), [System.Text.Encoding]::UTF8) } catch {} }
function Sor($db, $q, $sn = 120) { try { return @(Invoke-Sqlcmd -ServerInstance $SqlServer -Database $db -Query $q -QueryTimeout $sn -MaxCharLength 20000 -ErrorAction Stop) } catch { Yaz "  HATA: $($_.Exception.Message)"; return @() } }
function Deger($v) { if ($v -is [DBNull]) { return "NULL" } elseif ($v -is [byte[]]) { return "0x" + (($v | ForEach-Object { $_.ToString("X2") }) -join "") } elseif ($v -is [datetime]) { return $v.ToString("yyyy-MM-dd HH:mm:ss") } else { return [string]$v } }
function Dok($satirlar, $on) { foreach ($r in $satirlar) { $p = @(); foreach ($c in $r.Table.Columns) { $p += "$($c.ColumnName)=$(Deger $r[$c.ColumnName])" }; Yaz ("  $on" + ($p -join " | ")) } }
function Tirnak($s) { return "'" + ([string]$s).Replace("'", "''") + "'" }

$dbler = @(Sor "master" "SELECT name FROM sys.databases WHERE name LIKE 'ERP12[0-9][0-9][0-9][0-9]' AND state = 0 ORDER BY name DESC")
$db = $null
foreach ($d in $dbler) { $n = @(Sor ([string]$d.name) "SELECT COUNT(*) AS n FROM dbo.FIS WITH (NOLOCK) WHERE FIS_TARIHI >= DATEADD(day, -7, GETDATE())"); if ($n.Count -and [int]$n[0].n -gt 0) { $db = [string]$d.name; break } }
if (-not $db) { $db = [string]$dbler[0].name }
Yaz "KESIF-KASA3 $(Get-Date -Format 'yyyy-MM-dd HH:mm')  veri tabani: $db"
$kotuBarkod = (Read-Host "Kasada OKUNMAYAN MKS urununun barkodu").Trim()
$iyiBarkod = (Read-Host "Kasada OKUNAN, ERP'de YAKIN ZAMANDA ELLE acilmis bir urunun barkodu (bos: otomatik)").Trim()

function KartBarkodla($b) { $r = @(Sor $db "SELECT TOP 1 STOK FROM dbo.STOK_BARKOD_BIRIM WITH (NOLOCK) WHERE BARKOD = $(Tirnak $b)"); if ($r.Count) { return [long]$r[0].STOK } else { return $null } }
$kotu = if ($kotuBarkod) { KartBarkodla $kotuBarkod } else { $null }
if (-not $kotu) { Yaz "MKS barkodu ERP'de bulunamadi."; Kaydet; Read-Host "Kapatmak icin Enter"; exit 1 }
$iyi = if ($iyiBarkod) { KartBarkodla $iyiBarkod } else { $null }
if (-not $iyi) {
    # Defterde ISLEM=1 STOK satiri olan, MKS olmayan, en son acilmis ve kasada satilmis kart
    $r = @(Sor $db "SELECT TOP 1 s.ID FROM dbo.STOK s WITH (NOLOCK) WHERE s.KOD NOT LIKE 'MKS-%' AND EXISTS (SELECT 1 FROM dbo.SEQUNCES_DEGISIKLIK g WITH (NOLOCK) WHERE g.SEQUNCES = s.ID AND g.ISLEM = 1) AND EXISTS (SELECT 1 FROM dbo.FIS_DETAY d WITH (NOLOCK) JOIN dbo.FIS f WITH (NOLOCK) ON f.ID = d.FIS WHERE d.STOK = s.ID AND f.YAZAR_KASA_NO > 0 AND f.FIS_TARIHI >= DATEADD(day, -30, GETDATE())) ORDER BY s.ID DESC" 300)
    if ($r.Count) { $iyi = [long]$r[0].ID }
}
if (-not $iyi) { Yaz "Karsilastirilacak okunan kart bulunamadi - okunan bir urunun barkodunu yazarak tekrar deneyin."; Kaydet; Read-Host "Kapatmak icin Enter"; exit 1 }
Dok (Sor $db "SELECT ID, KOD, LEFT(AD, 40) AS AD FROM dbo.STOK WITH (NOLOCK) WHERE ID IN ($iyi, $kotu)") ""

function Kimlik($sid) {
    $k = @{ STOK = @($sid) }
    $k.BIRIM = @(Sor $db "SELECT ID FROM dbo.STOK_STOK_BIRIM WITH (NOLOCK) WHERE STOK = $sid ORDER BY ID" | ForEach-Object { [long]$_.ID })
    $in = if ($k.BIRIM.Count) { $k.BIRIM -join "," } else { "-1" }
    $k.FIYAT = @(Sor $db "SELECT ID FROM dbo.STOK_STOK_BIRIM_FIYAT WITH (NOLOCK) WHERE STOK_STOK_BIRIM IN ($in) ORDER BY ID" | ForEach-Object { [long]$_.ID })
    $k.BARKOD = @(Sor $db "SELECT ID FROM dbo.STOK_BARKOD WITH (NOLOCK) WHERE STOK_STOK_BIRIM IN ($in) ORDER BY ID" | ForEach-Object { [long]$_.ID })
    $k.TUM = @($k.STOK + $k.BIRIM + $k.FIYAT + $k.BARKOD)
    return $k
}
$I = Kimlik $iyi; $K = Kimlik $kotu
function Fark($tablo, $a, $b) {
    if (-not $a -or -not $b) { Yaz "  ${tablo}: satir yok (okunan $a, MKS $b)"; return }
    $x = @(Sor $db "SELECT * FROM dbo.[$tablo] WITH (NOLOCK) WHERE ID = $a"); $y = @(Sor $db "SELECT * FROM dbo.[$tablo] WITH (NOLOCK) WHERE ID = $b")
    if (-not $x.Count -or -not $y.Count) { return }
    foreach ($c in $x[0].Table.Columns) { $n = $c.ColumnName; if ($n -eq "ID") { continue }; $va = Deger $x[0][$n]; $vb = Deger $y[0][$n]; if ($va -ne $vb) { Yaz ("  {0}.{1}: okunan=[{2}]  MKS=[{3}]" -f $tablo, $n, $va, $vb) } }
}
Yaz ""; Yaz "== 1) FARKLI ALANLAR =="
Yaz ("  satir sayisi: okunan birim {0} fiyat {1} barkod {2} | MKS birim {3} fiyat {4} barkod {5}" -f $I.BIRIM.Count, $I.FIYAT.Count, $I.BARKOD.Count, $K.BIRIM.Count, $K.FIYAT.Count, $K.BARKOD.Count)
Fark "STOK" $iyi $kotu
Fark "STOK_STOK_BIRIM" $I.BIRIM[0] $K.BIRIM[0]
Fark "STOK_BARKOD" $I.BARKOD[0] $K.BARKOD[0]
for ($i = 0; $i -lt [Math]::Max($I.FIYAT.Count, $K.FIYAT.Count); $i++) { Fark "STOK_STOK_BIRIM_FIYAT" $I.FIYAT[$i] $K.FIYAT[$i] }
Kaydet
Yaz ""; Yaz "== 2) DEGISIKLIK DEFTERI (SEQUNCES_DEGISIKLIK) =="
Yaz "  -- okunan kart"; Dok (Sor $db "SELECT * FROM dbo.SEQUNCES_DEGISIKLIK WITH (NOLOCK) WHERE SEQUNCES IN ($($I.TUM -join ',')) ORDER BY ID") "I "
Yaz "  -- MKS kart"; Dok (Sor $db "SELECT * FROM dbo.SEQUNCES_DEGISIKLIK WITH (NOLOCK) WHERE SEQUNCES IN ($($K.TUM -join ',')) ORDER BY ID") "M "
Yaz ""; Yaz "== 3) SEQUNCES =="
Dok (Sor $db "SELECT * FROM dbo.SEQUNCES WITH (NOLOCK) WHERE ID IN ($(@($I.TUM + $K.TUM) -join ',')) ORDER BY ID") ""
Yaz ""; Yaz "== 4) STOK_BARKOD_BIRIM ve fiyat satirlari =="
Dok (Sor $db "SELECT * FROM dbo.STOK_BARKOD_BIRIM WITH (NOLOCK) WHERE STOK IN ($iyi, $kotu)") ""
Dok (Sor $db "SELECT f.* FROM dbo.STOK_STOK_BIRIM_FIYAT f WITH (NOLOCK) WHERE f.ID IN ($(@($I.FIYAT + $K.FIYAT + @(-1)) -join ','))") ""
Yaz ""; Yaz "== 5) Defterin son 5 satiri (kasalar en son neyi aldi) =="
Dok (Sor $db "SELECT TOP 5 * FROM dbo.SEQUNCES_DEGISIKLIK WITH (NOLOCK) ORDER BY ID DESC") ""
Kaydet
Write-Host ""; Write-Host "Bitti. Ekranin fotografini ya da $Cikti dosyasini gonderin."
Read-Host "Kapatmak icin Enter"
