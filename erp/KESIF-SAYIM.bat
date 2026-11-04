@echo off
rem KRT Saha - KESIF SAYIM: ERP12 sayim bolumunu ve urun gruplarini okur. ERP12ye HICBIR SEY YAZMAZ.
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0kesif-sayim.ps1"
