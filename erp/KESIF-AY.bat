@echo off
rem KRT Saha - AY INCELEME: bir ayin kari neden dusuk? Kari en cok dusuren urunler, alis ve satis satirlari. ERP12ye HICBIR SEY YAZMAZ.
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0kesif-ay.ps1"
