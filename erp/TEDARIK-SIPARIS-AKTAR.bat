@echo off
rem KRT Saha - Tedarikci siparislerini ERP'ye VERILEN SIPARIS olarak yazar (bir kez, simdi).
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Scripts\tedarik-siparis-aktar.ps1"
echo.
echo Sonuc C:\Scripts\tedarik-siparis-log.txt dosyasinda.
pause
