@echo off
rem KRT Saha: ERP12 veri tabanlarinin en son ne zaman yedeklendigini gosterir (yedek ALMAZ, hicbir seye dokunmaz).
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Scripts\erp-sql-yedek.ps1" KONTROL
echo.
echo Bu ekranin fotografini gonderin. Gunluk: C:\Scripts\erp-sql-yedek-log.txt
pause
