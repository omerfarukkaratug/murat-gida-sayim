@echo off
rem Gorev Zamanlayici: MK Cari Hareketleri gorevini ekler. SAG TIKLA - Yonetici olarak calistir.
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0gorev-cari-ekle.ps1"
