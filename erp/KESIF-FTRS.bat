@echo off
rem ERP12 kesif (bozuk fatura no nereden): sadece okur.
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0kesif-ftrs.ps1"
