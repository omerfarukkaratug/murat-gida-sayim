@echo off
rem KRT Saha - KDV durum raporu (acik / fazla + stoktaki KDV). SADECE OKUR, ERPye yazmaz.
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0kdv-raporu.ps1"
