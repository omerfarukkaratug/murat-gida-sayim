@echo off
rem Saglik raporu kontrolu: tuhaf aylarin sebebi. Sadece okur.
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0kesif-saglik.ps1"
