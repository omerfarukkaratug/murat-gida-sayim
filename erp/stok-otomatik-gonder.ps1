# =====================================================================
#  Murat Gıda - ERP12 (SQL Server) -> Sayım Uygulaması OTOMATİK aktarım
#  Sürüm 2 (gölge veri tabanı + yanıt kontrolü)
# =====================================================================
#  Ne yapar: ERP12'deki stok listesini ve cari listesini çekip
#   1) sayım uygulamasının Google Sheets sunucusuna gönderir (ASIL),
#   2) ayar dosyası varsa aynı listeyi bulut veri tabanına da gönderir
#      (Supabase — gölge kopya; hata verse bile 1. adımı etkilemez).
#
#  ERP12'ye HİÇBİR ŞEY YAZMAZ, sadece okur.
#
#  Sürüm 1'e göre farklar:
#   - Sunucu cevabı kontrol ediliyor: {"status":"ok"} gelmezse "BASARILI"
#     yazılmaz, 30 sn sonra bir kez daha denenir, olmazsa HATA yazılır.
#   - Veri tabanı gönderimi (C:\Scripts\db-anahtar.txt varsa).
#   - TLS 1.2 açıkça etkin (eski Windows'ta bazı sitelere bağlanmak için şart).
#   - Eski stok ÜRÜN bazında: aynı ürünün tüm barkodlarındaki miktar toplanır
#     (önceden sadece okutulan barkodunki geliyordu; ikincil barkodda yanlıştı).
#   - Koli barkodlarının çarpanı (carpan) da gönderilir; sayımda koli okutulunca
#     telefon girilen koli sayısını adede çevirir (stok ERP12'de adet tutuluyor).
#   - Barkodun birim adı (ADET, KOLİ, PAKET, KG… — STOK_BIRIM.AD) gönderilir;
#     uygulamada ürünün yanında gösterilir.
#
#  Veri tabanı ayarı (bir kez): C:\Scripts\db-anahtar.txt dosyası oluşturup
#  içine TEK SATIR olarak Supabase "secret" anahtarını (sb_secret_...) yazın.
#  Dosya yoksa veri tabanı adımı sessizce atlanır, gerisi eskisi gibi çalışır.
# =====================================================================

# ---------------------- AYARLAR (kendine göre kontrol et) ----------------------
$SqlServer     = "SERVER\ERP12"
# Bos: ERP12'nin AKTIF yil veri tabani otomatik bulunur (yil devrinden sonra
# kendiliginden yeni yila gecer). Elle sabitlemek icin: "ERP122026"
$Database      = ""
$AppsScriptUrl = "https://script.google.com/macros/s/AKfycbwH0hVGDXIQhdSxg2neDBNUEOxY1SNacJRz4cqf3WaP8xgAhlEnKfRv5xnlENKnh3XuYA/exec"
$LogFile       = "C:\Scripts\stok-gonderim-log.txt"
$DbUrl         = "https://wjyqempcmyrmruhdpcwk.supabase.co"
$DbAnahtarDosyasi = "C:\Scripts\db-anahtar.txt"
# Sunucunun (Apps Script) ERP anahtari: Yonetici Paneli > Ayarlar > Veri Guvenligi >
# "ERP anahtari olustur" ile uretilir ve bu dosyaya TEK SATIR olarak yazilir.
# Dosya yoksa gonderim anahtarsiz yapilir ("Kimlik zorunlu" acikken REDDEDILIR).
$ErpAnahtarDosyasi = "C:\Scripts\erp-anahtar.txt"
# --------------------------------------------------------------------------------

try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}

# ERP anahtarini dosyadan oku (yoksa bos). Anahtar ASLA gunluge yazilmaz.
$ErpAnahtar = ""
try {
    if (Test-Path $ErpAnahtarDosyasi) { $ErpAnahtar = ((Get-Content -Path $ErpAnahtarDosyasi -TotalCount 1 -ErrorAction Stop) -as [string]).Trim() }
} catch { $ErpAnahtar = "" }
# JSON govdesine eklenecek parca: "anahtar":"...", (anahtar yoksa bos)
$ErpAnahtarJson = ""
if ($ErpAnahtar) { $ErpAnahtarJson = '"anahtar":' + (ConvertTo-Json -InputObject $ErpAnahtar -Compress) + ',' }

function Yaz-Log($mesaj) {
    $satir = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $mesaj"
    # Write-Host: fonksiyonların dönüş değerine karışmasın (Write-Output karışırdı).
    Write-Host $satir
    try { Add-Content -Path $LogFile -Value $satir -ErrorAction SilentlyContinue } catch {}
}

# Sunucunun cevabı gerçekten başarılı mı? Sadece {"status":"ok"} kabul edilir.
# ("Sayım toplama servisi çalışıyor" yazısı = veri sunucuya ULAŞMADI demektir.)
function Cevap-Basarili($sonuc) {
    if ($sonuc -eq $null) { return $false }
    if ($sonuc -is [string]) { return $false }
    return ([string]$sonuc.status -eq "ok")
}

# Sheets sunucusuna gönder; başarısızsa 30 sn bekleyip BİR kez daha dene.
function Gonder-Sheets($govde, $ne, $adet) {
    for ($deneme = 1; $deneme -le 2; $deneme++) {
        try {
            $sonuc = Invoke-RestMethod -Uri $AppsScriptUrl -Method Post -Body ([System.Text.Encoding]::UTF8.GetBytes($govde)) -ContentType "application/json; charset=utf-8" -TimeoutSec 300
            $cevapMetni = if ($sonuc -is [string]) { $sonuc.Substring(0, [Math]::Min(120, $sonuc.Length)) } else { $sonuc | ConvertTo-Json -Compress }
            if (Cevap-Basarili $sonuc) {
                Yaz-Log "BASARILI: $adet $ne gonderildi. Sunucu yaniti: $cevapMetni"
                return $true
            }
            Yaz-Log "UYARI: $ne gonderimi dogrulanamadi (deneme $deneme/2). Sunucu yaniti: $cevapMetni"
        } catch {
            Yaz-Log "UYARI: $ne gonderilemedi (deneme $deneme/2): $($_.Exception.Message)"
        }
        if ($deneme -lt 2) { Start-Sleep -Seconds 30 }
    }
    Yaz-Log "HATA: $ne Sheets'e GONDERILEMEDI (2 deneme). 15 dk sonraki calismada tekrar denenecek."
    return $false
}

# Veri tabanına gönder (gölge kopya). Hata olursa sadece günlüğe yazar.
# -UserAgent şart: Supabase, tarayıcıya benzeyen istemcide gizli anahtarı 401 ile reddeder.
function Gonder-VeriTabani($fonksiyon, $govde, $ne) {
    if (-not (Test-Path $DbAnahtarDosyasi)) { return }
    $baytlar = $null
    try {
        $anahtar = (Get-Content -Path $DbAnahtarDosyasi -TotalCount 1).Trim()
        if (-not $anahtar) { return }
        # ERP'deki bazi adlarda gorunmez NUL karakteri olabiliyor; PostgreSQL
        # JSON'da "\u0000"i kabul etmez (400 Bad Request). Sadece DB kopyasi icin silinir.
        $govde = $govde -replace '(?<!\\)((?:\\\\)*)\\u0000', '$1'
        $baytlar = [System.Text.Encoding]::UTF8.GetBytes($govde)
        $sonuc = Invoke-RestMethod -Uri "$DbUrl/rest/v1/rpc/$fonksiyon" -Method Post -Body $baytlar `
            -ContentType "application/json; charset=utf-8" -Headers @{ apikey = $anahtar } -TimeoutSec 120 -UserAgent "MK-Sayim/1.0"
        if (Cevap-Basarili $sonuc) {
            Yaz-Log "VERI TABANI: $ne yazildi. Yanit: $($sonuc | ConvertTo-Json -Compress)"
        } else {
            Yaz-Log "VERI TABANI HATA: $ne yazilamadi. Yanit: $($sonuc | ConvertTo-Json -Compress) (Sheets etkilenmedi)"
        }
    } catch {
        # Sunucunun hata aciklamasi (hangi alan/satir) da gunluge yazilir.
        $hata = $_
        $ayrinti = ''
        if ($hata.ErrorDetails -and $hata.ErrorDetails.Message) { $ayrinti = $hata.ErrorDetails.Message }
        elseif ($hata.Exception.Response) {
            # PowerShell 5 hata govdesini her zaman vermez; yanit akisindan okunur.
            try {
                $akis = $hata.Exception.Response.GetResponseStream()
                if ($akis.CanSeek) { $akis.Position = 0 }
                $ayrinti = (New-Object System.IO.StreamReader($akis)).ReadToEnd()
            } catch {}
        }
        if ($ayrinti) { $ayrinti = ' Ayrinti: ' + $ayrinti.Substring(0, [Math]::Min(500, $ayrinti.Length)) }
        $boyut = ''
        if ($baytlar) { $boyut = ' Govde: ' + [Math]::Round($baytlar.Length / 1MB, 2) + ' MB.' }
        Yaz-Log "VERI TABANI HATA: $ne gonderilemedi: $($hata.Exception.Message)$boyut$ayrinti (Sheets etkilenmedi)"
    }
}

$query = @"
SELECT
  w.AD AS UrunAdi,
  bb.BARKOD AS Barkod,
  s.KOD AS StokKodu,
  us.EskiStok AS EskiStok,
  f.FIYAT AS Fiyat,
  v.KDV_PAREKENDE AS KdvOrani,
  bb.CARPAN AS Carpan,
  sb.AD AS Birim,
  ul.AD AS Ulke,
  bb.STOK_STOK_BIRIM AS Ssb,
  bb.STOK AS StokId,
  s.STOK_GRUP AS StokGrup,
  s.STOK_MARKA AS StokMarka,
  s.SON_ALIS_FIYAT AS SonAlis
FROM dbo.STOK_BARKOD_BIRIM bb
LEFT JOIN dbo.STOK_BARKOD_W w ON w.ID = bb.BARKOD
LEFT JOIN dbo.STOK_BARKOD_FIYAT_VARSAYILAN f ON f.STOK_STOK_BIRIM = bb.STOK_STOK_BIRIM
LEFT JOIN dbo.STOK s ON s.ID = bb.STOK
LEFT JOIN dbo.STOK_VERGI v ON v.ID = s.STOK_VERGI
LEFT JOIN dbo.STOK_BIRIM sb ON sb.ID = bb.STOK_BIRIM
-- Uretim yeri: stok kartindaki ULKE alani (dbo.ULKE.AD, orn. "Turkiye", "Almanya").
-- Fiyat etiketindeki "Uretim yeri" ve yerli uretim logosu buradan gelir.
LEFT JOIN dbo.ULKE ul ON ul.ID = s.ULKE
-- Eski stok URUN bazinda: ERP12 stogu barkod barkod tutar; ayni urunun
-- butun barkodlarindaki miktar toplanir, hangi barkod okutulursa okutulsun
-- ayni (dogru) stok gorunur. Hic miktari olmayan urunde bos kalir.
LEFT JOIN (
  SELECT ub.STOK, SUM(COALESCE(um.MIKTAR, ubar.MIKTAR)) AS EskiStok
  FROM dbo.STOK_BARKOD_BIRIM ub
  LEFT JOIN dbo.STOK_BARKOD ubar ON ubar.BARKOD = ub.BARKOD
  LEFT JOIN dbo.STOK_MIKTAR_BARKODLU um ON um.BARKOD = ub.BARKOD
  GROUP BY ub.STOK
) us ON us.STOK = bb.STOK
"@

# Fiyat degisiklik kaydi (ERP12: STOK_STOK_BIRIM_DEGISIM). Her urun-birim icin
# KDV dahil fiyat listesindeki SON degisiklik: tarihi, o gunku yeni fiyat ve
# degisiklikten onceki 30 gunde gecerli olmus en dusuk fiyat. Etiketteki
# "fiyat degisiklik tarihi" ve indirimdeki "onceki fiyat" buradan gelir.
$fiyatTarihQuery = @"
SELECT t.STOK_STOK_BIRIM AS Ssb, t.TARIH AS Tarih, t.FIYAT AS Fiyat, MIN(d2.ESKI_FIYAT) AS EnDusuk
FROM (
  SELECT d.STOK_STOK_BIRIM, d.STOK_FIYAT_AD, d.TARIH, d.FIYAT,
         ROW_NUMBER() OVER (PARTITION BY d.STOK_STOK_BIRIM ORDER BY d.TARIH DESC, d.ID_IDENT DESC) AS sira
  FROM dbo.STOK_STOK_BIRIM_DEGISIM d
  JOIN dbo.STOK_FIYAT_AD fa ON fa.ID = d.STOK_FIYAT_AD
  WHERE fa.KDV_DAHILMI = 1 AND d.FIYAT <> d.ESKI_FIYAT
) t
LEFT JOIN dbo.STOK_STOK_BIRIM_DEGISIM d2
  ON d2.STOK_STOK_BIRIM = t.STOK_STOK_BIRIM AND d2.STOK_FIYAT_AD = t.STOK_FIYAT_AD
 AND d2.ESKI_FIYAT > 0 AND d2.FIYAT <> d2.ESKI_FIYAT
 AND d2.TARIH <= t.TARIH AND d2.TARIH > DATEADD(day, -30, t.TARIH)
WHERE t.sira = 1
GROUP BY t.STOK_STOK_BIRIM, t.TARIH, t.FIYAT
"@

$hataVar = $false
try {
    Yaz-Log "Basliyor: ERP12'den stok listesi cekiliyor..."

    if (-not (Get-Module -ListAvailable -Name SqlServer)) {
        try { Install-Module -Name SqlServer -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop } catch {}
    }
    Import-Module SqlServer -ErrorAction SilentlyContinue

    # YIL DEVRI: aktif yil = son 7 gunde belge girilmis EN YENI "ERP12yyyy"
    # veri tabani (devirden hemen sonra yeni yila gecer; yeni yil acilmis ama
    # henuz kullanilmiyorsa eskide kalir). Hicbirinde hareket yoksa en yenisi.
    if (-not $Database) {
        $adaylar = @(Invoke-Sqlcmd -ServerInstance $SqlServer -Database master -QueryTimeout 60 -Query "SELECT name FROM sys.databases WHERE name LIKE 'ERP12[0-9][0-9][0-9][0-9]' AND state = 0 ORDER BY name DESC" | ForEach-Object { [string]$_.name })
        if ($adaylar.Count -eq 0) { Yaz-Log "HATA: ERP12 yil veri tabani bulunamadi."; exit 1 }
        foreach ($aday in $adaylar) {
            $son = Invoke-Sqlcmd -ServerInstance $SqlServer -Database $aday -QueryTimeout 60 -Query "SELECT COUNT(*) AS n FROM dbo.FIS WHERE FIS_TARIHI >= DATEADD(day, -7, GETDATE())"
            if ($son -and [int]$son.n -gt 0) { $Database = $aday; break }
        }
        if (-not $Database) { $Database = $adaylar[0] }
        Yaz-Log "Aktif ERP veri tabani: $Database"
    }

    $rows = Invoke-Sqlcmd -ServerInstance $SqlServer -Database $Database -Query $query -QueryTimeout 180

    if (-not $rows -or $rows.Count -eq 0) {
        Yaz-Log "HATA: Sorgudan hic satir donmedi, gonderim iptal edildi."
        exit 1
    }

    Yaz-Log "$($rows.Count) satir cekildi, gonderim icin hazirlaniyor..."

    # Fiyat degisiklik tarihleri: bu sorgu basarisiz olursa katalog YINE gonderilir,
    # sadece tarih bilgisi eksik kalir (sunucu kendi takibini kullanir).
    $fiyatTarih = @{}
    $fiyatGecmisBasJson = ''
    try {
        $ftRows = Invoke-Sqlcmd -ServerInstance $SqlServer -Database $Database -Query $fiyatTarihQuery -QueryTimeout 180
        foreach ($g in $ftRows) { $fiyatTarih[[string]$g.Ssb] = $g }
        $ilk = Invoke-Sqlcmd -ServerInstance $SqlServer -Database $Database -QueryTimeout 60 -Query "SELECT MIN(TARIH) AS Ilk FROM dbo.STOK_STOK_BIRIM_DEGISIM"
        if ($ilk -and $ilk.Ilk -isnot [System.DBNull]) { $fiyatGecmisBasJson = '"fiyatGecmisBas":"' + ([datetime]$ilk.Ilk).ToString('yyyy-MM-dd') + '",' }
        Yaz-Log "Fiyat degisiklik kaydi: $($fiyatTarih.Count) urun-birim icin tarih bulundu."
    } catch {
        Yaz-Log "UYARI: Fiyat degisiklik tarihleri alinamadi: $($_.Exception.Message) (katalog tarihsiz gonderilecek)"
    }

    # Kasanin miktar indirimi (ERP12: POS_PROMASYON). "Su kadar al, hepsine %x indirim" kurallari
    # (ADET = P_ADET, hedef urunun kendisi / grubu / markasi). Koli barkodu olmayan urunlerde
    # koli fiyatli afis bununla cikar. Sorgu basarisiz olursa katalog YINE gonderilir.
    $promoStok = @{}; $promoGrup = @{}; $promoMarka = @{}
    try {
        $prRows = @(Invoke-Sqlcmd -ServerInstance $SqlServer -Database $Database -QueryTimeout 60 -Query @"
SELECT FK_H_STOK AS S, H_GRUP AS G, H_MARKA AS M, ADET AS Adet, FIYAT AS Yuzde, BITIS_TARIHI AS Bitis
FROM dbo.POS_PROMASYON
WHERE AKTIF = 1 AND INDIRIMMI = 1 AND ADET > 1 AND ADET = P_ADET AND FIYAT > 0 AND FIYAT < 100
  AND BASLANGIC_TARIHI <= GETDATE() AND BITIS_TARIHI >= GETDATE()
  AND ISNULL(FK_P_STOK, 0) = ISNULL(FK_H_STOK, 0) AND ISNULL(P_GRUP, 0) = ISNULL(H_GRUP, 0) AND ISNULL(P_MARKA, 0) = ISNULL(H_MARKA, 0)
ORDER BY ADET DESC
"@)
        foreach ($p in $prRows) {
            # Ayni hedefe birden cok kural varsa EN AZ adetli olan kalir (sorgu coktan aza sirali).
            $deger = ([double]$p.Adet).ToString('0.###', [Globalization.CultureInfo]::InvariantCulture) + ':' + ([double]$p.Yuzde).ToString('0.##', [Globalization.CultureInfo]::InvariantCulture) + ':' + ([datetime]$p.Bitis).ToString('yyyy-MM-dd')
            if ($p.S -isnot [System.DBNull] -and [long]$p.S -gt 0) { $promoStok[[string]$p.S] = $deger }
            elseif ($p.G -isnot [System.DBNull] -and [long]$p.G -gt 0) { $promoGrup[[string]$p.G] = $deger }
            elseif ($p.M -isnot [System.DBNull] -and [long]$p.M -gt 0) { $promoMarka[[string]$p.M] = $deger }
        }
        Yaz-Log "Kasa promosyonu: $($prRows.Count) gecerli miktar indirimi kurali."
    } catch {
        Yaz-Log "UYARI: Kasa promosyonlari alinamadi: $($_.Exception.Message) (katalog promosyonsuz gonderilecek)"
    }

    $entries = foreach ($r in $rows) {
        $fiyatDeger = $null
        if ($r.Fiyat -ne $null -and $r.Fiyat -isnot [System.DBNull]) { $fiyatDeger = [double]$r.Fiyat }
        $eskiStokDeger = $null
        if ($r.EskiStok -ne $null -and $r.EskiStok -isnot [System.DBNull]) { $eskiStokDeger = [double]$r.EskiStok }
        $kdvDeger = $null
        if ($r.KdvOrani -ne $null -and $r.KdvOrani -isnot [System.DBNull]) { $kdvDeger = [double]$r.KdvOrani }
        # Koli barkodu (CARPAN > 1, orn. 24'lu koli): telefon koli sayisini adede cevirir.
        $carpanDeger = $null
        if ($r.Carpan -ne $null -and $r.Carpan -isnot [System.DBNull] -and [double]$r.Carpan -gt 1) { $carpanDeger = [double]$r.Carpan }
        $ulkeDeger = ""
        if ($r.Ulke -ne $null -and $r.Ulke -isnot [System.DBNull]) { $ulkeDeger = ([string]$r.Ulke).Trim() }
        # ERP'nin kayitli son fiyat degisikligi, SU ANKI fiyatla ayni fiyata aitse kullanilir.
        $ftDeger = $null
        $ofDeger = $null
        $g = $fiyatTarih[[string]$r.Ssb]
        if ($g -and $fiyatDeger -ne $null -and [Math]::Abs([double]$g.Fiyat - $fiyatDeger) -lt 0.005) {
            $ftDeger = ([datetime]$g.Tarih).ToString('yyyy-MM-dd')
            if ($g.EnDusuk -isnot [System.DBNull] -and $g.EnDusuk -ne $null) { $ofDeger = [double]$g.EnDusuk }
        }
        # Miktar indirimi yalnizca tekli barkoda yazilir; oncelik: urun > grup > marka.
        $prDeger = ""
        if ($carpanDeger -eq $null) {
            if ($promoStok.ContainsKey([string]$r.StokId)) { $prDeger = $promoStok[[string]$r.StokId] }
            elseif ($r.StokGrup -isnot [System.DBNull] -and $promoGrup.ContainsKey([string]$r.StokGrup)) { $prDeger = $promoGrup[[string]$r.StokGrup] }
            elseif ($r.StokMarka -isnot [System.DBNull] -and $promoMarka.ContainsKey([string]$r.StokMarka)) { $prDeger = $promoMarka[[string]$r.StokMarka] }
        }
        # Son alis fiyati (STOK.SON_ALIS_FIYAT, KDV haric). Koli barkodunda carpanla carpilir. Mal giriste kullanilir.
        $afDeger = $null
        if ($r.SonAlis -ne $null -and $r.SonAlis -isnot [System.DBNull] -and [double]$r.SonAlis -gt 0) {
            $afDeger = [Math]::Round([double]$r.SonAlis * $(if ($carpanDeger -ne $null) { $carpanDeger } else { 1 }), 4)
        }
        [PSCustomObject]@{
            name      = [string]$r.UrunAdi
            barcode   = [string]$r.Barkod
            stockCode = [string]$r.StokKodu
            oldStock  = $eskiStokDeger
            price     = $fiyatDeger
            kdv       = $kdvDeger
            carpan    = $carpanDeger
            birim     = [string]$r.Birim
            ulke      = $ulkeDeger
            ft        = $ftDeger
            of        = $ofDeger
            pr        = $prDeger
            af        = $afDeger
        }
    }

    # Liste BİR KEZ JSON'a çevrilir, iki gönderimde de aynı metin kullanılır.
    $entriesJson = ConvertTo-Json -InputObject @($entries) -Depth 4 -Compress
    $payload = '{"type":"katalog_bulk",' + $ErpAnahtarJson + $fiyatGecmisBasJson + '"entries":' + $entriesJson + '}'

    Yaz-Log "Sunucuya gonderiliyor..."
    if (-not (Gonder-Sheets $payload "urun" $entries.Count)) { $hataVar = $true }

    # Veri tabanina fiyat tarihi/onceki fiyat alanlari GONDERILMEZ (orada kullanilmiyor);
    # govde eski boyutunda kalir. Alanlar JSON metninden cikarilir, liste yeniden cevrilmez.
    $dbJson = $entriesJson -replace ',"ft":(null|"[0-9-]*")', '' -replace ',"of":(null|-?[0-9][0-9.eE+-]*)', '' -replace ',"pr":"[0-9.:-]*"', '' -replace ',"af":(null|-?[0-9][0-9.eE+-]*)', ''
    Gonder-VeriTabani "katalog_yukle" ('{"p_kaynak":"ERP12 otomatik","p_urunler":' + $dbJson + '}') "$($entries.Count) urun"

    # ---------------------------------------------------------------
    # BEKLEYEN ALISTAN IADE IRSALIYELERI (FIS_TURU = 7, henuz faturalanmamis satirlar, son 180 gun).
    # Mal kabulde o cari secilince uygulama "bekleyen iadesi var" diye uyarir. Hata verirse gerisi etkilenmez.
    # ---------------------------------------------------------------
    try {
        $iadeRows = @(Invoke-Sqlcmd -ServerInstance $SqlServer -Database $Database -QueryTimeout 120 -Query @"
SELECT f.ID AS FisId, ISNULL(f.BELGENO, '') AS BelgeNo, f.FIS_TARIHI AS Tarih, f.GENELTOPLAM AS Toplam,
       ISNULL(c.KOD, '') AS CariKod, ISNULL(c.AD, '') AS CariAd,
       ISNULL(d.BARKOD, '') AS Barkod, ISNULL(w.AD, '') AS UrunAdi, d.MIKTAR_FIS AS Miktar, d.DAHIL_FIYAT AS Fiyat
FROM dbo.FIS f
JOIN dbo.FIS_DETAY d ON d.FIS = f.ID
LEFT JOIN dbo.CARI c ON c.ID = f.CARI
LEFT JOIN dbo.STOK_BARKOD_W w ON w.ID = d.BARKOD
WHERE f.FIS_TURU = 7 AND f.AKTIF = 1 AND ISNULL(d.FATRALANDIRILMIS_IRSALIYEMI, 0) = 0
  AND f.FIS_TARIHI >= DATEADD(day, -180, GETDATE())
ORDER BY f.FIS_TARIHI DESC, f.ID, d.ID
"@)
        $iadeFis = [ordered]@{}
        foreach ($r in $iadeRows) {
            $fid = [string]$r.FisId
            if (-not $iadeFis.Contains($fid)) {
                $iadeFis[$fid] = [PSCustomObject]@{ cariKod = [string]$r.CariKod; cari = [string]$r.CariAd; belgeNo = [string]$r.BelgeNo
                    tarih = ([datetime]$r.Tarih).ToString('yyyy-MM-dd'); toplam = $(if ($r.Toplam -isnot [System.DBNull]) { [double]$r.Toplam } else { $null })
                    satirlar = (New-Object System.Collections.ArrayList) }
            }
            [void]$iadeFis[$fid].satirlar.Add([PSCustomObject]@{ b = [string]$r.Barkod; a = [string]$r.UrunAdi
                m = $(if ($r.Miktar -isnot [System.DBNull]) { [double]$r.Miktar } else { $null }); f = $(if ($r.Fiyat -isnot [System.DBNull]) { [Math]::Round([double]$r.Fiyat, 2) } else { $null }) })
        }
        $iadeJson = ConvertTo-Json -InputObject @($iadeFis.Values) -Depth 5 -Compress
        Yaz-Log "Bekleyen alistan iade irsaliyesi: $($iadeFis.Count) fis, $($iadeRows.Count) satir. Sunucuya gonderiliyor..."
        [void](Gonder-Sheets ('{"type":"iade_bulk",' + $ErpAnahtarJson + '"fisler":' + $iadeJson + '}') "iade irsaliyesi" $iadeFis.Count)
    } catch {
        Yaz-Log "UYARI: Bekleyen iade irsaliyeleri gonderilemedi: $($_.Exception.Message) (katalog ve cari etkilenmedi)"
    }

    # ---------------------------------------------------------------
    # CARI (tedarikci/musteri) listesi + bakiye
    # ---------------------------------------------------------------
    Yaz-Log "Basliyor: cari listesi ve bakiyeler cekiliyor..."

    $cariQuery = @"
SELECT c.AD AS CariAdi, c.KOD AS CariKodu, b.BAKIYE AS Bakiye
FROM dbo.CARI_BAKIYELER b
JOIN dbo.CARI c ON c.ID = b.ID
WHERE b.DOVIZ_AD = 'TRY'
"@

    $cariRows = Invoke-Sqlcmd -ServerInstance $SqlServer -Database $Database -Query $cariQuery -QueryTimeout 180

    if ($cariRows -and $cariRows.Count -gt 0) {
        Yaz-Log "$($cariRows.Count) cari cekildi, gonderim icin hazirlaniyor..."

        $cariEntries = foreach ($r in $cariRows) {
            $bakiyeDeger = $null
            if ($r.Bakiye -ne $null -and $r.Bakiye -isnot [System.DBNull]) { $bakiyeDeger = [double]$r.Bakiye }
            [PSCustomObject]@{
                name    = [string]$r.CariAdi
                code    = [string]$r.CariKodu
                balance = $bakiyeDeger
            }
        }

        $cariJson = ConvertTo-Json -InputObject @($cariEntries) -Depth 4 -Compress
        $cariPayload = '{"type":"cari_bulk",' + $ErpAnahtarJson + '"entries":' + $cariJson + '}'

        Yaz-Log "Cari listesi sunucuya gonderiliyor..."
        if (-not (Gonder-Sheets $cariPayload "cari" $cariEntries.Count)) { $hataVar = $true }

        Gonder-VeriTabani "cari_yukle" ('{"p_kaynak":"ERP12 otomatik","p_cariler":' + $cariJson + '}') "$($cariEntries.Count) cari"
    } else {
        Yaz-Log "UYARI: Cari sorgusundan hic satir donmedi, cari gonderimi atlandi."
    }
}
catch {
    Yaz-Log "HATA: $($_.Exception.Message)"
    exit 1
}
if ($hataVar) { exit 1 }
