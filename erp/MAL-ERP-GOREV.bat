@echo off
rem MK Saha - Mal Giris / Cikis irsaliyelerini 10 dakikada bir ERP'ye aktaran gorevi kurar.
rem ONCE MAL-SIPARIS-DENE.bat ve MAL-SIPARIS-AKTAR.bat ile elle deneyin; sorun yoksa bunu "Yonetici olarak calistir".
schtasks /Create /F /SC MINUTE /MO 10 /TN "MK Saha ERP Aktarim" /TR "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"C:\Scripts\siparis-aktar.ps1\""
if errorlevel 1 (
  echo.
  echo GOREV KURULAMADI. Bu dosyaya sag tiklayip "Yonetici olarak calistir" deneyin.
) else (
  echo.
  echo Gorev kuruldu: "MK Saha ERP Aktarim" - 10 dakikada bir calisir.
)
pause
