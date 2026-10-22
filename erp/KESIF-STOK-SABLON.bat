@echo off
rem ERP12 kesif (yeni stok karti hangi tablolara yaziliyor): sadece okur. Cift tikla.
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0kesif-stok-sablon.ps1"
