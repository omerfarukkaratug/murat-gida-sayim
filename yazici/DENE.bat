@echo off
rem Baski programini GORUNUR pencerede calistirir (sorun ararken). Arka planda gorunmez calisan kopya once kapatilir.
rem Is bitince gorunmez calismaya donmek icin OTOMATIK-BASLAT.bat'a cift tikla (ya da bilgisayari yeniden baslat).
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Get-CimInstance Win32_Process | Where-Object { $_.ProcessId -ne $PID -and (($_.Name -eq 'cmd.exe' -and $_.CommandLine -like '*CALISTIR.bat*') -or ($_.Name -eq 'powershell.exe' -and $_.CommandLine -like '*baski-ajani.ps1*')) } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0baski-ajani.ps1"
echo.
echo Program durdu. Yukaridaki yaziya bak. Gorunmez calismaya donmek icin OTOMATIK-BASLAT.bat. Kapatmak icin bir tusa bas.
pause >nul
