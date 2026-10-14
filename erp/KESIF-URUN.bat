@echo off
rem ERP12 kesif (bir urun stoga nereden girmis): sadece okur. Cift tikla, barkodu yaz.
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0kesif-urun.ps1"
notepad C:\Scripts\kesif-urun.txt
