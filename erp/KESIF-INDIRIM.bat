@echo off
rem KRT Saha - KESIF INDIRIM: ERP12 indirim gruplarinin tablosunu bulur. ERP12ye HICBIR SEY YAZMAZ.
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0kesif-indirim.ps1"
