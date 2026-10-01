# =====================================================================
#  Murat Gıda - ERP12 -> Veri tabanı: ÜRÜN HAREKETLERİ (alış / satış)
# =====================================================================
#  Ne yapar: ERP12'deki belgelerden
#   - alışları (FIS_TURU 1 fatura, 5 irsaliye) ve firmalara satışları
#     (2, 6, 12 — Peşin Satış Carisi hariç) satır satır,
#   - perakendeyi (11 kasa fişleri + Peşin Satış Carisi) ürün/gün toplamı olarak
#  okuyup bulut veri tabanına yazar. Uygulamadaki "Ürün Hareketleri" ekranı
#  buradan beslenir.
#
#  - ERP12'ye HİÇBİR ŞEY YAZMAZ, sadece okur.
#  - Günde bir kez son 400 günü baştan gönderir (ERP'de düzeltilen/silinen
#    belgeler de düzelsin), diğer çalışmalarda sadece son 3 günü.
#  - YIL DEVRİ OTOMATİK: ERP12'nin en yeni İKİ yıl veri tabanını (örn. ERP122026
#    ve ERP122025) kendisi bulur ve ikisini de gönderir — devirden sonra eski
#    yıla geç girilen faturalar da gelir. Daha eski yılların kayıtları veri
#    tabanında olduğu gibi kalır (silinmez), uygulamada görünmeye devam eder.
#
#  Kurulum: C:\Scripts\db-anahtar.txt (Supabase secret anahtarı) olmalı.
#  Görev Zamanlayıcı: saatte bir
#    powershell.exe -ExecutionPolicy Bypass -File "C:\Scripts\hareket-gonder.ps1"
# =====================================================================

# ---------------------- AYARLAR ----------------------
$SqlServer        = "SERVER\ERP12"
# Bos: ERP12 yil veri tabanlari (ERP12 + 4 haneli yil) otomatik bulunur.
# Elle vermek icin virgulle: "ERP122026,ERP122025"
$Database         = ""
$DbUrl            = "https://wjyqempcmyrmruhdpcwk.supabase.co"
$DbAnahtarDosyasi = "C:\Scripts\db-anahtar.txt"
$LogFile          = "C:\Scripts\hareket-log.txt"
$TamGonderimKlasor = "C:\Scripts"
$TamGun           = 400
# Bir yil veri tabani ILK kez gonderilirken (durum dosyasi yok) daha geriye git.
$IlkGun           = 800
$KisaGun          = 3
$Parca            = 3000
# FIS_DETAY'daki miktar ve KDV DAHIL birim fiyat. Bos birakilirsa sutun
# adlarindan otomatik bulunmaya calisilir; bulunamazsa fiyat bos gonderilir
# ve gunluge sutun listesi yazilir.
$MiktarKolonu     = ""
$FiyatIfadesi     = ""
# -----------------------------------------------------

try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}

function Yaz-Log($mesaj) {
    $satir = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $mesaj"
    Write-Host $satir
    try { Add-Content -Path $LogFile -Value $satir -ErrorAction SilentlyContinue } catch {}
}

function Sql-Tablo($baglanti, $sql) {
    $cmd = $baglanti.CreateCommand(); $cmd.CommandText = $sql; $cmd.CommandTimeout = 600
    $da = New-Object System.Data.SqlClient.SqlDataAdapter($cmd)
    $dt = New-Object System.Data.DataTable
    [void]$da.Fill($dt)
    return ,$dt
}

# Turkiye saati (+03:00, 2016'dan beri sabit) ile ISO metin.
function Iso($t) { return ([datetime]$t).ToString("yyyy-MM-ddTHH:mm:ss", [Globalization.CultureInfo]::InvariantCulture) + "+03:00" }
function Sayi($v) {
    if ($v -eq $null -or $v -is [DBNull]) { return $null }
    return [double]$v
}

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
        # DIKKAT: "$x = if (...) { @(...) }" tek elemanli diziyi tek nesneye cevirir
        # (veri tabani "dizi degil" diye reddeder) -> once bos dizi, sonra ata.
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
    $TamGonderimDosya = Join-Path $TamGonderimKlasor "hareket-son-tam-$Db.txt"
    $tam = $true
    $ilk = -not (Test-Path $TamGonderimDosya)
    if (-not $ilk) {
        $sonTam = [datetime]::MinValue
        if ([datetime]::TryParse((Get-Content $TamGonderimDosya -TotalCount 1), [ref]$sonTam)) {
            $tam = ((Get-Date) - $sonTam).TotalHours -ge 20
        }
    }
    $gun = if ($ilk) { $IlkGun } elseif ($tam) { $TamGun } else { $KisaGun }
    $bas = (Get-Date).Date.AddDays(-$gun)
    $bit = (Get-Date).Date.AddDays(1)
    Yaz-Log "[$Db] Basliyor: son $gun gun ($(if ($tam) { 'TAM' } else { 'kisa' }) gonderim)"
    $baglanti.ChangeDatabase($Db)

    # --- FIS_DETAY sutunlari: miktar ve KDV dahil fiyat ---
    $kolonlar = @((Sql-Tablo $baglanti "SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'FIS_DETAY'") | ForEach-Object { [string]$_.COLUMN_NAME })
    $miktar = $MiktarKolonu
    if (-not $miktar) { $miktar = @("MIKTAR_FIS", "MIKTAR", "MIKTAR1", "ADET") | Where-Object { $kolonlar -contains $_ } | Select-Object -First 1 }
    if (-not $miktar) { throw "[$Db] FIS_DETAY'da miktar sutunu bulunamadi. Sutunlar: $($kolonlar -join ', ')" }
    $fiyat = $FiyatIfadesi
    if (-not $fiyat) {
        # ERP12 SIPARIS_DETAY'da: MIKTAR_FIS ve DAHIL_FIYAT (FIS_DETAY'in da ayni oldugu varsayiliyor).
        $aday = @("DAHIL_FIYAT", "KDV_DAHIL_FIYAT", "FIYAT_KDV_DAHIL", "BIRIM_FIYAT_KDV_DAHIL", "KDVLI_FIYAT", "KDVLI_BIRIM_FIYAT") | Where-Object { $kolonlar -contains $_ } | Select-Object -First 1
        if ($aday) { $fiyat = "d.$aday" }
    }
    if (-not $fiyat) {
        Yaz-Log "[$Db] UYARI: KDV dahil fiyat sutunu bulunamadi, fiyatlar bos gonderiliyor. Sutunlar: $($kolonlar -join ', ')"
        $fiyat = "CAST(NULL AS decimal(18,4))"
    }

    $basSql = $bas.ToString("yyyy-MM-dd"); $bitSql = $bit.ToString("yyyy-MM-dd")
    # Pesin Satis Carisi. Turkce harfler (S/I noktali-noktasiz) icin her harf yerine
    # joker: "PE__N SAT__" hem PESIN SATIS hem PE(S-cedilla)(I-nokta)N SATI(S-cedilla) ile eslesir.
    $pesin = "UPPER(ISNULL(c.AD, '')) LIKE N'%PE__N SAT__%'"

    # --- 1) Tek tek listelenecekler: alis (1, 5) + firmalara satis (2, 6, 12; pesin haric) ---
    $sql = @"
SELECT d.ID AS detay_id, f.ID AS fis_id, f.FIS_TURU AS fis_turu, f.FIS_TARIHI AS tarih,
       ISNULL(f.BELGENO, '') AS belge_no, ISNULL(c.AD, '') AS cari,
       ISNULL(s.KOD, '') AS stok_kodu, ISNULL(d.BARKOD, '') AS barkod,
       d.$miktar AS miktar, $fiyat AS birim_fiyat
FROM dbo.FIS f
JOIN dbo.FIS_DETAY d ON d.FIS = f.ID
LEFT JOIN dbo.STOK s ON s.ID = d.STOK
LEFT JOIN dbo.CARI c ON c.ID = f.CARI
WHERE f.FIS_TARIHI >= '$basSql' AND f.FIS_TARIHI < '$bitSql'
  AND (f.FIS_TURU IN (1, 5) OR (f.FIS_TURU IN (2, 6, 12) AND NOT ($pesin)))
"@
    $dt = Sql-Tablo $baglanti $sql
    $satirlar = New-Object System.Collections.ArrayList
    foreach ($r in $dt.Rows) {
        $tur = [int]$r.fis_turu
        [void]$satirlar.Add([PSCustomObject]@{
            detay_id = [long]$r.detay_id; fis_id = [long]$r.fis_id; fis_turu = $tur
            yon = $(if ($tur -eq 1 -or $tur -eq 5) { "gelen" } else { "satilan" })
            tarih = Iso $r.tarih; belge_no = [string]$r.belge_no; cari = [string]$r.cari
            stok_kodu = [string]$r.stok_kodu; barkod = [string]$r.barkod
            miktar = Sayi $r.miktar; birim_fiyat = Sayi $r.birim_fiyat
        })
    }
    $n1 = Parcali-Gonder "hareket_yukle" $Db $satirlar ('"' + (Iso $bas) + '"') ('"' + (Iso $bit) + '"')

    # --- 2) Perakende: kasa (11) + Pesin Satis Carisi -> urun/gun toplami ---
    $sql2 = @"
SELECT ISNULL(s.KOD, '') AS stok_kodu, CONVERT(char(10), f.FIS_TARIHI, 23) AS gun, SUM(d.$miktar) AS miktar
FROM dbo.FIS f
JOIN dbo.FIS_DETAY d ON d.FIS = f.ID
JOIN dbo.STOK s ON s.ID = d.STOK
LEFT JOIN dbo.CARI c ON c.ID = f.CARI
WHERE f.FIS_TARIHI >= '$basSql' AND f.FIS_TARIHI < '$bitSql'
  AND (f.FIS_TURU = 11 OR (f.FIS_TURU IN (2, 6, 12) AND $pesin))
GROUP BY s.KOD, CONVERT(char(10), f.FIS_TARIHI, 23)
"@
    $dt2 = Sql-Tablo $baglanti $sql2
    $gunluk = New-Object System.Collections.ArrayList
    foreach ($r in $dt2.Rows) {
        [void]$gunluk.Add([PSCustomObject]@{ stok_kodu = [string]$r.stok_kodu; gun = [string]$r.gun; miktar = Sayi $r.miktar })
    }
    $n2 = Parcali-Gonder "perakende_yukle" $Db $gunluk ('"' + $basSql + '"') ('"' + $bitSql + '"')

    if ($tam) { Set-Content -Path $TamGonderimDosya -Value (Get-Date -Format "yyyy-MM-dd HH:mm:ss") }
    Yaz-Log "[$Db] TAMAM: $n1 belge satiri, $n2 perakende gun-urun toplami gonderildi (miktar: $miktar, fiyat: $fiyat)"
}

$baglanti = $null
$hataVar = $false
try {
    if (-not (Test-Path $DbAnahtarDosyasi)) { Yaz-Log "HATA: $DbAnahtarDosyasi yok."; exit 1 }
    $script:Anahtar = (Get-Content -Path $DbAnahtarDosyasi -TotalCount 1).Trim()

    $baglanti = New-Object System.Data.SqlClient.SqlConnection("Server=$SqlServer;Database=master;Integrated Security=SSPI;")
    $baglanti.Open()

    # Hangi yil veri tabanlari? (en yeni iki tanesi)
    if ($Database) {
        $dbler = @($Database.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    } else {
        $dbler = @((Sql-Tablo $baglanti "SELECT TOP 2 name FROM sys.databases WHERE name LIKE 'ERP12[0-9][0-9][0-9][0-9]' AND state = 0 ORDER BY name DESC") | ForEach-Object { [string]$_.name })
    }
    if ($dbler.Count -eq 0) { Yaz-Log "HATA: ERP12 yil veri tabani bulunamadi."; exit 1 }

    foreach ($db in $dbler) {
        try { Veritabani-Gonder $db $baglanti }
        catch { $hataVar = $true; Yaz-Log "HATA: [$db] $($_.Exception.Message)" }
    }
}
catch {
    Yaz-Log "HATA: $($_.Exception.Message)"
    exit 1
}
finally {
    if ($baglanti -ne $null) { $baglanti.Close() }
}
if ($hataVar) { exit 1 }
