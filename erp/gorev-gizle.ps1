# =====================================================================
#  KRT Saha - Gorev Zamanlayici'daki C:\Scripts gorevlerini PENCERESIZ yapar.
#  "powershell.exe ... -File C:\Scripts\x.ps1 ..." calistiran her gorevin eylemi
#  "wscript.exe gizli-calistir.vbs C:\Scripts\x.ps1 ..." olur. Zamanlama, kullanici,
#  ayarlar AYNEN kalir; yalniz calistirma sekli degisir. Gorevlerin yaptigi isi DEGISTIRMEZ.
#  Geri almak icin: ilgili ...-GOREV.bat dosyasini yeniden calistirmak yeterli.
# =====================================================================
$Vbs = "C:\Scripts\gizli-calistir.vbs"
try {
    if (-not (Test-Path $Vbs)) { throw "$Vbs yok - once bu dosyayi C:\Scripts icine koyun." }
    $n = 0
    foreach ($g in @(Get-ScheduledTask | Where-Object { $_.TaskPath -eq "\" })) {
        $degisti = $false
        $yeni = @()
        foreach ($e in $g.Actions) {
            $arg = [string]$e.Arguments
            if ($e.Execute -match "powershell" -and $arg -match '-File\s+"?([A-Za-z]:\\Scripts\\[^"]+?\.ps1)"?\s*(.*)$') {
                $dosya = $Matches[1]; $kalan = $Matches[2].Trim()
                $yeniArg = '//B //Nologo "' + $Vbs + '" "' + $dosya + '"' + $(if ($kalan) { " " + $kalan } else { "" })
                $yeni += New-ScheduledTaskAction -Execute "wscript.exe" -Argument $yeniArg -WorkingDirectory "C:\Scripts"
                $degisti = $true
            } else { $yeni += $e }
        }
        if ($degisti) {
            try {
                Set-ScheduledTask -TaskName $g.TaskName -TaskPath $g.TaskPath -Action $yeni -ErrorAction Stop | Out-Null
                Write-Host ("PENCERESIZ yapildi: {0}" -f $g.TaskName)
                $n++
            } catch { Write-Host ("ATLANDI: {0} ({1}) - bu gorev sifreli hesapla calisiyor olabilir, dokunulmadi." -f $g.TaskName, $_.Exception.Message) }
        }
    }
    Write-Host ""
    if ($n -eq 0) { Write-Host "Degistirilecek gorev bulunamadi (zaten penceresiz olabilir)." }
    else { Write-Host "TAMAM: $n gorev artik pencere acmadan calisacak." }
} catch {
    Write-Host ""
    Write-Host "HATA: $($_.Exception.Message)"
    Write-Host "Bu dosyayi 'Yonetici olarak calistir' ile acin."
}
