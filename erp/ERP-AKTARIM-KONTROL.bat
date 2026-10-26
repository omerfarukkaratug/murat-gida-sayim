@echo off
rem KRT Saha: ERP aktarim gorevine bakar, takili kalmissa duzeltir. Sag tik - "Yonetici olarak calistir".
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Scripts\aktarim-kontrol.ps1" AYAR
echo.
pause
