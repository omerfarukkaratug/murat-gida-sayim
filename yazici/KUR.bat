@echo off
rem MK ERP - Baski programi kurulumu. Bu dosyaya CIFT TIKLA.
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0kur.ps1"
echo.
echo Pencereyi kapatmak icin bir tusa bas.
pause >nul
