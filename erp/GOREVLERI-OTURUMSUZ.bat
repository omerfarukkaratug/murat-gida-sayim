@echo off
rem KRT Saha: ERP gorevleri bilgisayar acik oldugu surece calissin (oturum kapali olsa da). Sag tik - "Yonetici olarak calistir".
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Scripts\gorev-oturumsuz.ps1"
echo.
pause
