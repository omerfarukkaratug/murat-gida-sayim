@echo off
rem MK ERP - Baski programi bilgisayar acilinca KENDILIGINDEN baslasin diye bir kez cift tiklanir.
rem Yonetici yetkisi gerekmez. C:\MKBaski icinden calistir.
cd /d "%~dp0"
if not exist "%~dp0baski-ajani.ps1" ( echo HATA: Bu dosyayi C:\MKBaski icine kopyalayip oradan calistir. & pause & exit /b 1 )
if not exist "%~dp0CALISTIR.bat" ( echo HATA: CALISTIR.bat ayni klasorde olmali. & pause & exit /b 1 )
set "BASL=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup"
rem Eski baslaticilar kaldirilir (gizli pencereyle baslatan surum calismiyordu).
schtasks /Delete /TN "MK Baski Programi" /F >nul 2>&1
del "%BASL%\MK Baski Programi.cmd" >nul 2>&1
> "%BASL%\MK Baski Programi.cmd" echo @start "MK Baski Programi" /min "%~dp0CALISTIR.bat"
if not exist "%BASL%\MK Baski Programi.cmd" ( echo HATA: Baslangic klasorune yazilamadi. & pause & exit /b 1 )
echo Tamam: bilgisayar acilip oturum acilinca baski programi kendiliginden baslayacak.
echo Simdi de baslatiliyor (gorev cubugunda kucultulmus "MK Baski Programi" penceresi).
start "MK Baski Programi" /min "%~dp0CALISTIR.bat"
echo.
echo Bu pencereyi kapatabilirsin. Acik DENE penceresi varsa onu da kapat.
pause
