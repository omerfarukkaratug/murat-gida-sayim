# =====================================================================
#  KRT Saha - KDV DURUM RAPORU (KDV acigi / fazlasi + stoktaki KDV)  —  SADECE OKUR, ERP'ye HICBIR SEY YAZMAZ
# =====================================================================
#  Baz alinan belgeler (istenen):
#   - ALIS FATURALARI (+ alistan iade faturalari): INDIRILECEK KDV
#   - SATIS FATURALARI (+ satistan iade faturalari): HESAPLANAN KDV
#   - PESIN SATIS CARISI (firma sabitlerindeki varsayilan cari) ve carisiz kasa / perakende belgeleri:
#     satis ve iadeleri (fatura olmasa da, irsaliye / perakende fis / POS dahil): HESAPLANAN KDV
#   Faturalanmis irsaliye satirlari ATLANIR (fatura zaten sayiliyor; cift sayim olmasin).
#   KDV tutari ERP'nin satira yazdigi TOPLAM_KDV, matrah TOPLAM_KDV_MATRAHI (iskontolar dusulmus).
#  Hesap: HESAPLANAN - INDIRILECEK > 0  -> o donem ODENECEK KDV (acik)
#                                    < 0  -> DEVREDEN KDV (fazla)
#  Ayrica: STOKTAKI KDV = bugunku arti stok x son alis fiyati x KDV orani (mallarin icinde odenmis, henuz satilmamis KDV).
#  NOT: Bu ERP hareketlerinden hesaplanan bir YONETIM raporudur; resmi beyanname degildir (giderler, demirbas,
#  hizmet faturalari, tevkifat, onceki donem devri muhasebede ayrica girer). Muhasebeyle karsilastirma icin kullanin.
#  Cikti: C:\Scripts\sayim-raporlari\kdv-*.csv  |  Calistirma: KDV-RAPORU.bat
# =====================================================================
$SqlServer    = "SERVER\ERP12"
$Database     = ""
$RaporKlasoru = "C:\Scripts\sayim-raporlari"
$Surum        = "2026-11-27a"

$Tr = [Globalization.CultureInfo]::GetCultureInfo("tr-TR")
function NormTr($s) { return ([string]$s).ToLower($Tr).Replace([string][char]0x131, "i").Replace([string][char]0x15F, "s").Replace([string][char]0x11F, "g").Replace([string][char]0xFC, "u").Replace([string][char]0xF6, "o").Replace([string][char]0xE7, "c") }
function Tl($x) { return ([double]$x).ToString("N2", $Tr) }
function Baslik($m) { Write-Host ""; Write-Host ("=" * 78) -ForegroundColor Cyan; Write-Host "  $m" -ForegroundColor Cyan; Write-Host ("=" * 78) -ForegroundColor Cyan }

try {
    Write-Host "KRT Saha - KDV durum raporu (surum $Surum) - SADECE OKUR" -ForegroundColor Green
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

    $varsBas = "01.01." + (Get-Date).Year
    $g1 = (Read-Host "  Baslangic tarihi [Enter = $varsBas]").Trim(); if (-not $g1) { $g1 = $varsBas }
    $g2 = (Read-Host "  Bitis tarihi (dahil) [Enter = bugun]").Trim(); if (-not $g2) { $g2 = (Get-Date).ToString("dd.MM.yyyy") }
    $B = [datetime]::ParseExact($g1, "dd.MM.yyyy", $Tr); $S = [datetime]::ParseExact($g2, "dd.MM.yyyy", $Tr).AddDays(1)
    $pesin = (Tablo "SELECT TOP 1 f.VARSAYILANCARI AS ID, ISNULL(c.AD, '') AS AD FROM dbo.FIRMASABITLERI f LEFT JOIN dbo.CARI c ON c.ID = f.VARSAYILANCARI" $null).Rows[0]
    $pesinId = if ($pesin.ID -is [DBNull]) { -1 } else { [long]$pesin.ID }
    Write-Host "  Veri tabani $Database | donem $g1 - $g2 | pesin satis carisi: $($pesin.AD) (ID $pesinId)"

    # Belge turu x ay x KDV orani x pesin mi: matrah / KDV
    Write-Host "  Belgeler okunuyor (birkac dakika surebilir)..."
    $sql = @"
SELECT CONVERT(char(7), f.FIS_TARIHI, 120) AS AY, f.FIS_TURU AS TUR_ID, ISNULL(FT.AD, '') AS TUR, ISNULL(FT.GIRIS, 0) AS GIRIS,
       CASE WHEN f.CARI = @p OR (f.CARI IS NULL AND f.FIS_TURU IN (11, 12, 35, 36)) THEN 1 ELSE 0 END AS PESIN,
       CAST(ISNULL(d.KDV_TOPTAN, 0) AS float) AS ORAN,
       SUM(CAST(ISNULL(d.TOPLAM_KDV_MATRAHI, 0) AS float)) AS MATRAH, SUM(CAST(ISNULL(d.TOPLAM_KDV, 0) AS float)) AS KDV,
       COUNT(DISTINCT f.ID) AS BELGE, COUNT(*) AS SATIR
FROM dbo.FIS f WITH (NOLOCK)
JOIN dbo.FIS_DETAY d WITH (NOLOCK) ON d.FIS = f.ID
JOIN dbo.FIS_TURU FT ON FT.ID = f.FIS_TURU
WHERE f.FIS_TARIHI >= @b AND f.FIS_TARIHI < @s AND ISNULL(d.FATRALANDIRILMIS_IRSALIYEMI, 0) = 0 AND f.FIS_TURU NOT IN (17, 18)
GROUP BY CONVERT(char(7), f.FIS_TARIHI, 120), f.FIS_TURU, FT.AD, FT.GIRIS,
         CASE WHEN f.CARI = @p OR (f.CARI IS NULL AND f.FIS_TURU IN (11, 12, 35, 36)) THEN 1 ELSE 0 END, CAST(ISNULL(d.KDV_TOPTAN, 0) AS float)
"@
    $ham = (Tablo $sql @{ "@b" = $B; "@s" = $S; "@p" = $pesinId }).Rows

    # Siniflandirma: ad + cari
    $satirlar = @()
    foreach ($h in $ham) {
        $ad = NormTr $h.TUR; $fatura = $ad -match 'fatura'; $iade = $ad -match 'iade'
        $alisMi = $ad -match 'alis'; $satisMi = ($ad -match 'satis') -or ([int]$h.TUR_ID -in 11, 12, 35, 36)
        # "Alistan iade" = bizden cikan iade (alis tarafini azaltir); "Satistan iade" = bize gelen iade (satis tarafini azaltir)
        $alistanIade = $ad -match 'alistan iade|alis iade'; $satistanIade = $ad -match 'satistan iade|satis iade'
        $kalem = ''; $isaret = 0
        if ($fatura -and $alisMi -and -not $iade) { $kalem = 'Alis faturasi'; $isaret = 1 }
        elseif ($fatura -and $alistanIade) { $kalem = 'Alistan iade faturasi'; $isaret = -1 }
        elseif ($fatura -and $satisMi -and -not $iade) { $kalem = 'Satis faturasi'; $isaret = 1 }
        elseif ($fatura -and $satistanIade) { $kalem = 'Satistan iade faturasi'; $isaret = -1 }
        elseif ([int]$h.PESIN -eq 1 -and $satistanIade) { $kalem = 'Pesin satis iadesi'; $isaret = -1 }
        elseif ([int]$h.PESIN -eq 1 -and $satisMi) { $kalem = 'Pesin satis'; $isaret = 1 }
        elseif ([int]$h.PESIN -eq 1 -and $iade -and [int]$h.GIRIS -eq 1) { $kalem = 'Pesin satis iadesi'; $isaret = -1 }
        $taraf = if ($kalem -like 'Alis*' -or $kalem -like 'Alistan*') { 'INDIRILECEK' } elseif ($kalem) { 'HESAPLANAN' } else { 'DAHIL DEGIL' }
        # Pesin carinin faturalari ikinci kez sayilmasin: fatura ise fatura kalemi zaten aldi
        $satirlar += [pscustomobject]@{ Ay = [string]$h.AY; BelgeTuru = [string]$h.TUR; TurId = [int]$h.TUR_ID; Pesin = $(if ([int]$h.PESIN -eq 1) { 'evet' } else { '' })
            KdvOrani = [double]$h.ORAN; Matrah = [Math]::Round([double]$h.MATRAH, 2); Kdv = [Math]::Round([double]$h.KDV, 2); Belge = [int]$h.BELGE; Satir = [int]$h.SATIR
            Kalem = $(if ($kalem) { $kalem } else { '-' }); Taraf = $taraf; Isaret = $isaret
            KdvEtki = [Math]::Round([double]$h.KDV * $isaret, 2); MatrahEtki = [Math]::Round([double]$h.MATRAH * $isaret, 2) }
    }
    function Top($l, $alan) { $s = 0.0; foreach ($x in @($l)) { $s += [double]$x.$alan }; return $s }
    $dahil = @($satirlar | Where-Object { $_.Isaret -ne 0 })

    # Ay ay
    $aylar = $dahil | Group-Object Ay | Sort-Object Name | ForEach-Object {
        $h = Top @($_.Group | Where-Object { $_.Taraf -eq 'HESAPLANAN' }) 'KdvEtki'; $i = Top @($_.Group | Where-Object { $_.Taraf -eq 'INDIRILECEK' }) 'KdvEtki'
        [pscustomobject]@{ Ay = $_.Name
            SatisFaturasiKdv = [Math]::Round((Top @($_.Group | Where-Object { $_.Kalem -like 'Satis faturasi' -or $_.Kalem -like 'Satistan iade faturasi' }) 'KdvEtki'), 2)
            PesinSatisKdv = [Math]::Round((Top @($_.Group | Where-Object { $_.Kalem -like 'Pesin*' }) 'KdvEtki'), 2)
            HesaplananKdv = [Math]::Round($h, 2); IndirilecekKdv = [Math]::Round($i, 2); Net = [Math]::Round($h - $i, 2)
            Durum = $(if ($h - $i -gt 0) { 'ODENECEK (acik)' } else { 'DEVREDEN (fazla)' })
            SatisMatrahi = [Math]::Round((Top @($_.Group | Where-Object { $_.Taraf -eq 'HESAPLANAN' }) 'MatrahEtki'), 2); AlisMatrahi = [Math]::Round((Top @($_.Group | Where-Object { $_.Taraf -eq 'INDIRILECEK' }) 'MatrahEtki'), 2) }
    }
    # Kumulatif (devir): her ay net eklenir; eksi = devreden
    $kum = 0.0; foreach ($a in $aylar) { $kum += $a.Net; Add-Member -InputObject $a -MemberType NoteProperty -Name Kumulatif -Value ([Math]::Round($kum, 2)) }

    # Oran bazinda (tum donem)
    $oranlar = $dahil | Group-Object KdvOrani | Sort-Object { [double]$_.Name } | ForEach-Object {
        $h = Top @($_.Group | Where-Object { $_.Taraf -eq 'HESAPLANAN' }) 'KdvEtki'; $i = Top @($_.Group | Where-Object { $_.Taraf -eq 'INDIRILECEK' }) 'KdvEtki'
        [pscustomobject]@{ KdvOrani = $_.Name; SatisMatrahi = [Math]::Round((Top @($_.Group | Where-Object { $_.Taraf -eq 'HESAPLANAN' }) 'MatrahEtki'), 2); HesaplananKdv = [Math]::Round($h, 2)
            AlisMatrahi = [Math]::Round((Top @($_.Group | Where-Object { $_.Taraf -eq 'INDIRILECEK' }) 'MatrahEtki'), 2); IndirilecekKdv = [Math]::Round($i, 2); Net = [Math]::Round($h - $i, 2) }
    }

    # Stoktaki KDV (bugun): arti stok x son alis x oran
    Write-Host "  Stoktaki KDV hesaplaniyor..."
    $stk = (Tablo @"
SELECT CAST(ISNULL(v.KDV_PAREKENDE, 0) AS float) AS ORAN, COUNT(*) AS URUN, SUM(x.M * ISNULL(s.SON_ALIS_FIYAT, 0)) AS DEGER
FROM (SELECT d.STOK, SUM(d.MIKTAR_GIRIS - d.MIKTAR_CIKIS) AS M FROM dbo.FIS_DETAY d WITH (NOLOCK) WHERE d.FATRALANDIRILMIS_IRSALIYEMI = 0 GROUP BY d.STOK HAVING SUM(d.MIKTAR_GIRIS - d.MIKTAR_CIKIS) > 0.0001) x
JOIN dbo.STOK s WITH (NOLOCK) ON s.ID = x.STOK LEFT JOIN dbo.STOK_VERGI v ON v.ID = s.STOK_VERGI
GROUP BY CAST(ISNULL(v.KDV_PAREKENDE, 0) AS float) ORDER BY 1
"@ $null).Rows
    $stokKdv = @(); foreach ($x in $stk) { $dg = [double]$(if ($x.DEGER -is [DBNull]) { 0 } else { $x.DEGER }); $stokKdv += [pscustomobject]@{ KdvOrani = [double]$x.ORAN; Urun = [int]$x.URUN; StokDegeri_KdvHaric = [Math]::Round($dg, 2); StoktakiKdv = [Math]::Round($dg * [double]$x.ORAN / 100, 2) } }

    if (-not (Test-Path $RaporKlasoru)) { New-Item -ItemType Directory -Path $RaporKlasoru | Out-Null }
    $z = (Get-Date).ToString("yyyyMMdd-HHmm"); $on = Join-Path $RaporKlasoru "kdv-$z"
    $aylar | Export-Csv "$on-aylar.csv" -NoTypeInformation -Encoding UTF8 -Delimiter ';'
    $oranlar | Export-Csv "$on-oranlar.csv" -NoTypeInformation -Encoding UTF8 -Delimiter ';'
    $stokKdv | Export-Csv "$on-stoktaki-kdv.csv" -NoTypeInformation -Encoding UTF8 -Delimiter ';'
    $satirlar | Sort-Object Ay, BelgeTuru | Export-Csv "$on-belge-turleri.csv" -NoTypeInformation -Encoding UTF8 -Delimiter ';'

    $H = Top @($dahil | Where-Object { $_.Taraf -eq 'HESAPLANAN' }) 'KdvEtki'; $I = Top @($dahil | Where-Object { $_.Taraf -eq 'INDIRILECEK' }) 'KdvEtki'
    Baslik "KDV DURUMU  $g1 - $g2"
    foreach ($k in @('Satis faturasi', 'Satistan iade faturasi', 'Pesin satis', 'Pesin satis iadesi', 'Alis faturasi', 'Alistan iade faturasi')) {
        $g = @($dahil | Where-Object { $_.Kalem -eq $k }); Write-Host ("  {0,-26} matrah {1,18}   KDV {2,16}" -f $k, (Tl (Top $g 'MatrahEtki')), (Tl (Top $g 'KdvEtki')))
    }
    Write-Host ""
    Write-Host ("  HESAPLANAN KDV (satis)     {0,18}" -f (Tl $H))
    Write-Host ("  INDIRILECEK KDV (alis)     {0,18}" -f (Tl $I))
    $net = $H - $I
    Write-Host ("  NET                        {0,18}  -> {1}" -f (Tl $net), $(if ($net -gt 0) { 'ODENECEK KDV (acik)' } else { 'DEVREDEN KDV (fazla)' })) -ForegroundColor $(if ($net -gt 0) { 'Yellow' } else { 'Green' })
    Write-Host ("  STOKTAKI KDV (bugun)       {0,18}  (arti stok x son alis x KDV orani)" -f (Tl (Top $stokKdv 'StoktakiKdv')))
    Baslik "Ay ay"
    foreach ($a in $aylar) { Write-Host ("  {0}  hesaplanan {1,15}  indirilecek {2,15}  net {3,15}  kumulatif {4,15}" -f $a.Ay, (Tl $a.HesaplananKdv), (Tl $a.IndirilecekKdv), (Tl $a.Net), (Tl $a.Kumulatif)) }
    $disari = @($satirlar | Where-Object { $_.Isaret -eq 0 -and [Math]::Abs($_.Kdv) -gt 0.01 } | Group-Object BelgeTuru | ForEach-Object { [pscustomobject]@{ Tur = $_.Name; Kdv = (Top $_.Group 'Kdv') } } | Sort-Object { [Math]::Abs($_.Kdv) } -Descending)
    if ($disari.Count) {
        Baslik "HESABA KATILMAYAN (KDV'li) belge turleri - kontrol edin"
        $disari | Select-Object -First 15 | ForEach-Object { Write-Host ("  {0,-45} KDV {1,16}" -f $_.Tur, (Tl $_.Kdv)) }
        Write-Host "  (Bunlar alis/satis faturasi ya da pesin cari satisi degil: irsaliye, depo, fire vb. Yanlis disarida kalan varsa bana yazin.)" -ForegroundColor DarkGray
    }
    Baslik "Dosyalar - bana gonderin"
    Get-ChildItem "$on-*.csv" | ForEach-Object { Write-Host "  $($_.FullName)" -ForegroundColor Green }
} catch {
    Write-Host "HATA: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""; Read-Host "Kapatmak icin Enter"
