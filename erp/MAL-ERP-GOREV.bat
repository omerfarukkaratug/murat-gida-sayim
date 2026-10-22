@echo off
rem MK Saha - Mal Giris / Cikis irsaliyelerini 10 saniyede bir ERP'ye aktaran gorevi kurar.
rem ONCE MAL-SIPARIS-DENE.bat ve MAL-SIPARIS-AKTAR.bat ile elle deneyin; sorun yoksa bunu "Yonetici olarak calistir".
schtasks /Create /F /SC MINUTE /MO 1 /TN "MK Saha ERP Aktarim" /TR "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"C:\Scripts\siparis-aktar.ps1\" DONGU"
if errorlevel 1 (
  echo.
  echo GOREV KURULAMADI. Bu dosyaya sag tiklayip "Yonetici olarak calistir" deneyin.
) else (
  echo.
  echo Gorev kuruldu: "MK Saha ERP Aktarim" - 10 saniyede bir calisir.
)
pause
