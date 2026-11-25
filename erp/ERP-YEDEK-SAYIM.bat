@echo off
rem KRT Saha: SAYIM AKTARIMI ONCESI yedek. C: dar oldugu icin daha dusuk bos yer sinirla calisir;
rem takili USB bellek (3 GB+ bos) varsa yedegin bir kopyasi da oraya (KRT-ERP-Yedek klasoru) yazilir.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Scripts\erp-sql-yedek.ps1" SAYIM
echo.
echo Bitti. "YEDEK TAMAM" ve "BITTI" satirlarini kontrol edin. Gunluk: C:\Scripts\erp-sql-yedek-log.txt
pause
