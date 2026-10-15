@echo off
rem MK Sunucu: kapanirsa 5 sn sonra yeniden baslar (Gorev Zamanlayici bunu bilgisayar acilinca calistirir)
cd /d "%~dp0.."
:bas
echo %date% %time% baslatiliyor >> "%~dp0..\sunucu.log"
node ana.js >> "%~dp0..\sunucu.log" 2>&1
echo %date% %time% durdu (kod %errorlevel%), 5 sn sonra yeniden >> "%~dp0..\sunucu.log"
timeout /t 5 /nobreak > nul
goto bas
