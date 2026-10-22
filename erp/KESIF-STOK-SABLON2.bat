@echo off
rem ERP12 kesif 2 (sablon stok kartinin barkod/fiyat/sayac kayitlari): sadece okur.
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0kesif-stok-sablon2.ps1"
