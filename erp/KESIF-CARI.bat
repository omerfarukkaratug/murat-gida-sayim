@echo off
rem ERP12 kesif (cari hareketleri): sadece okur. Cift tikla.
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0kesif-cari.ps1"
