# =====================================================================
#  KRT Saha - ERP AKTARIM DONGUSU (surekli calisir)
#  Eskiden Gorev Zamanlayici siparis-aktar.ps1'i HER DAKIKA ayri ayri baslatiyordu. Gorev Zamanlayici
#  bir noktada baslatmayi birakinca (kacirilan calisma) aktarim saatlerce duruyordu.
#  Simdi: bu dongu bir kez baslar ve hic durmadan ~30 saniyede bir (bulut hata verirse 1-10 dk bekler) siparis-aktar.ps1'i calistirir.
#   - Bir tur 10 dakikadan uzun surerse (takilirsa) o tur kapatilir, dongu devam eder.
#   - Ayni anda tek dongu calisir (ikinci kopya hemen kapanir).
#   - Dongu herhangi bir sebeple kapanirsa gorev 5 dakika icinde yeniden baslatir.
#  ERP'ye yazan is siparis-aktar.ps1'dir; bu dosya yalnizca onu duzenli calistirir.
# =====================================================================
$Program = "C:\Scripts\siparis-aktar.ps1"
$Log     = "C:\Scripts\aktarim-dongu-log.txt"
$TurSiniriMs = 600000      # bir tur en fazla 10 dakika
$Bekle   = 30              # turlar arasi saniye (bulut zorlanmasin)
$HataBekle = 30           # ust uste hata olursa bekleme ikiye katlanir (en fazla 10 dk)

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
$tur = 0; $sonHaber = Get-Date; $ardisikHata = 0
try {
    while ($true) {
        $tur++
        try {
            $p = Start-Process -FilePath "powershell.exe" -ArgumentList @("-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File", "`"$Program`"") -WindowStyle Hidden -PassThru
            $null = $p.Handle   # PowerShell 5: tutamak hemen alinmazsa ExitCode bos doner ve her tur "hata" gibi gorunur
            if (-not $p.WaitForExit($TurSiniriMs)) {
                try { $p.Kill() } catch {}
                Yaz "UYARI: tur $tur 10 dakikada bitmedi (takildi) - kapatildi, devam ediliyor"
                $ardisikHata++
            } elseif ($p.ExitCode -ne $null -and $p.ExitCode -ne 0) {
                $ardisikHata++
                if ($ardisikHata -le 3 -or $ardisikHata % 10 -eq 0) { Yaz "Tur $tur hata koduyla bitti ($($p.ExitCode)), ust uste $ardisikHata - ayrinti siparis-aktar-log.txt" }
            } else {
                if ($ardisikHata -ge 3) { Yaz "Baglanti duzeldi ($ardisikHata hatadan sonra)" }
                $ardisikHata = 0
            }
        } catch { Yaz "HATA: tur baslatilamadi: $($_.Exception.Message)" }
        if (((Get-Date) - $sonHaber).TotalMinutes -ge 60) { Yaz "Dongu calisiyor ($tur tur)"; $sonHaber = Get-Date }
        # Bulut cevap vermiyorsa her 30 sn'de yuklenmek sorunu buyutur: bekleme 1-2-4-8 dk'ya cikar (en fazla 10 dk).
        $bekleSn = $Bekle
        if ($ardisikHata -gt 0) { $bekleSn = [Math]::Min(600, $HataBekle * [Math]::Pow(2, [Math]::Min($ardisikHata, 5))) }
        Start-Sleep -Seconds $bekleSn
    }
} finally {
    Yaz "Dongu kapandi"
    try { $kilit.ReleaseMutex() } catch {}
}
