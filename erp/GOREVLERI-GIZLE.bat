@echo off
rem KRT Saha: her dakika acilan mavi PowerShell penceresini kaldirir. Sag tik - "Yonetici olarak calistir".
rem Gorevlerin yaptigi is DEGISMEZ; yalniz pencere acmadan calisirlar.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Scripts\gorev-gizle.ps1"
echo.
pause
