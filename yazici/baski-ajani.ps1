# =====================================================================
#  MK ERP - BASKI PROGRAMI
#  Yazicinin bagli oldugu bilgisayarda calisir. Birkac saniyede bir
#  sunucuya "is var mi" diye sorar; telefondan gonderilen etiket isini
#  alir, gorunmez tarayicida PDF'e cevirir ve secilen yaziciya basar.
#
#  Kurulum: yazici\KURULUM.md
#  Gerekenler (hepsi C:\MKBaski icinde):
#    baski-ajani.ps1     bu dosya
#    baski-anahtar.txt   uygulamadaki ERP anahtari (tek satir)
#    SumatraPDF.exe      PDF'i sessizce yaziciya gonderen arac
#  Bilgisayarda Chrome ya da Edge kurulu olmali.
# =====================================================================

$Klasor        = "C:\MKBaski"
$AppsScriptUrl = "https://script.google.com/macros/s/AKfycbwH0hVGDXIQhdSxg2neDBNUEOxY1SNacJRz4cqf3WaP8xgAhlEnKfRv5xnlENKnh3XuYA/exec"
$SayfaUrl      = "https://omerfarukkaratug.github.io/murat-gida-sayim/etiket.html"
$AnahtarDosyasi = Join-Path $Klasor "baski-anahtar.txt"
$LogFile       = Join-Path $Klasor "baski-log.txt"
$Sumatra       = Join-Path $Klasor "SumatraPDF.exe"
$IsKlasoru     = Join-Path $Klasor "is"
$Profil        = Join-Path $Klasor "tarayici-profil"
$BeklemeSn     = 8      # iki sorgu arasi bekleme
# Uygulamada GORUNMEYECEK yazicilar (sanal yazicilar)
$YaziciHaric   = 'PDF|XPS|OneNote|Fax|Send To'

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Yaz-Log($mesaj) {
    $satir = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $mesaj"
    Write-Host $satir
    try {
        Add-Content -Path $LogFile -Value $satir -Encoding UTF8
        # Gunluk 2 MB'i gecince eskisi yedeklenir.
        if ((Get-Item $LogFile).Length -gt 2MB) { Move-Item $LogFile ($LogFile + ".eski") -Force }
    } catch {}
}

# Ayni anda tek kopya calissin.
$kilit = New-Object System.Threading.Mutex($false, "MKBaskiAjani")
if (-not $kilit.WaitOne(0)) { Write-Host "Baski programi zaten calisiyor."; exit 0 }

foreach ($d in @($Klasor, $IsKlasoru)) { if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null } }

if (-not (Test-Path $AnahtarDosyasi)) { Yaz-Log "HATA: $AnahtarDosyasi yok. Uygulamadaki ERP anahtarini bu dosyaya tek satir olarak yaz."; exit 1 }
$Anahtar = (Get-Content $AnahtarDosyasi -Raw).Trim()
if (-not $Anahtar) { Yaz-Log "HATA: baski-anahtar.txt bos."; exit 1 }
if (-not (Test-Path $Sumatra)) { Yaz-Log "HATA: $Sumatra yok. SumatraPDF (portable) indirip bu adla klasore koy."; exit 1 }

# Tarayici: once Chrome, yoksa Edge.
$Tarayici = $null
foreach ($aday in @(
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
    "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
    "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe")) {
    if ($aday -and (Test-Path $aday)) { $Tarayici = $aday; break }
}
if (-not $Tarayici) { Yaz-Log "HATA: Chrome ya da Edge bulunamadi."; exit 1 }

function Sor($parametreler) {
    $parcalar = foreach ($k in $parametreler.Keys) { "$k=" + [uri]::EscapeDataString([string]$parametreler[$k]) }
    return Invoke-RestMethod -Uri ($AppsScriptUrl + "?" + ($parcalar -join "&")) -Method Get -TimeoutSec 60
}

function Yazici-Adlari {
    $adlar = @()
    try { $adlar = @(Get-Printer -ErrorAction Stop | Where-Object { $_.Name -notmatch $YaziciHaric } | ForEach-Object { $_.Name }) }
    catch { $adlar = @(Get-WmiObject Win32_Printer | Where-Object { $_.Name -notmatch $YaziciHaric } | ForEach-Object { $_.Name }) }
    return $adlar
}

function Bitti($id, $durum, $mesaj) {
    for ($i = 1; $i -le 3; $i++) {
        try { Sor @{ action = "baski_ajan_bitti"; anahtar = $Anahtar; id = $id; durum = $durum; mesaj = $mesaj } | Out-Null; return }
        catch { Start-Sleep -Seconds 5 }
    }
    Yaz-Log "UYARI: Is sonucu sunucuya yazilamadi (is $id, $durum)."
}

function Pdf-Uret($id, $pdf) {
    $url = $SayfaUrl + "?is=" + $id + "&anahtar=" + [uri]::EscapeDataString($Anahtar) + "&t=" + (Get-Date).Ticks
    # Yeni Chrome/Edge "--headless=new" ister; eski surum icin ikinci deneme "--headless".
    foreach ($bassiz in @("--headless=new", "--headless")) {
        if (Test-Path $pdf) { Remove-Item $pdf -Force }
        $arg = @($bassiz, "--disable-gpu", "--no-first-run", "--no-pdf-header-footer", "--print-to-pdf-no-header",
                 "--user-data-dir=$Profil", "--virtual-time-budget=25000", "--print-to-pdf=$pdf", "`"$url`"")
        $p = Start-Process -FilePath $Tarayici -ArgumentList $arg -PassThru -WindowStyle Hidden
        if (-not $p.WaitForExit(120000)) { try { $p.Kill() } catch {}; continue }
        Start-Sleep -Milliseconds 500
        if ((Test-Path $pdf) -and (Get-Item $pdf).Length -gt 800) { return $true }
    }
    return $false
}

function Bas($is) {
    $id = [string]$is.id
    $yazici = [string]$is.windowsAdi
    $bicim = [string]$is.bicim
    $pdf = Join-Path $IsKlasoru ($id + ".pdf")
    Yaz-Log "Is alindi: $id ($bicim) -> $yazici"

    if (-not (Yazici-Adlari | Where-Object { $_ -eq $yazici })) { Bitti $id "hata" "Yazici bu bilgisayarda bulunamadi: $yazici"; Yaz-Log "HATA: yazici yok: $yazici"; return }
    if (-not (Pdf-Uret $id $pdf)) { Bitti $id "hata" "Etiket sayfasi hazirlanamadi (tarayici/Internet)"; Yaz-Log "HATA: PDF uretilemedi."; return }

    # Sayfa etiketleri cizemediyse isi kendisi "hata" yapar; o zaman bos kagit basilmaz.
    try { $k = Sor @{ action = "baski_ajan_bitti"; anahtar = $Anahtar; id = $id; durum = "kontrol" } } catch { $k = $null }
    if (-not $k -or $k.status -ne "ok") { Yaz-Log "Is basilmadi: sayfa hata bildirdi ya da is iptal edildi."; return }

    # Kagit: A6/A5 afisler A4'e dizili gelir (a4diz); dizili A5 yatik A4'tur.
    $dizili = $false
    if ($is.ayar -and $is.ayar.a4diz -eq $true -and ($bicim -eq "a6" -or $bicim -eq "a5")) { $dizili = $true }
    $kagit = "A4"
    if (-not $dizili) { if ($bicim -eq "a3") { $kagit = "A3" } elseif ($bicim -eq "a5") { $kagit = "A5" } elseif ($bicim -eq "a6") { $kagit = "A6" } }
    $ayar = "noscale,paper=$kagit"
    if ($dizili -and $bicim -eq "a5") { $ayar += ",landscape" } else { $ayar += ",portrait" }
    # Zebra (rulo etiket): kagit boyutu yazicinin kendi ayarindan gelir, yalnizca olcek korunur.
    if ($bicim -eq "zebra") { $ayar = "noscale"; $kagit = "rulo etiket" }

    $p = Start-Process -FilePath $Sumatra -ArgumentList @("-print-to", "`"$yazici`"", "-print-settings", "`"$ayar`"", "-silent", "`"$pdf`"") -PassThru -WindowStyle Hidden
    if (-not $p.WaitForExit(120000)) { try { $p.Kill() } catch {}; Bitti $id "hata" "Yaziciya gonderme zaman asimina ugradi"; Yaz-Log "HATA: SumatraPDF zaman asimi."; return }
    if ($p.ExitCode -ne 0) { Bitti $id "hata" "Yazici isi kabul etmedi (kod $($p.ExitCode))"; Yaz-Log "HATA: SumatraPDF cikis kodu $($p.ExitCode)."; return }

    Bitti $id "basildi" ""
    Yaz-Log "Yaziciya gonderildi: $id ($kagit)"
}

Yaz-Log "Baski programi basladi. Bilgisayar: $env:COMPUTERNAME, tarayici: $Tarayici"
Yaz-Log ("Yazicilar: " + ((Yazici-Adlari) -join " | "))
$hataSayisi = 0
while ($true) {
    try {
        $yaziciJson = ConvertTo-Json -InputObject @(Yazici-Adlari) -Compress
        $cevap = Sor @{ action = "baski_ajan_al"; anahtar = $Anahtar; bilgisayar = $env:COMPUTERNAME; yazicilar = $yaziciJson }
        if ($cevap -and $cevap.status -eq "error") {
            if ($hataSayisi % 40 -eq 0) { Yaz-Log "HATA: Sunucu reddetti: $($cevap.message) (anahtar dogru mu, Code.gs guncel mi?)" }
            $hataSayisi++
        } else {
            $hataSayisi = 0
            if ($cevap -and $cevap.is) { Bas $cevap.is }
        }
    } catch {
        # Internet kesintisi vb.: gunlugu doldurmamak icin seyrek yazilir, program calismaya devam eder.
        if ($hataSayisi % 40 -eq 0) { Yaz-Log "UYARI: Sunucuya ulasilamadi: $($_.Exception.Message)" }
        $hataSayisi++
    }
    # 2 gunden eski PDF'ler silinir.
    try { Get-ChildItem $IsKlasoru -Filter *.pdf | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-2) } | Remove-Item -Force } catch {}
    Start-Sleep -Seconds $BeklemeSn
}
