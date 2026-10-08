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
$BeklemeSn     = 3      # iki sorgu arasi bekleme
$AjanSurum     = "169"  # sunucuya bildirilir; uygulama eski programi uyarir
Add-Type -AssemblyName System.Drawing   # Zebra etiketi goruntu olarak basilir
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

# Isin nerede ne kadar surdugu: telefonda ve gunlukte gorunur (yavaslik nerede, oradan anlasilir).
function Sure-Ozeti {
    $t = [Math]::Round(((Get-Date) - $script:IsBas).TotalSeconds, 1)
    $o = "Bilgisayarda $t sn: " + $script:Sure + "gerisi sunucu sorgulari ve yazici"
    Yaz-Log "Sure: $o"
    return $o
}

# Windows yazici kuyrugu: "yaziciya verildi" demek isin Windows'a teslim edildigi demektir; kagida cikip cikmadigini
# buradan anlamaya calisiriz. Is kuyrukta hata / cevrimdisi / kagit yok durumunda bekliyorsa telefona yazilir.
# Kuyruk WMI ile ve 3 sn zaman sinirla okunur (Get-PrintJob bazi yazicilarda uzun sure cevap vermeyebiliyor).
function Kuyruk-Isler($yazici) {
    $on = $yazici + ","
    return @(Get-CimInstance -ClassName Win32_PrintJob -OperationTimeoutSec 3 -ErrorAction Stop | Where-Object { ([string]$_.Name).StartsWith($on) })
}
function Kuyruk-Say($yazici) { try { return @(Kuyruk-Isler $yazici).Count } catch { return -1 } }
function Kuyruk-Izle($yazici, $once) {
    if ($once -lt 0) { return "kuyruk okunamadi" }
    $gorulen = $false; $durum = ""; $n = 0
    for ($i = 0; $i -lt 4; $i++) {
        $isler = $null
        try { $isler = @(Kuyruk-Isler $yazici) } catch { return "kuyruk okunamadi" }
        $n = $isler.Count
        if ($n -gt 0) { $gorulen = $true; $durum = (($isler | ForEach-Object { ([string]$_.JobStatus) + ([string]$_.Status) } | Select-Object -Unique) -join "; ") }
        if ($durum -match 'Error|Offline|PaperOut|Blocked|UserIntervention|Paused') { return "DIKKAT: is yazici kuyrugunda takili ($durum) - yaziciya bak" }
        if ($gorulen -and $n -eq 0) { return "yazici isi aldi" }
        Start-Sleep -Milliseconds 400
    }
    if ($n -gt 0) { return "is yazici kuyrugunda ($n is; $durum)" }
    if ($gorulen) { return "yazici isi aldi" }
    return "DIKKAT: yazici kuyrugunda is gorulmedi - kagit cikmadiysa yaziciyi ve secili yaziciyi kontrol et"
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
        $tHazirlik = [Math]::Round(((Get-Date) - $bas).TotalSeconds, 1); $tBas = Get-Date
        $p = Start-Process -FilePath $Tarayici -ArgumentList $arg -PassThru -WindowStyle Hidden
        if (-not $p.WaitForExit(90000)) { try { $p.Kill() } catch {} }
        $tTarayici = [Math]::Round(((Get-Date) - $tBas).TotalSeconds, 1)
        # Tarayici kapandiktan sonra dosya en gec birkac saniyede gelir; gelmezse beklemeden oteki denemeye gecilir.
        $son = -1; $yok = 0
        for ($bekle = 0; $bekle -lt 60; $bekle++) {
            if (Test-Path $cikti) {
                $boyut = (Get-Item $cikti).Length
                if ($boyut -gt 800 -and $boyut -eq $son) {
                    $tToplam = [Math]::Round(((Get-Date) - $bas).TotalSeconds, 1)
                    Yaz-Log ("$ne hazir: $tToplam sn (on hazirlik $tHazirlik, tarayici $tTarayici) ($bassiz)")
                    $script:Sure += "sayfa $tToplam sn (tarayici $tTarayici); " 
                    return $true
                }
                $son = $boyut
            } else { $yok++; if ($yok -ge 32) { break } }      # 8 sn icinde dosya hic olusmadi
            Start-Sleep -Milliseconds 250
        }
        Yaz-Log "UYARI: $bassiz ile $ne olusmadi (tarayici cikis kodu: $($p.ExitCode))."
    }
    return $false
}
# >>> HIZLI YOL: hazir bekleyen tarayici
# Tarayici her is icin bastan acilmaz: program acilirken bir kez (gorunmez) baslatilir ve acik kalir.
# Is gelince yeni bir sekmede etiket sayfasi acilir; isin verisi sayfaya dogrudan verilir (sayfa sunucuya
# tekrar sormaz), sayfa hazir olunca goruntu / PDF yine bu baglantidan alinir. Bir sey ters giderse
# program o is icin kendiliginden eski yola (tarayiciyi bastan acma) doner.
$CdpPort = 9333
$script:CdpNo = 0
if (-not (Test-Path variable:TarayiciEk)) { $TarayiciEk = @() }   # yalnizca deneme ortami icin ek bayraklar
function Cdp-Http($yol, $metot) {
    $wc = New-Object System.Net.WebClient
    $wc.Proxy = $null
    $wc.Encoding = [Text.Encoding]::UTF8
    try {
        if ($metot -eq "PUT") { return $wc.UploadString("http://127.0.0.1:$CdpPort$yol", "PUT", "") }
        return $wc.DownloadString("http://127.0.0.1:$CdpPort$yol")
    } finally { $wc.Dispose() }
}
function Cdp-Hazir { try { [void](Cdp-Http "/json/version" "GET"); return $true } catch { return $false } }
function Cdp-Baslat {
    if (Cdp-Hazir) { return $true }
    Eski-Tarayicilari-Kapat
    $arg = @("--headless=new", "--remote-debugging-port=$CdpPort", "--remote-allow-origins=*", "--disable-gpu", "--no-first-run", "--do-not-de-elevate",
             "--no-default-browser-check", "--disable-extensions", "--disable-sync", "--disable-component-update", "--hide-scrollbars",
             "--force-device-scale-factor=1", "--disable-lcd-text", "--user-data-dir=$Profil") + $TarayiciEk + @("about:blank")
    [void](Start-Process -FilePath $Tarayici -ArgumentList $arg -PassThru -WindowStyle Hidden)
    for ($i = 0; $i -lt 80; $i++) { Start-Sleep -Milliseconds 250; if (Cdp-Hazir) { Yaz-Log "Tarayici hazir bekliyor (hizli yol)."; return $true } }
    return $false
}
function Cdp-Kapat { Eski-Tarayicilari-Kapat }
# Komutu gonderir, AYNI numarali yaniti bekler (aradaki olay bildirimleri atlanir). Yanit ham metin olarak doner.
function Cdp-Gonder($ws, $metot, $param, $zamanSn) {
    $script:CdpNo++
    $no = $script:CdpNo
    $govde = (@{ id = $no; method = $metot; params = $param } | ConvertTo-Json -Compress -Depth 8)
    $bayt = [Text.Encoding]::UTF8.GetBytes($govde)
    $seg = New-Object 'System.ArraySegment[byte]' -ArgumentList @(, $bayt)
    [void]$ws.SendAsync($seg, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, [Threading.CancellationToken]::None).GetAwaiter().GetResult()
    $son = (Get-Date).AddSeconds($zamanSn)
    $tampon = New-Object byte[] 262144
    $tseg = New-Object 'System.ArraySegment[byte]' -ArgumentList @(, $tampon)
    while ((Get-Date) -lt $son) {
        $ms = New-Object System.IO.MemoryStream
        do {
            $kalan = [int](($son - (Get-Date)).TotalMilliseconds) + 500
            $iptal = New-Object Threading.CancellationTokenSource
            $iptal.CancelAfter($kalan)
            $r = $ws.ReceiveAsync($tseg, $iptal.Token).GetAwaiter().GetResult()
            $ms.Write($tampon, 0, $r.Count)
        } while (-not $r.EndOfMessage)
        $metin = [Text.Encoding]::UTF8.GetString($ms.ToArray())
        $ms.Dispose()
        $bas = $metin.Substring(0, [Math]::Min(40, $metin.Length))
        if ($bas -match ('"id":' + $no + '[,}]')) { return $metin }
    }
    throw "tarayici yanit vermedi: $metot"
}
# Yanittaki "data" alanini (base64) dosyaya yazar. Buyuk yanit oldugu icin JSON cozucusu kullanilmaz.
function Cdp-Dosya($metin, $cikti) {
    $i = $metin.IndexOf('"data":"')
    if ($i -lt 0) { throw ("tarayici cikti vermedi: " + $metin.Substring(0, [Math]::Min(200, $metin.Length))) }
    $b = $i + 8; $s = $metin.IndexOf('"', $b)
    [IO.File]::WriteAllBytes($cikti, [Convert]::FromBase64String($metin.Substring($b, $s - $b)))
}
# Sayfayi acar, hazir olmasini bekler, ciktiyi dosyaya yazar. $genPx > 0: etiket goruntusu (PNG); degilse PDF.
# Donus: @{ durum = "ok"; adet = sayfadaki etiket/sayfa sayisi } ya da @{ durum = "hata"; mesaj = ... }
function Cdp-Sayfa($url, $veriJson, $cikti, $genPx, $yukPx, $satirPx) {
    $hedefMetin = $null
    try { $hedefMetin = Cdp-Http "/json/new?about:blank" "PUT" } catch { $hedefMetin = Cdp-Http "/json/new?about:blank" "GET" }
    $hedef = $hedefMetin | ConvertFrom-Json
    $ws = New-Object System.Net.WebSockets.ClientWebSocket
    try {
        [void]$ws.ConnectAsync([Uri]$hedef.webSocketDebuggerUrl, [Threading.CancellationToken]::None).GetAwaiter().GetResult()
        [void](Cdp-Gonder $ws "Page.enable" @{} 10)
        [void](Cdp-Gonder $ws "Page.addScriptToEvaluateOnNewDocument" @{ source = ("window.MK_IS_VERI=" + $veriJson + ";") } 10)
        if ($genPx -gt 0) { [void](Cdp-Gonder $ws "Emulation.setDeviceMetricsOverride" @{ width = [int]$genPx; height = [int]$yukPx; deviceScaleFactor = 1; mobile = $false } 10) }
        [void](Cdp-Gonder $ws "Page.navigate" @{ url = $url } 30)
        $baslik = ""; $adet = 0
        $son = (Get-Date).AddSeconds(40)
        while ((Get-Date) -lt $son) {
            Start-Sleep -Milliseconds 120
            $y = Cdp-Gonder $ws "Runtime.evaluate" @{ expression = "document.title + '|' + document.querySelectorAll('#baski .sayfa').length"; returnByValue = $true } 10
            $deger = $null
            try { $deger = [string](($y | ConvertFrom-Json).result.result.value) } catch { $deger = $null }
            if (-not $deger) { continue }
            if ($deger.StartsWith("HAZIR") -or $deger.StartsWith("HATA")) {
                $k = $deger.LastIndexOf("|")
                $baslik = $deger.Substring(0, $k); $adet = [int]$deger.Substring($k + 1)
                break
            }
        }
        if (-not $baslik) { throw "sayfa 40 saniyede hazir olmadi" }
        if ($baslik.StartsWith("HATA")) { return @{ durum = "hata"; mesaj = $baslik.Substring(4).Trim() } }
        if ($genPx -gt 0) {
            if ($adet -gt 0) {
                $y = Cdp-Gonder $ws "Page.captureScreenshot" @{ format = "png"; captureBeyondViewport = $true; clip = @{ x = 0; y = 0; width = [int]$genPx; height = [int]($adet * $satirPx); scale = 1 } } 60
                Cdp-Dosya $y $cikti
            }
        } else {
            $y = Cdp-Gonder $ws "Page.printToPDF" @{ printBackground = $true; preferCSSPageSize = $true; displayHeaderFooter = $false; marginTop = 0; marginBottom = 0; marginLeft = 0; marginRight = 0 } 90
            Cdp-Dosya $y $cikti
        }
        return @{ durum = "ok"; adet = $adet }
    } finally {
        try { $ws.Dispose() } catch {}
        try { [void](Cdp-Http ("/json/close/" + $hedef.id) "GET") } catch {}
    }
}
# Is icin sayfayi hizli yoldan hazirlar. Donus durumu: "ok" (dosya yazildi), "hata" (sayfa isi reddetti), "yok" (hizli yol kullanilamadi).
function Hizli-Sayfa($is, $id, $cikti, $parca, $genPx, $yukPx) {
    if (-not $is.veri) { return @{ durum = "yok" } }
    $bas = Get-Date
    try {
        if (Test-Path $cikti) { Remove-Item $cikti -Force }
        if (-not (Cdp-Baslat)) { throw "tarayici baslatilamadi" }
        $url = $SayfaUrl + "?is=" + $id + "&anahtar=" + [uri]::EscapeDataString($Anahtar)
        if ($parca -ge 0) { $url += "&goruntu=1&parca=" + $parca }
        $url += "&t=" + (Get-Date).Ticks
        $s = Cdp-Sayfa $url ([string]$is.veri) $cikti $genPx $yukPx ([int]($yukPx / $ZebraParcaBoy))
        $sn = [Math]::Round(((Get-Date) - $bas).TotalSeconds, 1)
        if ($s.durum -eq "ok") { Yaz-Log "Sayfa hazir (hizli yol): $sn sn"; $script:Sure += "sayfa $sn sn (hizli yol); " }
        return $s
    } catch {
        Yaz-Log "UYARI: hizli yol calismadi, eski yola geciliyor: $($_.Exception.Message)"
        try { Cdp-Kapat } catch {}
        return @{ durum = "yok" }
    }
}
# <<< HIZLI YOL

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
    $toplam = 0; $hizli = $true
    for ($parca = 0; $parca -lt 50; $parca++) {
        $png = Join-Path $IsKlasoru ($id + "-" + $parca + ".png")
        $hz = @{ durum = "yok" }
        if ($hizli) { $hz = Hizli-Sayfa $is $id $png $parca $genPx $yukPx }
        if ($hz.durum -eq "hata") { Bitti $id "hata" $hz.mesaj; Yaz-Log "Is basilmadi: sayfa hata bildirdi: $($hz.mesaj)"; return }
        if ($hz.durum -eq "ok") {
            if ($hz.adet -eq 0) { break }      # bu parcada etiket yok
        } else {
        $hizli = $false
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
        }
        try { $n = [int](Zebra-Bas $png $yazici $w $h) }
        catch { Bitti $id "hata" ("Yazici isi kabul etmedi: " + $_.Exception.Message); Yaz-Log "HATA: Zebra baski: $($_.Exception.Message)"; return }
        $toplam += $n
        if ($n -lt $ZebraParcaBoy) { break }
    }
    if ($toplam -eq 0) { Bitti $id "hata" "Etiket goruntusu bos cikti"; Yaz-Log "HATA: goruntude etiket yok."; return }
    Bitti $id "basildi" (Sure-Ozeti)
    Yaz-Log "Yaziciya gonderildi: $id (rulo etiket, $toplam adet)"
}

function Bas($is) {
    $id = [string]$is.id
    $yazici = [string]$is.windowsAdi
    $bicim = [string]$is.bicim
    $pdf = Join-Path $IsKlasoru ($id + ".pdf")
    $script:IsBas = Get-Date; $script:Sure = ""
    Yaz-Log "Is alindi: $id ($bicim) -> $yazici"

    if (-not (Yazici-Adlari | Where-Object { $_ -eq $yazici })) { Bitti $id "hata" "Yazici bu bilgisayarda bulunamadi: $yazici"; Yaz-Log "HATA: yazici yok: $yazici"; return }
    $wd = (Yazici-Durumlari)[$yazici]
    if ($wd) { Yaz-Log "UYARI: Windows bu yaziciyi '$wd' gosteriyor: $yazici (is yine de gonderiliyor)" }
    if ($bicim -eq "zebra") { Zebra-Is $is $id $yazici; return }
    Yaz-Log "Sayfa hazirlaniyor..."
    $hz = Hizli-Sayfa $is $id $pdf -1 0 0
    if ($hz.durum -eq "hata") { Bitti $id "hata" $hz.mesaj; Yaz-Log "Is basilmadi: sayfa hata bildirdi: $($hz.mesaj)"; return }
    if ($hz.durum -ne "ok") {
    if (-not (Pdf-Uret $id $pdf)) { Bitti $id "hata" "Etiket sayfasi hazirlanamadi (tarayici/Internet)"; Yaz-Log "HATA: PDF uretilemedi."; return }

    # Sayfa etiketleri cizemediyse isi kendisi "hata" yapar; o zaman bos kagit basilmaz.
    # Sunucuya ulasilamazsa is "basiliyor"da takili kalmasin: uc kez denenir, olmazsa hata olarak bildirilir.
    $k = $null
    for ($d = 1; $d -le 3 -and -not $k; $d++) {
        try { $k = Sor @{ action = "baski_ajan_bitti"; anahtar = $Anahtar; id = $id; durum = "kontrol" } } catch { $k = $null; Start-Sleep -Seconds 4 }
    }
    if (-not $k) { Yaz-Log "HATA: basmadan onceki kontrol icin sunucuya ulasilamadi."; Bitti $id "hata" "Baski programi sunucuya ulasamadi - yeniden gonder"; return }
    if ($k.status -ne "ok") { Yaz-Log "Is basilmadi: sayfa hata bildirdi ya da is iptal edildi."; return }

    }

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

    $pdfKb = 0; try { $pdfKb = [Math]::Round((Get-Item $pdf).Length / 1KB) } catch {}
    if ($pdfKb -lt 1) { Bitti $id "hata" "Etiket dosyasi bos olustu - yeniden gonder"; Yaz-Log "HATA: PDF bos ($pdf)."; return }
    Yaz-Log "Yaziciya veriliyor: $yazici ($kagit, PDF $pdfKb KB)..."
    $yBas = Get-Date
    $p = Start-Process -FilePath $Sumatra -ArgumentList @("-print-to", "`"$yazici`"", "-print-settings", "`"$ayar`"", "-silent", "`"$pdf`"") -PassThru -WindowStyle Hidden
    if (-not $p.WaitForExit(60000)) { try { $p.Kill() } catch {}; Bitti $id "hata" "Yazici 60 sn icinde isi almadi (SumatraPDF cevap vermedi) - yaziciyi kontrol edip yeniden gonder"; Yaz-Log "HATA: SumatraPDF 60 sn zaman asimi."; return }
    Yaz-Log "SumatraPDF bitti (kod $($p.ExitCode)), kuyruga bakiliyor..." 
    if ($p.ExitCode -ne 0) { Bitti $id "hata" "Yazici isi kabul etmedi (kod $($p.ExitCode))"; Yaz-Log "HATA: SumatraPDF cikis kodu $($p.ExitCode)."; return }

    # Sonuc HEMEN bildirilir (telefondaki sayac durur); kuyruk kontrolu sadece kayit icindir, telefonu bekletmez.
    Bitti $id "basildi" (Sure-Ozeti)
    $kNot = Kuyruk-Izle $yazici 0
    Yaz-Log "Yazici kuyrugu: $kNot (PDF $pdfKb KB)"
    Yaz-Log ("Yaziciya gonderildi: $id ($kagit) - yaziciya verme " + [Math]::Round(((Get-Date) - $yBas).TotalSeconds, 1) + " sn")
}

Yaz-Log "Baski programi basladi (surum $AjanSurum). Bilgisayar: $env:COMPUTERNAME, tarayici: $Tarayici"
Yaz-Log ("Yazicilar: " + ((Yazici-Adlari) -join " | "))
try { [void](Cdp-Baslat) } catch { Yaz-Log "UYARI: tarayici onceden baslatilamadi: $($_.Exception.Message)" }
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
