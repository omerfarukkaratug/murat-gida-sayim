# =====================================================================
#  KRT Saha - "MK Saha ERP Aktarim" gorevini SAGLAM sekilde YENIDEN KURAR.
#  - Gorev artik aktarim-dongu.ps1'i calistirir: bir kez baslar, surekli calisir (her dakika
#    yeniden baslatilmaya muhtac degil - "kacirilan calisma" sorunu biter).
#  - Bilgisayar acilinca baslar; dongu kapanirsa en gec 5 dakikada yeniden baslar
#    (gece 00:00'dan itibaren 5 dakikada bir kontrol; zaten calisiyorsa yeni kopya acilmaz).
#  - Oturum acik olmasa da calisir (Windows sifresi burada sorulur, hicbir yere gonderilmez).
#  - Gorev gecmisi (Tum gorevler gecmisi) acilir: bir daha sorun olursa sebebi gorulur.
#  ERP verisine DOKUNMAZ.
# =====================================================================
$Ad    = "MK Saha ERP Aktarim"
$Dongu = "C:\Scripts\aktarim-dongu.ps1"
try {
    if (-not (Test-Path $Dongu)) { throw "$Dongu yok - once bu dosyayi C:\Scripts icine koyun." }
    if (-not (Test-Path "C:\Scripts\siparis-aktar.ps1")) { throw "C:\Scripts\siparis-aktar.ps1 yok." }
    $kullanici = "$env:COMPUTERNAME\$env:USERNAME"
    $gs = Read-Host "Bu Windows hesabinin ($kullanici) sifresini yazin (ekranda gorunmez)" -AsSecureString
    $sifre = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($gs))
    if (-not $sifre) { throw "Sifre bos." }

    # Gorev gecmisini ac (sorun olursa Olay Goruntuleyici'de sebep yazsin)
    try { wevtutil set-log Microsoft-Windows-TaskScheduler/Operational /enabled:true | Out-Null; Write-Host "Gorev gecmisi acildi." } catch {}

    # Eski gorevi ve calisan kopyalarini durdur
    $eski = Get-ScheduledTask -TaskName $Ad -ErrorAction SilentlyContinue
    if ($eski) { try { Stop-ScheduledTask -TaskName $Ad -TaskPath $eski.TaskPath -ErrorAction SilentlyContinue } catch {}; Unregister-ScheduledTask -TaskName $Ad -TaskPath $eski.TaskPath -Confirm:$false; Write-Host "Eski gorev kaldirildi." }
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='wscript.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like "*aktarim-dongu.ps1*" -or ($_.CommandLine -like "*siparis-aktar.ps1*" -and $_.CommandLine -like "*DONGU*") } |
        ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force -ErrorAction Stop; Write-Host "Eski calisan kopya kapatildi (PID $($_.ProcessId))" } catch {} }

    $eylem = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Dongu`"" -WorkingDirectory "C:\Scripts"
    $t1 = New-ScheduledTaskTrigger -AtStartup
    $t2 = New-ScheduledTaskTrigger -Daily -At "00:00"
    $t2.Repetition = (New-ScheduledTaskTrigger -Once -At "00:00" -RepetitionInterval (New-TimeSpan -Minutes 5) -RepetitionDuration (New-TimeSpan -Hours 23 -Minutes 59)).Repetition
    $ayar = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew `
        -ExecutionTimeLimit (New-TimeSpan -Seconds 0) -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1)
    Register-ScheduledTask -TaskName $Ad -Action $eylem -Trigger @($t1, $t2) -Settings $ayar -User $kullanici -Password $sifre -RunLevel Highest `
        -Description "KRT Saha: telefondan gelen irsaliyeleri ERP'ye aktaran surekli dongu (aktarim-dongu.ps1)" -ErrorAction Stop | Out-Null
    $sifre = $null
    Write-Host "TAMAM: gorev kuruldu (acilista + 5 dakikada bir kontrol, surekli dongu)."
    Start-ScheduledTask -TaskName $Ad
    Write-Host "Baslatildi, 30 saniye bekleniyor..."
    Start-Sleep -Seconds 30
    $i = Get-ScheduledTaskInfo -TaskName $Ad
    Write-Host ("Durum: {0} | son baslama {1}" -f (Get-ScheduledTask -TaskName $Ad).State, $i.LastRunTime)
    $calisan = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -like "*aktarim-dongu.ps1*" })
    if ($calisan.Count) { Write-Host "Dongu CALISIYOR (PID $($calisan[0].ProcessId))." } else { Write-Host "UYARI: dongu calismiyor gorunuyor - C:\Scripts\aktarim-dongu-log.txt dosyasina bakin." }
    if (Test-Path "C:\Scripts\aktarim-dongu-log.txt") { Write-Host ""; Write-Host "aktarim-dongu-log.txt (son satirlar):"; Get-Content "C:\Scripts\aktarim-dongu-log.txt" -Tail 5 }
} catch {
    Write-Host ""
    Write-Host "HATA: $($_.Exception.Message)"
    Write-Host "Sifre yanlis olabilir ya da bu dosya 'Yonetici olarak calistir' ile acilmamistir."
}
