@echo off
rem Cari hareketlerini ve belge satirlarini TUM GECMISIYLE yeniden gonderir (ERP12ye yazmaz). Cift tikla.
rem Normalde gerek yok: program gunde bir zaten tumunu gonderir. Degisiklikten sonra hemen gorunsun diye.
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0cari-hareket-gonder.ps1" TAM
echo.
echo Bitti. Sonuc yukarida ve C:\Scripts\cari-hareket-log.txt icinde.
pause
