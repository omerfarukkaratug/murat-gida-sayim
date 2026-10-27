# =====================================================================
#  KRT Saha - TELEFON -> ERP AKTARIMI BASTAN SONA TANI
#  Zincir:  telefon -> KRT Saha sunucusu -> bulut veri tabani -> bu bilgisayardaki program -> ERP12
#  Bu program zincirin bu bilgisayardan gorunen her halkasina bakar ve SONUC'ta sorunun nerede
#  oldugunu yazar. Rapor ayrica C:\Scripts\tani-rapor.txt dosyasina kaydedilir.
#  ERP verisini DEGISTIRMEZ. (Bekleyen belge varsa 5. adimda aktarim programini bir kez normal
#  sekilde calistirir - gorevin zaten her dakika yaptigi is.)
# =====================================================================
$DbUrl   = "https://wjyqempcmyrmruhdpcwk.supabase.co"
$Anahtar = "C:\Scripts\db-anahtar.txt"
$Gorev   = "MK Saha ERP Aktarim"
$Log     = "C:\Scripts\siparis-aktar-log.txt"
$Rapor   = "C:\Scripts\tani-rapor.txt"
$Program = "C:\Scripts\siparis-aktar.ps1"
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}
$satirlar = New-Object System.Collections.ArrayList
$sonuc = New-Object System.Collections.ArrayList
function Y($m) { Write-Host $m; [void]$satirlar.Add([string]$m) }
function Sonuc($m) { [void]$sonuc.Add([string]$m) }
function Rpc($fn, $govde) {
    $k = (Get-Content -Path $Anahtar -TotalCount 1).Trim()
    $b = [Text.Encoding]::UTF8.GetBytes(($govde | ConvertTo-Json -Depth 5 -Compress))
    return Invoke-RestMethod -Uri "$DbUrl/rest/v1/rpc/$fn" -Method Post -Body $b -ContentType "application/json; charset=utf-8" -Headers @{ apikey = $k } -TimeoutSec 60 -UserAgent "MK-Sayim/1.0"
}
Y ("KRT Saha tani - " + (Get-Date -Format "yyyy-MM-dd HH:mm:ss") + " - " + $env:COMPUTERNAME)

# ---------- 1) BULUT ----------
Y ""; Y "=== 1) BULUT VERI TABANI ==="
$bulutOk = $false; $bekleyenSayi = -1; $durum = $null
if (-not (Test-Path $Anahtar)) { Y "HATA: $Anahtar yok"; Sonuc "db-anahtar.txt yok: program buluta baglanamaz." }
else {
    try {
        $durum = Rpc "erp_aktarim_durum" @{ p_gun = 2 }
        $bulutOk = $true
        $n = $durum.nabiz
        if ($n) { Y ("Programin son haberi: {0} dk once ({1})" -f $n.dk, $n.mesaj) } else { Y "Programdan hic haber yok (nabiz)" }
        $o = $durum.ozet
        Y ("Son 2 gun: {0} aktarildi, {1} bekliyor, {2} hata, {3} degisti" -f $o.ok, $o.bekliyor, $o.hata, $o.degisti)
        foreach ($r in (@($durum.belgeler) | Select-Object -First 15)) {
            Y ("  [{0}] {1} / {2} / {3} / {4} {5}" -f $r[5], $r[4], $r[1], $r[2], $r[6], $(if ($r[7]) { "- " + $r[7] } else { "" }))
        }
    } catch { Y "HATA: bulut cevap vermedi: $($_.Exception.Message)"; Sonuc "BULUTA ULASILAMIYOR (internet / guvenlik duvari / bulut). Hata: $($_.Exception.Message)" }
    if ($bulutOk) {
        try { [void](Rpc "erp_nabiz_yaz" @{ p_ad = "tani"; p_mesaj = "tani $env:COMPUTERNAME"; p_baslangic = $null }); Y "Buluta yazma: CALISIYOR" }
        catch { Y "HATA: buluta YAZILAMIYOR: $($_.Exception.Message)"; Sonuc "Bulut veri tabani yazmaya KAPALI (dolu / salt okunur olabilir): $($_.Exception.Message)" }
        try {
            $is = Rpc "aktarilacak_mal" @{ p_baslangic = "2026-10-21T00:00:00+03:00"; p_bekle_dk = 0; p_limit = 50 }
            $bekleyenSayi = @($is.belgeler | Where-Object { $_ }).Count
            Y ("Programin alacagi (aktarilacak) belge: {0}" -f $bekleyenSayi)
            foreach ($b in (@($is.belgeler | Where-Object { $_ }) | Select-Object -First 10)) { Y ("  - {0} / {1} / {2} satir / {3}" -f $b.belge_turu, $b.cari, @($b.satirlar).Count, $b.tarih) }
        } catch { Y "HATA: aktarilacak liste alinamadi: $($_.Exception.Message)"; Sonuc "Bulutta 'aktarilacak_mal' calismiyor: $($_.Exception.Message)" }
    }
}

# ---------- 2) GOREV ----------
Y ""; Y "=== 2) GOREV ZAMANLAYICI ==="
$g = Get-ScheduledTask -TaskName $Gorev -ErrorAction SilentlyContinue
$gorevGec = $false
if (-not $g) { Y "GOREV YOK"; Sonuc "'$Gorev' gorevi YOK - MAL-ERP-GOREV.bat ile kurulup ERP-AKTARIM-KONTROL.bat calistirilmali." }
else {
    $i = Get-ScheduledTaskInfo -TaskName $Gorev -TaskPath $g.TaskPath
    $kod = [uint32]$i.LastTaskResult
    Y ("Durum {0} | hesap {1} ({2}) | son {3} | sonuc 0x{4:X} | sonraki {5} | kacirilan {6}" -f $g.State, $g.Principal.UserId, $g.Principal.LogonType, $i.LastRunTime, $kod, $i.NextRunTime, $i.NumberOfMissedRuns)
    Y ("Sure siniri {0} | ayni anda {1} | pil {2}/{3}" -f $g.Settings.ExecutionTimeLimit, $g.Settings.MultipleInstances, $g.Settings.DisallowStartIfOnBatteries, $g.Settings.StopIfGoingOnBatteries)
    foreach ($e in $g.Actions) { Y ("Eylem: {0} {1}" -f $e.Execute, $e.Arguments) }
    foreach ($t in $g.Triggers) {
        $rep = $t.Repetition
        Y ("Tetik: {0} acik={1} baslangic={2} bitis={3} tekrar={4} sure={5}" -f $t.CimClass.CimClassName, $t.Enabled, $t.StartBoundary, $t.EndBoundary, $rep.Interval, $rep.Duration)
        if ($t.EndBoundary -and ([datetime]$t.EndBoundary) -lt (Get-Date)) { Sonuc "Gorevin tetiginin BITIS tarihi gecmis ($($t.EndBoundary)) - tetik yenilenmeli." }
        if ($rep.Duration -and $rep.Duration -ne "" -and $t.StartBoundary) {
            try { $sonTekrar = ([datetime]$t.StartBoundary) + [Xml.XmlConvert]::ToTimeSpan($rep.Duration); if ($sonTekrar -lt (Get-Date)) { Sonuc "Gorevin 'her dakika tekrarla' suresi $sonTekrar tarihinde BITMIS - gorev bu yuzden calismiyor olabilir." } } catch {}
        }
    }
    if ($g.State -eq "Disabled") { Sonuc "Gorev KAPALI (Disabled)." }
    $dk = if ($i.LastRunTime) { [int]((Get-Date) - $i.LastRunTime).TotalMinutes } else { 99999 }
    if ($dk -gt 3) { $gorevGec = $true; Y "UYARI: gorev $dk dakikadir calismamis" }
    if ($kod -eq 2147943726) { Sonuc "Gorev OTURUM ACAMIYOR: Windows sifresi degismis - GOREVLERI-OTURUMSUZ.bat / ERP-AKTARIM-KONTROL.bat yeniden calistirilmali." }
    # Gorev gecmisi (acik ise)
    try {
        $olay = @(Get-WinEvent -FilterHashtable @{ LogName = "Microsoft-Windows-TaskScheduler/Operational"; StartTime = (Get-Date).AddHours(-30) } -ErrorAction Stop |
            Where-Object { $_.Message -like "*$Gorev*" -and $_.Id -in 101, 103, 111, 203, 322, 329, 332 } | Select-Object -First 12)
        if ($olay.Count) { Y "Gorev olaylari (hata / atlama / zaman asimi):"; foreach ($x in $olay) { Y ("  {0} id {1}: {2}" -f $x.TimeCreated, $x.Id, (($x.Message -split "`n")[0]).Trim()) } }
        else { Y "Son 30 saatte gorev hatasi / atlamasi yok (ya da gorev gecmisi kapali)." }
    } catch { Y "Gorev gecmisi okunamadi (Gorev Zamanlayici'da 'Tum gorevler gecmisini etkinlestir' kapali olabilir)." }
}

# ---------- 3) BILGISAYAR ----------
Y ""; Y "=== 3) BILGISAYAR (uyku / kapanma / yeniden baslama, son 30 saat) ==="
try { $os = Get-CimInstance Win32_OperatingSystem; Y ("Son acilis: {0}" -f $os.LastBootUpTime) } catch {}
try {
    $p = @(Get-WinEvent -FilterHashtable @{ LogName = "System"; StartTime = (Get-Date).AddHours(-30) } -ErrorAction Stop |
        Where-Object { ($_.ProviderName -eq "Microsoft-Windows-Kernel-Power" -and $_.Id -in 41, 42, 107, 506, 507) -or ($_.ProviderName -eq "Microsoft-Windows-Power-Troubleshooter" -and $_.Id -eq 1) -or ($_.Id -in 1074, 6006, 6008) } | Select-Object -First 15)
    if ($p.Count) {
        foreach ($x in $p) { Y ("  {0} {1} id {2}: {3}" -f $x.TimeCreated, $x.ProviderName, $x.Id, (($x.Message -split "`n")[0]).Trim()) }
        if (@($p | Where-Object { $_.Id -in 42, 506 }).Count) { Sonuc "Bilgisayar son 30 saatte UYKUYA GECMIS - uyurken gorev calismaz. Guc ayarlarinda uyku 'Hicbir zaman' yapilmali." }
        if (@($p | Where-Object { $_.Id -in 41, 6008 }).Count) { Sonuc "Bilgisayar beklenmedik sekilde KAPANMIS (elektrik / donma)." }
    } else { Y "  Uyku / kapanma kaydi yok." }
} catch { Y "Olay gunlugu okunamadi: $($_.Exception.Message)" }
try { $u = (powercfg /query SCHEME_CURRENT SUB_SLEEP STANDBYIDLE) -join " "; if ($u -match "Current AC Power Setting Index:\s*0x([0-9a-f]+)") { $sn = [Convert]::ToInt32($Matches[1], 16); Y ("Uyku (prizde): {0}" -f $(if ($sn -eq 0) { "kapali (iyi)" } else { "$([int]($sn/60)) dk sonra uyur" })); if ($sn -gt 0) { Sonuc "Bilgisayar $([int]($sn/60)) dk islem yapilmazsa UYKUYA geciyor - uyku 'Hicbir zaman' yapilmali." } } } catch {}

# ---------- 4) LOG ----------
Y ""; Y "=== 4) AKTARIM LOGU (son 30 satir) ==="
if (Test-Path $Log) { Get-Content $Log -Tail 30 | ForEach-Object { Y ("  " + $_) } } else { Y "  $Log yok" }

# ---------- 5) SIMDI BIR TUR ----------
if ($bekleyenSayi -gt 0) {
    Y ""; Y "=== 5) AKTARIM PROGRAMI SIMDI BIR KEZ CALISTIRILIYOR ($bekleyenSayi belge bekliyor) ==="
    $cikti = Join-Path $env:TEMP "tani-tur.txt"
    $pr = Start-Process -FilePath "powershell.exe" -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$Program`"") -RedirectStandardOutput $cikti -RedirectStandardError ($cikti + ".err") -WindowStyle Hidden -PassThru
    if (-not $pr.WaitForExit(240000)) { try { $pr.Kill() } catch {}; Y "  4 dakikada BITMEDI - program bir yerde TAKILIYOR"; Sonuc "Aktarim programi tek bir turda 4 dakikadan uzun takiliyor (SQL kilidi / ERP'de acik belge / ag)." }
    foreach ($f in @($cikti, ($cikti + ".err"))) { if (Test-Path $f) { Get-Content $f | Select-Object -Last 25 | ForEach-Object { Y ("  " + $_) } } }
    try {
        $is2 = Rpc "aktarilacak_mal" @{ p_baslangic = "2026-10-21T00:00:00+03:00"; p_bekle_dk = 0; p_limit = 50 }
        $kalan = @($is2.belgeler | Where-Object { $_ }).Count
        Y ("Calistiktan sonra bekleyen: {0}" -f $kalan)
        if ($kalan -lt $bekleyenSayi) { if ($gorevGec) { Sonuc "Program elle calisinca belgeler AKTARILDI -> program saglam, sorun GOREVIN calismamasinda (yukaridaki gorev bilgisine bak)." } else { Y "Belgeler aktarildi." } }
        elseif ($kalan -gt 0) { Sonuc "Program calisti ama belgeler AKTARILAMADI -> sebep yukaridaki program ciktisinda / logda (stok karti, cari, ERP hatasi)." }
    } catch {}
}

# ---------- SONUC ----------
Y ""; Y "================ SONUC ================"
if ($bulutOk -and $bekleyenSayi -eq 0 -and -not $sonuc.Count) {
    Sonuc "Bu bilgisayar tarafinda SORUN YOK: bulutta aktarilmayi bekleyen belge yok. Telefonda kaydedilen belge ERP'ye gitmediyse belge BULUTA HIC ULASMAMIS demektir -> sorun KRT Saha sunucusunda (telefonda Irsaliyeler ekraninda 'Buluta gitmedi' yazar; sunucuda 'krtsaha guncelle' yapilmis olmali)."
}
if ($bulutOk -and $bekleyenSayi -gt 0 -and $gorevGec -and -not $sonuc.Count) { Sonuc "Bulutta bekleyen belge var ama gorev son dakikalarda calismamis - gorev bilgisine bak." }
foreach ($s in $sonuc) { Y ("* " + $s) }
try { $satirlar | Set-Content -Path $Rapor -Encoding UTF8; Write-Host ""; Write-Host "Rapor kaydedildi: $Rapor" } catch {}
