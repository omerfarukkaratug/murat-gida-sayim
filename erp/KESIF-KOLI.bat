@echo off
rem ERP12 kesif: sadece okur. Cift tikla, barkodu yaz.
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0kesif-koli-fiyat.ps1"
