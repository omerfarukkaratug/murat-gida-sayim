@echo off
rem MK Saha - KESIF KASA 3: kasada okunmayan MKS karti ile okunan karti yan yana gosterir. ERP12ye HICBIR SEY YAZMAZ.
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0kesif-kasa3.ps1"
