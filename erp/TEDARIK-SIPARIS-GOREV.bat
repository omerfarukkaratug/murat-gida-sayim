@echo off
rem KRT Saha - Tedarikci siparisi aktarim gorevini kurar (10 dakikada bir, oturum acikken).
schtasks /Create /F /SC MINUTE /MO 10 /TN "KRT Tedarik Siparis" /TR "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"C:\Scripts\tedarik-siparis-aktar.ps1\""
if errorlevel 1 (
  echo.
  echo GOREV KURULAMADI. Bu dosyaya sag tiklayip "Yonetici olarak calistir" deneyin.
) else (
  echo.
  echo Gorev kuruldu: "KRT Tedarik Siparis" - 10 dakikada bir calisir.
)
pause
