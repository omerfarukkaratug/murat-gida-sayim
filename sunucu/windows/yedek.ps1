# MK Sunucu - gece veritabani yedegi (pg_dump). Son 30 gun saklanir.
# Gorev Zamanlayici her gece 02:30'da calistirir (kur.ps1 kurar).
param([string]$Dizin = "D:\MK-Yedek\pg", [string]$Veritabani = "mkerp", [string]$Kullanici = "mk")
$ErrorActionPreference = "Stop"
$pgBin = (Get-ChildItem "C:\Program Files\PostgreSQL\*\bin\pg_dump.exe" | Sort-Object FullName -Descending | Select-Object -First 1).DirectoryName
if (-not $pgBin) { throw "pg_dump bulunamadi" }
New-Item -ItemType Directory -Force -Path $Dizin | Out-Null
$dosya = Join-Path $Dizin ("mkerp-" + (Get-Date -Format "yyyy-MM-dd_HHmm") + ".dump")
$env:PGPASSFILE = Join-Path $PSScriptRoot "..\pgpass.conf"
& "$pgBin\pg_dump.exe" -h localhost -U $Kullanici -Fc -f "$dosya.tmp" $Veritabani
if ($LASTEXITCODE -ne 0) { throw "pg_dump hata verdi ($LASTEXITCODE)" }
Move-Item "$dosya.tmp" $dosya -Force
Get-ChildItem $Dizin -Filter "mkerp-*.dump" | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } | Remove-Item -Force
"$(Get-Date -Format s) yedek tamam: $dosya" | Add-Content (Join-Path $Dizin "yedek-log.txt")
