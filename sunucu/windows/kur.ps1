# =====================================================================
#  MK Sunucu - Windows kurulumu (YONETICI PowerShell ile calistir)
#  Once: Node.js LTS (nodejs.org) ve PostgreSQL 16 (postgresql.org/download/windows) kurulu olmali.
#  Calistirma:  powershell -ExecutionPolicy Bypass -File kur.ps1 -PostgresSifresi "<kurulumda verilen postgres sifresi>" -Adres "https://erp.ornek.com"
#  Ne yapar:
#   1) PostgreSQL'de "mkerp" veritabani ve "mk" kullanicisi (rastgele guclu sifre) olusturur
#   2) ayar.json ve pgpass.conf yazar (sifreler yalnizca bu bilgisayarda)
#   3) Gorev Zamanlayici: "MK Sunucu" (bilgisayar acilinca, kapanirsa yeniden) + "MK Yedek" (her gece 02:30)
#  ERP12 veritabanina HIC dokunmaz.
# =====================================================================
param([Parameter(Mandatory = $true)][string]$PostgresSifresi, [string]$Adres = "", [int]$Port = 8080, [string]$YedekDizini = "D:\MK-Yedek", [switch]$Deneme)
$ErrorActionPreference = "Stop"
$kok = Split-Path $PSScriptRoot -Parent
$node = (Get-Command node -ErrorAction SilentlyContinue).Source
if (-not $node) { throw "Node.js bulunamadi. nodejs.org'dan LTS surumunu kur, sonra bu pencereyi kapatip yeniden ac." }
$surum = (& $node -v); if ([int]($surum.TrimStart('v').Split('.')[0]) -lt 20) { throw "Node.js 20 veya ustu gerekli (bulunan: $surum)" }
$pgBin = (Get-ChildItem "C:\Program Files\PostgreSQL\*\bin\psql.exe" | Sort-Object FullName -Descending | Select-Object -First 1).DirectoryName
if (-not $pgBin) { throw "PostgreSQL bulunamadi (C:\Program Files\PostgreSQL)." }
Write-Host "Node $surum, PostgreSQL: $pgBin"

# 1) veritabani + kullanici
$mkSifre = -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 32 | ForEach-Object { [char]$_ })
$env:PGPASSWORD = $PostgresSifresi
$var = & "$pgBin\psql.exe" -h localhost -U postgres -Atc "select 1 from pg_roles where rolname='mk'"
if ($var -eq "1") { & "$pgBin\psql.exe" -h localhost -U postgres -c "alter role mk with login password '$mkSifre'" | Out-Null }
else { & "$pgBin\psql.exe" -h localhost -U postgres -c "create role mk with login password '$mkSifre'" | Out-Null }
$db = & "$pgBin\psql.exe" -h localhost -U postgres -Atc "select 1 from pg_database where datname='mkerp'"
if ($db -ne "1") { & "$pgBin\psql.exe" -h localhost -U postgres -c "create database mkerp owner mk encoding 'UTF8' template template0" | Out-Null }
Remove-Item Env:PGPASSWORD
Write-Host "Veritabani hazir: mkerp (kullanici mk)"

# 2) ayarlar
New-Item -ItemType Directory -Force -Path $YedekDizini | Out-Null
$ayar = [ordered]@{ port = $Port; veritabani = "postgres://mk:$mkSifre@localhost:5432/mkerp"; kod = "../Code.gs"; statik = ".."; yedekDizini = ($YedekDizini -replace '\\', '/'); adres = $Adres }
$ayar | ConvertTo-Json | Set-Content -Encoding UTF8 (Join-Path $kok "ayar.json")
"localhost:5432:mkerp:mk:$mkSifre" | Set-Content -Encoding ASCII (Join-Path $kok "pgpass.conf")
icacls (Join-Path $kok "ayar.json") /inheritance:r /grant:r "SYSTEM:F" "Administrators:F" | Out-Null
icacls (Join-Path $kok "pgpass.conf") /inheritance:r /grant:r "SYSTEM:F" "Administrators:F" | Out-Null
Write-Host "ayar.json yazildi (yalnizca Yoneticiler ve SYSTEM okuyabilir)"

if ($Deneme) {
  Write-Host ""
  Write-Host "DENEME kurulumu: zamanlanmis gorev KURULMADI (bilgisayar surekli acik degil)." -ForegroundColor Yellow
  Write-Host "Sunucuyu baslatmak icin: windows\baslat.cmd dosyasina cift tikla (pencere acik kaldigi surece calisir)."
  exit 0
}
# 3) zamanlanmis gorevler
$ayarlar = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -StartWhenAvailable
$sistem = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$is1 = New-ScheduledTaskAction -Execute "cmd.exe" -Argument ("/c `"" + (Join-Path $PSScriptRoot "baslat.cmd") + "`"") -WorkingDirectory $kok
Register-ScheduledTask -TaskName "MK Sunucu" -Action $is1 -Trigger (New-ScheduledTaskTrigger -AtStartup) -Settings $ayarlar -Principal $sistem -Force | Out-Null
$is2 = New-ScheduledTaskAction -Execute "powershell.exe" -Argument ("-ExecutionPolicy Bypass -File `"" + (Join-Path $PSScriptRoot "yedek.ps1") + "`" -Dizin `"" + (Join-Path $YedekDizini "pg") + "`"")
Register-ScheduledTask -TaskName "MK Yedek" -Action $is2 -Trigger (New-ScheduledTaskTrigger -Daily -At 2:30am) -Settings $ayarlar -Principal $sistem -Force | Out-Null
Start-ScheduledTask -TaskName "MK Sunucu"
Start-Sleep -Seconds 6
try { $s = Invoke-RestMethod "http://localhost:$Port/saglik"; Write-Host "MK Sunucu calisiyor: $($s.durum)" -ForegroundColor Green }
catch { Write-Host "Sunucu henuz cevap vermedi - sunucu.log dosyasina bak" -ForegroundColor Yellow }
Write-Host "Sonraki adim: tasima (KURULUM.md, Adim 4)"
