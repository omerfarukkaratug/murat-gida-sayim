@echo off
rem ERP12 kesif: uygulamanin actigi MKS- stok kartlari neden kasada okunmuyor. Sadece okur, hicbir sey yazmaz.
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0kesif-kasa.ps1"
