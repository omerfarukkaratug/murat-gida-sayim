# =====================================================================
#  KRT Saha - BOLUM BOLUM SAYIMI ERP12'ye AKTARMA
# =====================================================================
#  Ne yapar: Telefonlarla yapilan sayimi (bulut veri tabanindaki sayim donemi) gece gece ERP12'nin KENDI
#  SAYIM BELGESINE yazar. STOGA DOKUNMAZ: stok, ERP'de bu belge "farkla" KESINLESTIRILINCE degisir.
#
#  Yontem (sifirlama YOK):
#   - Uygulamada reyon "Bolge / Bolum / Raf" secilir (or. "Magaza / Atistirmalik / Cikolata"). BOLUM = ilk iki parca.
#   - Depo bir kez sayilir ve kilitlenir: bolgesi "Depo" ile baslayan her okutma DEPO sayilir.
#   - Her gece (magaza kapaliyken) bir ya da birkac bolum sayilir; program bolumleri ilk-son okutma saatleriyle
#     listeler, siz o gecenin bolumlerini secersiniz. Geceleri istediginiz zaman (or. hepsi bitince, sirayla) aktarabilirsiniz.
#   - O gece rafta ILK KEZ sayilan her urun icin: SAYILAN = o gecenin raf sayimi + ayni urunun depo sayimi.
#     ERP'de "farkla kesinlestirme" (STOK_SAYIM_KESINLESTIRMEYE_ADET_VER) secilen tarihteki stokla karsilastirir,
#     stok SAYILAN'a esitlenir. Gunduzki satislar sorun olmaz: karsilastirma o gecenin saatindeki stokla yapilir.
#   - Daha once bir gece kapanmis urun baska bir gece baska bir rafta yine cikarsa: o rafin sayimi STOGUN USTUNE eklenir
#     (belgeye "o anki stok + yeni raf" yazilir; farkla kesinlestirince fark = yeni raf).
#   - SON kapanis: depoda sayilip hicbir rafta cikmayan urunler depo sayimiyla kapanir; HIC sayilmayan ama ERP'de
#     stogu gorunen urunler yalnizca listelenir (sifirlamaya siz karar verirsiniz).
#   - ERP stogu BARKOD barkod tutar: sayilan miktar urunun stogunun durdugu (carpani 1) barkoda yazilir; urunun
#     stoklu baska barkodlari varsa onlara 0 yazilir. Boylece "ustune ekleme" olmaz, urunun toplami = sayilan.
#
#  Guvenlik:
#   - Once DENEME raporu: ERP'ye hicbir sey yazmaz; urun urun sayilan / ERP stogu / fark / TL dosyaya yazilir.
#   - Yazmadan once denetler: sayim gecesi (magaza kapanisi -> kesinlestirme ani) ERP'de hareket var mi,
#     onceki gecenin belgesi kesinlestirilmis mi, ayni gece daha once yazildi mi, eslesmeyen urun var mi.
#   - Yazma tek islemde (transaction): ya butun belge ya hicbiri. Numaralar ERP'nin kendi sayacindan (dbo.ID).
#   - Kesinlestirilmemis belge bu programla SILINEBILIR (geri alma).
#   - KONTROL: kesinlestirmeden sonra ERP stogu gercekten sayilana esitlenmis mi urun urun denetler
#     (yanlislikla "sayilani ekle" secilirse yakalar).
#  Calistirma: SAYIM-AKTAR.bat (menulu). Gunluk: C:\Scripts\sayim-aktar-log.txt
# =====================================================================
$SqlServer        = "SERVER\ERP12"
$Database         = ""     # bos: aktif yil veri tabani otomatik bulunur
$DbUrl            = "https://wjyqempcmyrmruhdpcwk.supabase.co"
$DbAnahtarDosyasi = "C:\Scripts\db-anahtar.txt"
$SunucuUrl        = "https://sunucu.krtsaha.com/exec"
$ErpAnahtarDosyasi = "C:\Scripts\erp-anahtar.txt"
$LogFile          = "C:\Scripts\sayim-aktar-log.txt"
$DurumDosyasi     = "C:\Scripts\sayim-aktar-durum.json"
$RaporKlasoru     = "C:\Scripts\sayim-raporlari"
$AciklamaOn       = "KRT Saha: "

try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}
$Inv = [Globalization.CultureInfo]::InvariantCulture
$Tr  = [Globalization.CultureInfo]::GetCultureInfo("tr-TR")

function Yaz-Log($m) { $s = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $m"; Write-Host $m; try { Add-Content -Path $LogFile -Value $s -ErrorAction SilentlyContinue } catch {} }
function Baslik($m) { Write-Host ""; Write-Host ("=" * 70) -ForegroundColor Cyan; Write-Host "  $m" -ForegroundColor Cyan; Write-Host ("=" * 70) -ForegroundColor Cyan }
function Uyari($m) { Write-Host "  ! $m" -ForegroundColor Yellow; try { Add-Content -Path $LogFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - UYARI: $m" } catch {} }
function Hata($m) { Write-Host "  X $m" -ForegroundColor Red; try { Add-Content -Path $LogFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - HATA: $m" } catch {} }
function Sayi($x, $n = 3) { return ([decimal]$x).ToString("N$n", $Tr) }
function Tl($x) { return ([decimal][Math]::Round([double]$x, 2)).ToString("N2", $Tr) + " TL" }
function Kisalt($s, $n) { $s = [string]$s; if ($n -gt 0 -and $s.Length -gt $n) { return $s.Substring(0, $n) }; return $s }
function NormTr($s) { return ([string]$s).ToLower($Tr).Replace([string][char]0x131, "i").Replace([string][char]0x15F, "s").Replace([string][char]0x11F, "g").Replace([string][char]0xFC, "u").Replace([string][char]0xF6, "o").Replace([string][char]0xE7, "c") }
function ReyonParca($r) { return ,@(([string]$r).Split('/') | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
function BolumAdi($r) { $p = ReyonParca $r; if (-not $p.Count) { return "(reyonsuz)" }; return ($p[0..([Math]::Min(1, $p.Count - 1))] -join " / ") }
function DepoMu($reyon) { $p = ReyonParca $reyon; return $p.Count -gt 0 -and (NormTr $p[0]) -match '^depo' }
function EpochTarih($ms) { return [DateTimeOffset]::FromUnixTimeMilliseconds([long]$ms).ToLocalTime().DateTime }
function TarihOku($metin, $varsayilan) {
    $m = ([string]$metin).Trim(); if (-not $m) { return $varsayilan }
    $bicim = @("dd.MM.yyyy HH:mm", "dd.MM.yyyy HH:mm:ss", "d.M.yyyy H:mm", "dd.MM.yyyy")
    foreach ($b in $bicim) { $t = [datetime]::MinValue; if ([datetime]::TryParseExact($m, $b, $Inv, [Globalization.DateTimeStyles]::None, [ref]$t)) { return $t } }
    return $null
}
function Sor-Tarih($soru, $varsayilan) {
    while ($true) {
        $c = Read-Host "$soru [Enter = $($varsayilan.ToString('dd.MM.yyyy HH:mm:ss'))]"
        $t = TarihOku $c $varsayilan; if ($t) { return $t }
        Write-Host "  Tarihi GG.AA.YYYY SS:DD olarak yazin (or. 23.11.2026 21:00)" -ForegroundColor Yellow
    }
}

# ---------------------------------------------------------------------
#  BIRLESTIRME (saf hesap, ERP'ye ve buluta dokunmaz; test edilebilir)
#  $satirlar: [kayit_id, stok_kodu, barkod, urun_adi, adet, birim, reyon, epoch ms, personel]
#  $esle: stok_kodu/barkod -> ERP STOK ID (hashtable); bulunamayanlar "eslesmeyen" olur.
#  Doner: @{ urunler = @{ stokId = @{ depo; raf; mod (esitle|ekle); ad; barkodlar } }; eslesmeyen; kalan }
# ---------------------------------------------------------------------
function Birlestir($satirlar, $esle, $secili, $yapilan, [bool]$son, $atanmis) {
    # $secili: bu gecenin bolumleri (ad -> $true). $atanmis: daha once yazilan gecelerin bolumleri.
    # Depo okutmalari (bolge "Depo...") urunun ILK raf gecesinde ya da SON'da depo miktari olarak eklenir.
    # KALAN: ne depo ne bu gece ne onceki bir gece olan bolumlerin okutmalari (sonraki gecelere kalir; SON'da engel).
    $depo = @{}; $raf = @{}; $ad = @{}; $bark = @{}; $sonRaf = @{}; $sonDepo = @{}
    $eslesmeyen = New-Object System.Collections.ArrayList; $kalan = New-Object System.Collections.ArrayList
    foreach ($s in $satirlar) {
        $kod = ([string]$s[1]).Trim(); $bk = ([string]$s[2]).Trim(); $adet = [double]$s[4]; $reyon = [string]$s[6]
        $depoMu = DepoMu $reyon; $bolum = BolumAdi $reyon
        if (-not $depoMu -and -not $secili.ContainsKey($bolum)) { if (-not $atanmis.ContainsKey($bolum)) { [void]$kalan.Add($s) }; continue }
        $sid = $null
        if ($kod -and $esle.ContainsKey("K:" + $kod)) { $sid = $esle["K:" + $kod] } elseif ($bk -and $esle.ContainsKey("B:" + $bk)) { $sid = $esle["B:" + $bk] }
        if ($sid -eq $null) { if (-not $depoMu -or $son) { [void]$eslesmeyen.Add($s) }; continue }
        if (-not $ad.ContainsKey($sid)) { $ad[$sid] = [string]$s[3]; $bark[$sid] = @{} }
        if ($bk) { $bark[$sid][$bk] = $true }
        $ts = EpochTarih $s[7]
        if ($depoMu) { $depo[$sid] = [double]($depo[$sid]) + $adet; if (-not $sonDepo.ContainsKey($sid) -or $ts -gt $sonDepo[$sid]) { $sonDepo[$sid] = $ts } }
        else { $raf[$sid] = [double]($raf[$sid]) + $adet; if (-not $sonRaf.ContainsKey($sid) -or $ts -gt $sonRaf[$sid]) { $sonRaf[$sid] = $ts } }
    }
    $urunler = @{}
    foreach ($sid in $raf.Keys) {
        if ($yapilan.ContainsKey($sid)) { $urunler[$sid] = @{ depo = 0.0; raf = [double]$raf[$sid]; mod = "ekle"; ad = $ad[$sid]; barkodlar = @($bark[$sid].Keys); son = $sonRaf[$sid] } }
        else { $urunler[$sid] = @{ depo = [double]($depo[$sid]); raf = [double]$raf[$sid]; mod = "esitle"; ad = $ad[$sid]; barkodlar = @($bark[$sid].Keys); son = $sonRaf[$sid]; sonDepo = $sonDepo[$sid] } }
    }
    if ($son) {
        foreach ($sid in $depo.Keys) {
            if ($urunler.ContainsKey($sid) -or $yapilan.ContainsKey($sid)) { continue }
            $urunler[$sid] = @{ depo = [double]$depo[$sid]; raf = 0.0; mod = "esitle"; ad = $ad[$sid]; barkodlar = @($bark[$sid].Keys); son = $sonDepo[$sid] }
        }
    }
    return @{ urunler = $urunler; eslesmeyen = $eslesmeyen; kalan = $kalan }
}

# Donemin bolumleri: ad, ilk / son okutma, okutma, urun, personel, depo mu
function Bolumler($satirlar) {
    $b = @{}
    foreach ($s in $satirlar) {
        $ad = if (DepoMu $s[6]) { "DEPO (" + (BolumAdi $s[6]) + ")" } else { BolumAdi $s[6] }
        $t = EpochTarih $s[7]
        if (-not $b.ContainsKey($ad)) { $b[$ad] = @{ ad = $ad; bolum = (BolumAdi $s[6]); depo = (DepoMu $s[6]); ilk = $t; son = $t; okutma = 0; urun = @{}; kisi = @{} } }
        $x = $b[$ad]; $x.okutma++; $x.urun[[string]$s[1] + "|" + [string]$s[2]] = 1; $x.kisi[[string]$s[8]] = 1
        if ($t -lt $x.ilk) { $x.ilk = $t }; if ($t -gt $x.son) { $x.son = $t }
    }
    return @($b.Values | Sort-Object { $_.ilk })
}

# Bir urunun belge satirlari. $barkodlar: [barkod, ssb, stokBirim, carpan, stokT]; $okutulan: okutulan barkodlar
# esitle: ana barkoda HEDEF, stoklu diger barkodlara 0. ekle: ana barkoda (o barkodun stogu + raf).
# Doner: @{ satirlar = @(@{ barkod; ssb; stokBirim; carpan; miktar; stokT }); hedefToplam; stokToplam }
function Satirlar($u, $barkodlar, $okutulan) {
    $tek = @($barkodlar | Where-Object { [double]$_[3] -le 1 })
    $stokToplam = 0.0; foreach ($b in $barkodlar) { $stokToplam += [double]$b[4] }
    $ana = $null
    $stoklu = @($tek | Where-Object { [double]$_[4] -ne 0 } | Sort-Object { -[Math]::Abs([double]$_[4]) })
    if ($stoklu.Count) { $ana = $stoklu[0] }
    if (-not $ana) { $ok = @($tek | Where-Object { $okutulan -contains [string]$_[0] }); if ($ok.Count) { $ana = $ok[0] } }
    if (-not $ana -and $tek.Count) { $ana = $tek[0] }
    if (-not $ana) { return $null }
    $sat = New-Object System.Collections.ArrayList
    if ($u.mod -eq "ekle") {
        $m = [double]$ana[4] + [double]$u.raf
        [void]$sat.Add(@{ barkod = [string]$ana[0]; ssb = $ana[1]; stokBirim = $ana[2]; miktar = $m; stokT = [double]$ana[4] })
        return @{ satirlar = $sat; hedefToplam = $stokToplam + [double]$u.raf; stokToplam = $stokToplam }
    }
    $hedef = [double]$u.depo + [double]$u.raf
    [void]$sat.Add(@{ barkod = [string]$ana[0]; ssb = $ana[1]; stokBirim = $ana[2]; miktar = $hedef; stokT = [double]$ana[4] })
    foreach ($b in $barkodlar) {
        if ([string]$b[0] -eq [string]$ana[0]) { continue }
        if ([double]$b[4] -ne 0) { [void]$sat.Add(@{ barkod = [string]$b[0]; ssb = $b[1]; stokBirim = $b[2]; miktar = 0.0; stokT = [double]$b[4] }) }
    }
    return @{ satirlar = $sat; hedefToplam = $hedef; stokToplam = $stokToplam }
}

if ($env:SAYIM_AKTAR_TEST -eq "1") { return }   # yalnizca hesap fonksiyonlari yuklensin (deneme icin)

# ---------------------------------------------------------------------
#  ERP ve bulut baglantilari
# ---------------------------------------------------------------------
function Rpc($fonksiyon, $govde) {
    $json = $govde | ConvertTo-Json -Depth 6 -Compress
    $baytlar = [System.Text.Encoding]::UTF8.GetBytes($json)
    return Invoke-RestMethod -Uri "$DbUrl/rest/v1/rpc/$fonksiyon" -Method Post -Body $baytlar -ContentType "application/json; charset=utf-8" `
        -Headers @{ apikey = $script:Anahtar; Authorization = "Bearer $script:Anahtar" } -TimeoutSec 300 -UserAgent "KRT-Saha-Sayim/1.0"
}
function Baglan() {
    $c = New-Object System.Data.SqlClient.SqlConnection("Server=$SqlServer;Database=$Database;Integrated Security=True;Connect Timeout=30")
    $c.Open(); return $c
}
function Sql($baglanti, $tx, $sql, $param) {
    $cmd = $baglanti.CreateCommand(); if ($tx) { $cmd.Transaction = $tx }; $cmd.CommandText = $sql; $cmd.CommandTimeout = 600
    if ($param) { foreach ($k in $param.Keys) { $v = $param[$k]; if ($v -eq $null) { $v = [DBNull]::Value }; [void]$cmd.Parameters.AddWithValue($k, $v) } }
    return $cmd
}
function Deger($tx, $sql, $param) { $v = (Sql $script:Bag $tx $sql $param).ExecuteScalar(); if ($v -is [DBNull]) { return $null }; return $v }
function Tablo($tx, $sql, $param) { $da = New-Object System.Data.SqlClient.SqlDataAdapter((Sql $script:Bag $tx $sql $param)); $dt = New-Object System.Data.DataTable; [void]$da.Fill($dt); return ,$dt }
function Parcala($liste, $boy) { $p = @(); for ($i = 0; $i -lt $liste.Count; $i += $boy) { $p += ,@($liste[$i..([Math]::Min($i + $boy, $liste.Count) - 1)]) }; return $p }

$script:KolonOnbellek = @{}
function Kopyala($tx, $tablo, $kaynakId, $ust) {
    if (-not $script:KolonOnbellek.ContainsKey($tablo)) {
        $script:KolonOnbellek[$tablo] = @((Tablo $tx "SELECT c.name FROM sys.columns c JOIN sys.types y ON y.user_type_id = c.user_type_id WHERE c.object_id = OBJECT_ID('dbo.$tablo') AND c.is_computed = 0 AND c.is_identity = 0 AND y.name NOT IN ('timestamp','rowversion') ORDER BY c.column_id" $null).Rows | ForEach-Object { [string]$_.name })
    }
    $kol = $script:KolonOnbellek[$tablo]; $p = @{ "@kaynak" = $kaynakId }; $sec = @()
    foreach ($k in $kol) { if ($ust.ContainsKey($k)) { $p["@u_$k"] = $ust[$k]; $sec += "@u_$k" } else { $sec += "[$k]" } }
    foreach ($k in $ust.Keys) { if ($kol -notcontains $k) { throw "$tablo tablosunda $k kolonu yok" } }
    $sql = "INSERT INTO dbo.[$tablo] (" + (($kol | ForEach-Object { "[$_]" }) -join ", ") + ") SELECT " + ($sec -join ", ") + " FROM dbo.[$tablo] WHERE ID = @kaynak"
    if ((Sql $script:Bag $tx $sql $p).ExecuteNonQuery() -ne 1) { throw "$tablo kopyalanamadi (sablon satiri $kaynakId)" }
}
function Sayac($tx, $id, $tablo, $kodPc) {
    if ($kodPc -eq $null) { return }
    [void](Sql $script:Bag $tx "IF NOT EXISTS (SELECT 1 FROM dbo.SEQUNCES WHERE ID = @i) INSERT INTO dbo.SEQUNCES (ID, TABLO, KOD_PC) VALUES (@i, @t, @p)" @{ "@i" = $id; "@t" = $tablo; "@p" = $kodPc }).ExecuteNonQuery()
}

# ---------------------------------------------------------------------
#  ANLASILIR RAPOR (HTML): tarayicida acilir. Ozet kartlari + urun urun tablo; urune tiklayinca okutmalari
#  (nerede, ne zaman, kim, kac) gorunur. ERP'ye yazmadan once bakilir.
# ---------------------------------------------------------------------
function HtmlK($x) { return [System.Net.WebUtility]::HtmlEncode([string]$x) }
function RaporHtml($dosya, $ad, $T, $kap, $saatli, $plan, $b, $satirlar, $esle, $engel, $ozet) {
    $okutma = @{}
    foreach ($s in $satirlar) {
        $kod = ([string]$s[1]).Trim(); $bk = ([string]$s[2]).Trim()
        $sid = if ($kod -and $esle.ContainsKey("K:" + $kod)) { $esle["K:" + $kod] } elseif ($bk -and $esle.ContainsKey("B:" + $bk)) { $esle["B:" + $bk] } else { $null }
        if (-not $sid) { continue }
        if (-not $okutma.ContainsKey([long]$sid)) { $okutma[[long]$sid] = New-Object System.Collections.ArrayList }
        [void]$okutma[[long]$sid].Add($s)
    }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('<!doctype html><html lang="tr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>KRT Saha say&#305;m raporu</title><style>')
    [void]$sb.Append('body{font-family:Segoe UI,Arial,sans-serif;margin:0;background:#f5f6f8;color:#1d1d1f}header{background:#1f2a44;color:#fff;padding:16px 22px}h1{margin:0;font-size:20px}.alt{opacity:.8;font-size:13px;margin-top:4px}')
    [void]$sb.Append('.kartlar{display:flex;flex-wrap:wrap;gap:10px;padding:16px 22px}.kart{background:#fff;border-radius:10px;padding:12px 16px;min-width:150px;box-shadow:0 1px 3px rgba(0,0,0,.08)}.kart small{display:block;color:#666;font-size:12px}.kart b{font-size:20px}')
    [void]$sb.Append('.uyari{margin:0 22px 12px;padding:12px 16px;border-radius:10px;background:#fff3cd;border:1px solid #e0c060}.engel{background:#fde2e1;border-color:#d9534f}.iyi{background:#e3f6e8;border-color:#5cb85c}')
    [void]$sb.Append('table{border-collapse:collapse;width:calc(100% - 44px);margin:0 22px 24px;background:#fff;border-radius:10px;overflow:hidden;font-size:13px}th,td{padding:7px 9px;border-bottom:1px solid #eee;text-align:left}th{background:#eef0f4;position:sticky;top:0;cursor:pointer}td.s{text-align:right;font-family:Consolas,monospace}')
    [void]$sb.Append('.ar{color:#1a7f37;font-weight:700}.ek{color:#c0392b;font-weight:700}tr.u{cursor:pointer}tr.u:hover{background:#f7f9ff}tr.d td{background:#fafbfd;font-size:12px;color:#444}.ara{margin:0 22px 10px}.ara input{padding:8px 10px;width:320px;border:1px solid #ccc;border-radius:8px}')
    [void]$sb.Append('</style></head><body>')
    [void]$sb.Append('<header><h1>Say&#305;m: ' + (HtmlK $ad) + '</h1><div class="alt">' + $(if ($saatli) { 'Saat-dakika: her &#252;r&#252;n kendi okutma saatine g&#246;re' } else { 'Kesinle&#351;tirme an&#305; ' + $T.ToString('dd.MM.yyyy HH:mm:ss') + ' &middot; kapan&#305;&#351; ' + $kap.ToString('dd.MM.yyyy HH:mm') }) + ' &middot; haz&#305;rland&#305; ' + (Get-Date).ToString('dd.MM.yyyy HH:mm') + '</div></header>')
    [void]$sb.Append('<div class="kartlar">')
    foreach ($k in $ozet) { [void]$sb.Append('<div class="kart"><small>' + $k[0] + '</small><b' + $(if ($k[2]) { ' class="' + $k[2] + '"' }) + '>' + (HtmlK $k[1]) + '</b></div>') }
    [void]$sb.Append('</div>')
    if ($engel -gt 0) { [void]$sb.Append('<div class="uyari engel">&#10060; ENGEL VAR: program ERP&#39;ye yazmayacak. Siyah ekrandaki k&#305;rm&#305;z&#305; X sat&#305;rlar&#305;na bak&#305;n.</div>') } else { [void]$sb.Append('<div class="uyari iyi">&#9989; Engel yok. Tablo do&#287;ruysa siyah ekranda EVET yaz&#305;nca bu belge ERP&#39;ye yaz&#305;l&#305;r.</div>') }
    if ($b.eslesmeyen.Count) { [void]$sb.Append('<div class="uyari">' + $b.eslesmeyen.Count + ' okutma ERP&#39;de bir &#252;r&#252;nle e&#351;le&#351;medi (belgeye girmez): ' + (HtmlK ((@($b.eslesmeyen | ForEach-Object { [string]$_[3] + ' (' + [string]$_[2] + ')' } | Select-Object -Unique -First 30)) -join ', ')) + '</div>') }
    [void]$sb.Append('<div class="ara"><input id="q" placeholder="&#220;r&#252;n ara (ad ya da kod)&#8230;" oninput="ara()"> <span style="color:#666;font-size:12px">&#220;r&#252;ne t&#305;klay&#305;nca okutmalar&#305; a&#231;&#305;l&#305;r: nerede, ne zaman, kim, ka&#231;. Ba&#351;l&#305;&#287;a t&#305;klay&#305;nca s&#305;ralan&#305;r.</span></div>')
    [void]$sb.Append('<table id="t"><thead><tr><th onclick="sirala(0)">&#220;r&#252;n</th><th onclick="sirala(1)">Stok kodu</th><th onclick="sirala(2)">Depo</th><th onclick="sirala(3)">Raf</th><th onclick="sirala(4)">Say&#305;lan (yaz&#305;lacak)</th><th onclick="sirala(5)">ERP stok</th><th onclick="sirala(6)">Fark</th><th onclick="sirala(7)">Fark TL</th><th>Ne olacak</th></tr></thead><tbody>')
    $i = 0
    foreach ($p in ($plan | Sort-Object { -[Math]::Abs($_.fark * $_.x.alis) })) {
        $i++; $tl = [Math]::Round($p.fark * $p.x.alis, 2); $cls = if ($p.fark -gt 0) { 'ar' } elseif ($p.fark -lt 0) { 'ek' } else { '' }
        $yon = if ($p.sifir) { 'S&#305;f&#305;rlanacak (hi&#231; say&#305;lmad&#305;)' } elseif ($p.u.mod -eq 'ekle') { '&#220;st&#252;ne eklenecek (ba&#351;ka b&#246;l&#252;mde de say&#305;ld&#305;)' } else { 'Stok say&#305;lana e&#351;itlenecek' }
        [void]$sb.Append('<tr class="u" onclick="ac(' + $i + ')"><td>' + (HtmlK $p.x.ad) + '</td><td>' + (HtmlK $p.x.kod) + '</td><td class="s">' + $p.u.depo + '</td><td class="s">' + $p.u.raf + '</td><td class="s"><b>' + $p.s.hedefToplam + '</b></td><td class="s">' + $p.s.stokToplam + '</td><td class="s ' + $cls + '">' + $(if ($p.fark -gt 0) { '+' }) + $p.fark + '</td><td class="s ' + $cls + '">' + $tl.ToString('N2', $Tr) + '</td><td>' + $yon + '</td></tr>')
        $ok = $okutma[[long]$p.sid]
        $det = if ($ok) { (@($ok | Sort-Object { [long]$_[7] } | ForEach-Object { (EpochTarih $_[7]).ToString('dd.MM HH:mm') + ' &middot; ' + (HtmlK $_[6]) + ' &middot; ' + (HtmlK $_[8]) + ' &middot; <b>' + $_[4] + '</b> (' + (HtmlK $_[2]) + ')' })) -join '<br>' } else { '(okutma yok)' }
        [void]$sb.Append('<tr class="d" id="d' + $i + '" style="display:none"><td colspan="9">' + $det + '</td></tr>')
    }
    [void]$sb.Append('</tbody></table>')
    [void]$sb.Append('<script>function ac(i){var e=document.getElementById("d"+i);e.style.display=e.style.display=="none"?"":"none"}function ara(){var q=document.getElementById("q").value.toLocaleLowerCase("tr");document.querySelectorAll("#t tbody tr.u").forEach(function(r){var g=r.textContent.toLocaleLowerCase("tr").indexOf(q)>=0;r.style.display=g?"":"none";var d=r.nextElementSibling;if(!g)d.style.display="none"})}var yon={};function sirala(c){var tb=document.querySelector("#t tbody"),rs=[].slice.call(tb.querySelectorAll("tr.u"));yon[c]=!yon[c];rs.sort(function(a,b){var x=a.cells[c].textContent,y=b.cells[c].textContent,nx=parseFloat(x.replace(/\./g,"").replace(",",".")),ny=parseFloat(y.replace(/\./g,"").replace(",","."));var r=(!isNaN(nx)&&!isNaN(ny))?nx-ny:x.localeCompare(y,"tr");return yon[c]?r:-r});rs.forEach(function(r){var d=r.nextElementSibling;tb.appendChild(r);tb.appendChild(d)})}</script>')
    [void]$sb.Append('</body></html>')
    [System.IO.File]::WriteAllText($dosya, $sb.ToString(), (New-Object System.Text.UTF8Encoding($true)))
}

# ---------------------------------------------------------------------
#  ERP YEDEGI: ERP'ye yazmadan / silmeden HEMEN ONCE aktif veri tabaninin tam yedegi alinir ve dogrulanir.
#  COPY_ONLY: muhasebenin / gece yedeginin zincirini bozmaz. Yedek alinamazsa ERP'ye YAZILMAZ.
#  Dosya: SQL Server'in yedek klasorunde SAYIM_<veritabani>_<tarih>.bak (son 3 tanesi tutulur).
# ---------------------------------------------------------------------
function ErpYedekAl($neden) {
    Write-Host "  ERP yedegi aliniyor ($neden)... birkac dakika surebilir, kapatmayin." -ForegroundColor Cyan
    $klasor = [string](Deger $null "DECLARE @d nvarchar(4000); EXEC master.dbo.xp_instance_regread N'HKEY_LOCAL_MACHINE', N'Software\Microsoft\MSSQLServer\MSSQLServer', N'BackupDirectory', @d OUTPUT; SELECT ISNULL(@d, '')" $null)
    if (-not $klasor) { throw "SQL Server yedek klasoru bulunamadi" }
    $dosya = Join-Path $klasor ("SAYIM_{0}_{1}.bak" -f $Database, (Get-Date -Format "yyyyMMdd_HHmmss"))
    try { [void](Sql $script:Bag $null "BACKUP DATABASE [$Database] TO DISK = @f WITH COPY_ONLY, CHECKSUM, INIT, COMPRESSION" @{ "@f" = $dosya }).ExecuteNonQuery() }
    catch { [void](Sql $script:Bag $null "BACKUP DATABASE [$Database] TO DISK = @f WITH COPY_ONLY, CHECKSUM, INIT" @{ "@f" = $dosya }).ExecuteNonQuery() }   # Express: sikistirma yok
    [void](Sql $script:Bag $null "RESTORE VERIFYONLY FROM DISK = @f WITH CHECKSUM" @{ "@f" = $dosya }).ExecuteNonQuery()
    try { Get-ChildItem -Path $klasor -Filter "SAYIM_*.bak" -ErrorAction Stop | Sort-Object LastWriteTime -Descending | Select-Object -Skip 3 | Remove-Item -Force -ErrorAction SilentlyContinue } catch {}
    Yaz-Log "ERP YEDEGI ($neden): $dosya (dogrulandi)"
    Write-Host "  Yedek alindi ve dogrulandi: $dosya" -ForegroundColor Green
    return $dosya
}

# ---------------------------------------------------------------------
#  Durum dosyasi: hangi gece ne yazildi (ERP'deki belgeyle her acilista karsilastirilir)
# ---------------------------------------------------------------------
function Durum-Oku() {
    if (Test-Path $DurumDosyasi) { try { return (Get-Content $DurumDosyasi -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { throw "Durum dosyasi okunamadi: $DurumDosyasi ($($_.Exception.Message)) - silmeyin, bana gonderin." } }
    return $null
}
function Durum-Yaz($d) {
    if (Test-Path $DurumDosyasi) { Copy-Item $DurumDosyasi "$DurumDosyasi.yedek" -Force }
    [System.IO.File]::WriteAllText($DurumDosyasi, ($d | ConvertTo-Json -Depth 8), [System.Text.Encoding]::UTF8)
}
function Durum-Uzlastir($d) {
    # ERP'de silinmis belgeler durumdan dusulur; kesinlestirme bilgisi guncellenir
    if (-not $d) { return $d }
    $kalan = @()
    foreach ($g in @($d.geceler)) {
        $r = @((Tablo $null "SELECT ID, ISNULL(FIS, 0) AS FIS FROM dbo.SAYIM WHERE ID = @i" @{ "@i" = [long]$g.sayimId }).Rows)
        if (-not $r.Count) { Uyari "'$($g.ad)' belgesi (SAYIM $($g.sayimId)) ERP'de yok - silinmis; bu gece yazilmamis sayilir."; continue }
        $f = [long]$r[0].FIS
        if ($f -gt 0 -and -not (Deger $null "SELECT ID FROM dbo.FIS WHERE ID = @f" @{ "@f" = $f })) { Uyari "'$($g.ad)' icin ERP'deki sayim fisi silinmis: bu gece KESINLESMEMIS sayilir (3) ile belgeyi silip yeniden aktarabilirsiniz)."; $f = 0 }
        $g.fis = $f
        $kalan += $g
    }
    $d.geceler = $kalan
    return $d
}

# ---------------------------------------------------------------------
#  HAZIRLIK
# ---------------------------------------------------------------------
function Hazirla() {
    if (-not (Test-Path $DbAnahtarDosyasi)) { throw "Anahtar dosyasi yok: $DbAnahtarDosyasi" }
    $script:Anahtar = (Get-Content $DbAnahtarDosyasi -Raw).Trim()
    if (-not $Database) {
        $m = New-Object System.Data.SqlClient.SqlConnection("Server=$SqlServer;Database=master;Integrated Security=True"); $m.Open()
        $c = $m.CreateCommand(); $c.CommandText = "SELECT name FROM sys.databases WHERE name LIKE 'ERP12[0-9][0-9][0-9][0-9]' AND state = 0 ORDER BY name DESC"
        $r = $c.ExecuteReader(); $adlar = @(); while ($r.Read()) { $adlar += [string]$r[0] }; $r.Close(); $m.Close()
        foreach ($a in $adlar) {
            $t = New-Object System.Data.SqlClient.SqlConnection("Server=$SqlServer;Database=$a;Integrated Security=True"); $t.Open()
            $k = $t.CreateCommand(); $k.CommandText = "SELECT COUNT(*) FROM dbo.FIS WITH (NOLOCK) WHERE FIS_TARIHI >= DATEADD(day, -7, GETDATE())"
            $n = [int]$k.ExecuteScalar(); $t.Close(); if ($n -gt 0) { $script:Database = $a; break }
        }
        if (-not $script:Database) { $script:Database = $adlar[0] }
    }
    $script:Bag = Baglan
    $script:Lokasyon = [long](Deger $null "SELECT TOP 1 LOKASYON FROM dbo.SAYIM ORDER BY ID DESC" $null)
    if (-not $script:Lokasyon) { $script:Lokasyon = [long](Deger $null "SELECT TOP 1 LOKASYON FROM dbo.FIS WITH (NOLOCK) WHERE FIS_TURU = 17 ORDER BY ID DESC" $null) }
    if (-not $script:Lokasyon) { throw "Lokasyon bulunamadi" }
    Yaz-Log "ERP veri tabani: $Database, lokasyon: $script:Lokasyon"
}

# Bulut kopyasi (buradan okunan) ile sunucudaki ASIL sayim kayitlari birebir ayni mi? Degilse yazilmaz.
function Asil-Karsilastir($satirlar) {
    if (-not (Test-Path $ErpAnahtarDosyasi)) { return "ERP anahtari yok ($ErpAnahtarDosyasi) - asil kayitlarla karsilastirilamadi" }
    $anahtar = ((Get-Content -Path $ErpAnahtarDosyasi -TotalCount 1) -as [string]).Trim()
    $govde = [System.Text.Encoding]::UTF8.GetBytes((@{ type = "sayim_aktar_kontrol"; anahtar = $anahtar } | ConvertTo-Json -Compress))
    try { $c = Invoke-RestMethod -Uri $SunucuUrl -Method Post -Body $govde -ContentType "application/json; charset=utf-8" -TimeoutSec 300 -UserAgent "KRT-Saha-Sayim/1.0" }
    catch { return "Sunucuya ulasilamadi: $($_.Exception.Message)" }
    if (-not $c -or $c.status -ne "ok") { return "Sunucu kontrolu reddetti: $(if ($c) { $c.message } else { 'bos yanit' })" }
    $sorun = @()
    if ([int]$c.kuyruk.bekleyen -gt 0) { $sorun += "sunucuda buluta henuz gonderilmemis $($c.kuyruk.bekleyen) kayit var (en eskisi $($c.kuyruk.enEskiDk) dk) - birkac dakika bekleyip tekrar deneyin" }
    if ([int]$c.kuyruk.karantina -gt 0) { $sorun += "bulutun kabul etmedigi $($c.kuyruk.karantina) kayit var (DbKuyrukHata sekmesi) - bana haber verin" }
    $asil = @{}; foreach ($x in @($c.kayitlar)) { $asil[[string]$x[0]] = [double]$x[1] }
    $bulut = @{}; foreach ($x in $satirlar) { $bulut[[string]$x[0]] = [double]$x[4] }
    $eksik = @($asil.Keys | Where-Object { -not $bulut.ContainsKey($_) })
    $fazla = @($bulut.Keys | Where-Object { -not $asil.ContainsKey($_) })
    $farkli = @($asil.Keys | Where-Object { $bulut.ContainsKey($_) -and [Math]::Abs($asil[$_] - $bulut[$_]) -gt 0.0001 })
    if ($eksik.Count) { $sorun += "$($eksik.Count) okutma sunucuda var, bulut kopyasinda YOK (or. $(($eksik | Select-Object -First 3) -join ', '))" }
    if ($fazla.Count) { $sorun += "$($fazla.Count) okutma bulutta var, sunucuda YOK (silinmis olabilir; or. $(($fazla | Select-Object -First 3) -join ', '))" }
    if ($farkli.Count) { $sorun += "$($farkli.Count) okutmanin adedi sunucuyla farkli (or. $(($farkli | Select-Object -First 3) -join ', '))" }
    if ($sorun.Count) { return ($sorun -join "; ") }
    Write-Host "  Asil kayitlarla birebir ayni: $($asil.Count) okutma, kuyruk bos." -ForegroundColor Green
    Yaz-Log "ASIL KARSILASTIRMA tamam: $($asil.Count) okutma"
    return ""
}

function Donem-Sec($durum) {
    $r = Rpc "sayim_donemleri_ver" @{}
    if (-not $r -or $r.status -ne "ok") { throw "Sayim donemleri alinamadi (039_sayim_aktar.sql calistirildi mi?)" }
    $l = @($r.donemler)
    if ($durum -and $durum.donem) {
        $d = $l | Where-Object { [long]$_[0] -eq [long]$durum.donem } | Select-Object -First 1
        if ($d -and [long]$l[0][0] -ne [long]$d[0]) {
            Write-Host "  Daha once kullanilan donem #$($d[0]); ama daha YENI bir donem var: #$($l[0][0]) ($($l[0][1]), $($l[0][3]) okutma)." -ForegroundColor Yellow
            if ((Read-Host "  Yeni donemle (yeni sayim) devam edilsin mi? E / H").Trim().ToUpper() -eq "E") { return [long]$l[0][0] }
        }
        if ($d) { Write-Host "  Sayim donemi: #$($d[0]) ($($d[1]), $($d[3]) okutma) - bu sayim icin daha once secilmis." -ForegroundColor Green; return [long]$d[0] }
    }
    Write-Host "  Son sayim donemleri:"
    for ($i = 0; $i -lt [Math]::Min(8, $l.Count); $i++) { Write-Host ("   {0}) #{1}  basladi {2}  {3} okutma  {4}" -f ($i + 1), $l[$i][0], $l[$i][1], $l[$i][3], $l[$i][2]) }
    $s = Read-Host "  Hangi donem? [Enter = 1]"; if (-not $s) { $s = "1" }
    return [long]$l[[int]$s - 1][0]
}

function Okutmalar($donem) {
    Write-Host "  Okutmalar buluttan aliniyor..."
    $r = Rpc "sayim_kayitlari_ver" @{ p_donem = $donem }
    if (-not $r -or $r.status -ne "ok") { throw "Okutmalar alinamadi" }
    $s = @($r.satirlar); Yaz-Log "Donem #$donem : $($s.Count) okutma"
    # Ham kopya: her calistirmada butun okutmalar bu bilgisayara da yazilir (bulut / sunucu disinda 3. kopya)
    try {
        $hk = Join-Path $RaporKlasoru "ham"; if (-not (Test-Path $hk)) { New-Item -ItemType Directory -Path $hk -Force | Out-Null }
        $hd = Join-Path $hk ("donem{0}-{1}.json" -f $donem, (Get-Date -Format "yyyyMMdd-HHmmss"))
        [System.IO.File]::WriteAllText($hd, ($r | ConvertTo-Json -Depth 6 -Compress), [System.Text.Encoding]::UTF8)
        $sb = New-Object System.Text.StringBuilder; [void]$sb.AppendLine("Kayit ID;Stok Kodu;Barkod;Urun;Adet;Birim;Reyon;Okutma Zamani;Personel")
        foreach ($x in $s) { [void]$sb.AppendLine(("{0};{1};{2};{3};{4};{5};{6};{7};{8}" -f $x[0], $x[1], $x[2], ([string]$x[3] -replace ';', ','), ([double]$x[4]).ToString($Inv), $x[5], ([string]$x[6] -replace ';', ','), (EpochTarih $x[7]).ToString("dd.MM.yyyy HH:mm:ss"), $x[8])) }
        [System.IO.File]::WriteAllText([System.IO.Path]::ChangeExtension($hd, ".csv"), "$([char]0xFEFF)" + $sb.ToString(), [System.Text.Encoding]::UTF8)
        Write-Host "  Okutmalarin kopyasi bu bilgisayara kaydedildi: $hk" -ForegroundColor DarkGray
    } catch { Uyari "Okutmalarin yerel kopyasi yazilamadi: $($_.Exception.Message)" }
    return $s
}

# Stok kodu / barkod -> STOK ID
function Eslestir($satirlar) {
    $esle = @{}
    $kodlar = @($satirlar | ForEach-Object { ([string]$_[1]).Trim() } | Where-Object { $_ } | Sort-Object -Unique)
    foreach ($p in (Parcala $kodlar 500)) {
        $param = @{}; $ad = @(); for ($i = 0; $i -lt $p.Count; $i++) { $param["@k$i"] = $p[$i]; $ad += "@k$i" }
        foreach ($r in (Tablo $null "SELECT ID, KOD FROM dbo.STOK WITH (NOLOCK) WHERE KOD IN ($($ad -join ','))" $param).Rows) { $esle["K:" + [string]$r.KOD] = [long]$r.ID }
    }
    $barkodlar = @($satirlar | Where-Object { -not $esle.ContainsKey("K:" + ([string]$_[1]).Trim()) } | ForEach-Object { ([string]$_[2]).Trim() } | Where-Object { $_ } | Sort-Object -Unique)
    foreach ($p in (Parcala $barkodlar 500)) {
        $param = @{}; $ad = @(); for ($i = 0; $i -lt $p.Count; $i++) { $param["@b$i"] = $p[$i]; $ad += "@b$i" }
        foreach ($r in (Tablo $null "SELECT DISTINCT BARKOD, STOK FROM dbo.STOK_BARKOD_BIRIM WITH (NOLOCK) WHERE BARKOD IN ($($ad -join ','))" $param).Rows) { $esle["B:" + [string]$r.BARKOD] = [long]$r.STOK }
    }
    return $esle
}

# Urunlerin barkodlari ve $T anindaki barkod barkod stogu (ERP'nin kendi formulu: SAYIM_MIKTARI_VER_TARIHLI)
function ErpBilgi($ids, $T, $tMap) {
    # $tMap (istege bagli): stokId -> datetime. Verilirse her urunun stogu KENDI aninda hesaplanir (saat-dakika modu).
    $bilgi = @{}
    foreach ($p in (Parcala @($ids) 400)) {
        $liste = ($p | ForEach-Object { [long]$_ }) -join ","
        foreach ($r in (Tablo $null "SELECT s.ID, s.KOD, s.AD, ISNULL(s.SON_ALIS_FIYAT, 0) AS ALIS FROM dbo.STOK s WITH (NOLOCK) WHERE s.ID IN ($liste)" $null).Rows) {
            $bilgi[[long]$r.ID] = @{ kod = [string]$r.KOD; ad = [string]$r.AD; alis = [double]$r.ALIS; barkodlar = @{} }
        }
        foreach ($r in (Tablo $null "SELECT u.STOK, b.BARKOD, u.ID AS SSB, u.STOK_BIRIM, ISNULL(u.CARPAN, 1) AS CARPAN FROM dbo.STOK_BARKOD b WITH (NOLOCK) JOIN dbo.STOK_STOK_BIRIM u WITH (NOLOCK) ON u.ID = b.STOK_STOK_BIRIM WHERE u.STOK IN ($liste)" $null).Rows) {
            $x = $bilgi[[long]$r.STOK]; if (-not $x) { continue }
            $x.barkodlar[[string]$r.BARKOD] = @([string]$r.BARKOD, [long]$r.SSB, [long]$r.STOK_BIRIM, [double]$r.CARPAN, 0.0)
        }
        $stokSql = "SELECT STOK, BARKOD, SUM(MIKTAR_GIRIS - MIKTAR_CIKIS) AS M FROM dbo.FIS_DETAY WITH (NOLOCK) WHERE FATRALANDIRILMIS_IRSALIYEMI = 0 AND FIS_TARIHI <= @t AND LOKASYON = @l AND ISNULL(PARTINO, '') = '' AND STOK IN ($liste) GROUP BY STOK, BARKOD"
        if ($tMap) {
            $vals = ($p | ForEach-Object { "($([long]$_), CONVERT(datetime, '$(([datetime]$tMap[[long]$_]).ToString('yyyy-MM-ddTHH:mm:ss'))', 126))" }) -join ","
            $stokSql = "SELECT d.STOK, d.BARKOD, SUM(d.MIKTAR_GIRIS - d.MIKTAR_CIKIS) AS M FROM dbo.FIS_DETAY d WITH (NOLOCK) JOIN (VALUES $vals) v(S, T) ON v.S = d.STOK AND d.FIS_TARIHI <= v.T WHERE d.FATRALANDIRILMIS_IRSALIYEMI = 0 AND d.LOKASYON = @l AND ISNULL(d.PARTINO, '') = '' GROUP BY d.STOK, d.BARKOD"
        }
        foreach ($r in (Tablo $null $stokSql @{ "@t" = $T; "@l" = $script:Lokasyon }).Rows) {
            $x = $bilgi[[long]$r.STOK]; if (-not $x) { continue }
            $m = if ($r.M -is [DBNull]) { 0.0 } else { [double]$r.M }
            $bk = [string]$r.BARKOD
            if ($x.barkodlar.ContainsKey($bk)) { $x.barkodlar[$bk][4] = $m }
            elseif ($m -ne 0) {
                # Karttan silinmis ama stogu kalmis barkod: sifirlanmasi icin birim bilgisi ilk barkoddan alinir
                $ilk = @($x.barkodlar.Values)[0]
                if ($ilk) { $x.barkodlar[$bk] = @($bk, $ilk[1], $ilk[2], 99.0, $m) }   # carpan 99: ana barkod secilmesin, yalniz 0'lansin
            }
        }
    }
    return $bilgi
}

function Yapilanlar($durum) {
    $y = @{}
    if ($durum) { foreach ($g in @($durum.geceler)) { foreach ($u in @($g.urunler)) { $y[[long]$u[0]] = $true } } }
    return $y
}

# ---------------------------------------------------------------------
#  1) GECE AKTAR
# ---------------------------------------------------------------------
function Gece-Aktar() {
    $durum = Durum-Uzlastir (Durum-Oku)
    $donem = Donem-Sec $durum
    if ($durum -and $durum.donem -and [long]$durum.donem -ne $donem) {
        # Yeni sayim donemi (or. deneme sayimindan sonra asil sayim): eski donemin kaydi arsivlenir, yeni sayim temiz baslar
        $acikEski = @($durum.geceler | Where-Object { [long]$_.fis -le 0 })
        if ($acikEski.Count) { throw "Eski donemin (#$($durum.donem)) kesinlestirilmemis belgesi var: $(($acikEski | ForEach-Object { $_.ad }) -join ', '). Once kesinlestirin ya da 3) ile silin." }
        $arsiv = $DurumDosyasi -replace '\.json$', ("-donem{0}-{1}.json" -f $durum.donem, (Get-Date -Format "yyyyMMdd-HHmm"))
        if ((Read-Host "  Donem #$($durum.donem) kaydi arsivlenip ($arsiv) yeni sayim #$donem baslatilsin mi? EVET yazin") -cne "EVET") { return }
        Move-Item $DurumDosyasi $arsiv -Force; if (Test-Path "$DurumDosyasi.yedek") { Remove-Item "$DurumDosyasi.yedek" -Force }
        Yaz-Log "Durum arsivlendi: $arsiv (yeni donem #$donem)"
        $durum = $null
    }
    if (-not $durum) { $durum = [pscustomobject]@{ donem = $donem; geceler = @() } }
    $acik = @($durum.geceler | Where-Object { [long]$_.fis -le 0 })
    if ($acik.Count) { throw "Once onceki gece(ler) ERP'de kesinlestirilmeli: $(($acik | ForEach-Object { $_.ad + ' (SAYIM ' + $_.sayimId + ')' }) -join ', '). Sonra bu programda 2) KONTROL yapin." }

    $satirlar = Okutmalar $donem
    $sonDonem = [long]((Rpc "sayim_donemleri_ver" @{}).donemler[0][0])
    $asilSorun = if ($donem -eq $sonDonem) { Asil-Karsilastir $satirlar } else { "Secilen donem en son donem degil; sunucudaki asil kayitlarla karsilastirilamaz" }
    $atanmis = @{}; foreach ($g in @($durum.geceler)) { foreach ($x in @($g.bolumler)) { if ($x) { $atanmis[[string]$x] = [string]$g.ad } } }

    Baslik "Sayim bolumleri (ilk okutma -> son okutma)"
    $liste = Bolumler $satirlar; $secilebilir = @()
    foreach ($x in $liste) {
        $durumM = if ($x.depo) { "depo: urunun ilk raf gecesinde / SON'da eklenir" } elseif ($atanmis.ContainsKey($x.bolum)) { "YAZILDI: " + $atanmis[$x.bolum] } else { $secilebilir += $x; "[" + $secilebilir.Count + "]" }
        Write-Host ("  {0,-6} {1,-38} {2} -> {3}  {4,6} okutma {5,5} urun  {6}" -f $(if ($x.depo -or $atanmis.ContainsKey($x.bolum)) { "" } else { "[" + $secilebilir.Count + "]" }), (Kisalt $x.ad 38), $x.ilk.ToString("dd.MM HH:mm"), $x.son.ToString("dd.MM HH:mm"), $x.okutma, $x.urun.Count, $(if ($x.depo -or $atanmis.ContainsKey($x.bolum)) { $durumM } else { (@($x.kisi.Keys) -join ', ') }))
    }
    $depoB = @($liste | Where-Object { $_.depo })
    if ($depoB.Count) { $dIlk = ($depoB | ForEach-Object { $_.ilk } | Sort-Object)[0]; $dSon = ($depoB | ForEach-Object { $_.son } | Sort-Object)[-1]; if (($dSon - $dIlk).TotalHours -gt 16) { Uyari "Depo okutmalari $([Math]::Round(($dSon - $dIlk).TotalHours)) saate yayiliyor ($($dIlk.ToString('dd.MM HH:mm')) - $($dSon.ToString('dd.MM HH:mm'))). Gece rafta sayarken reyonu 'Depo'da unutan olmus olabilir: uygulamada Bolumler / Duzelt ile bakin." } }

    Write-Host ""
    Write-Host "  HEPSI: depo dahil butun okutmalar TEK belgede (deneme / tek seferde yapilan sayim icin)" -ForegroundColor DarkGray
    $sec = (Read-Host "  Bu gecenin bolumleri (numaralar, or. 1,3)  |  hepsi bitince depoda kalan urunleri kapatmak icin: SON  |  HEPSI").Trim()
    $son = (NormTr $sec) -eq "son"
    $hepsi = (NormTr $sec) -eq "hepsi"
    $secili = @{}
    if ($son) {
        if (@($durum.geceler | Where-Object { $_.son }).Count) { throw "SON kapanis zaten yazilmis" }
        if ($secilebilir.Count) { Hata "Henuz yazilmamis $($secilebilir.Count) bolum var: $(($secilebilir | ForEach-Object { $_.ad }) -join ', '). SON'dan once bu bolumler gece olarak yazilmali."; if ((Read-Host "  Bu bolumler HIC aktarilmayacak. Bilerek devam icin DEVAM yazin") -cne "DEVAM") { return } }
        $ad = "SON kapanis"
    } elseif ($hepsi) {
        if (@($durum.geceler).Count) { throw "HEPSI yalniz hic gece yazilmamis bir donemde kullanilabilir" }
        foreach ($x in $secilebilir) { $secili[$x.bolum] = $true }
        $ad = "Hepsi (depo dahil)"
    } else {
        foreach ($n in ($sec -split '[,; ]+' | Where-Object { $_ })) { $k = 0; if (-not [int]::TryParse($n, [ref]$k) -or $k -lt 1 -or $k -gt $secilebilir.Count) { throw "Gecersiz numara: $n" }; $secili[$secilebilir[$k - 1].bolum] = $true }
        if (-not $secili.Count) { throw "Bolum secilmedi" }
        $ad = (@($secili.Keys) -join " + ")
    }
    $sx = @($liste | Where-Object { ($hepsi -and $_.depo) -or (-not $_.depo -and $secili.ContainsKey($_.bolum)) })
    if ($son) { $ilk = ($depoB | ForEach-Object { $_.ilk } | Sort-Object)[0] } else { $ilk = ($sx | ForEach-Object { $_.ilk } | Sort-Object)[0] }
    if (-not $ilk) { $ilk = Get-Date }
    $gun = if ($ilk.Hour -lt 6) { $ilk.Date.AddDays(-1) } else { $ilk.Date }
    $sonT = (@($durum.geceler) | ForEach-Object { [datetime]$_.T } | Sort-Object | Select-Object -Last 1)
    $saatli = $false
    if ($son) { Write-Host "  SON kapanis: depoda sayilip hicbir bolumde cikmayan urunler depo sayimiyla kapanir; istenirse hic sayilmayanlar sifirlanir." -ForegroundColor Cyan }
    Baslik "$ad"
    if ($son) {
        $kap = Sor-Tarih "  Depo sayiminin BASLADIGI an (bundan sonra depodaki mallarda ERP hareketi olmamali)" $ilk
        $T = Sor-Tarih "  ERP kesinlestirme ani" $(if ($sonT) { $sonT.AddMinutes(1) } else { $gun.AddHours(23).AddMinutes(59).AddSeconds(59) })
    } else {
        $sonOk = (($sx | ForEach-Object { $_.son } | Sort-Object)[-1])
        Write-Host "  Secilen bolumlerin ilk okutmasi: $($ilk.ToString('dd.MM.yyyy HH:mm')), son okutmasi: $($sonOk.ToString('dd.MM.yyyy HH:mm'))"
        Write-Host ""
        Write-Host "  Bu sayim nasil yapildi?"
        Write-Host "   1) Gece, magaza KAPALIYKEN (butun urunler tek bir ana gore)"
        Write-Host "   2) Magaza ACIKKEN / saat-dakika: her urun KENDI okutma saatindeki stokla karsilastirilir;"
        Write-Host "      okutmadan sonra yapilan satislar dogru duser (deneme sayimi, gunduz sayimi)"
        $saatli = ((Read-Host "  Secim [Enter = 1]").Trim() -eq "2")
    }
    if ($saatli) {
        $kap = $ilk
        $T = Sor-Tarih "  Belge / kesinlestirme ani (son okutmadan sonra olmali)" ($sonOk.AddSeconds(60 - $sonOk.Second))
        if ($T -lt $sonOk) { throw "Kesinlestirme ani son okutmadan ($($sonOk.ToString('dd.MM HH:mm:ss'))) once olamaz" }
        Write-Host "  Saat-dakika modu: her urunun stogu kendi SON okutma anina gore hesaplanir." -ForegroundColor Cyan
    } elseif (-not $son) {
        $kap = Sor-Tarih "  Magaza / kasa KAPANIS saati o gece (bundan sonra ERP'de hareket olmamali)" $(if ($ilk.Hour -ge 6) { $ilk.AddMinutes(-$ilk.Minute) } else { $gun.AddHours(21) })
        $T = Sor-Tarih "  ERP kesinlestirme ani (sayimin basladigi gunun 23:59'u onerilir)" ($gun.AddHours(23).AddMinutes(59).AddSeconds(59))
        if ($ilk -lt $kap) { Uyari "Secilen bolumlerde kapanistan ($($kap.ToString('HH:mm'))) ONCE okutma var ($($ilk.ToString('dd.MM HH:mm'))): magaza acikken sayilmis olabilir. Oyleyse vazgecip 2) saat-dakika modunu secin." }
    }
    if ($T -lt $kap) { throw "Kesinlestirme ani kapanistan once olamaz" }
    if ($sonT -and $T -le $sonT) { throw "Kesinlestirme ani, daha once yazilan son geceden ($($sonT.ToString('dd.MM.yyyy HH:mm'))) sonra olmali. Geceleri sirayla aktarin." }
    if (@($durum.geceler | Where-Object { (NormTr $_.ad) -eq (NormTr $ad) }).Count) { throw "'$ad' adiyla bir gece zaten yazilmis." }

    $esle = Eslestir $satirlar
    $yapilan = Yapilanlar $durum
    $b = Birlestir $satirlar $esle $secili $yapilan ($son -or $hepsi) $atanmis
    $u = $b.urunler
    if (-not $u.Count) { throw "Secilen bolumlerde aktarilacak urun yok." }
    Write-Host "  Bu gece: $($u.Count) urun ($(@($u.Values | Where-Object { $_.mod -eq 'esitle' }).Count) ilk kez, $(@($u.Values | Where-Object { $_.mod -eq 'ekle' }).Count) daha once baska bolumde sayilmis: ustune eklenir)"

    $tMap = $null
    if ($saatli) {
        $tMap = @{}
        foreach ($sid in $u.Keys) {
            $t0 = $(if ($u[$sid].son) { [datetime]$u[$sid].son } else { $T })
            if ($hepsi -and $u[$sid].sonDepo -and [datetime]$u[$sid].sonDepo -gt $t0) { $t0 = [datetime]$u[$sid].sonDepo }   # HEPSI: 'Depo' etiketli okutma da magaza acikken yapildi
            $tMap[[long]$sid] = $t0
        }
        if ($sonT) { $erken = @($tMap.Values | Where-Object { $_ -le $sonT }); if ($erken.Count) { throw "$($erken.Count) urunun okutmasi daha once yazilan son geceden ($($sonT.ToString('dd.MM HH:mm'))) once. Geceleri sirayla aktarin." } }
    }
    $bilgi = ErpBilgi @($u.Keys) $T $tMap
    # Belge satirlari
    $plan = New-Object System.Collections.ArrayList; $kartsiz = New-Object System.Collections.ArrayList
    foreach ($sid in $u.Keys) {
        $x = $bilgi[[long]$sid]; if (-not $x) { [void]$kartsiz.Add($sid); continue }
        $s = Satirlar $u[$sid] @($x.barkodlar.Values) @($u[$sid].barkodlar)
        if (-not $s) { [void]$kartsiz.Add($sid); continue }
        [void]$plan.Add(@{ sid = [long]$sid; x = $x; u = $u[$sid]; s = $s; fark = $s.hedefToplam - $s.stokToplam; tarih = $(if ($tMap) { $tMap[[long]$sid] } else { $null }) })
    }

    # SON: hic okutulmayan ama ERP'de stogu gorunen urunler istenirse SIFIRLANIR (ancak butun bolumler bittikten sonra
    # guvenli: daha once sifirlanirsa sayilmayi bekleyen bolumlerin satislari stogu bozar).
    $sifirlanan = @{}
    if ($son) {
        $sayilan = @{}; foreach ($v in $esle.Values) { $sayilan[[long]$v] = $true }
        $sz = @((Tablo $null "SELECT s.ID, SUM(d.MIKTAR_GIRIS - d.MIKTAR_CIKIS) AS M, ISNULL(s.SON_ALIS_FIYAT, 0) AS ALIS FROM dbo.FIS_DETAY d WITH (NOLOCK) JOIN dbo.STOK s WITH (NOLOCK) ON s.ID = d.STOK WHERE d.FATRALANDIRILMIS_IRSALIYEMI = 0 AND d.FIS_TARIHI <= @t AND d.LOKASYON = @l GROUP BY s.ID, s.SON_ALIS_FIYAT HAVING ABS(SUM(d.MIKTAR_GIRIS - d.MIKTAR_CIKIS)) > 0.0001" @{ "@t" = $T; "@l" = $script:Lokasyon }).Rows | Where-Object { -not $sayilan.ContainsKey([long]$_.ID) -and -not $u.ContainsKey([long]$_.ID) })
        if ($sz.Count) {
            $art = 0.0; $eks = 0.0; foreach ($x in $sz) { $tl = [double]$x.M * [double]$x.ALIS; if ($tl -gt 0) { $art += $tl } else { $eks += $tl } }
            Write-Host ""
            Write-Host "  Hic okutulmayan ama ERP'de stogu olan $($sz.Count) urun var (arti stok $(Tl $art), eksi stok $(Tl $eks))." -ForegroundColor Yellow
            Write-Host "  Listesi icin once 4) Sayilmayanlar'a bakabilirsiniz. SIFIRLANIRSA bu urunlerin stogu $($T.ToString('dd.MM.yyyy HH:mm')) itibariyla 0 olur." -ForegroundColor Yellow
            if ((Read-Host "  Bunlar da sifirlansin mi? Evet icin SIFIRLA yazin (Enter: hayir, dokunulmaz)") -ceq "SIFIRLA") {
                $sb2 = $sz | ForEach-Object { [long]$_.ID }
                $bilgi2 = ErpBilgi @($sb2) $T
                foreach ($sid in $sb2) {
                    $x = $bilgi2[[long]$sid]; if (-not $x) { continue }
                    $uu = @{ depo = 0.0; raf = 0.0; mod = "esitle"; ad = $x.ad; barkodlar = @() }
                    $st = Satirlar $uu @($x.barkodlar.Values) @()
                    if (-not $st) { [void]$kartsiz.Add($sid); continue }
                    [void]$plan.Add(@{ sid = [long]$sid; x = $x; u = $uu; s = $st; fark = $st.hedefToplam - $st.stokToplam; sifir = $true }); $sifirlanan[[long]$sid] = $true
                }
                Write-Host "  $($sifirlanan.Count) urun SIFIRLANMAK uzere belgeye eklendi (raporda 'SIFIRLANAN')." -ForegroundColor Yellow
            }
        }
    }

    # DENETIMLER
    Baslik "Denetimler"
    $engel = 0
    if ($asilSorun) { Hata "Okutmalar sunucudaki asil kayitlarla dogrulanamadi: $asilSorun"; $engel++ }
    if ($b.eslesmeyen.Count) { Uyari "$($b.eslesmeyen.Count) okutma ERP'de bir urunle eslesmedi (stok kodu / barkod ERP'de yok, ya da uygulamada acilan yeni urun). Raporda 'ESLESMEYEN'. Bu urunler belgeye GIRMEZ." }
    if ($kartsiz.Count) { Uyari "$($kartsiz.Count) urunun ERP kartinda adet barkodu yok; belgeye girmez (raporda)." }
    $hareket = @()
    foreach ($p in (Parcala @($plan | Where-Object { -not $_.sifir -and -not $saatli } | ForEach-Object { $_.sid }) 400)) {
        $hareket += @((Tablo $null "SELECT TOP 50 d.STOK, f.BELGENO, FT.AD AS TUR, d.FIS_TARIHI, d.MIKTAR_GIRIS - d.MIKTAR_CIKIS AS M FROM dbo.FIS_DETAY d WITH (NOLOCK) JOIN dbo.FIS f WITH (NOLOCK) ON f.ID = d.FIS JOIN dbo.FIS_TURU FT ON FT.ID = f.FIS_TURU WHERE d.FATRALANDIRILMIS_IRSALIYEMI = 0 AND d.FIS_TARIHI > @k AND d.FIS_TARIHI <= @t AND d.LOKASYON = @l AND f.FIS_TURU <> 17 AND d.STOK IN ($(($p | ForEach-Object { [long]$_ }) -join ',')) ORDER BY d.FIS_TARIHI" @{ "@k" = $kap; "@t" = $T; "@l" = $script:Lokasyon }).Rows)
    }
    if ($hareket.Count) {
        Hata "Kapanis ($($kap.ToString('dd.MM HH:mm'))) ile kesinlestirme ani ($($T.ToString('dd.MM HH:mm'))) arasinda sayilan urunlerde ERP hareketi var:"
        $hareket | Select-Object -First 15 | ForEach-Object { Write-Host ("     {0}  {1}  {2}  {3}" -f ([datetime]$_.FIS_TARIHI).ToString('dd.MM HH:mm'), $_.TUR, $_.BELGENO, $_.M) }
        Write-Host "     Bu belgeler sayimdan once mi sonra mi? Sayimdan SONRAki mal ise belge tarihi ertesi gune alinmali; ONCEyse kapanis saatini duzeltin." -ForegroundColor Yellow
        $engel++
    }
    $sonraki = Deger $null "SELECT TOP 1 FIS_TARIHI FROM dbo.FIS WITH (NOLOCK) WHERE FIS_TURU = 17 AND LOKASYON = @l AND FIS_TARIHI > @t ORDER BY FIS_TARIHI" @{ "@l" = $script:Lokasyon; "@t" = $T }
    if ($sonraki) { Hata "ERP'de bu andan SONRA tarihli bir sayim fisi var ($(([datetime]$sonraki).ToString('dd.MM.yyyy HH:mm'))). ERP eski tarihli kesinlestirmeyi karistirir."; $engel++ }
    $digerAcik = @((Tablo $null "SELECT ID, TARIH, ISNULL(ACIKLAMA, '') AS ACIKLAMA FROM dbo.SAYIM WHERE ISNULL(FIS, 0) = 0 AND TARIH >= DATEADD(day, -30, GETDATE())" $null).Rows)
    if ($digerAcik.Count) { Uyari "ERP'de kesinlestirilmemis $($digerAcik.Count) sayim belgesi var (son 30 gun). Kesinlestirirken YALNIZ bu programin yazdigi belgeyi secin." }
    $buyuk = @($plan | Where-Object { [Math]::Abs($_.fark) * [Math]::Max($_.x.alis, 0) -ge 1000 })
    if ($engel -eq 0) { Write-Host "  Engel yok." -ForegroundColor Green }

    # RAPOR
    if (-not (Test-Path $RaporKlasoru)) { New-Item -ItemType Directory -Path $RaporKlasoru | Out-Null }
    $dosya = Join-Path $RaporKlasoru ("{0}-{1}.csv" -f (Kisalt ((NormTr $ad) -replace '[^a-z0-9]+', '-') 60), (Get-Date -Format "yyyyMMdd-HHmm"))
    $csv = New-Object System.Text.StringBuilder
    [void]$csv.AppendLine("Durum;Stok Kodu;Urun;Depo;Raf;Sayilan (belgeye);ERP stok (o an);Fark;Fark TL (son alis);Yontem;Barkod satirlari")
    $topFazla = 0.0; $topEksik = 0.0; $tlFazla = 0.0; $tlEksik = 0.0
    foreach ($p in ($plan | Sort-Object { -[Math]::Abs($_.fark * $_.x.alis) })) {
        $tl = $p.fark * $p.x.alis
        if ($p.fark -gt 0) { $topFazla += $p.fark; $tlFazla += $tl } elseif ($p.fark -lt 0) { $topEksik += $p.fark; $tlEksik += $tl }
        $sat = ($p.s.satirlar | ForEach-Object { "$($_.barkod)=$($_.miktar.ToString($Inv))" }) -join " "
        [void]$csv.AppendLine(("{0};{1};{2};{3};{4};{5};{6};{7};{8};{9};{10}" -f $(if ($p.sifir) { "SIFIRLANAN (hic sayilmadi)" } else { "BELGE" }), $p.x.kod, ($p.x.ad -replace ';', ','), $p.u.depo.ToString($Inv), $p.u.raf.ToString($Inv), $p.s.hedefToplam.ToString($Inv), $p.s.stokToplam.ToString($Inv), $p.fark.ToString($Inv), ([Math]::Round($tl, 2)).ToString($Inv), $(if ($p.u.mod -eq 'ekle') { 'USTUNE EKLE (baska bolumde de sayildi)' } else { 'ESITLE' }), $sat))
    }
    foreach ($s in $b.eslesmeyen) { [void]$csv.AppendLine(("ESLESMEYEN;{0};{1};;{2};;;;;;barkod {3}, reyon {4}, {5}" -f $s[1], ([string]$s[3] -replace ';', ','), $s[4], $s[2], $s[6], $s[8])) }
    if ($son) { foreach ($s in $b.kalan) { [void]$csv.AppendLine(("HIC AKTARILMADI (bolumu yazilmadi);{0};{1};;{2};;;;;;barkod {3}, reyon {4}, {5}, {6}" -f $s[1], ([string]$s[3] -replace ';', ','), $s[4], $s[2], $s[6], (EpochTarih $s[7]).ToString('dd.MM HH:mm'), $s[8])) } }
    foreach ($sid in $kartsiz) { [void]$csv.AppendLine("KARTTA ADET BARKODU YOK;$sid;$($u[$sid].ad);;;;;;;;") }
    [System.IO.File]::WriteAllText($dosya, "$([char]0xFEFF)" + $csv.ToString(), [System.Text.Encoding]::UTF8)
    $htmlDosya = [System.IO.Path]::ChangeExtension($dosya, ".html")
    $ozet = @(
        @("&#220;r&#252;n say&#305;s&#305; (belgeye girecek)", [string]$plan.Count, ""),
        @("Fazla &#231;&#305;kan", ((Sayi $topFazla) + " adet / " + (Tl $tlFazla)), "ar"),
        @("Eksik &#231;&#305;kan", ((Sayi $topEksik) + " adet / " + (Tl $tlEksik)), "ek"),
        @("E&#351;le&#351;meyen okutma", [string]$b.eslesmeyen.Count, ""),
        @("1.000 TL &#252;st&#252; fark", [string]@($plan | Where-Object { [Math]::Abs($_.fark * $_.x.alis) -ge 1000 }).Count, ""))
    try { RaporHtml $htmlDosya $ad $T $kap $saatli $plan $b $satirlar $esle $engel $ozet; Start-Process $htmlDosya; Write-Host "  Anlasilir rapor tarayicida acildi: $htmlDosya" -ForegroundColor Green } catch { Uyari "HTML rapor yazilamadi: $($_.Exception.Message)" }

    Baslik "OZET: $ad"
    Write-Host "  Kesinlestirme ani: $($T.ToString('dd.MM.yyyy HH:mm:ss'))   kapanis: $($kap.ToString('dd.MM.yyyy HH:mm'))"
    Write-Host "  Belgeye girecek urun: $($plan.Count)   (satir: $(($plan | ForEach-Object { $_.s.satirlar.Count } | Measure-Object -Sum).Sum))"
    Write-Host "  Fazla cikan: $(Sayi $topFazla) adet  ($(Tl $tlFazla))"
    Write-Host "  Eksik cikan: $(Sayi $topEksik) adet  ($(Tl $tlEksik))"
    Write-Host "  1.000 TL'den buyuk farkli urun: $($buyuk.Count)  - ikinci kez saydirmaniz onerilir"
    Write-Host "  Rapor (Excel'de acilir): $dosya" -ForegroundColor Green
    Write-Host "  Kontrol icin bu dosyayi ve $RaporKlasoru\ham klasorundeki son dosyayi gonderebilirsiniz." -ForegroundColor DarkGray
    Write-Host "  En buyuk 10 fark:"
    $plan | Sort-Object { -[Math]::Abs($_.fark * $_.x.alis) } | Select-Object -First 10 | ForEach-Object { Write-Host ("     {0,-12} {1,-40} sayilan {2,9}  ERP {3,9}  fark {4,9}  {5}" -f $_.x.kod, (Kisalt $_.x.ad 40), $_.s.hedefToplam, $_.s.stokToplam, $_.fark, (Tl ($_.fark * $_.x.alis))) }
    Yaz-Log "DENEME '$ad' donem #$donem T $($T.ToString('s')) kapanis $($kap.ToString('s')): $($plan.Count) urun, fazla $topFazla ($tlFazla TL), eksik $topEksik ($tlEksik TL), engel $engel, rapor $dosya"

    if ($engel -gt 0) { Hata "Engel var: ERP'ye YAZILMADI. Sorunu giderip tekrar calistirin."; return }
    Write-Host ""
    $c = Read-Host "  Raporu kontrol ettiniz mi? ERP'ye SAYIM BELGESI olarak yazmak icin EVET yazin (baska her sey: vazgec - hicbir sey yazilmaz)"
    if ($c -cne "EVET") { Write-Host "  Yazilmadi." -ForegroundColor Yellow; return }

    $aciklama = Kisalt ($AciklamaOn + $ad + " " + $(if ($saatli) { $T.ToString("dd.MM.yyyy HH:mm") + " saatli" } else { $T.ToString("dd.MM.yyyy") })) 100
    Belge-Yaz $durum $plan $ad $aciklama $T $kap $son @($secili.Keys) $saatli
}

# Sayim belgesini tek islemde yazar (once dogrulanmis ERP yedegi), durum dosyasina isler, ERP talimatini gosterir.
function Belge-Yaz($durum, $plan, $ad, $aciklama, $T, $kap, $son, $bolumler, [bool]$saatli) {
    try { $yedek = ErpYedekAl "sayim '$ad' yazilmadan once" } catch { Hata "ERP yedegi alinamadi, ERP'ye YAZILMADI: $($_.Exception.Message)"; return }
    $tx = $script:Bag.BeginTransaction()
    try {
        if ([int](Deger $tx "SELECT COUNT(*) FROM dbo.SAYIM WITH (UPDLOCK, HOLDLOCK) WHERE ACIKLAMA = @a" @{ "@a" = $aciklama }) -gt 0) { throw "Ayni aciklamayla belge zaten var: $aciklama" }
        $sabS = Deger $tx "SELECT TOP 1 ID FROM dbo.SAYIM ORDER BY ID DESC" $null
        $sabD = Deger $tx "SELECT TOP 1 ID FROM dbo.SAYIM_DETAY ORDER BY ID DESC" $null
        if (-not $sabS -or -not $sabD) { throw "Sablon sayim belgesi bulunamadi (ERP'de daha once hic sayim yapilmamis olamaz)" }
        $kodPc = Deger $tx "SELECT KOD_PC FROM dbo.SEQUNCES WHERE ID = @s" @{ "@s" = $sabS }
        $sayimId = [long](Deger $tx "SELECT NEXT VALUE FOR dbo.ID" $null)
        Kopyala $tx "SAYIM" $sabS @{ ID = $sayimId; LOKASYON = $script:Lokasyon; TARIH = $T; ACIKLAMA = $aciklama; FIS = [long]0 }
        Sayac $tx $sayimId "SAYIM" $kodPc
        $n = 0; $urunKayit = @()
        foreach ($p in $plan) {
            foreach ($s in $p.s.satirlar) {
                $did = [long](Deger $tx "SELECT NEXT VALUE FOR dbo.ID" $null)
                Kopyala $tx "SAYIM_DETAY" $sabD @{ ID = $did; SAYIM = $sayimId; STOK = $p.sid; BARKOD = $s.barkod; KOLI_BARKODU = ""; STOK_BIRIM = $s.stokBirim; CARPAN = [decimal]1; KAB = [decimal]0;
                    HK_MIKTAR_FIS = ""; MIKTAR = [decimal]$s.miktar; SERINO_ZORUNLU = $false; SERI_NO = ""; ACIKLAMA = ""; KOD = $p.x.kod; PARTINO = ""; PARTINO_ZORUNLU = $false; TARIH = $(if ($p.tarih) { [datetime]$p.tarih } else { $T }) }
                Sayac $tx $did "SAYIM_DETAY" $kodPc
                $n++
            }
            $urunKayit += ,@($p.sid, $p.s.hedefToplam, $(if ($p.tarih) { ([datetime]$p.tarih).ToString("s") } else { "" }))
            if ($n % 500 -eq 0) { Write-Host "    $n satir..." }
        }
        $tx.Commit()
        $g = [pscustomobject]@{ ad = $ad; bolumler = @($bolumler); kapanis = $kap.ToString("s"); T = $T.ToString("s"); sayimId = $sayimId; aciklama = $aciklama; fis = 0; son = $son; saatli = $saatli; yazildi = (Get-Date).ToString("s"); urunler = $urunKayit }
        $durum.geceler = @($durum.geceler) + $g
        Durum-Yaz $durum
        Yaz-Log "YAZILDI '$ad': SAYIM $sayimId, $($plan.Count) urun, $n satir, kesinlestirme ani $($T.ToString('s'))"
        Baslik "ERP'ye yazildi"
        Write-Host "  Sayim belgesi: $aciklama  (SAYIM no $sayimId)" -ForegroundColor Green
        Write-Host "  Yazmadan once alinan ERP yedegi: $yedek"
        Write-Host "  Kesinlestirmeden once ERP'de ayrica yedek almaniza gerek yok; bu yedek o anki hali tutuyor." -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  SIMDI ERP'de:" -ForegroundColor Cyan
        Write-Host "   1) Stok > Sayim > Kesinlestirme ekranini acin, YALNIZ bu belgeyi secin."
        Write-Host "   2) Tarih / saat sorulursa: $($T.ToString('dd.MM.yyyy HH:mm:ss'))"
        if ($saatli) { Write-Host "   3) SATIR TARIHLI 'adet ver' secenegini kullanin (her urun kendi okutma saatine gore). Duz kesinlestirme ya da tek tarihli adet ver DEGIL." -ForegroundColor Yellow }
        else { Write-Host "   3) Sayilani stoga EKLEYEN degil, FARKI hesaplayan ('adet ver') secenegi kullanin (stok sayilana esitlenir)." }
        Write-Host "   4) 'Sayilmayanlari sifirla' ISARETLEMEYIN."
        Write-Host "   5) Kesinlestirdikten sonra bu programda 2) KONTROL calistirin."
    } catch {
        try { $tx.Rollback() } catch {}
        Hata "Yazma basarisiz, ERP'ye HICBIR SEY yazilmadi: $($_.Exception.Message)"
    }
}

# ---------------------------------------------------------------------
#  2) KONTROL: kesinlestirmeden sonra stok sayilana esit mi?
# ---------------------------------------------------------------------
function Kontrol() {
    $durum = Durum-Uzlastir (Durum-Oku)
    if (-not $durum -or -not @($durum.geceler).Count) { Write-Host "  Yazilmis gece yok."; return }
    foreach ($g in @($durum.geceler)) {
        Baslik "$($g.ad)  (SAYIM $($g.sayimId))"
        if ([long]$g.fis -le 0) { Uyari "Henuz kesinlestirilmemis."; continue }
        $f = @((Tablo $null "SELECT FIS_TARIHI, BELGENO, ISNULL(AKTIF, 1) AS AKTIF FROM dbo.FIS WHERE ID = @i" @{ "@i" = [long]$g.fis }).Rows)
        if (-not $f.Count) { Hata "Sayim fisi ($($g.fis)) ERP'de yok - silinmis olabilir."; continue }
        $T = [datetime]$g.T; $ft = [datetime]$f[0].FIS_TARIHI
        Write-Host "  Sayim fisi $($f[0].BELGENO), tarihi $($ft.ToString('dd.MM.yyyy HH:mm:ss'))"
        if ([Math]::Abs(($ft - $T).TotalMinutes) -gt 1) { Uyari "Fis tarihi beklenen anla ($($T.ToString('dd.MM.yyyy HH:mm:ss'))) ayni degil. Fark hesabi o tarihe gore yapildi." }
        $hedef = @{}; $tMap = $null
        foreach ($u in @($g.urunler)) { $hedef[[long]$u[0]] = [double]$u[1]; if ($g.saatli -and @($u).Count -ge 3 -and $u[2]) { if (-not $tMap) { $tMap = @{} }; $tMap[[long]$u[0]] = [datetime]$u[2] } }
        # Saat-dakika modunda: her urunun KENDI okutma anindaki stogu (sayim fisi haric) + fisteki fark = sayilan olmali
        $fisM = @{}
        if ($tMap) {
            $bilgi = ErpBilgi @($hedef.Keys) $T $tMap
            foreach ($r in (Tablo $null "SELECT STOK, SUM(MIKTAR_GIRIS - MIKTAR_CIKIS) AS M FROM dbo.FIS_DETAY WHERE FIS = @f GROUP BY STOK" @{ "@f" = [long]$g.fis }).Rows) { $fisM[[long]$r.STOK] = [double]$r.M }
            foreach ($sid in @($tMap.Keys)) { if ($ft -lt $tMap[$sid]) { Uyari "Fis tarihi bazi urunlerin okutma saatinden once; saat-dakika hesabi bozulur." ; break } }
        } else { $bilgi = ErpBilgi @($hedef.Keys) $T }
        $yanlis = @(); $iki = 0
        foreach ($sid in $hedef.Keys) {
            $x = $bilgi[[long]$sid]; if (-not $x) { continue }
            $st = 0.0; foreach ($b in $x.barkodlar.Values) { $st += [double]$b[4] }
            if ($tMap) { $st += [double]($fisM[[long]$sid]) }
            if ([Math]::Abs($st - $hedef[$sid]) -gt 0.001) { $yanlis += ,@($x.kod, $x.ad, $hedef[$sid], $st) ; if ($hedef[$sid] -ne 0 -and [Math]::Abs($st - $hedef[$sid]) -gt 0.001) { $iki++ } }
        }
        if (-not $yanlis.Count) { Write-Host "  TAMAM: $($hedef.Count) urunun hepsinde ERP stogu (o anda) sayilana esit$(if ($tMap) { ' (her urun kendi okutma saatinde; sonraki satislar stoktan dustu)' })." -ForegroundColor Green; Yaz-Log "KONTROL '$($g.ad)': tamam ($($hedef.Count) urun)"; continue }
        Hata "$($yanlis.Count) / $($hedef.Count) urunde ERP stogu sayilana esit DEGIL:"
        $yanlis | Select-Object -First 15 | ForEach-Object { Write-Host ("     {0,-12} {1,-40} beklenen {2,9}  ERP {3,9}" -f $_[0], (Kisalt $_[1] 40), $_[2], $_[3]) }
        # Hangi kesinlestirme secildi? Duz kesinlestirmede fis miktari = sayilan; "adet ver"de fis miktari = sayilan - stok.
        $mod = @((Tablo $null "SELECT COUNT(*) AS N, SUM(CASE WHEN ABS(ISNULL(f.M, 0) - s.M) < 0.001 THEN 1 ELSE 0 END) AS AYNI FROM (SELECT STOK, BARKOD, SUM(MIKTAR * ISNULL(NULLIF(CARPAN, 0), 1)) AS M FROM dbo.SAYIM_DETAY WHERE SAYIM = @s GROUP BY STOK, BARKOD HAVING SUM(MIKTAR) <> 0) s LEFT JOIN (SELECT STOK, BARKOD, SUM(MIKTAR_FIS * ISNULL(NULLIF(CARPAN, 0), 1)) AS M FROM dbo.FIS_DETAY WHERE FIS = @f GROUP BY STOK, BARKOD) f ON f.STOK = s.STOK AND f.BARKOD = s.BARKOD" @{ "@s" = [long]$g.sayimId; "@f" = [long]$g.fis }).Rows)
        if ($mod.Count -and [int]$mod[0].N -gt 0 -and [int]$mod[0].AYNI -ge [int]$mod[0].N * 0.8) { Hata "Fis satirlari sayilanla birebir ayni: kesinlestirmede DUZ (sayilani ekleyen) secenek secilmis. ERP'de bu sayim fisini silin, 'adet ver' (fark) secenegiyle tekrar kesinlestirin." }
        if ($tMap -and $yanlis.Count -gt $hedef.Count * 0.5) { Hata "Saat-dakika belgesi: kesinlestirmede SATIR TARIHLI 'adet ver' secilmemis olabilir (tek tarihli adet ver ya da duz). Fisi silip satir tarihli secenekle tekrar kesinlestirin." }
        if ($yanlis.Count -gt $hedef.Count * 0.5) { Hata "Urunlerin cogu tutmuyor: buyuk ihtimalle kesinlestirmede 'sayilani EKLE' secildi ya da tarih yanlis verildi. ERP'de bu sayim fisini silip FARK secenegi ve dogru tarihle tekrar kesinlestirin, sonra KONTROL'u tekrar calistirin." }
        else { Uyari "Az sayida urun tutmuyor: bu urunlerde kesinlestirmeden sonra o tarihe geriye donuk belge girilmis olabilir." }
        Yaz-Log "KONTROL '$($g.ad)': $($yanlis.Count) urun tutmuyor"
    }
}

# ---------------------------------------------------------------------
#  3) SIL: kesinlestirilmemis belgeyi geri al
# ---------------------------------------------------------------------
function Sil() {
    $durum = Durum-Uzlastir (Durum-Oku)
    $acik = @($durum.geceler | Where-Object { [long]$_.fis -le 0 })
    if (-not $acik.Count) { Write-Host "  Silinebilecek (kesinlestirilmemis) belge yok. Kesinlesmis bir geceyi geri almak icin: once ERP'de o gecenin sayim fisini silin (stok eski haline doner), sonra burada tekrar 3) secin."; return }
    $sonG = @($durum.geceler)[-1]
    $acik = @($acik | Where-Object { [long]$_.sayimId -eq [long]$sonG.sayimId })
    if (-not $acik.Count) { Write-Host "  Yalniz EN SON gece geri alinabilir (geceler birbirine bagli). Once sonraki geceleri geri alin."; return }
    for ($i = 0; $i -lt $acik.Count; $i++) { Write-Host ("   {0}) {1}  SAYIM {2}  yazildi {3}" -f ($i + 1), $acik[$i].ad, $acik[$i].sayimId, $acik[$i].yazildi) }
    $s = Read-Host "  Hangisi silinsin? (numara)"; if (-not $s) { return }
    $g = $acik[[int]$s - 1]
    if ((Read-Host "  '$($g.ad)' sayim belgesi ERP'den silinecek. Emin misiniz? EVET yazin") -cne "EVET") { return }
    try { [void](ErpYedekAl "sayim '$($g.ad)' silinmeden once") } catch { Hata "ERP yedegi alinamadi, SILINMEDI: $($_.Exception.Message)"; return }
    $tx = $script:Bag.BeginTransaction()
    try {
        if ([int](Deger $tx "SELECT COUNT(*) FROM dbo.SAYIM s WHERE s.ID = @i AND (ISNULL(s.FIS, 0) = 0 OR NOT EXISTS (SELECT 1 FROM dbo.FIS f WHERE f.ID = s.FIS))" @{ "@i" = [long]$g.sayimId }) -ne 1) { throw "Belge kesinlestirilmis (once ERP'de sayim fisini silin) ya da yok" }
        [void](Sql $script:Bag $tx "DELETE FROM dbo.SEQUNCES WHERE ID IN (SELECT ID FROM dbo.SAYIM_DETAY WHERE SAYIM = @i) OR ID = @i" @{ "@i" = [long]$g.sayimId }).ExecuteNonQuery()
        $n = (Sql $script:Bag $tx "DELETE FROM dbo.SAYIM_DETAY WHERE SAYIM = @i" @{ "@i" = [long]$g.sayimId }).ExecuteNonQuery()
        [void](Sql $script:Bag $tx "DELETE FROM dbo.SAYIM WHERE ID = @i" @{ "@i" = [long]$g.sayimId }).ExecuteNonQuery()
        $tx.Commit()
        $durum.geceler = @($durum.geceler | Where-Object { [long]$_.sayimId -ne [long]$g.sayimId })
        Durum-Yaz $durum
        Yaz-Log "SILINDI '$($g.ad)': SAYIM $($g.sayimId) ($n satir)"
        Write-Host "  Silindi. Bu geceyi duzeltip tekrar aktarabilirsiniz." -ForegroundColor Green
    } catch { try { $tx.Rollback() } catch {}; Hata "Silinemedi: $($_.Exception.Message)" }
}

# ---------------------------------------------------------------------
#  5) TEK URUN DUZELTME: kesinlesmis bir gecede bir urun yanlis sayildiysa. Urun SIMDI her yerde (raf + depo)
#     yeniden sayilir; o andaki stok sayilana esitlenir. Butun geceyi geri almaya gerek kalmaz.
# ---------------------------------------------------------------------
function Duzeltme() {
    $durum = Durum-Uzlastir (Durum-Oku)
    if (-not $durum) { throw "Henuz hic gece yazilmamis; duzeltme gerekmez (uygulamada Duzelt ekranini kullanin)." }
    $acik = @($durum.geceler | Where-Object { [long]$_.fis -le 0 })
    if ($acik.Count) { throw "Once kesinlestirilmemis belge(ler) kesinlestirilmeli ya da silinmeli: $(($acik | ForEach-Object { $_.ad }) -join ', ')" }
    Baslik "Tek urun duzeltme"
    Write-Host "  Urunu SIMDI magazanin ve deponun her yerinde sayin (toplam). O andaki ERP stogu bu sayiya esitlenir."
    Write-Host "  DIKKAT: urun henuz sayilmamis bir bolumde de duruyorsa o bolum sayilinca USTUNE eklenir; duzeltmeyi o bolum sayildiktan sonra yapin." -ForegroundColor Yellow
    $q = (Read-Host "  Stok kodu ya da barkod").Trim(); if (-not $q) { return }
    $esle = Eslestir @(,@("", $q, $q, "", 0, "", "", 0, ""))
    $sid = if ($esle.ContainsKey("K:" + $q)) { $esle["K:" + $q] } elseif ($esle.ContainsKey("B:" + $q)) { $esle["B:" + $q] } else { $null }
    if (-not $sid) { throw "ERP'de bu stok kodu / barkod yok: $q" }
    $T = Sor-Tarih "  Urunu saydiginiz an (bu saatten sonra satilan / gelen olmasin)" (Get-Date)
    $sonT = (@($durum.geceler) | ForEach-Object { [datetime]$_.T } | Sort-Object | Select-Object -Last 1)
    if ($sonT -and $T -le $sonT) { throw "Duzeltme ani son yazilan sayimdan ($($sonT.ToString('dd.MM.yyyy HH:mm'))) sonra olmali" }
    $mt = (Read-Host "  Sayilan TOPLAM adet (raf + depo, hepsi)").Trim().Replace(",", ".")
    $m = 0.0; if (-not [double]::TryParse($mt, [Globalization.NumberStyles]::Float, $Inv, [ref]$m) -or $m -lt 0) { throw "Gecersiz adet: $mt" }
    $bilgi = ErpBilgi @($sid) $T; $x = $bilgi[[long]$sid]
    $u = @{ depo = 0.0; raf = $m; mod = "esitle"; ad = $x.ad; barkodlar = @($q) }
    $st = Satirlar $u @($x.barkodlar.Values) @($q)
    if (-not $st) { throw "Urunun ERP kartinda adet barkodu yok" }
    $fark = $st.hedefToplam - $st.stokToplam
    Write-Host ""
    Write-Host ("  {0}  {1}" -f $x.kod, $x.ad) -ForegroundColor Cyan
    Write-Host ("  ERP stogu ({0}): {1}   sayilan: {2}   fark: {3}  ({4})" -f $T.ToString('dd.MM HH:mm'), $st.stokToplam, $m, $fark, (Tl ($fark * $x.alis)))
    $gecmis = @($durum.geceler | Where-Object { @($_.urunler | Where-Object { [long]$_[0] -eq [long]$sid }).Count })
    if ($gecmis.Count) { Write-Host "  Daha once sayildigi geceler: $(($gecmis | ForEach-Object { $_.ad }) -join ', ')" }
    $hareket = @((Tablo $null "SELECT TOP 5 d.FIS_TARIHI, FT.AD AS TUR, d.MIKTAR_GIRIS - d.MIKTAR_CIKIS AS M FROM dbo.FIS_DETAY d WITH (NOLOCK) JOIN dbo.FIS f WITH (NOLOCK) ON f.ID = d.FIS JOIN dbo.FIS_TURU FT ON FT.ID = f.FIS_TURU WHERE d.STOK = @s AND d.LOKASYON = @l AND d.FATRALANDIRILMIS_IRSALIYEMI = 0 AND d.FIS_TARIHI > @t ORDER BY d.FIS_TARIHI" @{ "@s" = [long]$sid; "@l" = $script:Lokasyon; "@t" = $T }).Rows)
    if ($hareket.Count) { Uyari "Bu andan SONRA tarihli hareket var (or. $(([datetime]$hareket[0].FIS_TARIHI).ToString('dd.MM HH:mm')) $($hareket[0].TUR) $($hareket[0].M)). Sorun degil, fark yalniz bu ana kadarki stoga gore hesaplanir." }
    if ((Read-Host "  ERP'ye duzeltme sayim belgesi yazilsin mi? EVET yazin") -cne "EVET") { Write-Host "  Yazilmadi." -ForegroundColor Yellow; return }
    $plan = @(@{ sid = [long]$sid; x = $x; u = $u; s = $st; fark = $fark })
    $ad = "Duzeltme " + $x.kod + " " + $T.ToString("dd.MM HH:mm")
    Belge-Yaz $durum $plan $ad (Kisalt ($AciklamaOn + $ad) 100) $T $T $false @()
}

# ---------------------------------------------------------------------
#  6) BIRLESIK ONIZLEME: butun bolumler (depo + raflar) urun urun toplanir, su anki ERP stoguyla yan yana.
#     ERP'ye HICBIR SEY YAZMAZ. Kontrol / gondermek icin tek Excel dosyasi. (Kesin fark her gecenin kendi
#     anina gore aktarimda hesaplanir; buradaki "su anki stok" kaba bir bakistir.)
# ---------------------------------------------------------------------
function Onizleme() {
    $durum = Durum-Uzlastir (Durum-Oku)
    $donem = Donem-Sec $durum
    $satirlar = Okutmalar $donem
    $sonDonem = [long]((Rpc "sayim_donemleri_ver" @{}).donemler[0][0])
    if ($donem -eq $sonDonem) { $as = Asil-Karsilastir $satirlar; if ($as) { Uyari "Asil kayitlarla karsilastirma: $as" } }
    $atanmis = @{}; foreach ($g in @($durum.geceler)) { foreach ($x in @($g.bolumler)) { if ($x) { $atanmis[[string]$x] = [string]$g.ad } } }
    $esle = Eslestir $satirlar
    $bolAd = @(Bolumler $satirlar | ForEach-Object { $_.ad })
    $u = @{}; $esz = 0
    foreach ($s in $satirlar) {
        $kod = ([string]$s[1]).Trim(); $bk = ([string]$s[2]).Trim()
        $sid = if ($kod -and $esle.ContainsKey("K:" + $kod)) { $esle["K:" + $kod] } elseif ($bk -and $esle.ContainsKey("B:" + $bk)) { $esle["B:" + $bk] } else { $null }
        $key = if ($sid) { "S" + $sid } else { $esz++; "X:" + $kod + "|" + $bk }
        if (-not $u.ContainsKey($key)) { $u[$key] = @{ sid = $sid; kod = $kod; bk = $bk; ad = [string]$s[3]; top = 0.0; b = @{} } }
        $ba = if (DepoMu $s[6]) { "DEPO (" + (BolumAdi $s[6]) + ")" } else { BolumAdi $s[6] }
        $u[$key].top += [double]$s[4]; $u[$key].b[$ba] = [double]($u[$key].b[$ba]) + [double]$s[4]
    }
    $ids = @($u.Values | Where-Object { $_.sid } | ForEach-Object { [long]$_.sid })
    $bilgi = if ($ids.Count) { ErpBilgi $ids (Get-Date) } else { @{} }
    if (-not (Test-Path $RaporKlasoru)) { New-Item -ItemType Directory -Path $RaporKlasoru | Out-Null }
    $dosya = Join-Path $RaporKlasoru ("birlesik-onizleme-{0}.csv" -f (Get-Date -Format "yyyyMMdd-HHmm"))
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("Stok Kodu;Urun;Sayilan TOPLAM;ERP stok (simdi);Fark (kaba);Fark TL (son alis);Durum;" + (($bolAd | ForEach-Object { ($_ -replace ';', ',') + $(if ($atanmis.ContainsKey(($_ -replace '^DEPO \((.*)\)$', '$1'))) { ' [yazildi]' } else { '' }) }) -join ';'))
    $tf = 0.0; $te = 0.0
    foreach ($x in ($u.Values | Sort-Object { $_.ad })) {
        $erp = ''; $fark = ''; $tl = ''; $dr = "ERP'de YOK (eslesmedi)"
        if ($x.sid -and $bilgi[[long]$x.sid]) {
            $e = $bilgi[[long]$x.sid]; $st = 0.0; foreach ($bb in $e.barkodlar.Values) { $st += [double]$bb[4] }
            $f = $x.top - $st; $erp = $st.ToString($Inv); $fark = $f.ToString($Inv); $tlv = [Math]::Round($f * $e.alis, 2); $tl = $tlv.ToString($Inv)
            if ($tlv -gt 0) { $tf += $tlv } else { $te += $tlv }
            $dr = if ($f -eq 0) { 'Tutuyor' } elseif ([Math]::Abs($tlv) -ge 1000) { 'BUYUK FARK - tekrar saydirin' } else { 'Fark var' }
            $x.kod = $e.kod; $x.ad = $e.ad
        }
        $kol = ($bolAd | ForEach-Object { if ($x.b.ContainsKey($_)) { ([double]$x.b[$_]).ToString($Inv) } else { '' } }) -join ';'
        [void]$sb.AppendLine(("{0};{1};{2};{3};{4};{5};{6};{7}" -f $x.kod, ($x.ad -replace ';', ','), $x.top.ToString($Inv), $erp, $fark, $tl, $dr, $kol))
    }
    [System.IO.File]::WriteAllText($dosya, "$([char]0xFEFF)" + $sb.ToString(), [System.Text.Encoding]::UTF8)
    Baslik "Birlesik onizleme (ERP'ye yazilmadi)"
    Write-Host "  $($u.Count) urun, $($bolAd.Count) bolum. ERP'de eslesmeyen: $(@($u.Values | Where-Object { -not $_.sid }).Count)"
    Write-Host "  Kaba fark (su anki stoga gore): fazla $(Tl $tf), eksik $(Tl $te)"
    Write-Host "  Dosya (her bolum ayri sutun): $dosya" -ForegroundColor Green
    Write-Host "  Bu dosyayi kontrol icin gonderebilirsiniz." -ForegroundColor DarkGray
    Yaz-Log "ONIZLEME donem #$donem : $($u.Count) urun, $dosya"
}

# ---------------------------------------------------------------------
#  4) SAYILMAYANLAR: ERP'de stogu olup hic okutulmayan urunler
# ---------------------------------------------------------------------
function Sayilmayanlar() {
    $durum = Durum-Oku
    $donem = Donem-Sec $durum
    $satirlar = Okutmalar $donem
    $esle = Eslestir $satirlar
    $sayilan = @{}; foreach ($v in $esle.Values) { $sayilan[[long]$v] = $true }
    $T = Sor-Tarih "  Hangi andaki stoga gore?" (Get-Date)
    $r = @((Tablo $null "SELECT s.ID, s.KOD, s.AD, ISNULL(s.SON_ALIS_FIYAT, 0) AS ALIS, SUM(d.MIKTAR_GIRIS - d.MIKTAR_CIKIS) AS M FROM dbo.FIS_DETAY d WITH (NOLOCK) JOIN dbo.STOK s WITH (NOLOCK) ON s.ID = d.STOK WHERE d.FATRALANDIRILMIS_IRSALIYEMI = 0 AND d.FIS_TARIHI <= @t AND d.LOKASYON = @l GROUP BY s.ID, s.KOD, s.AD, s.SON_ALIS_FIYAT HAVING ABS(SUM(d.MIKTAR_GIRIS - d.MIKTAR_CIKIS)) > 0.0001" @{ "@t" = $T; "@l" = $script:Lokasyon }).Rows)
    $l = @($r | Where-Object { -not $sayilan.ContainsKey([long]$_.ID) })
    if (-not (Test-Path $RaporKlasoru)) { New-Item -ItemType Directory -Path $RaporKlasoru | Out-Null }
    $dosya = Join-Path $RaporKlasoru ("sayilmayanlar-{0}.csv" -f (Get-Date -Format "yyyyMMdd-HHmm"))
    $sb = New-Object System.Text.StringBuilder; [void]$sb.AppendLine("Stok Kodu;Urun;ERP Stok;Deger (son alis)")
    $art = 0.0; $eks = 0.0
    foreach ($x in ($l | Sort-Object { -[Math]::Abs([double]$_.M * [double]$_.ALIS) })) { $tl = [double]$x.M * [double]$x.ALIS; if ($x.M -gt 0) { $art += $tl } else { $eks += $tl }; [void]$sb.AppendLine(("{0};{1};{2};{3}" -f $x.KOD, ([string]$x.AD -replace ';', ','), ([double]$x.M).ToString($Inv), ([Math]::Round($tl, 2)).ToString($Inv))) }
    [System.IO.File]::WriteAllText($dosya, "$([char]0xFEFF)" + $sb.ToString(), [System.Text.Encoding]::UTF8)
    Write-Host "  Hic okutulmayan ama ERP'de stogu olan: $($l.Count) urun (arti stok $(Tl $art), eksi stok $(Tl $eks))"
    Write-Host "  Liste: $dosya" -ForegroundColor Green
    Write-Host "  Bu urunler bu programla SIFIRLANMAZ. Kontrol edin; gercekten yoksa ERP'de elle duzeltin ya da bana yazin."
    Yaz-Log "SAYILMAYANLAR: $($l.Count) urun, $dosya"
}

# ---------------------------------------------------------------------
#  MENU
# ---------------------------------------------------------------------
try {
    Baslik "KRT Saha - Sayimi ERP12'ye aktarma"
    Hazirla
    while ($true) {
        Write-Host ""
        Write-Host "  1) Bir geceyi aktar  (bolumleri secersiniz; once DENEME raporu; EVET derseniz ERP'ye sayim belgesi yazar)"
        Write-Host "  2) KONTROL           (ERP'de kesinlestirdikten sonra stok sayilana esit mi)"
        Write-Host "  3) Belgeyi geri al   (kesinlestirilmemis belgeyi ERP'den siler)"
        Write-Host "  4) Sayilmayanlar     (ERP'de stogu olup hic okutulmayan urunler listesi)"
        Write-Host "  6) Birlesik onizleme (butun bolumler urun urun tek Excel'de; ERP'ye YAZMAZ)"
        Write-Host "  5) Tek urun duzelt   (kesinlesmis bir gecede yanlis sayilan urunu simdi yeniden sayip duzeltir)"
        Write-Host "  0) Cikis"
        $s = Read-Host "  Secim"
        try {
            switch ($s) { "1" { Gece-Aktar } "2" { Kontrol } "3" { Sil } "4" { Sayilmayanlar } "5" { Duzeltme } "6" { Onizleme } }
        } catch { Hata $_.Exception.Message }
        if ($s -eq "0") { break }
    }
} catch { Hata $_.Exception.Message }
finally { try { if ($script:Bag) { $script:Bag.Close() } } catch {} }
Read-Host "Kapatmak icin Enter"
