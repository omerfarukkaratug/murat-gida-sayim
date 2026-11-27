@echo off
rem KRT Saha - Sayim sermaye (stok degeri) raporu. SADECE OKUR, ERPye yazmaz.
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0sermaye-raporu.ps1"
