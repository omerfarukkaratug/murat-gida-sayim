@echo off
rem MK Saha - Mal Giris / Mal Cikis kayitlarini ERP'ye SIPARIS olarak yazar (bir kez, simdi).
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Scripts\siparis-aktar.ps1"
echo.
echo Sonuc C:\Scripts\siparis-aktar-log.txt dosyasinda.
pause
