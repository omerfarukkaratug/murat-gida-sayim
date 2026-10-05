@echo off
rem MK ERP - Baski programini calistirir ve kapanirsa 15 saniye sonra yeniden baslatir.
rem Bu pencere KUCULTULMUS olarak acik kalir; kapatilirsa baski durur.
title MK Baski Programi
cd /d "%~dp0"
:dongu
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0baski-ajani.ps1"
echo %date% %time% program durdu, 15 saniye sonra yeniden baslayacak...
timeout /t 15 /nobreak >nul
goto dongu
