# =====================================================================
#  KRT Saha - ERP gorevlerini OTURUM ACIK OLMASA DA calisir yapar.
#  Bilgisayar yeniden baslasa ya da Administrator oturumu kapansa da
#  "MK Saha ERP Aktarim" (telefondan gelen irsaliyeler) ve "KRT Saha ERP SQL Yedek"
#  calismaya devam eder. Pencere de acilmaz.
#  Windows sifresi BURADA, bu bilgisayarda sorulur; hicbir yere gonderilmez/kaydedilmez
#  (Gorev Zamanlayici kendi guvenli alaninda saklar).
#  Gorevlerin yaptigi isi DEGISTIRMEZ.
# =====================================================================
$Gorevler = @("MK Saha ERP Aktarim", "KRT Saha ERP SQL Yedek", "MK Mal Indir", "MK Cari Hareketleri", "MK Urun Hareketleri", "MK Sayim Yerel Kopya", "KRT Saha Yedek Indir")
try {
    $kullanici = "$env:COMPUTERNAME\$env:USERNAME"
    Write-Host "Gorevler '$kullanici' hesabiyla, oturum acik olmasa da calisacak."
    $gs = Read-Host "Bu Windows hesabinin sifresini yazin (ekranda gorunmez)" -AsSecureString
    $sifre = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($gs))
    if (-not $sifre) { throw "Sifre bos." }
    $n = 0
    foreach ($ad in $Gorevler) {
        $g = Get-ScheduledTask -TaskName $ad -ErrorAction SilentlyContinue
        if (-not $g) { Write-Host "YOK (atlandi): $ad"; continue }
        try {
            Set-ScheduledTask -TaskName $ad -TaskPath $g.TaskPath -User $kullanici -Password $sifre -ErrorAction Stop | Out-Null
            Write-Host "TAMAM: $ad - artik oturum kapali olsa da calisir"
            $n++
        } catch { Write-Host "HATA: $ad - $($_.Exception.Message)" }
    }
    $sifre = $null
    Write-Host ""
    Write-Host "$n gorev ayarlandi. Gorev Zamanlayici'da (F5) 'Kullanici oturum acmissa da acmamissa da calistir' gorunur."
} catch {
    Write-Host ""
    Write-Host "HATA: $($_.Exception.Message)"
    Write-Host "Sifre yanlis olabilir ya da bu dosya 'Yonetici olarak calistir' ile acilmamistir."
}
