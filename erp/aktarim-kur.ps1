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

    # Gorev XML ile kurulur: eski Windows surumlerinde (2012) tetik nesnesinin "Repetition" ozelligi yok.
    $baslangic = (Get-Date).ToString("yyyy-MM-dd") + "T00:00:00"
    $arg = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File &quot;$Dongu&quot;"
    $xml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo><Description>KRT Saha: telefondan gelen irsaliyeleri ERP'ye aktaran surekli dongu (aktarim-dongu.ps1)</Description></RegistrationInfo>
  <Triggers>
    <BootTrigger><Enabled>true</Enabled></BootTrigger>
    <CalendarTrigger>
      <Repetition><Interval>PT5M</Interval><Duration>P1D</Duration><StopAtDurationEnd>false</StopAtDurationEnd></Repetition>
      <StartBoundary>$baslangic</StartBoundary><Enabled>true</Enabled>
      <ScheduleByDay><DaysInterval>1</DaysInterval></ScheduleByDay>
    </CalendarTrigger>
  </Triggers>
  <Principals><Principal id="Author"><UserId>$kullanici</UserId><LogonType>Password</LogonType><RunLevel>HighestAvailable</RunLevel></Principal></Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <IdleSettings><StopOnIdleEnd>false</StopOnIdleEnd><RestartOnIdle>false</RestartOnIdle></IdleSettings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>
    <Priority>7</Priority>
    <RestartOnFailure><Interval>PT1M</Interval><Count>999</Count></RestartOnFailure>
  </Settings>
  <Actions Context="Author"><Exec><Command>powershell.exe</Command><Arguments>$arg</Arguments><WorkingDirectory>C:\Scripts</WorkingDirectory></Exec></Actions>
</Task>
"@
    try {
        Register-ScheduledTask -TaskName $Ad -Xml $xml -User $kullanici -Password $sifre -ErrorAction Stop | Out-Null
    } catch {
        # Gorev kurulamazsa aktarim yine de SIMDI baslasin (oturum acik kaldikca calisir)
        Start-Process -FilePath "powershell.exe" -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File", "`"$Dongu`"") -WindowStyle Hidden
        throw ("Gorev kurulamadi: " + $_.Exception.Message + " -- aktarim dongusu GECICI olarak bu oturumda baslatildi (oturum kapanirsa durur).")
    }
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
