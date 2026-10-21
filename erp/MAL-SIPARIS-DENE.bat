@echo off
rem MK Saha - Mal Giris / Mal Cikis kayitlarini ERP'ye YAZMADAN dener (log'a ne yazilacagini yazar).
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Scripts\siparis-aktar.ps1" DENEME
echo.
echo Sonuc C:\Scripts\siparis-aktar-log.txt dosyasinda. ERP'ye hicbir sey yazilmadi.
pause
