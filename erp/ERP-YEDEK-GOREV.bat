@echo off
rem KRT Saha: ERP12 yedegini her gece 23:30'da otomatik alan gorevi kurar. Sag tik - "Yonetici olarak calistir".
schtasks /Create /F /SC DAILY /ST 23:30 /TN "KRT Saha ERP SQL Yedek" /TR "wscript.exe //B //Nologo C:\Scripts\gizli-calistir.vbs C:\Scripts\erp-sql-yedek.ps1"
if errorlevel 1 (
  echo.
  echo GOREV KURULAMADI. Bu dosyaya sag tiklayip "Yonetici olarak calistir" deneyin.
) else (
  echo.
  echo Gorev kuruldu: "KRT Saha ERP SQL Yedek" - her gece 23:30.
)
pause
