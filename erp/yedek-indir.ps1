# =====================================================================
#  KRT Saha - gece yedegini ERP bilgisayarina indir (sunucu disinda ikinci kopya)
#
#  Ne yapar: sunucunun (sunucu.krtsaha.com) en son gece veritabani yedegini indirir,
#  $YedekKlasor icine kaydeder, en yeni $Sakla tanesini tutar, eskileri siler.
#  Ayni yedek zaten inmisse tekrar indirmez.
#  Anahtar: C:\Scripts\erp-anahtar.txt (stok gonderiminin kullandigi ayni ERP anahtari).
#  Klasoru Google Drive (masaustu uygulamasi) ile esitlenen bir klasor yaparsan bulutta da kopyasi olur.
#  Gorev: YEDEK-INDIR-GOREV.bat her sabah 07:30'da calistirir.
#  Geri yukleme gerekirse: yedek dosyasini bana / yoneticiye ver (pg_restore ile yuklenir).
# =====================================================================
$SunucuUrl      = "https://sunucu.krtsaha.com/yedek/son"
$AnahtarDosyasi = "C:\Scripts\erp-anahtar.txt"
$YedekKlasor    = "C:\KRTSahaYedek"
$Sakla          = 30
$LogFile        = "C:\Scripts\yedek-indir-log.txt"

try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}
function Yaz-Log($m) { $s = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $m"; Write-Host $s; try { Add-Content -Path $LogFile -Value $s } catch {} }

try {
    if (-not (Test-Path $AnahtarDosyasi)) { Yaz-Log "HATA: $AnahtarDosyasi yok."; exit 1 }
    $anahtar = (Get-Content -Path $AnahtarDosyasi -TotalCount 1).Trim()
    if (-not (Test-Path $YedekKlasor)) { New-Item -ItemType Directory -Path $YedekKlasor | Out-Null }
    $gecici = Join-Path $YedekKlasor "indiriliyor.tmp"
    $istek = [System.Net.HttpWebRequest]::Create($SunucuUrl)
    $istek.Headers.Add("X-Erp-Anahtar", $anahtar)
    $istek.Timeout = 600000; $istek.ReadWriteTimeout = 600000
    $cevap = $istek.GetResponse()
    $uzunluk = $cevap.ContentLength
    $ad = "mkerp-yedek.dump"
    $cd = $cevap.Headers["Content-Disposition"]
    if ($cd -and $cd -match 'filename="([^"]+)"') { $ad = $Matches[1] }
    $hedef = Join-Path $YedekKlasor $ad
    if ((Test-Path $hedef) -and ((Get-Item $hedef).Length -eq $uzunluk)) {
        $cevap.Close(); Yaz-Log "Zaten var: $ad (yeni yedek yok)"; exit 0
    }
    $akis = $cevap.GetResponseStream(); $dosya = [System.IO.File]::Create($gecici)
    try { $akis.CopyTo($dosya) } finally { $dosya.Close(); $akis.Close(); $cevap.Close() }
    $boy = (Get-Item $gecici).Length
    if ($uzunluk -gt 0 -and $boy -ne $uzunluk) { Remove-Item $gecici -Force; throw "eksik indi ($boy / $uzunluk bayt)" }
    Move-Item -Path $gecici -Destination $hedef -Force
    Yaz-Log ("BASARILI: $ad indirildi (" + [Math]::Round($boy / 1MB, 1) + " MB)")
    $eski = @(Get-ChildItem -Path $YedekKlasor -Filter "mkerp-*.dump" | Sort-Object LastWriteTime -Descending | Select-Object -Skip $Sakla)
    foreach ($e in $eski) { Remove-Item $e.FullName -Force; Yaz-Log "Eski yedek silindi: $($e.Name)" }
} catch {
    $m = $_.Exception.Message
    if ($m -match '403') { $m = "anahtar kabul edilmedi (erp-anahtar.txt uygulamadaki ERP anahtariyla ayni mi?)" }
    Yaz-Log "HATA: yedek indirilemedi: $m"
    exit 1
}
