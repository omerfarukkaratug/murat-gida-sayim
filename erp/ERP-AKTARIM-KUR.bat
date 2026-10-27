@echo off
rem KRT Saha: ERP aktarim gorevini SAGLAM (surekli dongu) olarak yeniden kurar. Sag tik - "Yonetici olarak calistir".
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Scripts\aktarim-kur.ps1"
echo.
pause
