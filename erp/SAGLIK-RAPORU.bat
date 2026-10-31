@echo off
rem KRT Saha - Magaza Saglik Raporu: ERP12 veri tabanini yalniz okur, rapor HTML dosyasi uretir.
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0saglik-raporu.ps1"
