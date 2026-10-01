# =====================================================================
#  Murat Gıda - Bulut (Supabase) -> YEREL SQL Server kopyası
# =====================================================================
#  Ne yapar: Buluttaki sayım ve mal kayıtlarından YENİ/DEĞİŞEN olanları
#  çekip bu bilgisayardaki MK_SAYIM veri tabanına yazar; buluttan silinenleri
#  burada da siler. İnternet kesilse bile son kopya mağazada durur.
#
#  - ERP12'nin veri tabanına HİÇ DOKUNMAZ (sadece MK_SAYIM).
#  - Buluta hiçbir şey YAZMAZ, sadece okur.
#  - Tekrar tekrar çalıştırmak güvenlidir (aynı kayıt iki kez yazılmaz).
#
#  Kurulum (bir kez):
#   1) SSMS'te MK_SAYIM_kurulum.sql çalıştırılmış olmalı.
#   2) C:\Scripts\db-anahtar.txt içinde Supabase "secret" anahtarı (tek satır).
#   3) Görev Zamanlayıcı: her 10 dakikada bir
#        powershell.exe -ExecutionPolicy Bypass -File "C:\Scripts\yerel-kopya.ps1"
# =====================================================================

# ---------------------- AYARLAR ----------------------
# MK_SAYIM, ERP12'den AYRI olan varsayilan SQL Server'da (SERVER) kuruldu.
$SqlServer        = "SERVER"
$YerelVeriTabani  = "MK_SAYIM"
$DbUrl            = "https://wjyqempcmyrmruhdpcwk.supabase.co"
$DbAnahtarDosyasi = "C:\Scripts\db-anahtar.txt"
$LogFile          = "C:\Scripts\yerel-kopya-log.txt"
$SayfaBoyutu      = 1000
# Ayni anda yazilan kayitlar kacmasin diye her seferinde 10 dk geriden baslanir.
$GeriPayDakika    = 10
# -----------------------------------------------------

try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}

function Yaz-Log($mesaj) {
    $satir = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $mesaj"
    Write-Host $satir
    try { Add-Content -Path $LogFile -Value $satir -ErrorAction SilentlyContinue } catch {}
}

# ISO zaman metni -> yerel saat (DateTime) ya da DBNull
function Zaman($v) {
    if ($v -eq $null -or [string]$v -eq "") { return [DBNull]::Value }
    if ($v -is [datetime]) { return $v.ToLocalTime() }
    return ([DateTimeOffset]::Parse([string]$v, [Globalization.CultureInfo]::InvariantCulture)).LocalDateTime
}
function Sayi($v) {
    if ($v -eq $null -or [string]$v -eq "") { return [DBNull]::Value }
    return [decimal]::Parse([string]$v, [Globalization.CultureInfo]::InvariantCulture)
}
function Metin($v) { if ($v -eq $null) { return [DBNull]::Value }; return [string]$v }
function Mantik($v) { if ($v -eq $null) { return [DBNull]::Value }; return [bool]$v }
function Tam($v) { if ($v -eq $null -or [string]$v -eq "") { return [DBNull]::Value }; return [long]$v }

# Buluttan sayfa sayfa çek. $filtre örn: "guncelleme=gte.2026-10-01T09:00:00Z"
function Buluttan-Cek($tablo, $filtre, $sira) {
    $hepsi = New-Object System.Collections.ArrayList
    $offset = 0
    while ($true) {
        $url = "$DbUrl/rest/v1/$tablo" + "?select=*&order=$sira&limit=$SayfaBoyutu&offset=$offset"
        if ($filtre) { $url += "&$filtre" }
        $sayfa = Invoke-RestMethod -Uri $url -Method Get -Headers @{ apikey = $script:Anahtar } -TimeoutSec 120
        $liste = @($sayfa)
        foreach ($s in $liste) { [void]$hepsi.Add($s) }
        if ($liste.Count -lt $SayfaBoyutu) { break }
        $offset += $SayfaBoyutu
    }
    return ,$hepsi
}

function Sql-Calistir($baglanti, $sql) {
    $cmd = $baglanti.CreateCommand(); $cmd.CommandText = $sql; $cmd.CommandTimeout = 300
    return $cmd.ExecuteNonQuery()
}
function Sql-Deger($baglanti, $sql) {
    $cmd = $baglanti.CreateCommand(); $cmd.CommandText = $sql; $cmd.CommandTimeout = 120
    return $cmd.ExecuteScalar()
}

function Durum-Oku($baglanti, $tablo) {
    $v = Sql-Deger $baglanti "SELECT SON_DEGISIM FROM dbo.KOPYA_DURUMU WHERE TABLO = N'$tablo'"
    if ($v -eq $null -or $v -is [DBNull] -or [string]$v -eq "") { return $null }
    return [DateTimeOffset]::Parse([string]$v, [Globalization.CultureInfo]::InvariantCulture)
}
function Durum-Yaz($baglanti, $tablo, $sonDegisim, $satir, $mesaj) {
    $cmd = $baglanti.CreateCommand()
    $cmd.CommandText = @"
IF EXISTS (SELECT 1 FROM dbo.KOPYA_DURUMU WHERE TABLO = @t)
  UPDATE dbo.KOPYA_DURUMU SET SON_DEGISIM = ISNULL(@d, SON_DEGISIM), SON_CALISMA = GETDATE(), SON_SATIR = @s, MESAJ = @m WHERE TABLO = @t
ELSE
  INSERT INTO dbo.KOPYA_DURUMU (TABLO, SON_DEGISIM, SON_CALISMA, SON_SATIR, MESAJ) VALUES (@t, @d, GETDATE(), @s, @m)
"@
    [void]$cmd.Parameters.AddWithValue("@t", $tablo)
    $dp = $cmd.Parameters.Add("@d", [Data.SqlDbType]::NVarChar, 40)
    if ($sonDegisim -ne $null) { $dp.Value = $sonDegisim.UtcDateTime.ToString("yyyy-MM-ddTHH:mm:ss.ffffffZ") } else { $dp.Value = [DBNull]::Value }
    [void]$cmd.Parameters.AddWithValue("@s", [int]$satir)
    [void]$cmd.Parameters.AddWithValue("@m", [string]$mesaj)
    [void]$cmd.ExecuteNonQuery()
}

# Satırları geçici tabloya toplu yükleyip hedefe MERGE eder (ekle ya da güncelle).
# $kolonlar: @( @("SQL_ADI", [tip], { param($r) dönüşüm }) ... ), ilk kolon anahtar.
function Yerele-Yaz($baglanti, $hedef, $kolonlar, $satirlar) {
    if ($satirlar.Count -eq 0) { return 0 }
    # Aynı kayıt iki kez geldiyse (sayfalar arasında değişmişse) sadece SONUNCUSU kalsın —
    # yoksa MERGE "aynı satır birden fazla kez" hatası verir.
    $tekil = @{}
    $anahtarAl = $kolonlar[0][2]
    foreach ($r in $satirlar) { $tekil[[string](& $anahtarAl $r)] = $r }
    $dt = New-Object System.Data.DataTable
    foreach ($k in $kolonlar) { [void]$dt.Columns.Add($k[0], $k[1]) }
    foreach ($r in $tekil.Values) {
        $row = $dt.NewRow()
        foreach ($k in $kolonlar) { $row[$k[0]] = & $k[2] $r }
        [void]$dt.Rows.Add($row)
    }
    $adlar = @($kolonlar | ForEach-Object { $_[0] })
    $anahtar = $adlar[0]
    [void](Sql-Calistir $baglanti "IF OBJECT_ID('tempdb..#GELEN') IS NOT NULL DROP TABLE #GELEN; SELECT TOP 0 $($adlar -join ', ') INTO #GELEN FROM dbo.$hedef;")
    $bc = New-Object System.Data.SqlClient.SqlBulkCopy($baglanti)
    $bc.DestinationTableName = "#GELEN"; $bc.BulkCopyTimeout = 300
    foreach ($a in $adlar) { [void]$bc.ColumnMappings.Add($a, $a) }
    $bc.WriteToServer($dt)
    $guncelle = ($adlar | Where-Object { $_ -ne $anahtar } | ForEach-Object { "h.$_ = g.$_" }) -join ", "
    $sql = @"
MERGE dbo.$hedef AS h
USING (SELECT * FROM #GELEN) AS g ON h.$anahtar = g.$anahtar
WHEN MATCHED THEN UPDATE SET $guncelle
WHEN NOT MATCHED THEN INSERT ($($adlar -join ', ')) VALUES ($(($adlar | ForEach-Object { "g.$_" }) -join ', '));
DROP TABLE #GELEN;
"@
    [void](Sql-Calistir $baglanti $sql)
    return $dt.Rows.Count
}

# Bir tabloyu kopyala: son kopyalanan değişiklikten (10 dk pay ile) sonrasını çek.
function Tablo-Kopyala($baglanti, $bulutTablo, $zamanSutunu, $yerelTablo, $kolonlar, $silinecekYerelTablo) {
    $son = Durum-Oku $baglanti $yerelTablo
    $filtre = $null
    if ($son -ne $null) {
        $baslangic = $son.AddMinutes(-$GeriPayDakika).UtcDateTime.ToString("yyyy-MM-ddTHH:mm:ss.ffffffZ")
        $filtre = "$zamanSutunu=gte." + [Uri]::EscapeDataString($baslangic)
    }
    $satirlar = Buluttan-Cek $bulutTablo $filtre "$zamanSutunu.asc,kayit_id.asc"
    $n = Yerele-Yaz $baglanti $yerelTablo $kolonlar $satirlar
    # Silinenler tablosuysa: ana tablodan da sil.
    if ($silinecekYerelTablo) {
        [void](Sql-Calistir $baglanti "DELETE k FROM dbo.$silinecekYerelTablo k INNER JOIN dbo.$yerelTablo s ON s.KAYIT_ID = k.KAYIT_ID;")
    }
    $enSon = $son
    foreach ($r in $satirlar) {
        $z = $r.$zamanSutunu
        if ($z -ne $null -and [string]$z -ne "") {
            $zo = if ($z -is [datetime]) { New-Object DateTimeOffset($z) } else { [DateTimeOffset]::Parse([string]$z, [Globalization.CultureInfo]::InvariantCulture) }
            if ($enSon -eq $null -or $zo -gt $enSon) { $enSon = $zo }
        }
    }
    Durum-Yaz $baglanti $yerelTablo $enSon $n "ok"
    return $n
}

# ---------------------------------------------------------------------
$baglanti = $null
try {
    if (-not (Test-Path $DbAnahtarDosyasi)) { Yaz-Log "HATA: $DbAnahtarDosyasi yok."; exit 1 }
    $script:Anahtar = (Get-Content -Path $DbAnahtarDosyasi -TotalCount 1).Trim()

    $baglanti = New-Object System.Data.SqlClient.SqlConnection("Server=$SqlServer;Database=$YerelVeriTabani;Integrated Security=SSPI;")
    $baglanti.Open()

    # 1) Dönemler (az satır: her seferinde hepsi)
    $donemler = Buluttan-Cek "sayim_donemleri" $null "id.asc"
    $nDonem = Yerele-Yaz $baglanti "SAYIM_DONEMLERI" @(
        @("ID", [long], { param($r) Tam $r.id }),
        @("TOKEN", [string], { param($r) Metin $r.token }),
        @("BASLANGIC", [datetime], { param($r) Zaman $r.baslangic }),
        @("ACIKLAMA", [string], { param($r) Metin $r.aciklama })
    ) $donemler

    # 2) Sayım kayıtları
    $nSayim = Tablo-Kopyala $baglanti "sayim_kayitlari" "guncelleme" "SAYIM_KAYITLARI" @(
        @("KAYIT_ID", [string], { param($r) Metin $r.kayit_id }),
        @("OTURUM_ID", [string], { param($r) Metin $r.oturum_id }),
        @("DONEM_ID", [long], { param($r) Tam $r.donem_id }),
        @("GEC_GELDI", [bool], { param($r) Mantik $r.gec_geldi }),
        @("PERSONEL", [string], { param($r) Metin $r.personel }),
        @("URUN_ADI", [string], { param($r) Metin $r.urun_adi }),
        @("STOK_KODU", [string], { param($r) Metin $r.stok_kodu }),
        @("BARKOD", [string], { param($r) Metin $r.barkod }),
        @("BIRIM", [string], { param($r) Metin $r.birim }),
        @("ESKI_STOK", [decimal], { param($r) Sayi $r.eski_stok }),
        @("ADET", [decimal], { param($r) Sayi $r.adet }),
        @("FARK", [decimal], { param($r) Sayi $r.fark }),
        @("REYON", [string], { param($r) Metin $r.reyon }),
        @("SUBE", [string], { param($r) Metin $r.sube }),
        @("SURUM", [int], { param($r) Tam $r.surum }),
        @("OKUTMA_TARIHI", [string], { param($r) Metin $r.okutma_tarihi }),
        @("OKUTMA_SAATI", [string], { param($r) Metin $r.okutma_saati }),
        @("OKUTMA_ZAMANI", [datetime], { param($r) Zaman $r.okutma_zamani }),
        @("OLUSTURMA", [datetime], { param($r) Zaman $r.olusturma }),
        @("GUNCELLEME", [datetime], { param($r) Zaman $r.guncelleme })
    ) $null

    # 3) Silinen sayım kayıtları -> yerelden de sil
    $nSil = Tablo-Kopyala $baglanti "silinen_kayitlar" "zaman" "SILINEN_KAYITLAR" @(
        @("KAYIT_ID", [string], { param($r) Metin $r.kayit_id }),
        @("OTURUM_ID", [string], { param($r) Metin $r.oturum_id }),
        @("SILEN", [string], { param($r) Metin $r.silen }),
        @("ZAMAN", [datetime], { param($r) Zaman $r.zaman })
    ) "SAYIM_KAYITLARI"

    # 4) Mal hareketleri
    $nMal = Tablo-Kopyala $baglanti "mal_hareketleri" "guncelleme" "MAL_HAREKETLERI" @(
        @("KAYIT_ID", [string], { param($r) Metin $r.kayit_id }),
        @("BATCH_ID", [string], { param($r) Metin $r.batch_id }),
        @("TIP", [string], { param($r) Metin $r.tip }),
        @("BELGE_TURU", [string], { param($r) Metin $r.belge_turu }),
        @("BELGE_NO", [string], { param($r) Metin $r.belge_no }),
        @("CARI", [string], { param($r) Metin $r.cari }),
        @("CARI_KODU", [string], { param($r) Metin $r.cari_kodu }),
        @("SEBEP", [string], { param($r) Metin $r.sebep }),
        @("PERSONEL", [string], { param($r) Metin $r.personel }),
        @("BARKOD", [string], { param($r) Metin $r.barkod }),
        @("URUN_ADI", [string], { param($r) Metin $r.urun_adi }),
        @("STOK_KODU", [string], { param($r) Metin $r.stok_kodu }),
        @("MIKTAR", [decimal], { param($r) Sayi $r.miktar }),
        @("BIRIM", [string], { param($r) Metin $r.birim }),
        @("KDV", [decimal], { param($r) Sayi $r.kdv }),
        @("FIYAT", [decimal], { param($r) Sayi $r.fiyat }),
        @("SURUM", [int], { param($r) Tam $r.surum }),
        @("ACIKLAMA", [string], { param($r) Metin $r.aciklama }),
        @("KONUM", [string], { param($r) Metin $r.konum }),
        @("TARIH", [string], { param($r) Metin $r.tarih }),
        @("SAAT", [string], { param($r) Metin $r.saat }),
        @("AKTARILDI", [datetime], { param($r) Zaman $r.aktarildi }),
        @("OLUSTURMA", [datetime], { param($r) Zaman $r.olusturma }),
        @("GUNCELLEME", [datetime], { param($r) Zaman $r.guncelleme })
    ) $null

    # 5) Telefonda silinen mal kalemleri -> yerelden de sil
    $nMalSil = Tablo-Kopyala $baglanti "mal_silinenler" "zaman" "MAL_SILINENLER" @(
        @("KAYIT_ID", [string], { param($r) Metin $r.kayit_id }),
        @("BATCH_ID", [string], { param($r) Metin $r.batch_id }),
        @("ZAMAN", [datetime], { param($r) Zaman $r.zaman })
    ) "MAL_HAREKETLERI"

    $toplam = Sql-Deger $baglanti "SELECT COUNT(*) FROM dbo.SAYIM_KAYITLARI"
    Yaz-Log "TAMAM: donem $nDonem, sayim $nSayim, silinen $nSil, mal $nMal, mal silinen $nMalSil (pay dahil). Yerelde toplam sayim satiri: $toplam"
}
catch {
    Yaz-Log "HATA: $($_.Exception.Message)"
    exit 1
}
finally {
    if ($baglanti -ne $null) { $baglanti.Close() }
}
