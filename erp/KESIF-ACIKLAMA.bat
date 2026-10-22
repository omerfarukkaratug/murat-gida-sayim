@echo off
rem ERP12 kesif (siparis aciklama alani): sadece okur. Cift tikla.
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0kesif-aciklama.ps1"
