@echo off
rem MK ERP - Mal giris/cikis indirme gorevini kurar (5 dakikada bir, oturum acikken).
rem Once C:\Scripts\mal-hareket-indir.ps1 ve C:\Scripts\mal-indir-giris.txt hazir olmali.
schtasks /Create /F /SC MINUTE /MO 5 /TN "MK Mal Indir" /TR "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"C:\Scripts\mal-hareket-indir.ps1\""
if errorlevel 1 (
  echo.
  echo GOREV KURULAMADI. Bu dosyaya sag tiklayip "Yonetici olarak calistir" deneyin.
) else (
  echo.
  echo Gorev kuruldu: "MK Mal Indir" - 5 dakikada bir calisir.
  echo Simdi bir kez deneniyor...
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Scripts\mal-hareket-indir.ps1"
)
pause
