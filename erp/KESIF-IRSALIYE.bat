@echo off
rem ERP12 kesif (irsaliyeler): sadece okur. Cift tikla.
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0kesif-irsaliye.ps1"
