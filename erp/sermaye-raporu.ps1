# =====================================================================
#  KRT Saha - SAYIM SERMAYE (STOK DEGERI) RAPORU  —  SADECE OKUR, ERP'ye HICBIR SEY YAZMAZ
# =====================================================================
#  Sayim kesinlestirmelerinden (FIS_TURU 17) ONCE ve SONRA stok degerini karsilastirir:
#   - Toplam stok degeri (son alis fiyatiyla, KDV haric), arti / eksi stok ayri
#   - Stok grubu (ust grup) bazinda once / sonra / fark
#   - Her sayim kesinlestirme fisinin etkisi (fazla / eksik / net TL)
#   - En buyuk fark yaratan urunler
#  Cikti: C:\Scripts\sayim-raporlari\sermaye-*.csv (Excel'de acilir) + ekranda ozet.
#  Calistirma: SERMAYE-RAPORU.bat
# =====================================================================
$SqlServer    = "SERVER\ERP12"
$Database     = ""
$RaporKlasoru = "C:\Scripts\sayim-raporlari"
$Surum        = "2026-11-27a"

$Tr = [Globalization.CultureInfo]::GetCultureInfo("tr-TR")
function Tl($x) { return ([double]$x).ToString("N2", $Tr) + " TL" }
function Baslik($m) { Write-Host ""; Write-Host ("=" * 70) -ForegroundColor Cyan; Write-Host "  $m" -ForegroundColor Cyan; Write-Host ("=" * 70) -ForegroundColor Cyan }

try {
    Write-Host "KRT Saha - Sayim sermaye raporu (surum $Surum) - SADECE OKUR" -ForegroundColor Green
    if (-not $Database) {
        $m = New-Object System.Data.SqlClient.SqlConnection("Server=$SqlServer;Database=master;Integrated Security=True"); $m.Open()
        $c = $m.CreateCommand(); $c.CommandText = "SELECT name FROM sys.databases WHERE name LIKE 'ERP12[0-9][0-9][0-9][0-9]' AND state = 0 ORDER BY name DESC"
        $r = $c.ExecuteReader(); $adlar = @(); while ($r.Read()) { $adlar += [string]$r[0] }; $r.Close(); $m.Close()
        foreach ($a in $adlar) {
            $t = New-Object System.Data.SqlClient.SqlConnection("Server=$SqlServer;Database=$a;Integrated Security=True"); $t.Open()
            $k = $t.CreateCommand(); $k.CommandText = "SELECT COUNT(*) FROM dbo.FIS WITH (NOLOCK) WHERE FIS_TARIHI >= DATEADD(day, -7, GETDATE())"
            $n = [int]$k.ExecuteScalar(); $t.Close(); if ($n -gt 0) { $Database = $a; break }
        }
        if (-not $Database) { $Database = $adlar[0] }
    }
    $bag = New-Object System.Data.SqlClient.SqlConnection("Server=$SqlServer;Database=$Database;Integrated Security=True;Connect Timeout=30"); $bag.Open()
    function Tablo($sql, $p) {
        $cmd = $bag.CreateCommand(); $cmd.CommandText = $sql; $cmd.CommandTimeout = 900
        if ($p) { foreach ($k in $p.Keys) { [void]$cmd.Parameters.AddWithValue($k, $p[$k]) } }
        $da = New-Object System.Data.SqlClient.SqlDataAdapter($cmd); $dt = New-Object System.Data.DataTable; [void]$da.Fill($dt); return ,$dt
    }
    $lok = Tablo "SELECT TOP 1 LOKASYON FROM dbo.FIS WITH (NOLOCK) WHERE FIS_TURU = 17 ORDER BY ID DESC" $null
    $L = [long]$lok.Rows[0].LOKASYON

    # Sayim kesinlestirme fisleri (varsayilan: 20.11.2026'dan beri)
    $bas = Read-Host "  Hangi tarihten sonraki sayim kesinlestirmeleri? [Enter = 20.11.2026]"
    if (-not $bas.Trim()) { $bas = "20.11.2026" }
    $B = [datetime]::ParseExact($bas.Trim(), "dd.MM.yyyy", $Tr)
    $fisler = Tablo "SELECT f.ID, f.BELGENO, f.FIS_TARIHI, ISNULL(f.ACIKLAMA, '') AS ACIKLAMA FROM dbo.FIS f WITH (NOLOCK) WHERE f.FIS_TURU = 17 AND f.LOKASYON = @l AND f.FIS_TARIHI >= @b ORDER BY f.FIS_TARIHI, f.ID" @{ "@l" = $L; "@b" = $B }
    if (-not $fisler.Rows.Count) { throw "Bu tarihten sonra sayim kesinlestirme fisi yok." }
    $idler = (@($fisler.Rows | ForEach-Object { [long]$_.ID }) -join ",")
    Write-Host "  Sayim kesinlestirme fisi: $($fisler.Rows.Count)  (veri tabani $Database, lokasyon $L)"

    # Urun bazinda: SONRA = bugunku stok (tum hareketler), ONCE = sayim fisleri haric; fiyat = son alis (KDV haric)
    $sql = @"
SELECT s.ID, s.KOD, ISNULL(s.AD, s.KOD) AS AD, ISNULL(ug.AD, ISNULL(g.AD, '(grupsuz)')) AS UST_GRUP, ISNULL(g.AD, '(grupsuz)') AS GRUP,
       ISNULL(s.SON_ALIS_FIYAT, 0) AS ALIS, x.SONRA, x.SAYIM, x.SONRA - x.SAYIM AS ONCE
FROM (SELECT d.STOK, SUM(d.MIKTAR_GIRIS - d.MIKTAR_CIKIS) AS SONRA,
             SUM(CASE WHEN d.FIS IN ($idler) THEN d.MIKTAR_GIRIS - d.MIKTAR_CIKIS ELSE 0 END) AS SAYIM
      FROM dbo.FIS_DETAY d WITH (NOLOCK)
      WHERE d.FATRALANDIRILMIS_IRSALIYEMI = 0 AND d.LOKASYON = @l
      GROUP BY d.STOK) x
JOIN dbo.STOK s WITH (NOLOCK) ON s.ID = x.STOK
LEFT JOIN dbo.STOK_GRUP g ON g.ID = s.STOK_GRUP
LEFT JOIN dbo.STOK_GRUP ug ON ug.ID = g.USTID
WHERE ABS(x.SONRA) > 0.0001 OR ABS(x.SAYIM) > 0.0001
"@
    Write-Host "  Stoklar hesaplaniyor (birkac dakika surebilir)..."
    $u = (Tablo $sql @{ "@l" = $L }).Rows
    $R = @()
    foreach ($r in $u) {
        $a = [double]$r.ALIS; $once = [double]$r.ONCE; $sonra = [double]$r.SONRA
        $R += [pscustomobject]@{ Kod = [string]$r.KOD; Urun = [string]$r.AD; UstGrup = [string]$r.UST_GRUP; Grup = [string]$r.GRUP; Alis = $a
            Once = $once; Sonra = $sonra; SayimFark = [double]$r.SAYIM; OnceTL = $once * $a; SonraTL = $sonra * $a; FarkTL = [double]$r.SAYIM * $a }
    }
    function Top($l, $alan) { $s = 0.0; foreach ($x in $l) { $s += [double]$x.$alan }; return $s }
    $artOnce = Top @($R | Where-Object { $_.OnceTL -gt 0 }) 'OnceTL'; $eksOnce = Top @($R | Where-Object { $_.OnceTL -lt 0 }) 'OnceTL'
    $artSon = Top @($R | Where-Object { $_.SonraTL -gt 0 }) 'SonraTL'; $eksSon = Top @($R | Where-Object { $_.SonraTL -lt 0 }) 'SonraTL'
    $fz = Top @($R | Where-Object { $_.FarkTL -gt 0 }) 'FarkTL'; $ek = Top @($R | Where-Object { $_.FarkTL -lt 0 }) 'FarkTL'
    $stokluOnce = @($R | Where-Object { [Math]::Abs($_.Once) -gt 0.0001 }).Count; $stokluSon = @($R | Where-Object { [Math]::Abs($_.Sonra) -gt 0.0001 }).Count
    $eksiOnceN = @($R | Where-Object { $_.Once -lt -0.0001 }).Count; $eksiSonN = @($R | Where-Object { $_.Sonra -lt -0.0001 }).Count

    if (-not (Test-Path $RaporKlasoru)) { New-Item -ItemType Directory -Path $RaporKlasoru | Out-Null }
    $z = (Get-Date).ToString("yyyyMMdd-HHmm"); $on = Join-Path $RaporKlasoru "sermaye-$z"

    # 1) Ozet
    $ozet = @(
        [pscustomobject]@{ Kalem = 'Stok degeri (net)';             Sayimdan_once = $artOnce + $eksOnce; Sayimdan_sonra = $artSon + $eksSon; Fark = ($artSon + $eksSon) - ($artOnce + $eksOnce) }
        [pscustomobject]@{ Kalem = 'Arti stoklu urunlerin degeri';  Sayimdan_once = $artOnce; Sayimdan_sonra = $artSon; Fark = $artSon - $artOnce }
        [pscustomobject]@{ Kalem = 'Eksi stoklu urunlerin degeri';  Sayimdan_once = $eksOnce; Sayimdan_sonra = $eksSon; Fark = $eksSon - $eksOnce }
        [pscustomobject]@{ Kalem = 'Stoklu urun sayisi';            Sayimdan_once = $stokluOnce; Sayimdan_sonra = $stokluSon; Fark = $stokluSon - $stokluOnce }
        [pscustomobject]@{ Kalem = 'Eksi stoklu urun sayisi';       Sayimdan_once = $eksiOnceN; Sayimdan_sonra = $eksiSonN; Fark = $eksiSonN - $eksiOnceN }
        [pscustomobject]@{ Kalem = 'Sayimda fazla cikan (TL)';      Sayimdan_once = ''; Sayimdan_sonra = ''; Fark = $fz }
        [pscustomobject]@{ Kalem = 'Sayimda eksik cikan (TL)';      Sayimdan_once = ''; Sayimdan_sonra = ''; Fark = $ek }
    )
    $ozet | Export-Csv "$on-ozet.csv" -NoTypeInformation -Encoding UTF8 -Delimiter ';'

    # 2) Grup bazinda
    $grp = $R | Group-Object UstGrup | ForEach-Object {
        [pscustomobject]@{ UstGrup = $_.Name; Urun = $_.Count; OnceTL = (Top $_.Group 'OnceTL'); SonraTL = (Top $_.Group 'SonraTL'); FarkTL = (Top $_.Group 'FarkTL')
            Fazla = (Top @($_.Group | Where-Object { $_.FarkTL -gt 0 }) 'FarkTL'); Eksik = (Top @($_.Group | Where-Object { $_.FarkTL -lt 0 }) 'FarkTL') }
    } | Sort-Object SonraTL -Descending
    $grp | Export-Csv "$on-gruplar.csv" -NoTypeInformation -Encoding UTF8 -Delimiter ';'

    # 3) Fis bazinda
    $fisOz = @(); foreach ($f in $fisler.Rows) {
        $d = (Tablo "SELECT SUM((d.MIKTAR_GIRIS - d.MIKTAR_CIKIS) * ISNULL(s.SON_ALIS_FIYAT, 0)) AS NET, SUM(CASE WHEN d.MIKTAR_GIRIS > d.MIKTAR_CIKIS THEN (d.MIKTAR_GIRIS - d.MIKTAR_CIKIS) * ISNULL(s.SON_ALIS_FIYAT, 0) ELSE 0 END) AS FAZLA, COUNT(DISTINCT d.STOK) AS N FROM dbo.FIS_DETAY d WITH (NOLOCK) JOIN dbo.STOK s WITH (NOLOCK) ON s.ID = d.STOK WHERE d.FIS = @f" @{ "@f" = [long]$f.ID }).Rows[0]
        $net = if ($d.NET -is [DBNull]) { 0.0 } else { [double]$d.NET }; $fa = if ($d.FAZLA -is [DBNull]) { 0.0 } else { [double]$d.FAZLA }
        $fisOz += [pscustomobject]@{ Fis = [string]$f.BELGENO; Tarih = ([datetime]$f.FIS_TARIHI).ToString('dd.MM.yyyy HH:mm'); Aciklama = [string]$f.ACIKLAMA; Urun = [int]$d.N; FazlaTL = $fa; EksikTL = $net - $fa; NetTL = $net }
    }
    $fisOz | Export-Csv "$on-belgeler.csv" -NoTypeInformation -Encoding UTF8 -Delimiter ';'

    # 4) Urun listesi (tamami) ve en buyuk farklar
    $R | Sort-Object { [Math]::Abs($_.FarkTL) } -Descending | Export-Csv "$on-urunler.csv" -NoTypeInformation -Encoding UTF8 -Delimiter ';'

    Baslik "SAYIM SERMAYE OZETI (son alis fiyatiyla, KDV haric)"
    Write-Host ("  {0,-32} {1,20} {2,20} {3,20}" -f "", "Sayimdan once", "Sayimdan sonra", "Fark")
    foreach ($o in $ozet) {
        $f = { param($v) if ($v -is [string]) { $v } elseif ($o.Kalem -like '*sayisi*') { ([double]$v).ToString('N0', $Tr) } else { ([double]$v).ToString('N2', $Tr) } }
        Write-Host ("  {0,-32} {1,20} {2,20} {3,20}" -f $o.Kalem, (& $f $o.Sayimdan_once), (& $f $o.Sayimdan_sonra), (& $f $o.Fark))
    }
    Baslik "Belgeler"
    foreach ($f in $fisOz) { Write-Host ("  {0}  {1,-45} {2,5} urun  net {3}" -f $f.Tarih, $f.Aciklama.Substring(0, [Math]::Min(45, $f.Aciklama.Length)), $f.Urun, (Tl $f.NetTL)) }
    Baslik "Dosyalar (Excel'de acilir) - bana gonderin, yonetim kurulu raporunu hazirlayayim"
    Get-ChildItem "$on-*.csv" | ForEach-Object { Write-Host "  $($_.FullName)" -ForegroundColor Green }
} catch {
    Write-Host "HATA: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""; Read-Host "Kapatmak icin Enter"
