@echo off
rem KRT Saha - SAYIM AKTAR: bolum bolum sayimi ERP12 SAYIM belgesine yazar (once DENEME raporu, EVET demeden yazmaz).
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0sayim-aktar.ps1"
