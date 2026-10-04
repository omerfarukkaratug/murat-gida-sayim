@echo off
rem Baski programini GORUNUR pencerede calistirir (sorun ararken). Kapatmak icin pencereyi kapat.
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0baski-ajani.ps1"
echo.
echo Program durdu. Yukaridaki yaziya bak. Kapatmak icin bir tusa bas.
pause >nul
