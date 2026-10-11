# =====================================================================
#  Murat Gida - Gorev Zamanlayici: "MK Cari Hareketleri" gorevini ekler.
#  Var olan "MK Urun Hareketleri" gorevini kopyalar (ayni kullanici, ayni
#  saatlik calisma), sadece calisan dosyayi cari-hareket-gonder.ps1 yapar.
#  ERP12'ye ve diger gorevlere DOKUNMAZ.
# =====================================================================
$Kaynak = "MK Urun Hareketleri"
$Yeni   = "MK Cari Hareketleri"
try {
    $xml = (schtasks.exe /Query /TN $Kaynak /XML | Out-String)
    if (-not $xml -or $xml -notmatch "hareket-gonder\.ps1") { throw "'$Kaynak' gorevi bulunamadi ya da hareket-gonder.ps1 calistirmiyor." }
    $xml = $xml -replace "(?<!cari-)hareket-gonder\.ps1", "cari-hareket-gonder.ps1"
    $kullanici = ""; if ($xml -match "<UserId>([^<]+)</UserId>") { $kullanici = $Matches[1] }
    $sifreli = $xml -match "<LogonType>Password</LogonType>"
    if (Get-ScheduledTask -TaskName $Yeni -ErrorAction SilentlyContinue) { Unregister-ScheduledTask -TaskName $Yeni -Confirm:$false }
    if ($sifreli -and $kullanici) {
        Write-Host "Gorev '$kullanici' hesabiyla calisacak."
        $sifre = Read-Host "Bu Windows hesabinin sifresini yaz (ekranda gorunmez)" -AsSecureString
        $duz = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sifre))
        Register-ScheduledTask -Xml $xml -TaskName $Yeni -User $kullanici -Password $duz | Out-Null
    } else {
        Register-ScheduledTask -Xml $xml -TaskName $Yeni | Out-Null
    }
    Write-Host ""
    Write-Host "TAMAM: '$Yeni' gorevi eklendi. Gorev Zamanlayici'da listeyi yenile (F5)."
} catch {
    Write-Host ""
    Write-Host "HATA: $($_.Exception.Message)"
}
Read-Host "Kapatmak icin Enter"
