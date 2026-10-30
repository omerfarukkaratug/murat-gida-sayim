# =====================================================================
#  MK Saha - Uygulamanin actigi MKS- stok kartlarini KASALARA gonderir.
#  Sebep: kasalar (POS bilgisayarlari) yeni kartlari ERP'nin degisiklik defterinden (SEQUNCES_DEGISIKLIK)
#  alir. ERP elle acilan kart icin bu deftere "yeni" (ISLEM=1) satirlari yazar; uygulamanin eski surumu
#  yazmiyordu, o yuzden MKS kartlari kasada okunmuyordu.
#  Bu program her MKS karti icin ERP'nin yazdigi 4 satirin aynisini yazar (STOK, STOK_STOK_BIRIM,
#  STOK_STOK_BIRIM_FIYAT, STOK_BARKOD). Stok kartlarinin KENDISINE DOKUNMAZ, yalnizca deftere satir ekler.
#  - Once tek bir barkodla denenir; kasada okununca hepsi gonderilir.
#  - Fiyati 0 olan kart gonderilmez (kasada 0 TL'ye satilmasin). Fiyat girilince program tekrar calistirilir.
#  - Daha once gonderilmis kart tekrar gonderilmez.
# =====================================================================
$SqlServer = "SERVER\ERP12"
$Log       = "C:\Scripts\kasa-kart-gonder-log.txt"
function Yaz($m) { $s = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $m"; Write-Host $m; try { Add-Content -Path $Log -Value $s } catch {} }

$bag = New-Object System.Data.SqlClient.SqlConnection("Server=$SqlServer;Database=master;Integrated Security=SSPI;")
function Sql($tx, $sql, $param) {
    $cmd = $bag.CreateCommand(); if ($tx) { $cmd.Transaction = $tx }; $cmd.CommandText = $sql; $cmd.CommandTimeout = 300
    if ($param) { foreach ($k in $param.Keys) { $v = $param[$k]; if ($v -eq $null) { $v = [DBNull]::Value }; [void]$cmd.Parameters.AddWithValue($k, $v) } }
    return $cmd
}
function Deger($tx, $sql, $param) { $v = (Sql $tx $sql $param).ExecuteScalar(); if ($v -is [DBNull]) { return $null }; return $v }
function Tablo($tx, $sql, $param) { $da = New-Object System.Data.SqlClient.SqlDataAdapter((Sql $tx $sql $param)); $t = New-Object System.Data.DataTable; [void]$da.Fill($t); return ,$t }

try {
    $bag.Open()
    # Aktif yil veri tabani (son 7 gunde belge girilen en yeni ERP12xxxx)
    $dbler = Tablo $null "SELECT name FROM sys.databases WHERE name LIKE 'ERP12[0-9][0-9][0-9][0-9]' AND state = 0 ORDER BY name DESC" $null
    $db = $null
    foreach ($d in $dbler.Rows) {
        $n = [int](Deger $null ("SELECT COUNT(*) FROM [" + $d.name + "].dbo.FIS WITH (NOLOCK) WHERE FIS_TARIHI >= DATEADD(day, -7, GETDATE())") $null)
        if ($n -gt 0) { $db = [string]$d.name; break }
    }
    if (-not $db) { throw "Aktif ERP veri tabani bulunamadi." }
    $bag.ChangeDatabase($db)
    Yaz "Veri tabani: $db"
    if ([int](Deger $null "SELECT COUNT(*) FROM sys.tables WHERE name = 'SEQUNCES_DEGISIKLIK'" $null) -eq 0) { throw "SEQUNCES_DEGISIKLIK tablosu yok - bu ERP'de kasa defteri farkli, islem yapilmadi." }

    Write-Host ""
    Write-Host "Once TEK bir urunle deneyin: kasada okunmayan bir MKS urununun barkodunu yazin."
    Write-Host "Kasada okundugunu gorunce programi tekrar calistirip 'HEPSI' yazin."
    $giris = (Read-Host "Barkod ya da HEPSI").Trim()
    if (-not $giris) { throw "Bir sey yazilmadi, islem yapilmadi." }

    $filtre = "s.KOD LIKE 'MKS-%'"; $p = @{}
    if ($giris -ne "HEPSI" -and $giris -ne "hepsi") { $filtre += " AND EXISTS (SELECT 1 FROM dbo.STOK_BARKOD_BIRIM bb WITH (NOLOCK) WHERE bb.STOK = s.ID AND bb.BARKOD = @b)"; $p["@b"] = $giris }
    $kartlar = Tablo $null ("SELECT s.ID, s.KOD, s.AD, (SELECT MAX(f.FIYAT) FROM dbo.STOK_STOK_BIRIM_FIYAT f WITH (NOLOCK) JOIN dbo.STOK_STOK_BIRIM u WITH (NOLOCK) ON u.ID = f.STOK_STOK_BIRIM WHERE u.STOK = s.ID) AS FIYAT FROM dbo.STOK s WITH (NOLOCK) WHERE " + $filtre + " ORDER BY s.KOD") $p
    if ($kartlar.Rows.Count -eq 0) { throw "MKS karti bulunamadi ($giris). Barkod uygulamanin actigi (MKS-) bir karta ait olmali." }

    $gonder = 0; $atla = 0; $zaten = 0
    foreach ($k in $kartlar.Rows) {
        $sid = [long]$k.ID; $ad = "$($k.KOD) $($k.AD)"
        $fiyat = if ($k.FIYAT -is [DBNull]) { 0 } else { [decimal]$k.FIYAT }
        if ($fiyat -le 0) { Yaz "ATLANDI (fiyat 0 - once ERP'de fiyat girin): $ad"; $atla++; continue }
        # Gonderilecek satirlar: ERP'nin yeni kartta yazdigi sirayla
        $satirlar = New-Object System.Collections.ArrayList
        [void]$satirlar.Add(@($sid, "STOK"))
        $birimler = Tablo $null "SELECT ID FROM dbo.STOK_STOK_BIRIM WITH (NOLOCK) WHERE STOK = @s ORDER BY ID" @{ "@s" = $sid }
        foreach ($u in $birimler.Rows) {
            $uid = [long]$u.ID
            [void]$satirlar.Add(@($uid, "STOK_STOK_BIRIM"))
            foreach ($f in (Tablo $null "SELECT ID FROM dbo.STOK_STOK_BIRIM_FIYAT WITH (NOLOCK) WHERE STOK_STOK_BIRIM = @u ORDER BY ID" @{ "@u" = $uid }).Rows) { [void]$satirlar.Add(@([long]$f.ID, "STOK_STOK_BIRIM_FIYAT")) }
            foreach ($b in (Tablo $null "SELECT ID FROM dbo.STOK_BARKOD WITH (NOLOCK) WHERE STOK_STOK_BIRIM = @u ORDER BY ID" @{ "@u" = $uid }).Rows) { [void]$satirlar.Add(@([long]$b.ID, "STOK_BARKOD")) }
        }
        $ids = ($satirlar | ForEach-Object { $_[0] }) -join ","
        $var = [int](Deger $null "SELECT COUNT(*) FROM dbo.SEQUNCES_DEGISIKLIK WITH (NOLOCK) WHERE ISLEM = 1 AND TABLO = 'STOK_BARKOD' AND SEQUNCES IN ($ids)" $null)
        if ($var -gt 0) { Yaz "ZATEN GONDERILMIS: $ad"; $zaten++; continue }
        $kodPc = Deger $null "SELECT KOD_PC FROM dbo.SEQUNCES WITH (NOLOCK) WHERE ID = @s" @{ "@s" = $sid }
        if ($kodPc -eq $null) { Yaz "ATLANDI (SEQUNCES kaydi yok): $ad"; $atla++; continue }
        $kul = Deger $null "SELECT TOP 1 KULLANICI FROM dbo.SEQUNCES_DEGISIKLIK WITH (NOLOCK) WHERE SEQUNCES = @s AND KULLANICI IS NOT NULL ORDER BY ID DESC" @{ "@s" = $sid }
        if ($kul -eq $null) { $kul = Deger $null "SELECT TOP 1 KULLANICI FROM dbo.SEQUNCES_DEGISIKLIK WITH (NOLOCK) WHERE KOD_PC = @p AND ISLEM = 1 AND TABLO = 'STOK' AND KULLANICI IS NOT NULL ORDER BY ID DESC" @{ "@p" = $kodPc } }
        if ($kul -eq $null) { $kul = [long]0 }
        $tx = $bag.BeginTransaction()
        try {
            foreach ($s in $satirlar) {
                [void](Sql $tx "INSERT INTO dbo.SEQUNCES_DEGISIKLIK (KOD_PC, SEQUNCES, KULLANICI, ISLEM, TARIH, TABLO) VALUES (@p, @s, @k, 1, GETDATE(), @t)" @{ "@p" = $kodPc; "@s" = $s[0]; "@k" = $kul; "@t" = $s[1] }).ExecuteNonQuery()
            }
            $tx.Commit()
            Yaz ("GONDERILDI ({0} satir, fiyat {1}): {2}" -f $satirlar.Count, $fiyat, $ad); $gonder++
        } catch { try { $tx.Rollback() } catch {}; Yaz "HATA ($ad): $($_.Exception.Message)" }
    }
    Write-Host ""
    Yaz "OZET: gonderilen $gonder, zaten gonderilmis $zaten, atlanan $atla"
    if ($gonder -gt 0) { Write-Host "Kasalar degisiklikleri birkac dakika icinde alir. Gelmezse kasa programini kapatip acin, sonra barkodu okutun." }
} catch {
    Yaz "HATA: $($_.Exception.Message)"
} finally { try { $bag.Close() } catch {} }
Read-Host "Kapatmak icin Enter"
