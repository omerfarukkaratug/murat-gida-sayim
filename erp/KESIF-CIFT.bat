@echo off
rem ERP12 kesif (irsaliye + fatura cift sayim): sadece okur. Cift tikla.
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0kesif-cift.ps1"
