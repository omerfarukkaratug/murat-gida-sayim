@echo off
rem KRT Saha - KESIF SAYIM 2: ERP12 sayim kesinlestirme programlarini okur. ERP12ye HICBIR SEY YAZMAZ.
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0kesif-sayim2.ps1"
