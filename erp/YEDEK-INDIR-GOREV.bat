@echo off
rem KRT Saha: gece yedegini her sabah 07:30'da ERP bilgisayarina indiren gorevi kurar (bir kez calistir).
rem Once C:\Scripts\yedek-indir.ps1 ve C:\Scripts\erp-anahtar.txt hazir olmali.
schtasks /Create /F /SC DAILY /ST 07:30 /TN "KRT Saha Yedek Indir" /TR "wscript.exe //B //Nologo C:\Scripts\gizli-calistir.vbs C:\Scripts\yedek-indir.ps1"
echo.
echo Simdi bir kez deneniyor...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Scripts\yedek-indir.ps1"
echo.
echo Bitti. Yedekler: C:\KRTSahaYedek   Gunluk: C:\Scripts\yedek-indir-log.txt
pause
