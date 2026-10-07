@echo off
rem ERP12 kesif (kasa promosyonu): sadece okur. Cift tikla.
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0kesif-promo.ps1"
