@echo off
rem ERP12 kesif kasa 2: kasalarin yeni kartlari aldigi degisiklik kaydi. Sadece okur, hicbir sey yazmaz.
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0kesif-kasa2.ps1"
