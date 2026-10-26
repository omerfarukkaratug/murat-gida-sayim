# =====================================================================
#  KRT Saha - "MK Saha ERP Aktarim" gorevi neden calismiyor? Bakar ve DUZELTIR.
#  1) Gorevin durumu: acik mi, en son ne zaman calisti, sonuc kodu ne, bir sonraki ne zaman.
#  2) Takili kalmis (10 dakikadan uzun suredir calisan) siparis-aktar.ps1 var mi? Varsa kapatir.
#     (Gorev ayari "onceki calisiyorsa yenisini baslatma" oldugu icin takili bir kopya
#      butun sonraki calismalari engeller.)
#  3) Gorevi simdi baslatir.
#  4) "AYAR" ile calistirilirsa: gorevler gizli-calistir.vbs olmadan dogrudan PowerShell ile calisir,
#     ERP aktarimi en fazla 10 dakika calisir (takilirsa Windows kapatir). Windows sifresi burada
#     sorulur, hicbir yere gonderilmez.
#  ERP verisine DOKUNMAZ.
# =====================================================================
$Gorev   = "MK Saha ERP Aktarim"
$Log     = "C:\Scripts\siparis-aktar-log.txt"
$Ayarla  = $args -contains "AYAR"

function Kod-Aciklama($k) {
    switch ($k) {
        0          { return "basarili" }
        267009     { return "su an calisiyor" }
        267011     { return "hic calismadi" }
        267014     { return "kullanici tarafindan durduruldu" }
        2147750687 { return "onceki kopya hala calistigi icin baslatilmadi" }
        2147943726 { return "OTURUM ACMA HATASI: Windows sifresi degismis ya da yanlis - GOREVLERI-OTURUMSUZ.bat yeniden calistirilmali" }
        2147942402 { return "dosya bulunamadi (C:\Scripts yolunu kontrol et)" }
        1          { return "program hata ile bitti (log dosyasina bak)" }
        default    { return "" }
    }
}

Write-Host "=== 1) GOREV ==="
$g = Get-ScheduledTask -TaskName $Gorev -ErrorAction SilentlyContinue
if (-not $g) { Write-Host "GOREV YOK: '$Gorev'. MAL-ERP-GOREV.bat ile kurulmali."; exit 1 }
$i = Get-ScheduledTaskInfo -TaskName $Gorev -TaskPath $g.TaskPath
$kod = [uint32]$i.LastTaskResult
Write-Host ("Durum          : {0}" -f $g.State)
Write-Host ("Hesap          : {0} ({1})" -f $g.Principal.UserId, $g.Principal.LogonType)
Write-Host ("Son calisma    : {0}" -f $i.LastRunTime)
Write-Host ("Son sonuc      : {0} (0x{1:X}) {2}" -f $kod, $kod, (Kod-Aciklama $kod))
Write-Host ("Sonraki        : {0}" -f $i.NextRunTime)
Write-Host ("Kacirilan      : {0}" -f $i.NumberOfMissedRuns)
Write-Host ("Sure siniri    : {0}  / Ayni anda: {1}" -f $g.Settings.ExecutionTimeLimit, $g.Settings.MultipleInstances)
if ($g.State -eq "Disabled") {
    Write-Host "Gorev KAPALI idi -> aciliyor."
    try { Enable-ScheduledTask -TaskName $Gorev -TaskPath $g.TaskPath | Out-Null; Write-Host "Gorev acildi." } catch { Write-Host "Acilamadi: $($_.Exception.Message)" }
}

Write-Host ""
Write-Host "=== 2) CALISAN KOPYALAR ==="
$kopyalar = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like "*siparis-aktar.ps1*" })
if (-not $kopyalar.Count) { Write-Host "Calisan siparis-aktar.ps1 yok." }
# gizli-calistir.vbs hata penceresi acarsa (Tamam'a basilmasini bekler) gorev de takili kalir: onlar da kapatilir.
$kopyalar += @(Get-CimInstance Win32_Process -Filter "Name='wscript.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like "*gizli-calistir.vbs*" })
foreach ($p in $kopyalar) {
    $dk = [int]((Get-Date) - $p.CreationDate).TotalMinutes
    Write-Host ("PID {0}: {1} dakikadir calisiyor" -f $p.ProcessId, $dk)
    if ($dk -ge 10) {
        try { Stop-Process -Id $p.ProcessId -Force -ErrorAction Stop; Write-Host "  -> TAKILI KALMISTI, kapatildi." } catch { Write-Host "  -> kapatilamadi: $($_.Exception.Message)" }
    }
}

if ($Ayarla) {
    Write-Host ""
    Write-Host "=== AYAR: gorevler gizli-calistir.vbs OLMADAN, dogrudan PowerShell ile calissin ==="
    Write-Host "(Oturum kapali calisan gorev zaten pencere acmaz; vbs hata verince gorev takiliyordu.)"
    $Gorevler = @("MK Saha ERP Aktarim", "KRT Saha ERP SQL Yedek", "MK Mal Indir", "MK Cari Hareketleri", "MK Urun Hareketleri", "MK Sayim Yerel Kopya", "KRT Saha Yedek Indir")
    try {
        $kullanici = "$env:COMPUTERNAME\$env:USERNAME"
        $gs = Read-Host "Bu Windows hesabinin ($kullanici) sifresini yazin (ekranda gorunmez)" -AsSecureString
        $sifre = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($gs))
        if (-not $sifre) { throw "Sifre bos." }
        foreach ($ad in $Gorevler) {
            $t = Get-ScheduledTask -TaskName $ad -ErrorAction SilentlyContinue
            if (-not $t) { Write-Host "YOK (atlandi): $ad"; continue }
            $yeni = @()
            foreach ($e in $t.Actions) {
                $arg = [string]$e.Arguments
                if ($e.Execute -match "wscript" -and $arg -match 'gizli-calistir\.vbs"?\s+"?([A-Za-z]:\\[^"]+?\.ps1)"?\s*(.*)$') {
                    $dosya = $Matches[1]; $kalan = $Matches[2].Trim()
                    $yeniArg = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $dosya + '"' + $(if ($kalan) { " " + $kalan } else { "" })
                    $yeni += New-ScheduledTaskAction -Execute "powershell.exe" -Argument $yeniArg -WorkingDirectory "C:\Scripts"
                } else { $yeni += $e }
            }
            $s = $t.Settings
            $s.ExecutionTimeLimit = $(if ($ad -eq "MK Saha ERP Aktarim") { "PT10M" } elseif ($ad -like "*Yedek*") { "PT3H" } else { "PT1H" })
            $s.MultipleInstances = "IgnoreNew"
            $s.DisallowStartIfOnBatteries = $false
            $s.StopIfGoingOnBatteries = $false
            try {
                Set-ScheduledTask -TaskName $ad -TaskPath $t.TaskPath -Action $yeni -Settings $s -User $kullanici -Password $sifre -ErrorAction Stop | Out-Null
                Write-Host ("TAMAM: {0} (sure siniri {1})" -f $ad, $s.ExecutionTimeLimit)
            } catch { Write-Host "AYARLANAMADI: $ad - $($_.Exception.Message)" }
        }
        $sifre = $null
    } catch { Write-Host "AYARLANAMADI: $($_.Exception.Message)" }
    $g = Get-ScheduledTask -TaskName $Gorev
}

Write-Host ""
Write-Host "=== 3) GOREV SIMDI BASLATILIYOR ==="
try { Start-ScheduledTask -TaskName $Gorev -TaskPath $g.TaskPath; Write-Host "Baslatildi. 1-2 dakika icinde telefondaki Irsaliyeler ekraninda 'calisiyor' gorunmeli." } catch { Write-Host "Baslatilamadi: $($_.Exception.Message)" }
Start-Sleep -Seconds 25
$i = Get-ScheduledTaskInfo -TaskName $Gorev -TaskPath $g.TaskPath
$kod = [uint32]$i.LastTaskResult
Write-Host ("Simdi: son calisma {0}, sonuc 0x{1:X} {2}" -f $i.LastRunTime, $kod, (Kod-Aciklama $kod))

Write-Host ""
Write-Host "=== 4) LOG (son 25 satir) ==="
if (Test-Path $Log) { Get-Content $Log -Tail 25 } else { Write-Host "$Log yok" }
