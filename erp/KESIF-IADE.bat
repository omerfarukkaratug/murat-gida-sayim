@echo off
rem ERP12 kesif (alistan iade irsaliyeleri): sadece okur. Cift tikla.
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0kesif-iade.ps1"
