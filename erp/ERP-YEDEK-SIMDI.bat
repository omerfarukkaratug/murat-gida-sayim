@echo off
rem KRT Saha: ERP12 veri tabanlarinin SIMDI bir yedegini alir (COPY_ONLY - mevcut yedek duzenini bozmaz).
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Scripts\erp-sql-yedek.ps1"
echo.
echo Bitti. "YEDEK TAMAM" ve "BITTI" satirlarini kontrol edin. Gunluk: C:\Scripts\erp-sql-yedek-log.txt
pause
