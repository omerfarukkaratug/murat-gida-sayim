# MK ERP - Baski programi kurulumu. Sag tik > "PowerShell ile calistir".
# C:\MKBaski klasorunu hazirlar ve programi Windows acilisinda (oturum acilinca)
# kendiliginden baslayacak sekilde gorev olarak ekler.
$Klasor = "C:\MKBaski"
if (-not (Test-Path $Klasor)) { New-Item -ItemType Directory -Path $Klasor -Force | Out-Null }
$kaynak = Join-Path $PSScriptRoot "baski-ajani.ps1"
$hedef = Join-Path $Klasor "baski-ajani.ps1"
# Dosyalar zaten C:\MKBaski icindeyse kopyalamaya gerek yok.
if ((Test-Path $kaynak) -and ((Resolve-Path $kaynak).Path -ne $hedef)) { Copy-Item $kaynak $hedef -Force }
if (-not (Test-Path (Join-Path $Klasor "baski-ajani.ps1"))) { Write-Host "HATA: baski-ajani.ps1 bulunamadi. Bu dosyayla ayni klasore koy."; Read-Host "Kapatmak icin Enter"; exit 1 }

$anahtarDosyasi = Join-Path $Klasor "baski-anahtar.txt"
if (-not (Test-Path $anahtarDosyasi)) {
    $a = Read-Host "Uygulamadaki ERP anahtarini yapistir (Ayarlar > Veri Guvenligi)"
    if ($a.Trim()) { Set-Content -Path $anahtarDosyasi -Value $a.Trim() -Encoding ASCII }
}
# Uzantilar gizliyken dosya "SumatraPDF.exe.exe" diye adlandirilmis olabilir: duzelt.
$cift = Join-Path $Klasor "SumatraPDF.exe.exe"
if ((Test-Path $cift) -and -not (Test-Path (Join-Path $Klasor "SumatraPDF.exe"))) { Rename-Item $cift "SumatraPDF.exe"; Write-Host "SumatraPDF.exe.exe -> SumatraPDF.exe olarak duzeltildi." }
if (-not (Test-Path (Join-Path $Klasor "SumatraPDF.exe"))) {
    Write-Host ""
    Write-Host "EKSIK: C:\MKBaski\SumatraPDF.exe yok."
    Write-Host "sumatrapdfreader.org adresinden 'portable' surumu indir, adini SumatraPDF.exe yapip C:\MKBaski icine koy."
}

# Otomatik baslatma: yonetici yetkisi GEREKTIRMEYEN yol - kullanicinin "Baslangic" klasorune
# kucuk bir dosya konur; oturum acilinca baski programi kendiliginden baslar.
$baslangic = [Environment]::GetFolderPath("Startup")
$baslatici = Join-Path $baslangic "MK Baski Programi.cmd"
try {
    Set-Content -Path $baslatici -Encoding ASCII -Value ("@echo off`r`nstart `"`" /min powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Klasor\baski-ajani.ps1`"")
    Write-Host "Otomatik baslatma eklendi: oturum acilinca baski programi kendiliginden baslar."
} catch {
    Write-Host "UYARI: Otomatik baslatma eklenemedi: $($_.Exception.Message)"
}
# Eski surumun ekledigi zamanlanmis gorev varsa kaldirilir (iki kez baslamasin).
schtasks /Delete /TN "MK Baski Programi" /F 2>$null | Out-Null

Write-Host "Simdi baslatiliyor..."
Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Klasor\baski-ajani.ps1`""
Write-Host "Tamam. Durum icin: C:\MKBaski\baski-log.txt ve uygulamada Etiket > Yazicilar ve baski isleri."
Read-Host "Kapatmak icin Enter"
