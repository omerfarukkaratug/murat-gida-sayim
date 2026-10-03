# MK ERP - Baski programi kurulumu. Sag tik > "PowerShell ile calistir".
# C:\MKBaski klasorunu hazirlar ve programi Windows acilisinda (oturum acilinca)
# kendiliginden baslayacak sekilde gorev olarak ekler.
$Klasor = "C:\MKBaski"
if (-not (Test-Path $Klasor)) { New-Item -ItemType Directory -Path $Klasor -Force | Out-Null }
$kaynak = Join-Path $PSScriptRoot "baski-ajani.ps1"
if (Test-Path $kaynak) { Copy-Item $kaynak (Join-Path $Klasor "baski-ajani.ps1") -Force }
if (-not (Test-Path (Join-Path $Klasor "baski-ajani.ps1"))) { Write-Host "HATA: baski-ajani.ps1 bulunamadi. Bu dosyayla ayni klasore koy."; Read-Host "Kapatmak icin Enter"; exit 1 }

$anahtarDosyasi = Join-Path $Klasor "baski-anahtar.txt"
if (-not (Test-Path $anahtarDosyasi)) {
    $a = Read-Host "Uygulamadaki ERP anahtarini yapistir (Ayarlar > Veri Guvenligi)"
    if ($a.Trim()) { Set-Content -Path $anahtarDosyasi -Value $a.Trim() -Encoding ASCII }
}
if (-not (Test-Path (Join-Path $Klasor "SumatraPDF.exe"))) {
    Write-Host ""
    Write-Host "EKSIK: C:\MKBaski\SumatraPDF.exe yok."
    Write-Host "sumatrapdfreader.org adresinden 'portable' surumu indir, adini SumatraPDF.exe yapip C:\MKBaski icine koy."
}

$komut = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Klasor\baski-ajani.ps1`""
schtasks /Create /TN "MK Baski Programi" /TR $komut /SC ONLOGON /RL LIMITED /F | Out-Null
if ($LASTEXITCODE -eq 0) { Write-Host "Gorev eklendi: oturum acilinca baski programi kendiliginden baslar." }
else { Write-Host "UYARI: Gorev eklenemedi. Bu dosyayi 'Yonetici olarak calistir' ile tekrar dene." }

Write-Host "Simdi baslatiliyor..."
Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Klasor\baski-ajani.ps1`""
Write-Host "Tamam. Durum icin: C:\MKBaski\baski-log.txt ve uygulamada Etiket > Yazicilar ve baski isleri."
Read-Host "Kapatmak icin Enter"
