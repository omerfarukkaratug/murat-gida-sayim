@echo off
rem KRT Saha - Tedarikci siparislerini ERP'ye YAZMADAN dener (log'a ne yazilacagini yazar).
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Scripts\tedarik-siparis-aktar.ps1" DENEME
echo.
echo Sonuc C:\Scripts\tedarik-siparis-log.txt dosyasinda. ERP'ye hicbir sey yazilmadi.
pause
