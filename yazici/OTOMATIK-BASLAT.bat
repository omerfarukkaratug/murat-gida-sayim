@echo off
rem MK ERP - Baski programi GORUNMEZ calissin (siyah pencere cikmasin) ve bilgisayar acilinca
rem KENDILIGINDEN baslasin diye bir kez cift tiklanir. Yonetici yetkisi gerekmez. C:\MKBaski icinden calistir.
cd /d "%~dp0"
if not exist "%~dp0baski-ajani.ps1" ( echo HATA: Bu dosyayi C:\MKBaski icine kopyalayip oradan calistir. & pause & exit /b 1 )
if not exist "%~dp0CALISTIR.bat" ( echo HATA: CALISTIR.bat ayni klasorde olmali. & pause & exit /b 1 )
if not exist "%~dp0GIZLI-BASLAT.vbs" ( echo HATA: GIZLI-BASLAT.vbs ayni klasorde olmali. & pause & exit /b 1 )
set "BASL=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup"
rem Eski baslaticilar kaldirilir.
schtasks /Delete /TN "MK Baski Programi" /F >nul 2>&1
del "%BASL%\MK Baski Programi.cmd" >nul 2>&1
copy /Y "%~dp0GIZLI-BASLAT.vbs" "%BASL%\MK Baski Programi.vbs" >nul
if not exist "%BASL%\MK Baski Programi.vbs" ( echo HATA: Baslangic klasorune yazilamadi. & pause & exit /b 1 )
echo Acik olan (gorunur) baski programi kapatiliyor...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Get-CimInstance Win32_Process | Where-Object { $_.ProcessId -ne $PID -and (($_.Name -eq 'cmd.exe' -and $_.CommandLine -like '*CALISTIR.bat*') -or ($_.Name -eq 'powershell.exe' -and $_.CommandLine -like '*baski-ajani.ps1*')) } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }"
timeout /t 2 /nobreak >nul
echo Gorunmez olarak baslatiliyor...
wscript.exe "%~dp0GIZLI-BASLAT.vbs"
echo.
echo Tamam: baski programi artik ekranda pencere gostermeden calisiyor.
echo Bilgisayar acilip oturum acilinca da kendiliginden (gorunmez) baslayacak.
echo Calistigini uygulamada gor: Etiket - Yazicilar ve baski isleri (yazici "acik" gorunur).
echo Sorun ararken DENE.bat kullan (gorunmez kopyayi kapatip gorunur pencerede calistirir).
echo.
pause
