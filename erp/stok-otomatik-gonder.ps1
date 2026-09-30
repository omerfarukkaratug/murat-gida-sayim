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
#
#  Veri tabanı ayarı (bir kez): C:\Scripts\db-anahtar.txt dosyası oluşturup
#  içine TEK SATIR olarak Supabase "secret" anahtarını (sb_secret_...) yazın.
#  Dosya yoksa veri tabanı adımı sessizce atlanır, gerisi eskisi gibi çalışır.
# =====================================================================

# ---------------------- AYARLAR (kendine göre kontrol et) ----------------------
$SqlServer     = "SERVER\ERP12"
$Database      = "ERP122025"
$AppsScriptUrl = "https://script.google.com/macros/s/AKfycbwH0hVGDXIQhdSxg2neDBNUEOxY1SNacJRz4cqf3WaP8xgAhlEnKfRv5xnlENKnh3XuYA/exec"
$LogFile       = "C:\Scripts\stok-gonderim-log.txt"
$DbUrl         = "https://wjyqempcmyrmruhdpcwk.supabase.co"
$DbAnahtarDosyasi = "C:\Scripts\db-anahtar.txt"
# --------------------------------------------------------------------------------

try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}

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
            $sonuc = Invoke-RestMethod -Uri $AppsScriptUrl -Method Post -Body $govde -ContentType "application/json; charset=utf-8" -TimeoutSec 300
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
function Gonder-VeriTabani($fonksiyon, $govde, $ne) {
    if (-not (Test-Path $DbAnahtarDosyasi)) { return }
    try {
        $anahtar = (Get-Content -Path $DbAnahtarDosyasi -TotalCount 1).Trim()
        if (-not $anahtar) { return }
        $baytlar = [System.Text.Encoding]::UTF8.GetBytes($govde)
        $sonuc = Invoke-RestMethod -Uri "$DbUrl/rest/v1/rpc/$fonksiyon" -Method Post -Body $baytlar `
            -ContentType "application/json; charset=utf-8" -Headers @{ apikey = $anahtar } -TimeoutSec 120
        if (Cevap-Basarili $sonuc) {
            Yaz-Log "VERI TABANI: $ne yazildi. Yanit: $($sonuc | ConvertTo-Json -Compress)"
        } else {
            Yaz-Log "VERI TABANI HATA: $ne yazilamadi. Yanit: $($sonuc | ConvertTo-Json -Compress) (Sheets etkilenmedi)"
        }
    } catch {
        Yaz-Log "VERI TABANI HATA: $ne gonderilemedi: $($_.Exception.Message) (Sheets etkilenmedi)"
    }
}

$query = @"
SELECT
  w.AD AS UrunAdi,
  bb.BARKOD AS Barkod,
  s.KOD AS StokKodu,
  COALESCE(m.MIKTAR, bar.MIKTAR) AS EskiStok,
  f.FIYAT AS Fiyat,
  v.KDV_PAREKENDE AS KdvOrani
FROM dbo.STOK_BARKOD_BIRIM bb
LEFT JOIN dbo.STOK_BARKOD bar ON bar.BARKOD = bb.BARKOD
LEFT JOIN dbo.STOK_MIKTAR_BARKODLU m ON m.BARKOD = bb.BARKOD
LEFT JOIN dbo.STOK_BARKOD_W w ON w.ID = bb.BARKOD
LEFT JOIN dbo.STOK_BARKOD_FIYAT_VARSAYILAN f ON f.STOK_STOK_BIRIM = bb.STOK_STOK_BIRIM
LEFT JOIN dbo.STOK s ON s.ID = bb.STOK
LEFT JOIN dbo.STOK_VERGI v ON v.ID = s.STOK_VERGI
"@

$hataVar = $false
try {
    Yaz-Log "Basliyor: ERP12'den stok listesi cekiliyor..."

    if (-not (Get-Module -ListAvailable -Name SqlServer)) {
        try { Install-Module -Name SqlServer -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop } catch {}
    }
    Import-Module SqlServer -ErrorAction SilentlyContinue

    $rows = Invoke-Sqlcmd -ServerInstance $SqlServer -Database $Database -Query $query -QueryTimeout 180

    if (-not $rows -or $rows.Count -eq 0) {
        Yaz-Log "HATA: Sorgudan hic satir donmedi, gonderim iptal edildi."
        exit 1
    }

    Yaz-Log "$($rows.Count) satir cekildi, gonderim icin hazirlaniyor..."

    $entries = foreach ($r in $rows) {
        $fiyatDeger = $null
        if ($r.Fiyat -ne $null -and $r.Fiyat -isnot [System.DBNull]) { $fiyatDeger = [double]$r.Fiyat }
        $eskiStokDeger = $null
        if ($r.EskiStok -ne $null -and $r.EskiStok -isnot [System.DBNull]) { $eskiStokDeger = [double]$r.EskiStok }
        $kdvDeger = $null
        if ($r.KdvOrani -ne $null -and $r.KdvOrani -isnot [System.DBNull]) { $kdvDeger = [double]$r.KdvOrani }
        [PSCustomObject]@{
            name      = [string]$r.UrunAdi
            barcode   = [string]$r.Barkod
            stockCode = [string]$r.StokKodu
            oldStock  = $eskiStokDeger
            price     = $fiyatDeger
            kdv       = $kdvDeger
        }
    }

    # Liste BİR KEZ JSON'a çevrilir, iki gönderimde de aynı metin kullanılır.
    $entriesJson = ConvertTo-Json -InputObject @($entries) -Depth 4 -Compress
    $payload = '{"type":"katalog_bulk","entries":' + $entriesJson + '}'

    Yaz-Log "Sunucuya gonderiliyor..."
    if (-not (Gonder-Sheets $payload "urun" $entries.Count)) { $hataVar = $true }

    Gonder-VeriTabani "katalog_yukle" ('{"p_kaynak":"ERP12 otomatik","p_urunler":' + $entriesJson + '}') "$($entries.Count) urun"

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
        $cariPayload = '{"type":"cari_bulk","entries":' + $cariJson + '}'

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
