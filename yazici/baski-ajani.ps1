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
$BeklemeSn     = 5      # iki sorgu arasi bekleme
$AjanSurum     = "163"  # sunucuya bildirilir; uygulama eski programi uyarir
$ZebraParcaBoy = 40     # bir goruntudeki en fazla etiket (etiket.html PARCA_BOY ile ayni olmali)
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

# Windows'un yazici icin bildirdigi durum: kapali (cevrimdisi / bagli degil), kagit, hata. Sorun yoksa listede yer almaz.
function Yazici-Durumlari {
    $d = @{}
    try {
        Get-Printer -ErrorAction Stop | Where-Object { $_.Name -notmatch $YaziciHaric } | ForEach-Object {
            $s = [string]$_.PrinterStatus
            if ($s -match 'Offline|NotAvailable') { $d[$_.Name] = "kapali" }
            elseif ($s -match 'Paper') { $d[$_.Name] = "kagit" }
            elseif ($s -match 'Error|UserIntervention|DoorOpen|NoToner') { $d[$_.Name] = "hata" }
        }
    } catch {
        try { Get-WmiObject Win32_Printer | Where-Object { $_.Name -notmatch $YaziciHaric -and $_.WorkOffline } | ForEach-Object { $d[$_.Name] = "kapali" } } catch {}
    }
    return $d
}

function Bitti($id, $durum, $mesaj) {
    for ($i = 1; $i -le 6; $i++) {
        try { Sor @{ action = "baski_ajan_bitti"; anahtar = $Anahtar; id = $id; durum = $durum; mesaj = $mesaj } | Out-Null; return }
        catch { Start-Sleep -Seconds (5 * $i) }
    }
    Yaz-Log "UYARI: Is sonucu sunucuya yazilamadi (is $id, $durum)."
}

# Bu programin tarayici profiliyle acik kalmis eski tarayici islemlerini kapatir.
# (Ayni profille ikinci bir tarayici acilinca yenisi isi eskisine devredip HEMEN kapanir, cikti olusmaz;
#  program da bos yere bir dakika beklerdi.)
function Eski-Tarayicilari-Kapat {
    try {
        Get-WmiObject Win32_Process -ErrorAction Stop | Where-Object { $_.CommandLine -and $_.CommandLine.IndexOf($Profil, [StringComparison]::OrdinalIgnoreCase) -ge 0 } |
            ForEach-Object { try { [void]$_.Terminate() } catch {} }
    } catch {}
}
# Basliksiz tarayiciyi calistirir, $cikti dosyasi olusup yazimi bitene kadar bekler. Basarili: $true.
function Tarayici-Calistir($ekArg, $cikti, $ne) {
    $bas = Get-Date
    foreach ($bassiz in @("--headless=new", "--headless")) {
        Eski-Tarayicilari-Kapat
        if (Test-Path $cikti) { Remove-Item $cikti -Force }
        # --do-not-de-elevate: program yonetici olarak calisiyorsa Chrome kendini yeniden baslatip
        # ilk islemi hemen kapatir; bu bayrak onu engeller.
        $arg = @($bassiz, "--disable-gpu", "--no-first-run", "--do-not-de-elevate", "--no-default-browser-check", "--disable-extensions", "--disable-sync", "--disable-component-update", "--user-data-dir=$Profil", "--virtual-time-budget=15000") + $ekArg
        $p = Start-Process -FilePath $Tarayici -ArgumentList $arg -PassThru -WindowStyle Hidden
        if (-not $p.WaitForExit(90000)) { try { $p.Kill() } catch {} }
        # Tarayici kapandiktan sonra dosya en gec birkac saniyede gelir; gelmezse beklemeden oteki denemeye gecilir.
        $son = -1; $yok = 0
        for ($bekle = 0; $bekle -lt 60; $bekle++) {
            if (Test-Path $cikti) {
                $boyut = (Get-Item $cikti).Length
                if ($boyut -gt 800 -and $boyut -eq $son) {
                    Yaz-Log ("$ne hazir: " + [Math]::Round(((Get-Date) - $bas).TotalSeconds, 1) + " sn ($bassiz)")
                    return $true
                }
                $son = $boyut
            } else { $yok++; if ($yok -ge 16) { break } }      # 8 sn icinde dosya hic olusmadi
            Start-Sleep -Milliseconds 500
        }
        Yaz-Log "UYARI: $bassiz ile $ne olusmadi (tarayici cikis kodu: $($p.ExitCode))."
    }
    return $false
}
function Pdf-Uret($id, $pdf) {
    $url = $SayfaUrl + "?is=" + $id + "&anahtar=" + [uri]::EscapeDataString($Anahtar) + "&t=" + (Get-Date).Ticks
    return (Tarayici-Calistir @("--no-pdf-header-footer", "--print-to-pdf-no-header", "--print-to-pdf=$pdf", "`"$url`"") $pdf "PDF")
}
function Goruntu-Uret($id, $png, $parca, $genPx, $yukPx) {
    $url = $SayfaUrl + "?is=" + $id + "&anahtar=" + [uri]::EscapeDataString($Anahtar) + "&goruntu=1&parca=" + $parca + "&t=" + (Get-Date).Ticks
    return (Tarayici-Calistir @("--hide-scrollbars", "--force-device-scale-factor=1", "--disable-lcd-text", "--window-size=$genPx,$yukPx", "--screenshot=$png", "`"$url`"") $png "Goruntu")
}

# Goruntudeki etiketleri yaziciya basar; basilan etiket sayisini dondurur (0 = goruntude etiket yok).
function Zebra-Bas($png, $yazici, $wMm, $hMm) {
    $script:zbBmp = New-Object System.Drawing.Bitmap($png)
    $doc = $null
    try {
        $script:zbW = [int]($wMm * 8); $script:zbH = [int]($hMm * 8)
        # Etiket say: her etiket diliminin sol kenari beyazdir, etiket olmayan yer kirmizidir.
        $n = 0
        while ((($n + 1) * $script:zbH) -le $script:zbBmp.Height) {
            $nokta = $script:zbBmp.GetPixel(2, ($n * $script:zbH + [int]($script:zbH / 2)))
            if ($nokta.R -gt 200 -and $nokta.G -lt 80 -and $nokta.B -lt 80) { break }
            $n++
        }
        if ($n -eq 0) { return 0 }
        $script:zbAdet = $n; $script:zbSira = 0; $script:zbWmm = [single]$wMm; $script:zbHmm = [single]$hMm
        $doc = New-Object System.Drawing.Printing.PrintDocument
        $doc.PrinterSettings.PrinterName = $yazici
        if (-not $doc.PrinterSettings.IsValid) { throw "Yazici acilamadi: $yazici" }
        $doc.DocumentName = "MK Etiket"
        $doc.PrintController = New-Object System.Drawing.Printing.StandardPrintController   # "yazdiriliyor" penceresi cikmasin
        $doc.OriginAtMargins = $false
        # Kagit boyu yazicinin kendi ayarindan (Yazdirma Varsayilanlari) gelir; burada degistirilmez.
        $doc.add_PrintPage({
            param($gonderen, $e)
            $kaynak = New-Object System.Drawing.RectangleF(0, ($script:zbSira * $script:zbH), $script:zbW, $script:zbH)
            $hedef = New-Object System.Drawing.RectangleF(0, 0, $script:zbWmm, $script:zbHmm)
            $e.Graphics.PageUnit = [System.Drawing.GraphicsUnit]::Millimeter
            $e.Graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
            $e.Graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
            $e.Graphics.DrawImage($script:zbBmp, $hedef, $kaynak, [System.Drawing.GraphicsUnit]::Pixel)
            $script:zbSira++
            $e.HasMorePages = ($script:zbSira -lt $script:zbAdet)
        })
        $doc.Print()
        return $n
    } finally {
        if ($doc) { $doc.Dispose() }
        $script:zbBmp.Dispose()
    }
}

function Zebra-Is($is, $id, $yazici) {
    $w = 80.0; $h = 34.0
    try { if ($is.ayar -and $is.ayar.zebra) { if ([double]$is.ayar.zebra.w -gt 0) { $w = [double]$is.ayar.zebra.w }; if ([double]$is.ayar.zebra.h -gt 0) { $h = [double]$is.ayar.zebra.h } } } catch {}
    $genPx = [int]($w * 8); $yukPx = [int]($h * 8) * $ZebraParcaBoy
    $toplam = 0
    for ($parca = 0; $parca -lt 50; $parca++) {
        $png = Join-Path $IsKlasoru ($id + "-" + $parca + ".png")
        if (-not (Goruntu-Uret $id $png $parca $genPx $yukPx)) { Bitti $id "hata" "Etiket sayfasi hazirlanamadi (tarayici/Internet)"; Yaz-Log "HATA: goruntu uretilemedi."; return }
        if ($parca -eq 0) {
            # Sunucuya ulasilamazsa is "basiliyor"da takili kalmasin: uc kez denenir, olmazsa hata olarak bildirilir.
            $k = $null
            for ($d = 1; $d -le 3 -and -not $k; $d++) {
                try { $k = Sor @{ action = "baski_ajan_bitti"; anahtar = $Anahtar; id = $id; durum = "kontrol" } } catch { $k = $null; Yaz-Log "UYARI: kontrol sorgusu basarisiz ($d): $($_.Exception.Message)"; Start-Sleep -Seconds 4 }
            }
            if (-not $k) { Yaz-Log "HATA: basmadan onceki kontrol icin sunucuya ulasilamadi."; Bitti $id "hata" "Baski programi sunucuya ulasamadi - yeniden gonder"; return }
            if ($k.status -ne "ok") { Yaz-Log "Is basilmadi: sayfa hata bildirdi ya da is iptal edildi."; return }
        }
        try { $n = [int](Zebra-Bas $png $yazici $w $h) }
        catch { Bitti $id "hata" ("Yazici isi kabul etmedi: " + $_.Exception.Message); Yaz-Log "HATA: Zebra baski: $($_.Exception.Message)"; return }
        $toplam += $n
        if ($n -lt $ZebraParcaBoy) { break }
    }
    if ($toplam -eq 0) { Bitti $id "hata" "Etiket goruntusu bos cikti"; Yaz-Log "HATA: goruntude etiket yok."; return }
    Bitti $id "basildi" ""
    Yaz-Log "Yaziciya gonderildi: $id (rulo etiket, $toplam adet)"
}

function Bas($is) {
    $id = [string]$is.id
    $yazici = [string]$is.windowsAdi
    $bicim = [string]$is.bicim
    $pdf = Join-Path $IsKlasoru ($id + ".pdf")
    Yaz-Log "Is alindi: $id ($bicim) -> $yazici"

    if (-not (Yazici-Adlari | Where-Object { $_ -eq $yazici })) { Bitti $id "hata" "Yazici bu bilgisayarda bulunamadi: $yazici"; Yaz-Log "HATA: yazici yok: $yazici"; return }
    $wd = (Yazici-Durumlari)[$yazici]
    if ($wd) { Yaz-Log "UYARI: Windows bu yaziciyi '$wd' gosteriyor: $yazici (is yine de gonderiliyor)" }
    if ($bicim -eq "zebra") { Zebra-Is $is $id $yazici; return }
    if (-not (Pdf-Uret $id $pdf)) { Bitti $id "hata" "Etiket sayfasi hazirlanamadi (tarayici/Internet)"; Yaz-Log "HATA: PDF uretilemedi."; return }

    # Sayfa etiketleri cizemediyse isi kendisi "hata" yapar; o zaman bos kagit basilmaz.
    # Sunucuya ulasilamazsa is "basiliyor"da takili kalmasin: uc kez denenir, olmazsa hata olarak bildirilir.
    $k = $null
    for ($d = 1; $d -le 3 -and -not $k; $d++) {
        try { $k = Sor @{ action = "baski_ajan_bitti"; anahtar = $Anahtar; id = $id; durum = "kontrol" } } catch { $k = $null; Start-Sleep -Seconds 4 }
    }
    if (-not $k) { Yaz-Log "HATA: basmadan onceki kontrol icin sunucuya ulasilamadi."; Bitti $id "hata" "Baski programi sunucuya ulasamadi - yeniden gonder"; return }
    if ($k.status -ne "ok") { Yaz-Log "Is basilmadi: sayfa hata bildirdi ya da is iptal edildi."; return }

    # Kagit: A6/A5 afisler A4'e dizili gelir (a4diz); dizili A5 de dik A4 sayfadir.
    $dizili = $false
    if ($is.ayar -and $is.ayar.a4diz -eq $true -and ($bicim -eq "a6" -or $bicim -eq "a5")) { $dizili = $true }
    $kagit = "A4"
    if (-not $dizili) { if ($bicim -eq "a3") { $kagit = "A3" } elseif ($bicim -eq "a5") { $kagit = "A5" } elseif ($bicim -eq "a6") { $kagit = "A6" } }
    $ayar = "noscale,paper=$kagit"
    # Dizili A5 de DIK A4 sayfa olarak gelir (afisler sayfanin icinde cevrilmis); yazici surucusu "yatik" istegini uygulamayabiliyor.
    $ayar += ",portrait"
    # Zebra (rulo etiket): kagit boyutu yazicinin kendi ayarindan gelir, yalnizca olcek korunur.
    if ($bicim -eq "zebra") { $ayar = "noscale"; $kagit = "rulo etiket" }

    $yBas = Get-Date
    $p = Start-Process -FilePath $Sumatra -ArgumentList @("-print-to", "`"$yazici`"", "-print-settings", "`"$ayar`"", "-silent", "`"$pdf`"") -PassThru -WindowStyle Hidden
    if (-not $p.WaitForExit(120000)) { try { $p.Kill() } catch {}; Bitti $id "hata" "Yaziciya gonderme zaman asimina ugradi"; Yaz-Log "HATA: SumatraPDF zaman asimi."; return }
    if ($p.ExitCode -ne 0) { Bitti $id "hata" "Yazici isi kabul etmedi (kod $($p.ExitCode))"; Yaz-Log "HATA: SumatraPDF cikis kodu $($p.ExitCode)."; return }

    Bitti $id "basildi" ""
    Yaz-Log ("Yaziciya gonderildi: $id ($kagit) - yaziciya verme " + [Math]::Round(((Get-Date) - $yBas).TotalSeconds, 1) + " sn")
}

Yaz-Log "Baski programi basladi. Bilgisayar: $env:COMPUTERNAME, tarayici: $Tarayici"
Yaz-Log ("Yazicilar: " + ((Yazici-Adlari) -join " | "))
$hataSayisi = 0
while ($true) {
    try {
        $yaziciJson = ConvertTo-Json -InputObject @(Yazici-Adlari) -Compress
        $durumJson = ConvertTo-Json -InputObject (Yazici-Durumlari) -Compress
        $cevap = Sor @{ action = "baski_ajan_al"; anahtar = $Anahtar; bilgisayar = $env:COMPUTERNAME; yazicilar = $yaziciJson; durumlar = $durumJson; surum = $AjanSurum }
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
    try { Get-ChildItem $IsKlasoru -Include *.pdf, *.png -File -Recurse | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-2) } | Remove-Item -Force } catch {}
    Start-Sleep -Seconds $BeklemeSn
}
