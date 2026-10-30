@echo off
rem Uygulamanin actigi MKS- stok kartlarini kasalara gonderir (ERP degisiklik defterine yeni kart satirlari ekler).
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0kasa-kart-gonder.ps1"
