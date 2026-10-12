# =====================================================================
#  MK ERP - Mal Giris / Mal Cikis kayitlarini masaustune Excel olarak indirir
#  (build 174+)
# =====================================================================
#  Ne yapar:
#   1) Telefondan kaydedilen mal giris / mal cikis kayitlarini sunucudan alir.
#   2) Her kaydi ERP12 mal aktarim sablonunda bir Excel (.xlsx) dosyasi olarak
#      ana klasordeki "Mal Alis" ya da "Mal Cikis" klasorune kaydeder.
#      Dosya adi: "Belge turu  Cari adi  Belge no"   ornek: "Satis Fisi ABC KIMYA 20260002.xlsx"
#      (Turkce harflerle; ayni adda dosya varsa sonuna (2), (3) eklenir.)
#   3) Kaydedilen kayitlari sunucuda "Aktarildi" diye isaretler (bir daha gelmez).
#
#  Fiyatlar Excel'e GERCEK SAYI olarak yazilir: eski CSV'de "12,50" metni ERP'de
#  1250 diye okunuyordu; artik 12,5 olarak okunur.
#
#  ERP12'ye ve ERP veri tabanina HICBIR SEY YAZMAZ, sadece dosya kaydeder.
#
#  Giris bilgisi (bir kez): C:\Scripts\mal-indir-giris.txt dosyasi olusturun,
#    1. satir: uygulamadaki kullanici adiniz (Rapor yetkisi olan)
#    2. satir: sifresi
#  Sifre gunluge ASLA yazilmaz.
# =====================================================================

# ---------------------- AYARLAR (kendine gore kontrol et) ----------------------
$AppsScriptUrl = "https://script.google.com/macros/s/AKfycbwH0hVGDXIQhdSxg2neDBNUEOxY1SNacJRz4cqf3WaP8xgAhlEnKfRv5xnlENKnh3XuYA/exec"
# Dosyalarin konacagi ana klasor. Icinde "Mal Alis" ve "Mal Cikis" klasorleri kendiliginden acilir.
# Bos birakilirsa: Masaustu\Mal Aktarim
$AnaKlasor     = ""
$GirisDosyasi  = "C:\Scripts\mal-indir-giris.txt"
$LogFile       = "C:\Scripts\mal-indir-log.txt"
# --------------------------------------------------------------------------------

try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}

function Yaz-Log($mesaj) {
    $satir = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $mesaj"
    Write-Host $satir
    try { Add-Content -Path $LogFile -Value $satir -Encoding UTF8 -ErrorAction SilentlyContinue } catch {}
}

# Ayni anda iki kopya calismasin (iki gorev ayni kaydi iki kez indirmesin).
$kilit = New-Object System.Threading.Mutex($false, "Global\MKMalHareketIndir")
$kilitAlindi = $false
try { $kilitAlindi = $kilit.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $kilitAlindi = $true }
if (-not $kilitAlindi) { Write-Host "Baska bir kopya zaten calisiyor, cikiliyor."; exit 0 }

try {
    if (-not $AnaKlasor) { $AnaKlasor = Join-Path ([Environment]::GetFolderPath('Desktop')) "Mal Aktarim" }

    if (-not (Test-Path $GirisDosyasi)) { Yaz-Log "HATA: $GirisDosyasi yok (1. satir kullanici, 2. satir sifre)."; exit 1 }
    # Dosya Not Defteri'nde hangi kodlamayla kaydedilmis olursa olsun (ANSI / UTF-8 / Unicode)
    # Turkce harfli sifre dogru okunsun.
    $bayt = [System.IO.File]::ReadAllBytes($GirisDosyasi)
    if ($bayt.Length -ge 2 -and $bayt[0] -eq 0xFF -and $bayt[1] -eq 0xFE) { $metin = [System.Text.Encoding]::Unicode.GetString($bayt) }
    elseif ($bayt.Length -ge 2 -and $bayt[0] -eq 0xFE -and $bayt[1] -eq 0xFF) { $metin = [System.Text.Encoding]::BigEndianUnicode.GetString($bayt) }
    else {
        try { $metin = (New-Object System.Text.UTF8Encoding($false, $true)).GetString($bayt) }
        catch { $metin = [System.Text.Encoding]::Default.GetString($bayt) }
    }
    $giris = @(($metin -replace [char]0xFEFF, '') -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
    $kullanici = if ($giris.Count -ge 1) { [string]$giris[0] } else { "" }
    $sifre     = if ($giris.Count -ge 2) { [string]$giris[1] } else { "" }
    if (-not $kullanici -or -not $sifre) { Yaz-Log "HATA: $GirisDosyasi icinde kullanici ya da sifre eksik."; exit 1 }

    # Sunucu yanitini UTF-8 olarak oku (Turkce harfler bozulmasin).
    function Sunucu-Get($parametreler) {
        $q = ($parametreler.GetEnumerator() | ForEach-Object { [Uri]::EscapeDataString($_.Key) + "=" + [Uri]::EscapeDataString([string]$_.Value) }) -join "&"
        $wc = New-Object System.Net.WebClient
        $wc.Encoding = [System.Text.Encoding]::UTF8
        try { $metin = $wc.DownloadString($AppsScriptUrl + "?" + $q) } finally { $wc.Dispose() }
        return ($metin | ConvertFrom-Json)
    }

    # Windows dosya adinda olmayacak karakterleri temizle.
    function Temiz-Ad($ad) {
        $t = [string]$ad
        foreach ($ch in [System.IO.Path]::GetInvalidFileNameChars()) { $t = $t.Replace([string]$ch, " ") }
        $t = ($t -replace '\s+', ' ').Trim().TrimEnd('.')
        if (-not $t) { $t = "Mal kaydi" }
        if ($t.Length -gt 120) { $t = $t.Substring(0, 120).Trim() }
        return $t
    }

    $toplam = 0
    for ($tur = 0; $tur -lt 20; $tur++) {
        $cevap = Sunucu-Get @{ action = "mal_export"; user = $kullanici; pass = $sifre }
        if ($cevap.status -ne "ok") { Yaz-Log ("HATA: sunucu: " + $cevap.message + " (kullanici: '" + $kullanici + "', sifre " + $sifre.Length + " karakter okundu)"); exit 1 }
        $kayitlar = @($cevap.batches)
        if ($kayitlar.Count -eq 0) { break }

        $tamamlanan = @()
        foreach ($b in $kayitlar) {
            try {
                if (-not $b.xlsx) { Yaz-Log ("ATLANDI: " + $b.ad + " - sunucu Excel dosyasi gondermedi (Code.gs build 174 dagitildi mi?)"); continue }
                $klasorAdi = if ($b.klasor) { Temiz-Ad $b.klasor } elseif ($b.hareket -match '^[CcÇç]') { "Mal Cikis" } else { "Mal Alis" }
                $klasor = Join-Path $AnaKlasor $klasorAdi
                if (-not (Test-Path $klasor)) { New-Item -ItemType Directory -Path $klasor -Force | Out-Null }
                $temel = Temiz-Ad $b.ad
                $yol = Join-Path $klasor ($temel + ".xlsx")
                $n = 2
                while (Test-Path $yol) { $yol = Join-Path $klasor ("$temel ($n).xlsx"); $n++ }
                [System.IO.File]::WriteAllBytes($yol, [Convert]::FromBase64String([string]$b.xlsx))
                $tamamlanan += [string]$b.batchId
                $toplam++
                Yaz-Log ("KAYDEDILDI: " + $yol + " (" + $b.kalemSayisi + " kalem)")
            } catch {
                Yaz-Log ("HATA: " + $b.ad + " kaydedilemedi: " + $_.Exception.Message)
            }
        }
        if ($tamamlanan.Count -eq 0) { break }
        $onay = Sunucu-Get @{ action = "mal_export_onay"; user = $kullanici; pass = $sifre; ids = ($tamamlanan -join ",") }
        if ($onay.status -ne "ok") { Yaz-Log ("HATA: Aktarildi isareti konamadi: " + $onay.message); exit 1 }
        if (-not $cevap.kalan -or [int]$cevap.kalan -le 0) { break }
    }
    if ($toplam -gt 0) { Yaz-Log "BASARILI: $toplam kayit indirildi -> $AnaKlasor" }
} catch {
    Yaz-Log ("HATA: " + $_.Exception.Message)
    exit 1
} finally {
    if ($kilitAlindi) { try { $kilit.ReleaseMutex() } catch {} }
}
