@echo off
rem MK Saha: uygulamanin actigi (MKS-) stok kartlarini KASALARA otomatik gonderen gorevi kurar.
rem 15 dakikada bir bakar: fiyati girilmis ama kasaya hic gonderilmemis kart varsa gonderir. Stok kartlarina dokunmaz.
rem Sag tik - "Yonetici olarak calistir". kasa-kart-gonder.ps1 ve gizli-calistir.vbs C:\Scripts icinde olmali.
schtasks /Create /F /SC MINUTE /MO 15 /TN "KRT Saha Kasa Kart Gonder" /TR "wscript.exe //B //Nologo C:\Scripts\gizli-calistir.vbs C:\Scripts\kasa-kart-gonder.ps1 -Otomatik"
if errorlevel 1 (
  echo.
  echo GOREV KURULAMADI. Bu dosyaya sag tiklayip "Yonetici olarak calistir" deneyin.
) else (
  echo.
  echo Gorev kuruldu: "KRT Saha Kasa Kart Gonder" - 15 dakikada bir.
  echo Uygulamada acilan urune ERP de fiyat girildikten en gec 15 dakika sonra kasalar okur.
)
pause
