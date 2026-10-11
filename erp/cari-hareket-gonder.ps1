# =====================================================================
#  Murat Gida - ERP12 -> Veri tabani: CARI HAREKETLERI (cari hesap ekstresi)
# =====================================================================
#  Ne yapar: ERP12'den okuyup bulut veri tabanina yazar; uygulamadaki "Cari
#  Hareketleri" ekrani buradan beslenir:
#   1) FINANS_DETAY: carilerin (CARI_TUR = 1) borc / alacak hareketleri. ERP12'deki
#      cari bakiyesi (CARI_BAKIYELER) de ayni satirlardan hesaplanir.
#   2) Perakende (Pesin Satis = varsayilan cari): her fis tek tek DEGIL, gun ve
#      hareket turu basina TOPLAM olarak (cari kodu "__PERAKENDE__").
#   3) FIS_DETAY: stoga etki eden tum belgelerin (fatura, irsaliye, fis, iade, depo,
#      sarf, fire, sayim) urun satirlari -> "fatura detayi", "carinin stok hareketleri"
#      ve "Stok Hareketleri" ekrani.
#   4) Perakende (kasa) satislari: urun + gun basina TOPLAM -> "Stok Hareketleri".
#
#  - ERP12'ye HICBIR SEY YAZMAZ, sadece okur (SELECT).
#  - Gunde bir kez TUM hareketleri bastan gonderir (ERP'de silinen/duzeltilen
#    kayitlar da duzelsin), diger calismalarda sadece son 7 gun.
#  - Sadece EN YENI ERP12 yil veri tabanini gonderir (devir kayitlari onda).
#
#  Kurulum: C:\Scripts\db-anahtar.txt (hareket-gonder.ps1 ile ayni) olmali.
#  Gorev Zamanlayici: saatte bir
#    powershell.exe -ExecutionPolicy Bypass -File "C:\Scripts\cari-hareket-gonder.ps1"
# =====================================================================

# ---------------------- AYARLAR ----------------------
$SqlServer        = "SERVER\ERP12"
# Bos: en yeni ERP12 yil veri tabani otomatik bulunur. Elle: "ERP122025"
$Database         = ""
$DbUrl            = "https://wjyqempcmyrmruhdpcwk.supabase.co"
$DbAnahtarDosyasi = "C:\Scripts\db-anahtar.txt"
$LogFile          = "C:\Scripts\cari-hareket-log.txt"
$TamGonderimKlasor = "C:\Scripts"
$KisaGun          = 7
$Parca            = 3000
# -----------------------------------------------------

try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}

function Yaz-Log($mesaj) {
    $satir = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $mesaj"
    Write-Host $satir
    try { Add-Content -Path $LogFile -Value $satir -ErrorAction SilentlyContinue } catch {}
}

function Sql-Tablo($baglanti, $sql) {
    $cmd = $baglanti.CreateCommand(); $cmd.CommandText = $sql; $cmd.CommandTimeout = 900
    $da = New-Object System.Data.SqlClient.SqlDataAdapter($cmd)
    $dt = New-Object System.Data.DataTable
    [void]$da.Fill($dt)
    return ,$dt
}

# Turkiye saati (+03:00) ile ISO metin.
function Iso($t) { return ([datetime]$t).ToString("yyyy-MM-ddTHH:mm:ss", [Globalization.CultureInfo]::InvariantCulture) + "+03:00" }
function Sayi($v) {
    if ($v -eq $null -or $v -is [DBNull]) { return 0 }
    return [double]$v
}
function Metin($v) { if ($v -eq $null -or $v -is [DBNull]) { return "" }; return ([string]$v).Trim() }

function Rpc($fonksiyon, $govdeJson) {
    $baytlar = [System.Text.Encoding]::UTF8.GetBytes($govdeJson)
    $sonuc = Invoke-RestMethod -Uri "$DbUrl/rest/v1/rpc/$fonksiyon" -Method Post -Body $baytlar `
        -ContentType "application/json; charset=utf-8" -Headers @{ apikey = $script:Anahtar } -TimeoutSec 300 -UserAgent "MK-Sayim/1.0"
    if (-not $sonuc -or [string]$sonuc.status -ne "ok") { throw "$fonksiyon reddetti: $($sonuc | ConvertTo-Json -Compress)" }
    return $sonuc
}

# Satirlari parca parca gonderir; ILK parca o araliktaki eski kayitlari siler.
function Parcali-Gonder($fonksiyon, $kaynak, $satirlar, $basJson, $bitJson) {
    $toplam = 0
    $i = 0
    do {
        $son = [Math]::Min($i + $Parca, $satirlar.Count)
        $dilim = @()
        if ($satirlar.Count -gt 0) { $dilim = @($satirlar[$i..($son - 1)]) }
        $json = if ($dilim.Count -gt 0) { ConvertTo-Json -InputObject $dilim -Depth 3 -Compress } else { "[]" }
        $temizle = if ($i -eq 0) { "true" } else { "false" }
        $govde = '{"p_kaynak":"' + $kaynak + '","p_satirlar":' + $json + ',"p_bas":' + $basJson + ',"p_bit":' + $bitJson + ',"p_temizle":' + $temizle + '}'
        $r = Rpc $fonksiyon $govde
        $toplam += [int]$r.eklenen
        $i = $son
    } while ($i -lt $satirlar.Count)
    return $toplam
}

function Veritabani-Gonder($Db, $baglanti) {
    $TamGonderimDosya = Join-Path $TamGonderimKlasor "cari-hareket-son-tam-$Db.txt"
    $tam = $true
    if (Test-Path $TamGonderimDosya) {
        $sonTam = [datetime]::MinValue
        if ([datetime]::TryParse((Get-Content $TamGonderimDosya -TotalCount 1), [ref]$sonTam)) {
            $tam = ((Get-Date) - $sonTam).TotalHours -ge 20
        }
    }
    $bas = if ($tam) { [datetime]"2000-01-01" } else { (Get-Date).Date.AddDays(-$KisaGun) }
    $bit = (Get-Date).Date.AddDays(1)
    Yaz-Log "[$Db] Basliyor: $(if ($tam) { 'TAM gonderim (tum hareketler)' } else { "son $KisaGun gun" })"
    $baglanti.ChangeDatabase($Db)
    $basSql = $bas.ToString("yyyy-MM-dd"); $bitSql = $bit.ToString("yyyy-MM-dd")

    # Cari borclu ise BORC, alacakli ise ALACAK (ERP12 AS_CARI_HESAP_EKSTRESI ile ayni mantik).
    # Varsayilan cari (Pesin Satis / kasa) ve personel carileri (CARI_TUR = 2) alinmaz.
    $ortak = @"
FROM dbo.FINANS_DETAY FD
JOIN dbo.FINANS F ON F.ID = FD.FINANS
JOIN dbo.CARI C ON C.ID = {KART}
LEFT JOIN dbo.FINANS_ISLEM_TURU T ON T.ID = FD.FINANS_ISLEM_TURU
LEFT JOIN dbo.DOVIZ_AD DV ON DV.ID = FD.DOVIZ_AD
LEFT JOIN dbo.FIS ON FIS.ID = FD.FIS
WHERE C.CARI_TUR = 1 AND C.ID <> COALESCE((SELECT TOP 1 VARSAYILANCARI FROM dbo.FIRMASABITLERI), -1)
  AND F.TARIH >= '$basSql' AND F.TARIH < '$bitSql'
"@
    $alanlar = "FD.ID AS detay_id, C.KOD AS cari_kod, C.AD AS cari_ad, F.TARIH AS tarih, FD.VADE_TARIHI AS vade, T.AD AS tur, " +
               "COALESCE(NULLIF(F.BELGENO, ''), FIS.BELGENO, '') AS belge_no, FD.ACIKLAMA AS aciklama, FD.TUTAR AS tutar, DV.AD AS doviz, FD.FIS AS fis_id"
    $sql = "SELECT 'B' AS taraf, $alanlar " + $ortak.Replace("{KART}", "FD.KART_BORCLU") +
           " UNION ALL SELECT 'A' AS taraf, $alanlar " + $ortak.Replace("{KART}", "FD.KART_ALACAKLI")
    $dt = Sql-Tablo $baglanti $sql

    $satirlar = New-Object System.Collections.ArrayList
    foreach ($r in $dt.Rows) {
        $taraf = [string]$r.taraf
        $tutar = Sayi $r.tutar
        $vade = $null
        if ($r.vade -isnot [DBNull] -and $r.vade -ne $null) { $vade = ([datetime]$r.vade).ToString("yyyy-MM-dd", [Globalization.CultureInfo]::InvariantCulture) }
        $fis = $null
        if ($r.fis_id -isnot [DBNull] -and $r.fis_id -ne $null -and [long]$r.fis_id -gt 0) { $fis = [long]$r.fis_id }
        [void]$satirlar.Add([PSCustomObject]@{
            detay_id = [long]$r.detay_id; taraf = $taraf
            cari_kod = Metin $r.cari_kod; cari_ad = Metin $r.cari_ad
            tarih = Iso $r.tarih; vade = $vade; tur = Metin $r.tur; belge_no = Metin $r.belge_no
            aciklama = (Metin $r.aciklama); doviz = Metin $r.doviz; fis_id = $fis
            borc = $(if ($taraf -eq "B") { $tutar } else { 0 }); alacak = $(if ($taraf -eq "A") { $tutar } else { 0 })
        })
    }
    # --- 2) Perakende: varsayilan cari (Pesin Satis), gun + hareket turu + taraf basina toplam ---
    # Sentetik satir no (eksi): -((yyyymmdd * 1000 + tur) * 10 + doviz) -> her gun/tur icin sabit, gonderimler arasi ayni kalir.
    $sqlP = @"
WITH VC AS (SELECT TOP 1 VARSAYILANCARI AS ID FROM dbo.FIRMASABITLERI)
SELECT 'B' AS taraf, CONVERT(char(10), F.TARIH, 23) AS gun, FD.FINANS_ISLEM_TURU AS tur_id, FD.DOVIZ_AD AS dv_id, MAX(T.AD) AS tur, MAX(DV.AD) AS doviz, SUM(FD.TUTAR) AS tutar, COUNT(*) AS adet
FROM dbo.FINANS_DETAY FD JOIN dbo.FINANS F ON F.ID = FD.FINANS JOIN VC ON VC.ID = FD.KART_BORCLU
LEFT JOIN dbo.FINANS_ISLEM_TURU T ON T.ID = FD.FINANS_ISLEM_TURU LEFT JOIN dbo.DOVIZ_AD DV ON DV.ID = FD.DOVIZ_AD
WHERE F.TARIH >= '$basSql' AND F.TARIH < '$bitSql'
GROUP BY CONVERT(char(10), F.TARIH, 23), FD.FINANS_ISLEM_TURU, FD.DOVIZ_AD
UNION ALL
SELECT 'A' AS taraf, CONVERT(char(10), F.TARIH, 23) AS gun, FD.FINANS_ISLEM_TURU AS tur_id, FD.DOVIZ_AD AS dv_id, MAX(T.AD) AS tur, MAX(DV.AD) AS doviz, SUM(FD.TUTAR) AS tutar, COUNT(*) AS adet
FROM dbo.FINANS_DETAY FD JOIN dbo.FINANS F ON F.ID = FD.FINANS JOIN VC ON VC.ID = FD.KART_ALACAKLI
LEFT JOIN dbo.FINANS_ISLEM_TURU T ON T.ID = FD.FINANS_ISLEM_TURU LEFT JOIN dbo.DOVIZ_AD DV ON DV.ID = FD.DOVIZ_AD
WHERE F.TARIH >= '$basSql' AND F.TARIH < '$bitSql'
GROUP BY CONVERT(char(10), F.TARIH, 23), FD.FINANS_ISLEM_TURU, FD.DOVIZ_AD
"@
    $nP = 0
    try {
        $dtP = Sql-Tablo $baglanti $sqlP
        foreach ($r in $dtP.Rows) {
            $taraf = [string]$r.taraf; $tutar = Sayi $r.tutar; $gun = [string]$r.gun
            $turId = 0; if ($r.tur_id -isnot [DBNull] -and $r.tur_id -ne $null) { $turId = [long]$r.tur_id }
            $dvId = 0; if ($r.dv_id -isnot [DBNull] -and $r.dv_id -ne $null) { $dvId = [long]$r.dv_id % 10 }
            [void]$satirlar.Add([PSCustomObject]@{
                detay_id = -((([long]($gun.Replace("-", ""))) * 1000 + $turId) * 10 + $dvId); taraf = $taraf
                cari_kod = "__PERAKENDE__"; cari_ad = "PERAKENDE (Pesin Satis)"
                tarih = $gun + "T23:59:00+03:00"; vade = $null; tur = Metin $r.tur; belge_no = ""
                aciklama = "Gunluk toplam (" + [string]$r.adet + " kayit)"; doviz = Metin $r.doviz; fis_id = $null
                borc = $(if ($taraf -eq "B") { $tutar } else { 0 }); alacak = $(if ($taraf -eq "A") { $tutar } else { 0 })
            })
            $nP++
        }
    } catch { Yaz-Log "[$Db] UYARI: perakende toplamlari alinamadi: $($_.Exception.Message) (cari hareketleri etkilenmedi)" }

    $n = Parcali-Gonder "cari_hareket_yukle" $Db $satirlar ('"' + (Iso $bas) + '"') ('"' + (Iso $bit) + '"')
    Yaz-Log "[$Db] Cari hareketleri: $n satir gonderildi ($nP perakende gun/tur toplami dahil)"

    # --- 3) Belge satirlari (fatura/irsaliye/fis detayi, carinin ve urunun stok hareketleri) ---
    # Stoga etki eden TUM belgeler (FIS_TURU.GIRIS = +1 / -1; Finans 18 haric): alis, satis, iade, depo, sarf, fire, sayim...
    # Perakende (kasa fisleri 11/12, perakende fatura/irsaliye 35/36, Pesin Satis carisinin belgeleri) burada DEGIL,
    # 4. adimda urun + gun toplami olarak gider.
    $kolD = @((Sql-Tablo $baglanti "SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'FIS_DETAY'") | ForEach-Object { [string]$_.COLUMN_NAME })
    $kolS = @((Sql-Tablo $baglanti "SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'STOK'") | ForEach-Object { [string]$_.COLUMN_NAME })
    $miktar = @("MIKTAR_FIS", "MIKTAR", "MIKTAR1", "ADET") | Where-Object { $kolD -contains $_ } | Select-Object -First 1
    $fiyat = @("DAHIL_FIYAT", "KDV_DAHIL_FIYAT", "FIYAT_KDV_DAHIL", "KDVLI_FIYAT") | Where-Object { $kolD -contains $_ } | Select-Object -First 1
    $tutarK = @("DAHIL_TUTAR", "KDV_DAHIL_TUTAR", "TUTAR_KDV_DAHIL", "KDVLI_TUTAR") | Where-Object { $kolD -contains $_ } | Select-Object -First 1
    $urunAd = @("AD", "STOK_ADI", "ADI") | Where-Object { $kolS -contains $_ } | Select-Object -First 1
    if (-not $miktar) { Yaz-Log "[$Db] UYARI: FIS_DETAY miktar sutunu bulunamadi; belge satirlari gonderilmedi. Sutunlar: $($kolD -join ', ')" }
    else {
        $fiyatIf = if ($fiyat) { "d.$fiyat" } else { "CAST(NULL AS decimal(18,4))" }
        $tutarIf = if ($tutarK) { "d.$tutarK" } else { "CAST(NULL AS decimal(18,4))" }
        $adIf = if ($urunAd) { "ISNULL(s.$urunAd, '')" } else { "''" }
        $sqlF = @"
SELECT d.ID AS detay_id, f.ID AS fis_id, f.FIS_TURU AS fis_turu, ISNULL(FT.AD, '') AS tur_ad, FT.GIRIS AS giris, f.FIS_TARIHI AS tarih,
       ISNULL(f.BELGENO, '') AS belge_no, ISNULL(C.KOD, '') AS cari_kod, ISNULL(C.AD, '') AS cari_ad, ISNULL(s.KOD, '') AS stok_kodu, ISNULL(d.BARKOD, '') AS barkod,
       $adIf AS urun_adi, d.$miktar AS miktar, $fiyatIf AS birim_fiyat, $tutarIf AS tutar
FROM dbo.FIS f
JOIN dbo.FIS_DETAY d ON d.FIS = f.ID
LEFT JOIN dbo.CARI C ON C.ID = f.CARI
JOIN dbo.FIS_TURU FT ON FT.ID = f.FIS_TURU
LEFT JOIN dbo.STOK s ON s.ID = d.STOK
WHERE f.FIS_TARIHI >= '$basSql' AND f.FIS_TARIHI < '$bitSql'
  AND FT.GIRIS IN (1, -1) AND f.FIS_TURU NOT IN (18, 11, 12, 35, 36)
  AND ISNULL(f.CARI, 0) <> COALESCE((SELECT TOP 1 VARSAYILANCARI FROM dbo.FIRMASABITLERI), -1)
"@
        $dtF = Sql-Tablo $baglanti $sqlF
        $fs = New-Object System.Collections.ArrayList
        foreach ($r in $dtF.Rows) {
            $m = Sayi $r.miktar; $bf = $null; $tt = $null
            if ($r.birim_fiyat -isnot [DBNull] -and $r.birim_fiyat -ne $null) { $bf = [double]$r.birim_fiyat }
            if ($r.tutar -isnot [DBNull] -and $r.tutar -ne $null) { $tt = [double]$r.tutar } elseif ($bf -ne $null) { $tt = [Math]::Round($m * $bf, 2) }
            [void]$fs.Add([PSCustomObject]@{
                detay_id = [long]$r.detay_id; fis_id = [long]$r.fis_id; fis_turu = [int]$r.fis_turu; tur_ad = Metin $r.tur_ad
                giris = [int]$r.giris; tarih = Iso $r.tarih; belge_no = Metin $r.belge_no; cari_kod = Metin $r.cari_kod; cari_ad = Metin $r.cari_ad
                stok_kodu = Metin $r.stok_kodu; barkod = Metin $r.barkod; urun_adi = Metin $r.urun_adi
                miktar = $m; birim_fiyat = $bf; tutar = $tt
            })
        }
        $nF = Parcali-Gonder "fis_satir_yukle" $Db $fs ('"' + (Iso $bas) + '"') ('"' + (Iso $bit) + '"')
        Yaz-Log "[$Db] Belge satirlari: $nF satir gonderildi (miktar: $miktar, fiyat: $fiyat, tutar: $tutarK, urun adi: $urunAd)"

        # --- 4) Perakende: urun + gun toplami (satis -, iade +). Ilk calismada tum gecmis, gunluk tam
        #        gonderimde son 60 gun, diger saatlerde son 7 gun (kasa fisleri sonradan pek degismez).
        $PerIlkDosya = Join-Path $TamGonderimKlasor "stok-perakende-ilk-$Db.txt"
        $pBas = if (-not (Test-Path $PerIlkDosya)) { [datetime]"2000-01-01" } elseif ($tam) { (Get-Date).Date.AddDays(-60) } else { $bas }
        $pBasSql = $pBas.ToString("yyyy-MM-dd")
        $tutarP = if ($tutarK) { "d.$tutarK" } elseif ($fiyat) { "d.$miktar * d.$fiyat" } else { "0" }
        $sqlP2 = @"
SELECT ISNULL(s.KOD, '') AS stok_kodu, CONVERT(char(10), f.FIS_TARIHI, 23) AS gun,
       SUM(d.$miktar * FT.GIRIS) AS miktar, SUM($tutarP * FT.GIRIS) AS tutar, COUNT(*) AS adet
FROM dbo.FIS f
JOIN dbo.FIS_DETAY d ON d.FIS = f.ID
JOIN dbo.STOK s ON s.ID = d.STOK
JOIN dbo.FIS_TURU FT ON FT.ID = f.FIS_TURU
WHERE f.FIS_TARIHI >= '$pBasSql' AND f.FIS_TARIHI < '$bitSql' AND FT.GIRIS IN (1, -1) AND f.FIS_TURU <> 18
  AND (f.FIS_TURU IN (11, 12, 35, 36) OR ISNULL(f.CARI, 0) = COALESCE((SELECT TOP 1 VARSAYILANCARI FROM dbo.FIRMASABITLERI), -1))
GROUP BY s.KOD, CONVERT(char(10), f.FIS_TARIHI, 23)
"@
        try {
            $dtP2 = Sql-Tablo $baglanti $sqlP2
            $ps = New-Object System.Collections.ArrayList
            foreach ($r in $dtP2.Rows) {
                [void]$ps.Add([PSCustomObject]@{ stok_kodu = Metin $r.stok_kodu; gun = [string]$r.gun; miktar = Sayi $r.miktar; tutar = [Math]::Round((Sayi $r.tutar), 2); adet = [int]$r.adet })
            }
            $nP2 = Parcali-Gonder "stok_perakende_yukle" $Db $ps ('"' + $pBasSql + '"') ('"' + $bitSql + '"')
            if (-not (Test-Path $PerIlkDosya)) { Set-Content -Path $PerIlkDosya -Value (Get-Date -Format "yyyy-MM-dd HH:mm:ss") }
            Yaz-Log "[$Db] Perakende urun/gun toplami: $nP2 satir gonderildi ($pBasSql itibaren)"
        } catch { Yaz-Log "[$Db] UYARI: perakende urun toplamlari gonderilemedi: $($_.Exception.Message) (veri tabanina 007_stok_hareketleri.sql calistirildi mi?)" }
    }

    if ($tam) { Set-Content -Path $TamGonderimDosya -Value (Get-Date -Format "yyyy-MM-dd HH:mm:ss") }
    Yaz-Log "[$Db] TAMAM"
}

$baglanti = $null
$hataVar = $false
try {
    if (-not (Test-Path $DbAnahtarDosyasi)) { Yaz-Log "HATA: $DbAnahtarDosyasi yok."; exit 1 }
    $script:Anahtar = (Get-Content -Path $DbAnahtarDosyasi -TotalCount 1).Trim()

    $baglanti = New-Object System.Data.SqlClient.SqlConnection("Server=$SqlServer;Database=master;Integrated Security=SSPI;")
    $baglanti.Open()

    if ($Database) { $db = $Database.Trim() }
    else { $db = [string]((Sql-Tablo $baglanti "SELECT TOP 1 name FROM sys.databases WHERE name LIKE 'ERP12[0-9][0-9][0-9][0-9]' AND state = 0 ORDER BY name DESC").Rows[0].name) }
    if (-not $db) { Yaz-Log "HATA: ERP12 yil veri tabani bulunamadi."; exit 1 }

    try { Veritabani-Gonder $db $baglanti }
    catch { $hataVar = $true; Yaz-Log "HATA: [$db] $($_.Exception.Message)" }
}
catch {
    Yaz-Log "HATA: $($_.Exception.Message)"
    exit 1
}
finally {
    if ($baglanti -ne $null) { $baglanti.Close() }
}
if ($hataVar) { exit 1 }
