# =====================================================================
#  Murat Gıda - Telefondaki Mal Giriş / Mal Çıkış -> ERP12 SİPARİŞ
# =====================================================================
#  Ne yapar: Telefondan kaydedilen Mal Giriş / Mal Çıkış belgelerini
#  (bulut veri tabanından) alır ve ERP12'ye SİPARİŞ olarak yazar:
#    Mal Giriş  -> Verilen Sipariş (SIPARIS_TURU 1), seri "MOB VRLN-"
#    Mal Çıkış  -> Alınan Sipariş  (SIPARIS_TURU 2), seri "MOB LNN-"
#  Sipariş stoğa ve cariye etki etmez; ERP'de faturaya çevrilir.
#
#  Fiyatlar:
#    Verilen sipariş: ürünün ERP'deki SON ALIŞ fiyatı (KDV hariç).
#    Alınan sipariş : telefondaki fiyat (katalogdaki KDV dahil satış fiyatı).
#
#  Güvenlik:
#  - Sadece AYARLAR'daki $Database'e yazar (otomatik seçim YOK). İlk denemeler
#    ERP'nin KOPYASINDA yapılır (örn. ERP122025_TEST).
#  - Her belge tek bir işlemde (transaction) yazılır: ya hepsi ya hiçbiri.
#  - Numaralar ERP'nin kendi ortak sayacından (dbo.ID) alınır.
#  - Aynı belge iki kez aktarılmaz (bulut kaydı + yerel liste).
#  - Aktarıldıktan sonra telefonda değiştirilen belgeye DOKUNULMAZ, sadece
#    uyarı yazılır (düzeltme ERP'de elle yapılır).
#  - Telefonda kaydedildikten sonra $BekleDakika dakika beklenir (personel
#    hâlâ düzeltiyor olabilir).
# =====================================================================

# ---------------------- AYARLAR ----------------------
$SqlServer        = "SERVER\ERP12"
$Database         = "ERP122025_TEST"
$DbUrl            = "https://wjyqempcmyrmruhdpcwk.supabase.co"
$DbAnahtarDosyasi = "C:\Scripts\db-anahtar.txt"
$LogFile          = "C:\Scripts\siparis-aktar-log.txt"
$AktarilanDosya   = "C:\Scripts\siparis-aktarilan.txt"
# Bu tarihten ONCE telefonda olusturulan belgeler aktarilmaz (gecmisi doldurmasin).
$BaslangicTarihi  = "2026-11-01"
$BekleDakika      = 10
$SeriVerilen      = "MOB VRLN-"
$SeriAlinan       = "MOB LNN-"
# -----------------------------------------------------

try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}
$Inv = [Globalization.CultureInfo]::InvariantCulture

function Yaz-Log($mesaj) {
    $satir = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $mesaj"
    Write-Host $satir
    try { Add-Content -Path $LogFile -Value $satir -ErrorAction SilentlyContinue } catch {}
}

function Rpc($fonksiyon, $govde) {
    $json = $govde | ConvertTo-Json -Depth 6 -Compress
    $baytlar = [System.Text.Encoding]::UTF8.GetBytes($json)
    return Invoke-RestMethod -Uri "$DbUrl/rest/v1/rpc/$fonksiyon" -Method Post -Body $baytlar `
        -ContentType "application/json; charset=utf-8" -Headers @{ apikey = $script:Anahtar } -TimeoutSec 120 -UserAgent "MK-Sayim/1.0"
}

function Bildir($b, $siparisId, $belgeNo, $durum, $mesaj) {
    $r = Rpc "siparis_aktarildi" @{ p_batch = [string]$b.batch_id; p_tip = [string]$b.tip; p_kaynak = $Database; p_siparis_id = $siparisId
        p_belge_no = $belgeNo; p_imza = [string]$b.imza; p_durum = $durum; p_mesaj = $mesaj }
    if (-not $r -or [string]$r.status -ne "ok") { throw "Buluta bildirilemedi: $($r | ConvertTo-Json -Compress)" }
}

function Sql($tx, $sql, $param) {
    $cmd = $tx.Connection.CreateCommand(); $cmd.Transaction = $tx; $cmd.CommandText = $sql; $cmd.CommandTimeout = 120
    if ($param) { foreach ($k in $param.Keys) { $v = $param[$k]; if ($v -eq $null) { $v = [DBNull]::Value }; [void]$cmd.Parameters.AddWithValue($k, $v) } }
    return $cmd
}
function Deger($tx, $sql, $param) { $v = (Sql $tx $sql $param).ExecuteScalar(); if ($v -is [DBNull]) { return $null }; return $v }
function Tablo($tx, $sql, $param) {
    $da = New-Object System.Data.SqlClient.SqlDataAdapter((Sql $tx $sql $param))
    $dt = New-Object System.Data.DataTable; [void]$da.Fill($dt); return ,$dt
}
function Yuvarla($x, $n) { return [Math]::Round([decimal]$x, $n, [MidpointRounding]::AwayFromZero) }
function Kisalt($s, $n) { $s = [string]$s; if ($n -gt 0 -and $s.Length -gt $n) { return $s.Substring(0, $n) }; return $s }

$SIP_KOLON = @("ID","SIPARIS_TURU","LOKASYON","CARI","CARI_ADRES","PROJE","BELGENO","SIPARIS_TARIHI","TERMIN_TARIHI","ISLEM_TARIHI","VADE_TARIHI",
    "DOVIZ_AD","DOVIZ_KUR","CARI_PERSONEL","SATIR_TOPLAM","SATIR_ISKONTO_TOPLAM","SIPARIS_ISKONTO_ORAN","SIPARIS_ISKONTO_TOPLAM","YUVARLAMA",
    "KDV_TOPLAM","OTV_TOPLAM","TEFKIFAT_TOPLAM","GENELTOPLAM","ACIKLAMA","FIS","AKTIF","SIPARIS_OZEL_KOD_1","SIPARIS_OZEL_KOD_2",
    "SIPARIS_OZEL_KOD_3","SIPARIS_OZEL_KOD_4","SIPARIS_OZEL_KOD_5","GONDERIM_ADRESI","ONAYLI","VADE_SECENEKLERI","BELGE_YETKILISI",
    "YAZILDI","EMAIL_GONDERILDI","NAKLIYE_ODEME_TIPI","SEVK_SEKLI","KARSI_SIPARIS_NO","ARTTIRIM","DOVIZ_KUR_SECIMI",
    "FIS_ODEME_TIPI_ISKONTOLARI","IHRACAT_GONDERIM_SEKLI","IHRACAT_TESLIM_SEKLI","FIS_ALT_TIPI")
$DET_KOLON = @("ID","SIPARIS","LOKASYON","STOK","STOK_CINSI","STOK_BIRIM","BARKOD","KOLI_BARKODU","DOVIZ_AD","CARPAN","KAB","MIKTAR_FIS",
    "MIKTAR_BEDELSIZ","ANLASMA_FIYAT","FIYAT","DAHIL_FIYAT","TUTAR","DAHIL_TUTAR","ISKONTO","ISKONTO_HESAP","OTV_ORAN","OTV_TUTAR",
    "KDV_TOPTAN","TEVKIF","KUR","FIYAT_FARKI","SERINO_ZORUNLU","YEREL_KARSI_FIYAT","BELGE_TARIHINDEKI_SON_ALIS_FIYATI","HK_MIKTAR_FIS",
    "TOPLAM_SATIR_ISKONTOSU","TOPLAM_FIS_ISKONTOSU","TOPLAM_OTV","TOPLAM_KDV_MATRAHI","TOPLAM_KDV","TOPLAM_TEVKIF","HESAPLANAN_FIYAT",
    "YEREL_FIYAT","ACIKLAMA","KOD","ONERILEN_FIYAT","JOKER","AMBALAJ_BIRIM","AMBALAJ_MIKTAR","AMBALAJ_CARPAN","FK_STOK_TEVKIF_LESTE",
    "FK_PERSONEL","ALT_BIRIM_MIKTARI","SEVK_ADRES","BUNDLE_DETAY","KT_BUNDLE_FIYAT","LISTE_FIYATI")

function Ekle($tx, $tablo, $kolonlar, $deger) {
    $p = @{}; foreach ($k in $kolonlar) { $p["@$k"] = $deger[$k] }
    $sql = "INSERT INTO dbo.$tablo (" + ($kolonlar -join ", ") + ") VALUES (" + (($kolonlar | ForEach-Object { "@$_" }) -join ", ") + ")"
    [void](Sql $tx $sql $p).ExecuteNonQuery()
}

# Bir telefon belgesini ERP'ye yaz. Doner: @{ id; belge; uyari }
function Belge-Yaz($baglanti, $b) {
    $giris = ([string]$b.tip).StartsWith("G")
    $tur = if ($giris) { 1 } else { 2 }
    $seri = if ($giris) { $SeriVerilen } else { $SeriAlinan }
    $tx = $baglanti.BeginTransaction([System.Data.IsolationLevel]::Serializable)
    try {
        # --- Cari ---
        $cari = $null
        if ([string]$b.cari_kodu) { $cari = Deger $tx "SELECT TOP 1 ID FROM dbo.CARI WHERE KOD = @k ORDER BY ID" @{ "@k" = [string]$b.cari_kodu } }
        if (-not $cari -and [string]$b.cari) { $cari = Deger $tx "SELECT TOP 1 ID FROM dbo.CARI WHERE AD = @a ORDER BY ID" @{ "@a" = [string]$b.cari } }
        if (-not $cari) { throw "Cari ERP'de bulunamadi: '$($b.cari)' (kod '$($b.cari_kodu)')" }
        $adres = Deger $tx "SELECT TOP 1 ID FROM dbo.CARI_ADRES WHERE CARI = @c ORDER BY ID" @{ "@c" = $cari }
        if (-not $adres) { $adres = 0 }

        # --- Lokasyon / proje: ERP'nin kendi son siparisinden (yoksa son fisten) ---
        $lp = Tablo $tx "SELECT TOP 1 LOKASYON, PROJE FROM dbo.SIPARIS WHERE BELGENO NOT LIKE 'MOB %' ORDER BY ID DESC" $null
        if ($lp.Rows.Count -eq 0) { $lp = Tablo $tx "SELECT TOP 1 LOKASYON, PROJE FROM dbo.FIS ORDER BY ID DESC" $null }
        if ($lp.Rows.Count -eq 0) { throw "LOKASYON/PROJE bulunamadi" }
        $lokasyon = $lp.Rows[0].LOKASYON; $proje = $lp.Rows[0].PROJE

        # --- KDV sutunu ---
        $kdvKolon = Deger $tx "SELECT TOP 1 name FROM sys.columns WHERE object_id = OBJECT_ID('dbo.STOK_VERGI') AND name IN ('KDV_TOPTAN','KDV_PAREKENDE') ORDER BY CASE name WHEN 'KDV_TOPTAN' THEN 0 ELSE 1 END" $null

        # --- Satirlar ---
        $satirlar = New-Object System.Collections.ArrayList
        $atlanan = New-Object System.Collections.ArrayList
        foreach ($r in @($b.satirlar)) {
            $bb = Tablo $tx "SELECT TOP 1 bb.STOK, bb.STOK_BIRIM, s.KOD, ISNULL(v.$kdvKolon, 0) AS KDV FROM dbo.STOK_BARKOD_BIRIM bb JOIN dbo.STOK s ON s.ID = bb.STOK LEFT JOIN dbo.STOK_VERGI v ON v.ID = s.STOK_VERGI WHERE bb.BARKOD = @b" @{ "@b" = [string]$r.barkod }
            if ($bb.Rows.Count -eq 0) { [void]$atlanan.Add("$($r.barkod) $($r.urun_adi)"); continue }
            $stok = $bb.Rows[0].STOK; $kdv = [decimal]$bb.Rows[0].KDV; $miktar = [decimal]$r.miktar
            $sonAlis = Deger $tx "SELECT TOP 1 d.FIYAT FROM dbo.FIS_DETAY d JOIN dbo.FIS f ON f.ID = d.FIS WHERE d.STOK = @s AND f.FIS_TURU IN (1, 5) AND d.FIYAT > 0 ORDER BY f.FIS_TARIHI DESC, d.ID DESC" @{ "@s" = $stok }
            if ($sonAlis -eq $null) { $sonAlis = [decimal]0 } else { $sonAlis = [decimal]$sonAlis }
            if ($giris) {
                $fiyat = $sonAlis
                $dahil = Yuvarla ($fiyat * (1 + $kdv / 100)) 4
            } else {
                $dahil = if ($r.fiyat -ne $null) { [decimal]$r.fiyat } else { [decimal]0 }
                $fiyat = Yuvarla ($dahil / (1 + $kdv / 100)) 4
            }
            $tutar = Yuvarla ($fiyat * $miktar) 4
            [void]$satirlar.Add(@{ stok = $stok; birim = $bb.Rows[0].STOK_BIRIM; kod = [string]$bb.Rows[0].KOD; barkod = [string]$r.barkod
                kdv = $kdv; miktar = $miktar; fiyat = $fiyat; dahil = $dahil; tutar = $tutar; dahilTutar = (Yuvarla ($dahil * $miktar) 4)
                kdvTutar = (Yuvarla ($tutar * $kdv / 100) 4); sonAlis = $sonAlis })
        }
        if ($satirlar.Count -eq 0) { throw "Hicbir urun ERP'de bulunamadi: $($atlanan -join ', ')" }

        # --- Belge numarasi: kendi serimizin en buyugu + 1 (kilitli) ---
        $son = Deger $tx "SELECT MAX(BELGENO) FROM dbo.SIPARIS WITH (UPDLOCK, HOLDLOCK) WHERE BELGENO LIKE @p" @{ "@p" = "$seri%" }
        $no = 1
        if ($son) { $no = [int]([string]$son).Substring($seri.Length) + 1 }
        $belgeNo = $seri + $no.ToString("000000")

        # --- Aciklama (sutun uzunluguna gore) ---
        $acikMax = Deger $tx "SELECT max_length / 2 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.SIPARIS') AND name = 'ACIKLAMA'" $null
        $acik = ("Telefon: " + (@([string]$b.belge_turu, [string]$b.belge_no) | Where-Object { $_ }) -join " ") + " / $($b.personel)"
        if ([string]$b.sebep) { $acik += " / $($b.sebep)" }
        if ([string]$b.aciklama) { $acik += " / $($b.aciklama)" }
        if ($atlanan.Count -gt 0) { $acik += " / ERP'de olmayan: " + ($atlanan -join ", ") }
        if ($acikMax -and [int]$acikMax -gt 0) { $acik = Kisalt $acik ([int]$acikMax) }

        # --- Baslik ---
        $id = [long](Deger $tx "SELECT NEXT VALUE FOR dbo.ID" $null)
        $tarih = [DateTimeOffset]::Parse([string]$b.tarih, $Inv).LocalDateTime
        $satirToplam = ($satirlar | ForEach-Object { $_.tutar } | Measure-Object -Sum).Sum
        $kdvToplam = ($satirlar | ForEach-Object { $_.kdvTutar } | Measure-Object -Sum).Sum
        $genel = ($satirlar | ForEach-Object { $_.dahilTutar } | Measure-Object -Sum).Sum
        Ekle $tx "SIPARIS" $SIP_KOLON @{ ID = $id; SIPARIS_TURU = $tur; LOKASYON = $lokasyon; CARI = $cari; CARI_ADRES = $adres; PROJE = $proje
            BELGENO = $belgeNo; SIPARIS_TARIHI = $tarih; TERMIN_TARIHI = $tarih.Date.AddDays(1); ISLEM_TARIHI = (Get-Date); VADE_TARIHI = $tarih.Date
            DOVIZ_AD = 1; DOVIZ_KUR = 1; CARI_PERSONEL = 0; SATIR_TOPLAM = (Yuvarla $satirToplam 2); SATIR_ISKONTO_TOPLAM = 0
            SIPARIS_ISKONTO_ORAN = "          "; SIPARIS_ISKONTO_TOPLAM = 0; YUVARLAMA = 0; KDV_TOPLAM = (Yuvarla $kdvToplam 2); OTV_TOPLAM = 0
            TEFKIFAT_TOPLAM = 0; GENELTOPLAM = (Yuvarla $genel 2); ACIKLAMA = $acik; FIS = 0; AKTIF = $true
            SIPARIS_OZEL_KOD_1 = 0; SIPARIS_OZEL_KOD_2 = 0; SIPARIS_OZEL_KOD_3 = 0; SIPARIS_OZEL_KOD_4 = 0; SIPARIS_OZEL_KOD_5 = 0
            GONDERIM_ADRESI = $adres; ONAYLI = $true; VADE_SECENEKLERI = 7; BELGE_YETKILISI = 0; YAZILDI = $false; EMAIL_GONDERILDI = $false
            NAKLIYE_ODEME_TIPI = 0; SEVK_SEKLI = 0; KARSI_SIPARIS_NO = ""; ARTTIRIM = 0; DOVIZ_KUR_SECIMI = 2; FIS_ODEME_TIPI_ISKONTOLARI = 1
            IHRACAT_GONDERIM_SEKLI = 0; IHRACAT_TESLIM_SEKLI = 0; FIS_ALT_TIPI = 1 }

        # --- Satirlar ---
        foreach ($s in $satirlar) {
            $did = [long](Deger $tx "SELECT NEXT VALUE FOR dbo.ID" $null)
            Ekle $tx "SIPARIS_DETAY" $DET_KOLON @{ ID = $did; SIPARIS = $id; LOKASYON = $lokasyon; STOK = $s.stok; STOK_CINSI = 1; STOK_BIRIM = $s.birim
                BARKOD = $s.barkod; KOLI_BARKODU = ""; DOVIZ_AD = 1; CARPAN = 1; KAB = 0; MIKTAR_FIS = $s.miktar; MIKTAR_BEDELSIZ = 0; ANLASMA_FIYAT = 0
                FIYAT = $s.fiyat; DAHIL_FIYAT = $s.dahil; TUTAR = $s.tutar; DAHIL_TUTAR = $s.dahilTutar; ISKONTO = ""; ISKONTO_HESAP = 0
                OTV_ORAN = 0; OTV_TUTAR = 0; KDV_TOPTAN = $s.kdv; TEVKIF = 0; KUR = 1; FIYAT_FARKI = 0; SERINO_ZORUNLU = $false
                YEREL_KARSI_FIYAT = 0; BELGE_TARIHINDEKI_SON_ALIS_FIYATI = $s.sonAlis; HK_MIKTAR_FIS = ""; TOPLAM_SATIR_ISKONTOSU = 0
                TOPLAM_FIS_ISKONTOSU = 0; TOPLAM_OTV = 0; TOPLAM_KDV_MATRAHI = $s.tutar; TOPLAM_KDV = $s.kdvTutar; TOPLAM_TEVKIF = 0
                HESAPLANAN_FIYAT = $s.fiyat; YEREL_FIYAT = $s.fiyat; ACIKLAMA = ""; KOD = $s.kod; ONERILEN_FIYAT = 0; JOKER = ""
                AMBALAJ_BIRIM = $s.birim; AMBALAJ_MIKTAR = $s.miktar; AMBALAJ_CARPAN = 1; FK_STOK_TEVKIF_LESTE = 0; FK_PERSONEL = 0
                ALT_BIRIM_MIKTARI = $s.miktar; SEVK_ADRES = 0; BUNDLE_DETAY = 0; KT_BUNDLE_FIYAT = 0; LISTE_FIYATI = 0 }
        }
        $tx.Commit()
        $uyari = if ($atlanan.Count -gt 0) { "ERP'de bulunamayan urunler atlandi: " + ($atlanan -join ", ") } else { "" }
        return @{ id = $id; belge = $belgeNo; uyari = $uyari; satir = $satirlar.Count }
    } catch {
        try { $tx.Rollback() } catch {}
        throw
    }
}

# ---------------------------------------------------------------------
$baglanti = $null
try {
    if (-not $Database) { Yaz-Log "HATA: AYARLAR'da `$Database bos. Once ERP'nin KOPYASINDA deneyin."; exit 1 }
    if (-not (Test-Path $DbAnahtarDosyasi)) { Yaz-Log "HATA: $DbAnahtarDosyasi yok."; exit 1 }
    $script:Anahtar = (Get-Content -Path $DbAnahtarDosyasi -TotalCount 1).Trim()
    $aktarilan = @{}
    if (Test-Path $AktarilanDosya) { Get-Content $AktarilanDosya | ForEach-Object { $p = $_.Split("`t"); if ($p[0]) { $aktarilan[$p[0]] = $_ } } }

    $bas = [datetime]::ParseExact($BaslangicTarihi, "yyyy-MM-dd", $Inv)
    $is = Rpc "aktarilacak_mal" @{ p_baslangic = $bas.ToString("yyyy-MM-ddT00:00:00", $Inv) + "+03:00"; p_bekle_dk = $BekleDakika; p_limit = 50 }
    if (-not $is -or [string]$is.status -ne "ok") { throw "Bekleyen belgeler alinamadi: $($is | ConvertTo-Json -Compress)" }

    foreach ($d in @($is.degisen)) {
        if (-not $d) { continue }
        Yaz-Log "UYARI: $($d.belge_no) ERP'ye aktarildiktan SONRA telefonda degistirildi. ERP'deki siparis degistirilmedi; elle kontrol edin."
        $b = [PSCustomObject]@{ batch_id = $d.batch_id; tip = ""; imza = "" }
        Bildir $b $null $d.belge_no "degisti" "Aktarildiktan sonra telefonda degisti; ERP'de elle kontrol edin"
    }

    $belgeler = @($is.belgeler | Where-Object { $_ })
    if ($belgeler.Count -eq 0) { Yaz-Log "Aktarilacak belge yok."; exit 0 }

    $baglanti = New-Object System.Data.SqlClient.SqlConnection("Server=$SqlServer;Database=$Database;Integrated Security=SSPI;")
    $baglanti.Open()
    $ok = 0; $hata = 0
    foreach ($b in $belgeler) {
        if ($aktarilan.ContainsKey([string]$b.batch_id)) {
            # ERP'ye yazilmis ama buluta bildirilememis: tekrar YAZMA, sadece bildir.
            $p = $aktarilan[[string]$b.batch_id].Split("`t")
            Bildir $b ([long]$p[1]) $p[2] "ok" "Yerel listeden bildirildi"
            continue
        }
        try {
            $sonuc = Belge-Yaz $baglanti $b
            Add-Content -Path $AktarilanDosya -Value ("{0}`t{1}`t{2}" -f $b.batch_id, $sonuc.id, $sonuc.belge)
            Bildir $b $sonuc.id $sonuc.belge "ok" $(if ($sonuc.uyari) { $sonuc.uyari } else { "$($sonuc.satir) satir" })
            Yaz-Log "TAMAM: $($sonuc.belge) ($($b.tip), $($b.cari), $($sonuc.satir) satir) $($sonuc.uyari)"
            $ok++
        } catch {
            $hata++
            Yaz-Log "HATA: belge $($b.batch_id) ($($b.cari)): $($_.Exception.Message)"
            try { Bildir $b $null "" "hata" $_.Exception.Message } catch {}
        }
    }
    Yaz-Log "Bitti: $ok aktarildi, $hata hata."
    if ($hata -gt 0) { exit 1 }
}
catch {
    Yaz-Log "HATA: $($_.Exception.Message)"
    exit 1
}
finally {
    if ($baglanti -ne $null) { $baglanti.Close() }
}
