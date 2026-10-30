@echo off
rem ERP12 kesif: kasa iptalleri / indirimler / yetkili islemleri on raporu. Sadece okur.
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0kesif-iptal.ps1"
