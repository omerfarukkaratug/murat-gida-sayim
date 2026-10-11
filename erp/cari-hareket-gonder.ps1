# =====================================================================
#  Murat Gida - ERP12 -> Veri tabani: CARI HAREKETLERI (cari hesap ekstresi)
# =====================================================================
#  Ne yapar: ERP12'deki FINANS_DETAY satirlarindan carilere (CARI_TUR = 1, Pesin
#  Satis / varsayilan cari haric) ait borc ve alacaklari okuyup bulut veri
#  tabanina yazar. Uygulamadaki "Cari Hareketleri" ekrani buradan beslenir.
#  ERP12'deki cari bakiyesi (CARI_BAKIYELER) de ayni satirlardan hesaplanir.
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
    $n = Parcali-Gonder "cari_hareket_yukle" $Db $satirlar ('"' + (Iso $bas) + '"') ('"' + (Iso $bit) + '"')
    if ($tam) { Set-Content -Path $TamGonderimDosya -Value (Get-Date -Format "yyyy-MM-dd HH:mm:ss") }
    Yaz-Log "[$Db] TAMAM: $n cari hareket satiri gonderildi"
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
