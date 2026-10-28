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

# Yardimci dosyalar da C:\MKBaski icine (baska klasorden calistirildiysa).
foreach ($f in @("CALISTIR.bat", "GIZLI-BASLAT.vbs", "DENE.bat", "OTOMATIK-BASLAT.bat")) {
    $k = Join-Path $PSScriptRoot $f; $h = Join-Path $Klasor $f
    if ((Test-Path $k) -and ((Resolve-Path $k).Path -ne $h)) { Copy-Item $k $h -Force }
}
if (-not (Test-Path (Join-Path $Klasor "CALISTIR.bat")) -or -not (Test-Path (Join-Path $Klasor "GIZLI-BASLAT.vbs"))) {
    Write-Host "HATA: CALISTIR.bat ve GIZLI-BASLAT.vbs de C:\MKBaski icinde olmali."; Read-Host "Kapatmak icin Enter"; exit 1
}

# Otomatik baslatma: yonetici yetkisi GEREKTIRMEYEN yol - kullanicinin "Baslangic" klasorune
# GIZLI-BASLAT.vbs konur; oturum acilinca baski programi ekranda pencere gostermeden baslar.
$baslangic = [Environment]::GetFolderPath("Startup")
try {
    Remove-Item (Join-Path $baslangic "MK Baski Programi.cmd") -Force -ErrorAction SilentlyContinue
    Copy-Item (Join-Path $Klasor "GIZLI-BASLAT.vbs") (Join-Path $baslangic "MK Baski Programi.vbs") -Force
    Write-Host "Otomatik baslatma eklendi: oturum acilinca baski programi gorunmez olarak baslar."
} catch {
    Write-Host "UYARI: Otomatik baslatma eklenemedi: $($_.Exception.Message)"
}
# Eski surumun ekledigi zamanlanmis gorev varsa kaldirilir (iki kez baslamasin).
schtasks /Delete /TN "MK Baski Programi" /F 2>$null | Out-Null

# Acik kalan eski (gorunur) kopya kapatilir.
Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessId -ne $PID -and (($_.Name -eq "cmd.exe" -and $_.CommandLine -like "*CALISTIR.bat*") -or ($_.Name -eq "powershell.exe" -and $_.CommandLine -like "*baski-ajani.ps1*")) } |
    ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force -ErrorAction Stop } catch {} }
Start-Sleep -Seconds 2

Write-Host "Simdi gorunmez olarak baslatiliyor..."
Start-Process wscript.exe -ArgumentList ("`"" + (Join-Path $Klasor "GIZLI-BASLAT.vbs") + "`"")
Write-Host "Tamam. Durum icin: C:\MKBaski\baski-log.txt ve uygulamada Etiket > Yazicilar ve baski isleri."
Read-Host "Kapatmak icin Enter"
