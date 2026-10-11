@echo off
rem Cari hareketlerini ERP12den okuyup veri tabanina gonderir (ERP12ye yazmaz). Cift tikla.
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0cari-hareket-gonder.ps1"
echo.
echo Bitti. Sonuc yukarida ve C:\Scripts\cari-hareket-log.txt icinde.
pause
