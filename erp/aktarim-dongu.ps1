# =====================================================================
#  KRT Saha - ERP AKTARIM DONGUSU (surekli calisir)
#  Eskiden Gorev Zamanlayici siparis-aktar.ps1'i HER DAKIKA ayri ayri baslatiyordu. Gorev Zamanlayici
#  bir noktada baslatmayi birakinca (kacirilan calisma) aktarim saatlerce duruyordu.
#  Simdi: bu dongu bir kez baslar ve hic durmadan ~15 saniyede bir siparis-aktar.ps1'i calistirir.
#   - Bir tur 10 dakikadan uzun surerse (takilirsa) o tur kapatilir, dongu devam eder.
#   - Ayni anda tek dongu calisir (ikinci kopya hemen kapanir).
#   - Dongu herhangi bir sebeple kapanirsa gorev 5 dakika icinde yeniden baslatir.
#  ERP'ye yazan is siparis-aktar.ps1'dir; bu dosya yalnizca onu duzenli calistirir.
# =====================================================================
$Program = "C:\Scripts\siparis-aktar.ps1"
$Log     = "C:\Scripts\aktarim-dongu-log.txt"
$TurSiniriMs = 600000      # bir tur en fazla 10 dakika
$Bekle   = 15              # turlar arasi saniye

function Yaz($m) {
    $s = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $m"
    try {
        if ((Test-Path $Log) -and (Get-Item $Log).Length -gt 2MB) { Move-Item $Log ($Log + ".eski") -Force }
        Add-Content -Path $Log -Value $s
    } catch {}
}

# Tek kopya: ayni anda iki dongu ERP'ye ayni belgeyi yazmaya kalkmasin.
$ilk = $false
$kilit = New-Object System.Threading.Mutex($true, "Global\KRTSahaAktarimDongu", [ref]$ilk)
if (-not $ilk) { exit 0 }

Yaz "Dongu basladi (PID $PID, hesap $env:USERNAME)"
$tur = 0; $sonHaber = Get-Date
try {
    while ($true) {
        $tur++
        try {
            $p = Start-Process -FilePath "powershell.exe" -ArgumentList @("-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File", "`"$Program`"") -WindowStyle Hidden -PassThru
            if (-not $p.WaitForExit($TurSiniriMs)) {
                try { $p.Kill() } catch {}
                Yaz "UYARI: tur $tur 10 dakikada bitmedi (takildi) - kapatildi, devam ediliyor"
            } elseif ($p.ExitCode -ne 0) {
                Yaz "Tur $tur hata koduyla bitti ($($p.ExitCode)) - ayrinti siparis-aktar-log.txt"
            }
        } catch { Yaz "HATA: tur baslatilamadi: $($_.Exception.Message)" }
        if (((Get-Date) - $sonHaber).TotalMinutes -ge 60) { Yaz "Dongu calisiyor ($tur tur)"; $sonHaber = Get-Date }
        Start-Sleep -Seconds $Bekle
    }
} finally {
    Yaz "Dongu kapandi"
    try { $kilit.ReleaseMutex() } catch {}
}
