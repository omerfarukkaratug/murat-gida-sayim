@echo off
rem KRT Saha: Magaza Saglik Raporu gorevini kurar. 30 dakikada bir bakar; rapor uygulamadan istenmisse
rem ya da son rapor 20 saatten eskiyse ERP12'yi YALNIZ OKUYARAK raporu hazirlar ve uygulamaya gonderir.
rem Sag tik - "Yonetici olarak calistir". saglik-raporu.ps1 ve saglik-sablon.html C:\Scripts icinde olmali.
schtasks /Create /F /SC MINUTE /MO 30 /TN "KRT Saha Saglik Raporu" /TR "wscript.exe //B //Nologo C:\Scripts\gizli-calistir.vbs C:\Scripts\saglik-raporu.ps1 -Gorev"
if errorlevel 1 (
  echo.
  echo GOREV KURULAMADI. Bu dosyaya sag tiklayip "Yonetici olarak calistir" deneyin.
) else (
  echo.
  echo Gorev kuruldu: "KRT Saha Saglik Raporu" - 30 dakikada bir kontrol eder.
  echo Ilk rapor birkac dakika icinde uygulamada Karlilik - Saglik sekmesinde gorunur.
)
pause
