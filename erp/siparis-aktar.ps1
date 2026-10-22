# =====================================================================
#  MK Saha - Telefondaki Mal Giris / Mal Cikis -> ERP12 SIPARIS
# =====================================================================
#  Ne yapar: Telefondan kaydedilen Mal Giris / Mal Cikis belgelerini
#  (bulut veri tabanindan) alir ve ERP12'ye SIPARIS olarak yazar:
#    Mal Giris -> Verilen Siparis (SIPARIS_TURU 1), belge no "MK SAHA G-000001"
#    Mal Cikis -> Alinan Siparis  (SIPARIS_TURU 2), belge no "MK SAHA C-000001"
#  Siparis STOGA ve CARIYE etki etmez. ERP'de siparis acilip faturaya /
#  irsaliyeye cevrilir; faturayi ERP kendisi olusturur.
#
#  Fiyatlar:
#    Verilen siparis: urunun ERP'deki SON ALIS fiyati (KDV haric).
#    Alinan siparis : telefondaki fiyat (katalogdaki KDV dahil satis fiyati).
#
#  Guvenlik:
#  - DENEME: "siparis-aktar.ps1 DENEME" her seyi hesaplar, ERP'ye YAZMAZ
#    (islem geri alinir), ne yazilacagini log'a yazar.
#  - Her belge tek bir islemde (transaction) yazilir: ya hepsi ya hicbiri.
#  - Numaralar ERP'nin kendi ortak sayacindan (dbo.ID) alinir.
#  - Ayni belge iki kez aktarilmaz (bulut kaydi + yerel liste).
#  - Aktarildiktan sonra telefonda degistirilen belgeye DOKUNULMAZ, sadece
#    uyari yazilir (duzeltme ERP'de elle yapilir).
#  - Telefonda kaydedildikten sonra $BekleDakika dakika beklenir (personel
#    hala duzeltiyor olabilir).
# =====================================================================

# ---------------------- AYARLAR ----------------------
$script:Argumanlar = @($args | ForEach-Object { ([string]$_).ToUpperInvariant().TrimStart("-") })
$Deneme           = $script:Argumanlar -contains "DENEME"
$SqlServer        = "SERVER\ERP12"
# Bos: ERP12'nin AKTIF yil veri tabani otomatik bulunur (son 7 gunde belge girilen en yeni).
# Elle sabitlemek icin: "ERP122025"
$Database         = ""
$DbUrl            = "https://wjyqempcmyrmruhdpcwk.supabase.co"
$DbAnahtarDosyasi = "C:\Scripts\db-anahtar.txt"
$LogFile          = "C:\Scripts\siparis-aktar-log.txt"
$AktarilanDosya   = "C:\Scripts\siparis-aktarilan.txt"
# ERP'de stok karti olmayan urunler: belge BEKLER (eksik siparis yazilmaz), liste bu dosyaya yazilir.
# Kart ERP'de ayni barkodla acilinca bir sonraki calismada belge kendiliginden aktarilir.
$EksikKartDosya   = "C:\Scripts\acilacak-stok-kartlari.txt"
$HataDosya        = "C:\Scripts\siparis-aktar-hata.txt"
# Bu tarihten ONCE telefonda olusturulan belgeler aktarilmaz (gecmisi doldurmasin).
$BaslangicTarihi  = "2026-10-21"
$BekleDakika      = 10
$SeriVerilen      = "MK SAHA G-"
$SeriAlinan       = "MK SAHA C-"
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
        $lp = Tablo $tx "SELECT TOP 1 LOKASYON, PROJE FROM dbo.SIPARIS WHERE BELGENO NOT LIKE 'MK SAHA%' AND BELGENO NOT LIKE 'MOB %' ORDER BY ID DESC" $null
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
            if ($bb.Rows.Count -eq 0) {
                [void]$atlanan.Add("$($r.barkod) $($r.urun_adi)")
                $script:EksikKart["$($r.barkod)"] = ("{0}`t{1}`t{2} x {3}`t{4} ({5})" -f $r.barkod, $r.urun_adi, $b.tip, $r.miktar, $b.cari, $b.belge_turu)
                continue
            }
            $stok = $bb.Rows[0].STOK; $kdv = [decimal]$bb.Rows[0].KDV; $miktar = [decimal]$r.miktar
            # Son alis: AYNI BIRIMDE (adet / koli karismasin), bedelsiz olmayan, fiyati olan en yeni alis satiri.
            $sonAlis = Deger $tx "SELECT TOP 1 d.FIYAT FROM dbo.FIS_DETAY d JOIN dbo.FIS f ON f.ID = d.FIS WHERE d.STOK = @s AND d.STOK_BIRIM = @u AND f.FIS_TURU IN (1, 5) AND f.AKTIF = 1 AND d.FIYAT > 0 AND d.MIKTAR_FIS > 0 ORDER BY f.FIS_TARIHI DESC, d.ID DESC" @{ "@s" = $stok; "@u" = $bb.Rows[0].STOK_BIRIM }
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
                kdvTutar = (Yuvarla ($tutar * $kdv / 100) 4); sonAlis = $sonAlis; ad = [string]$r.urun_adi })
        }
        # Stok karti olmayan urun varsa belge YAZILMAZ: eksik siparis gozden kacar. Kart acilinca tekrar denenir.
        if ($atlanan.Count -gt 0) { throw "ERP'de stok karti yok, kart acilinca aktarilacak: $($atlanan -join ', ')" }

        # --- Belge numarasi: kendi serimizin en buyugu + 1 (kilitli) ---
        $son = Deger $tx "SELECT MAX(BELGENO) FROM dbo.SIPARIS WITH (UPDLOCK, HOLDLOCK) WHERE BELGENO LIKE @p" @{ "@p" = "$seri%" }
        $no = 1
        if ($son) { $no = [int]([string]$son).Substring($seri.Length) + 1 }
        $belgeNo = $seri + $no.ToString("000000")

        # --- Aciklama (sutun uzunluguna gore) ---
        $acikMax = Deger $tx "SELECT max_length / 2 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.SIPARIS') AND name = 'ACIKLAMA'" $null
        $acik = ("MK Saha: " + (@([string]$b.belge_turu, [string]$b.belge_no) | Where-Object { $_ }) -join " ") + " / $($b.personel)"
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
            GONDERIM_ADRESI = $adres; ONAYLI = $true; VADE_SECENEKLERI = $(if ($giris) { 17 } else { 7 }); BELGE_YETKILISI = 0; YAZILDI = $false; EMAIL_GONDERILDI = $false
            NAKLIYE_ODEME_TIPI = 0; SEVK_SEKLI = 0; KARSI_SIPARIS_NO = ""; ARTTIRIM = 0; DOVIZ_KUR_SECIMI = 2; FIS_ODEME_TIPI_ISKONTOLARI = $(if ($giris) { 0 } else { 1 })
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
        $uyari = if ($atlanan.Count -gt 0) { "ERP'de bulunamayan urunler atlandi: " + ($atlanan -join ", ") } else { "" }
        if ($Deneme) {
            $tx.Rollback()
            Yaz-Log "DENEME (ERP'ye YAZILMADI): $belgeNo / $($b.tip) / $($b.cari) / $($satirlar.Count) satir / toplam KDV dahil $(Yuvarla $genel 2) $uyari"
            foreach ($s in $satirlar) { Yaz-Log ("   {0} {1} x {2} fiyat {3} (KDV dahil {4})" -f $s.barkod, $s.ad, $s.miktar, $s.fiyat, $s.dahil) }
        } else { $tx.Commit() }
        return @{ id = $id; belge = $belgeNo; uyari = $uyari; satir = $satirlar.Count }
    } catch {
        try { $tx.Rollback() } catch {}
        throw
    }
}

# ---------------------------------------------------------------------
$baglanti = $null
try {
    if (-not (Test-Path $DbAnahtarDosyasi)) { Yaz-Log "HATA: $DbAnahtarDosyasi yok."; exit 1 }
    $script:Anahtar = (Get-Content -Path $DbAnahtarDosyasi -TotalCount 1).Trim()
    $aktarilan = @{}
    $script:EksikKart = @{}
    $script:SonHata = @{}
    if (Test-Path $HataDosya) { Get-Content $HataDosya -Encoding UTF8 | ForEach-Object { $p = $_.Split("`t", 2); if ($p[0] -and $p.Count -eq 2) { $script:SonHata[$p[0]] = $p[1] } } }
    if (Test-Path $AktarilanDosya) { Get-Content $AktarilanDosya | ForEach-Object { $p = $_.Split("`t"); if ($p[0]) { $aktarilan[$p[0]] = $_ } } }

    $bas = [datetime]::ParseExact($BaslangicTarihi, "yyyy-MM-dd", $Inv)
    $is = Rpc "aktarilacak_mal" @{ p_baslangic = $bas.ToString("yyyy-MM-ddT00:00:00", $Inv) + "+03:00"; p_bekle_dk = $(if ($Deneme) { 0 } else { $BekleDakika }); p_limit = 50 }
    if (-not $is -or [string]$is.status -ne "ok") { throw "Bekleyen belgeler alinamadi: $($is | ConvertTo-Json -Compress)" }

    foreach ($d in @($is.degisen)) {
        if (-not $d -or $Deneme) { continue }
        Yaz-Log "UYARI: $($d.belge_no) ERP'ye aktarildiktan SONRA telefonda degistirildi. ERP'deki siparis degistirilmedi; elle kontrol edin."
        $b = [PSCustomObject]@{ batch_id = $d.batch_id; tip = ""; imza = "" }
        Bildir $b $null $d.belge_no "degisti" "Aktarildiktan sonra telefonda degisti; ERP'de elle kontrol edin"
    }

    $belgeler = @($is.belgeler | Where-Object { $_ })
    if ($belgeler.Count -eq 0) { Yaz-Log "Aktarilacak belge yok."; exit 0 }

    $baglanti = New-Object System.Data.SqlClient.SqlConnection("Server=$SqlServer;Database=master;Integrated Security=SSPI;")
    $baglanti.Open()
    if (-not $Database) {
        $cmd = $baglanti.CreateCommand(); $cmd.CommandText = "SELECT name FROM sys.databases WHERE name LIKE 'ERP12[0-9][0-9][0-9][0-9]' AND state = 0 ORDER BY name DESC"
        $rd = $cmd.ExecuteReader(); $adaylar = @(); while ($rd.Read()) { $adaylar += [string]$rd[0] }; $rd.Close()
        if ($adaylar.Count -eq 0) { throw "ERP12 yil veri tabani bulunamadi" }
        foreach ($aday in $adaylar) {
            $cmd = $baglanti.CreateCommand(); $cmd.CommandText = "SELECT COUNT(*) FROM [$aday].dbo.FIS WHERE FIS_TARIHI >= DATEADD(day, -7, GETDATE())"
            if ([int]$cmd.ExecuteScalar() -gt 0) { $Database = $aday; break }
        }
        if (-not $Database) { $Database = $adaylar[0] }
    }
    $baglanti.ChangeDatabase($Database)
    Yaz-Log "$(if ($Deneme) { 'DENEME - ' })ERP veri tabani: $Database, $($belgeler.Count) belge"
    $ok = 0; $hata = 0
    foreach ($b in $belgeler) {
        if (-not $Deneme -and $aktarilan.ContainsKey([string]$b.batch_id)) {
            # ERP'ye yazilmis ama buluta bildirilememis: tekrar YAZMA, sadece bildir.
            $p = $aktarilan[[string]$b.batch_id].Split("`t")
            Bildir $b ([long]$p[1]) $p[2] "ok" "Yerel listeden bildirildi"
            continue
        }
        try {
            $sonuc = Belge-Yaz $baglanti $b
            if ($Deneme) { $ok++; continue }
            Add-Content -Path $AktarilanDosya -Value ("{0}`t{1}`t{2}" -f $b.batch_id, $sonuc.id, $sonuc.belge)
            Bildir $b $sonuc.id $sonuc.belge "ok" $(if ($sonuc.uyari) { $sonuc.uyari } else { "$($sonuc.satir) satir" })
            Yaz-Log "TAMAM: $($sonuc.belge) ($($b.tip), $($b.cari), $($sonuc.satir) satir) $($sonuc.uyari)"
            $ok++
        } catch {
            $hata++
            Yaz-Log "HATA: belge $($b.batch_id) ($($b.cari)): $($_.Exception.Message)"
            # Ayni hata her calismada tekrar bildirilmez (gunluk dolmasin).
            $mesaj = [string]$_.Exception.Message
            if (-not $Deneme -and $script:SonHata[[string]$b.batch_id] -ne $mesaj) {
                try { Bildir $b $null "" "hata" $mesaj; $script:SonHata[[string]$b.batch_id] = $mesaj } catch {}
            }
        }
    }
    try {
        if ($script:EksikKart.Count -gt 0) {
            $baslik = "ERP'de STOK KARTI ACILACAK URUNLER ($(Get-Date -Format 'yyyy-MM-dd HH:mm')). Kart ayni BARKODLA acilinca belge kendiliginden aktarilir.`r`nBarkod`tUrun`tHareket`tCari (belge)"
            [System.IO.File]::WriteAllText($EksikKartDosya, $baslik + "`r`n" + (($script:EksikKart.Values | Sort-Object) -join "`r`n") + "`r`n", [System.Text.Encoding]::UTF8)
            Yaz-Log "UYARI: $($script:EksikKart.Count) urunun ERP'de stok karti yok; bu urunlerin oldugu belgeler bekliyor. Liste: $EksikKartDosya"
        } elseif (Test-Path $EksikKartDosya) { Remove-Item $EksikKartDosya -ErrorAction SilentlyContinue }
        if (-not $Deneme) { [System.IO.File]::WriteAllText($HataDosya, (($script:SonHata.Keys | ForEach-Object { "$_`t$($script:SonHata[$_])" }) -join "`r`n"), [System.Text.Encoding]::UTF8) }
    } catch {}
    Yaz-Log "Bitti: $ok $(if ($Deneme) { 'denendi (yazilmadi)' } else { 'aktarildi' }), $hata hata."
    if ($hata -gt 0) { exit 1 }
}
catch {
    Yaz-Log "HATA: $($_.Exception.Message)"
    exit 1
}
finally {
    if ($baglanti -ne $null) { $baglanti.Close() }
}
