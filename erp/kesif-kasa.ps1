# =====================================================================
#  MK Saha - ERP12 KESIF: "Uygulamanin actigi MKS- stok kartlari kasada okunmuyor"
#  Kasada OKUNAN normal bir kart ile OKUNMAYAN bir MKS- karti alan alan karsilastirir,
#  normal kartta olup MKS kartinda olmayan baska tablo kayitlarini ve kasa / POS ile ilgili
#  tablolari listeler.
#  ERP12'ye HICBIR SEY YAZMAZ, sadece okur. Sonuc: C:\Scripts\kesif-kasa.txt
# =====================================================================
$SqlServer = "SERVER\ERP12"
$Cikti     = "C:\Scripts\kesif-kasa.txt"
Import-Module SqlServer -ErrorAction SilentlyContinue
$sb = New-Object System.Text.StringBuilder
function Yaz($m) { [void]$sb.AppendLine([string]$m); Write-Host $m }
function Kaydet { try { [System.IO.File]::WriteAllText($Cikti, $sb.ToString(), [System.Text.Encoding]::UTF8) } catch {} }
function Sor($db, $q, $sn = 120) { try { return @(Invoke-Sqlcmd -ServerInstance $SqlServer -Database $db -Query $q -QueryTimeout $sn -MaxCharLength 20000 -ErrorAction Stop) } catch { Yaz "  HATA: $($_.Exception.Message)"; return @() } }
function Dok($satirlar) { foreach ($r in $satirlar) { $p = @(); foreach ($c in $r.Table.Columns) { $v = $r[$c.ColumnName]; if ($v -isnot [DBNull] -and [string]$v -ne '') { $p += "$($c.ColumnName)=$v" } }; Yaz ("  " + ($p -join " | ")); Yaz "" } }
function Tirnak($s) { return "'" + ([string]$s).Replace("'", "''") + "'" }

$dbler = @(Sor "master" "SELECT name FROM sys.databases WHERE name LIKE 'ERP12[0-9][0-9][0-9][0-9]' AND state = 0 ORDER BY name DESC")
$db = $null
foreach ($d in $dbler) { $n = @(Sor ([string]$d.name) "SELECT COUNT(*) AS n FROM dbo.FIS WITH (NOLOCK) WHERE FIS_TARIHI >= DATEADD(day, -7, GETDATE())"); if ($n.Count -and [int]$n[0].n -gt 0) { $db = [string]$d.name; break } }
if (-not $db) { $db = [string]$dbler[0].name }
Yaz "KESIF-KASA $(Get-Date -Format 'yyyy-MM-dd HH:mm')  veri tabani: $db"
Write-Host ""
$iyiBarkod = (Read-Host "Kasada OKUNAN bir urunun barkodu (bos birakip Enter: otomatik secilir)").Trim()
$kotuBarkod = (Read-Host "Kasada OKUNMAYAN bir MKS urununun barkodu (bos birakip Enter: en son acilan MKS karti)").Trim()

# --- Kartlari bul
function KartBarkodla($b) { $r = @(Sor $db "SELECT TOP 1 STOK FROM dbo.STOK_BARKOD_BIRIM WITH (NOLOCK) WHERE BARKOD = $(Tirnak $b)"); if ($r.Count) { return [long]$r[0].STOK } else { return $null } }
$kotu = $null; $iyi = $null
if ($kotuBarkod) { $kotu = KartBarkodla $kotuBarkod; if (-not $kotu) { Yaz "UYARI: $kotuBarkod barkodu ERP'de bulunamadi, en son MKS karti alinacak." } }
if (-not $kotu) { $r = @(Sor $db "SELECT TOP 1 ID FROM dbo.STOK WITH (NOLOCK) WHERE KOD LIKE 'MKS-%' ORDER BY ID DESC"); if ($r.Count) { $kotu = [long]$r[0].ID } }
if ($iyiBarkod) { $iyi = KartBarkodla $iyiBarkod; if (-not $iyi) { Yaz "UYARI: $iyiBarkod barkodu ERP'de bulunamadi, otomatik secilecek." } }
if (-not $iyi) {
    # Son 10 gunde kasada (yazar kasa fisi) satilmis, MKS olmayan, en son acilmis kart
    $r = @(Sor $db "SELECT TOP 1 s.ID FROM dbo.STOK s WITH (NOLOCK) WHERE s.KOD NOT LIKE 'MKS-%' AND EXISTS (SELECT 1 FROM dbo.FIS_DETAY d WITH (NOLOCK) JOIN dbo.FIS f WITH (NOLOCK) ON f.ID = d.FIS WHERE d.STOK = s.ID AND f.YAZAR_KASA_NO > 0 AND f.FIS_TARIHI >= DATEADD(day, -10, GETDATE())) ORDER BY s.ID DESC" 300)
    if ($r.Count) { $iyi = [long]$r[0].ID } else { $r = @(Sor $db "SELECT TOP 1 ID FROM dbo.STOK WITH (NOLOCK) WHERE KOD NOT LIKE 'MKS-%' ORDER BY ID DESC"); if ($r.Count) { $iyi = [long]$r[0].ID } }
}
if (-not $kotu -or -not $iyi) { Yaz "Kart bulunamadi (iyi=$iyi, mks=$kotu)."; Kaydet; Read-Host "Kapatmak icin Enter"; exit 1 }
Yaz "KASADA OKUNAN kart ID $iyi  |  OKUNMAYAN (MKS) kart ID $kotu"
Dok (Sor $db "SELECT ID, KOD, AD FROM dbo.STOK WITH (NOLOCK) WHERE ID IN ($iyi, $kotu)")

# --- Bagli kayit kimlikleri
function Kimlikler($sid) {
    $k = @{ STOK = @($sid); BIRIM = @(); FIYAT = @(); BARKOD = @() }
    $k.BIRIM = @(Sor $db "SELECT ID FROM dbo.STOK_STOK_BIRIM WITH (NOLOCK) WHERE STOK = $sid" | ForEach-Object { [long]$_.ID })
    if ($k.BIRIM.Count) {
        $in = $k.BIRIM -join ","
        $k.FIYAT = @(Sor $db "SELECT ID FROM dbo.STOK_STOK_BIRIM_FIYAT WITH (NOLOCK) WHERE STOK_STOK_BIRIM IN ($in)" | ForEach-Object { [long]$_.ID })
        $k.BARKOD = @(Sor $db "SELECT ID FROM dbo.STOK_BARKOD WITH (NOLOCK) WHERE STOK_STOK_BIRIM IN ($in)" | ForEach-Object { [long]$_.ID })
    }
    return $k
}
$KI = Kimlikler $iyi; $KK = Kimlikler $kotu
Yaz ("Okunan:  birim {0}, fiyat {1}, barkod {2} satiri" -f $KI.BIRIM.Count, $KI.FIYAT.Count, $KI.BARKOD.Count)
Yaz ("MKS:     birim {0}, fiyat {1}, barkod {2} satiri" -f $KK.BIRIM.Count, $KK.FIYAT.Count, $KK.BARKOD.Count)

# --- 1) Alan alan fark
function Fark($tablo, $idI, $idK) {
    if (-not $idI -or -not $idK) { Yaz "  (${tablo}: karsilastirilacak satir yok)"; return }
    $a = @(Sor $db "SELECT * FROM dbo.[$tablo] WITH (NOLOCK) WHERE ID = $idI"); $b = @(Sor $db "SELECT * FROM dbo.[$tablo] WITH (NOLOCK) WHERE ID = $idK")
    if (-not $a.Count -or -not $b.Count) { Yaz "  (${tablo}: satir okunamadi)"; return }
    foreach ($c in $a[0].Table.Columns) {
        $n = $c.ColumnName; $va = $a[0][$n]; $vb = $b[0][$n]
        $sa = if ($va -is [DBNull]) { "NULL" } elseif ($va -is [byte[]]) { "0x" + (($va | ForEach-Object { $_.ToString("X2") }) -join "") } else { [string]$va }
        $sb2 = if ($vb -is [DBNull]) { "NULL" } elseif ($vb -is [byte[]]) { "0x" + (($vb | ForEach-Object { $_.ToString("X2") }) -join "") } else { [string]$vb }
        if ($sa -ne $sb2) { Yaz ("  {0}.{1}:  okunan=[{2}]  MKS=[{3}]" -f $tablo, $n, $sa, $sb2) }
    }
}
Yaz ""; Yaz "== 1) ALAN FARKLARI (okunan kart / MKS karti) =="
Fark "STOK" $iyi $kotu
Fark "STOK_STOK_BIRIM" $KI.BIRIM[0] $KK.BIRIM[0]
Fark "STOK_BARKOD" $KI.BARKOD[0] $KK.BARKOD[0]
for ($i = 0; $i -lt [Math]::Max($KI.FIYAT.Count, $KK.FIYAT.Count); $i++) { Yaz "  -- fiyat satiri $($i + 1)"; Fark "STOK_STOK_BIRIM_FIYAT" $KI.FIYAT[$i] $KK.FIYAT[$i] }
Yaz "  -- SEQUNCES (kart)"; Dok (Sor $db "SELECT * FROM dbo.SEQUNCES WITH (NOLOCK) WHERE ID IN ($iyi, $kotu)")
Kaydet

# --- 2) Okunan kartin baska tablolarda kaydi var, MKS kartinin yok mu?
Yaz ""; Yaz "== 2) OKUNAN kartin baska tablolardaki kayitlari (MKS kartinda olmayanlar *** ile) =="
$tumI = @($KI.STOK + $KI.BIRIM + $KI.FIYAT + $KI.BARKOD) -join ","
$tumK = @($KK.STOK + $KK.BIRIM + $KK.FIYAT + $KK.BARKOD) -join ","
$haric = "'STOK','STOK_STOK_BIRIM','STOK_STOK_BIRIM_FIYAT','STOK_BARKOD','FIS_DETAY','FIS','SIPARIS','SIPARIS_DETAY','CARI_HAREKET'"
$kolonlar = @(Sor $db "SELECT t.name AS T, c.name AS C, ISNULL((SELECT SUM(p.rows) FROM sys.partitions p WHERE p.object_id = t.object_id AND p.index_id IN (0,1)), 0) AS N FROM sys.columns c JOIN sys.tables t ON t.object_id = c.object_id JOIN sys.types y ON y.user_type_id = c.user_type_id WHERE y.name = 'bigint' AND c.name <> 'ID' AND t.name NOT IN ($haric) ORDER BY t.name, c.name")
Yaz "  (taranacak sutun: $($kolonlar.Count))"
$say = 0
foreach ($k in $kolonlar) {
    $say++; if ($say % 50 -eq 0) { Write-Host "  ... $say / $($kolonlar.Count)" }
    if ([long]$k.N -gt 1000000 -or [long]$k.N -eq 0) { continue }
    $r = @(Sor $db "SELECT SUM(CASE WHEN [$($k.C)] IN ($tumI) THEN 1 ELSE 0 END) AS I, SUM(CASE WHEN [$($k.C)] IN ($tumK) THEN 1 ELSE 0 END) AS K FROM dbo.[$($k.T)] WITH (NOLOCK) WHERE [$($k.C)] IN ($tumI) OR [$($k.C)] IN ($tumK)" 60)
    if (-not $r.Count) { continue }
    $ni = if ($r[0].I -is [DBNull]) { 0 } else { [long]$r[0].I }; $nk = if ($r[0].K -is [DBNull]) { 0 } else { [long]$r[0].K }
    if ($ni -gt 0 -or $nk -gt 0) {
        $isaret = if ($ni -gt 0 -and $nk -eq 0) { "***" } else { "   " }
        Yaz ("  {0} {1}.{2}: okunan {3} satir, MKS {4} satir" -f $isaret, $k.T, $k.C, $ni, $nk)
        if ($ni -gt 0 -and $nk -eq 0) { Dok (Sor $db "SELECT TOP 2 * FROM dbo.[$($k.T)] WITH (NOLOCK) WHERE [$($k.C)] IN ($tumI)") }
    }
}
Kaydet

# --- 3) Kasa / POS / aktarim tablolari
Yaz ""; Yaz "== 3) Adi kasa / POS / terazi / aktarim / degisiklik gecen tablolar =="
$tl = @(Sor $db "SELECT t.name AS T, ISNULL((SELECT SUM(p.rows) FROM sys.partitions p WHERE p.object_id = t.object_id AND p.index_id IN (0,1)), 0) AS N FROM sys.tables t WHERE t.name LIKE '%KASA%' OR t.name LIKE '%POS%' OR t.name LIKE '%TERAZI%' OR t.name LIKE '%AKTAR%' OR t.name LIKE '%GONDER%' OR t.name LIKE '%DEGIS%' OR t.name LIKE '%SENK%' OR t.name LIKE '%SYNC%' OR t.name LIKE '%LOG%' OR t.name LIKE '%TRANSFER%' OR t.name LIKE '%MARKET%' ORDER BY t.name")
foreach ($t in $tl) {
    Yaz "-- $($t.T) ($($t.N) satir)"
    $cols = @(Sor $db "SELECT c.name FROM sys.columns c WHERE c.object_id = OBJECT_ID('dbo.[$($t.T)]') ORDER BY c.column_id" | ForEach-Object { [string]$_.name })
    Yaz ("   sutunlar: " + ($cols -join ", "))
    if ([long]$t.N -gt 0) { $sira = if ($cols -contains "ID") { "ORDER BY ID DESC" } else { "" }; Dok (Sor $db "SELECT TOP 3 * FROM dbo.[$($t.T)] WITH (NOLOCK) $sira") }
}
Kaydet

# --- 4) Tetikleyiciler ve firma sabitleri
Yaz ""; Yaz "== 4) Stok tablolarindaki tetikleyiciler (trigger) =="
Dok (Sor $db "SELECT tr.name AS TRIGGER_ADI, OBJECT_NAME(tr.parent_id) AS TABLO, tr.is_disabled AS KAPALI, LEFT(OBJECT_DEFINITION(tr.object_id), 1500) AS TANIM FROM sys.triggers tr WHERE OBJECT_NAME(tr.parent_id) LIKE 'STOK%'")
Yaz ""; Yaz "== 5) FIRMASABITLERI icinde kasa / POS gecen ayarlar =="
$fsCols = @(Sor $db "SELECT c.name FROM sys.columns c WHERE c.object_id = OBJECT_ID('dbo.FIRMASABITLERI')" | ForEach-Object { [string]$_.name })
if ($fsCols.Count) { $q = @($fsCols | Where-Object { $_ -match 'KASA|POS|TERAZI|MARKET' }); if ($q.Count) { Dok (Sor $db ("SELECT TOP 1 " + (($q | ForEach-Object { "[$_]" }) -join ", ") + " FROM dbo.FIRMASABITLERI")) } else { Yaz "  (ilgili sutun yok)" } }

# --- 6) Tum MKS kartlari: barkod ve fiyat
Yaz ""; Yaz "== 6) Uygulamanin actigi MKS- kartlari (barkod, fiyat satirlari) =="
Dok (Sor $db "SELECT s.KOD, LEFT(s.AD, 40) AS AD, (SELECT TOP 1 b.BARKOD FROM dbo.STOK_BARKOD b WITH (NOLOCK) JOIN dbo.STOK_STOK_BIRIM u WITH (NOLOCK) ON u.ID = b.STOK_STOK_BIRIM WHERE u.STOK = s.ID) AS BARKOD, (SELECT COUNT(*) FROM dbo.STOK_STOK_BIRIM_FIYAT f WITH (NOLOCK) JOIN dbo.STOK_STOK_BIRIM u WITH (NOLOCK) ON u.ID = f.STOK_STOK_BIRIM WHERE u.STOK = s.ID) AS FIYAT_SATIRI, (SELECT MAX(f.FIYAT) FROM dbo.STOK_STOK_BIRIM_FIYAT f WITH (NOLOCK) JOIN dbo.STOK_STOK_BIRIM u WITH (NOLOCK) ON u.ID = f.STOK_STOK_BIRIM WHERE u.STOK = s.ID) AS EN_YUKSEK_FIYAT FROM dbo.STOK s WITH (NOLOCK) WHERE s.KOD LIKE 'MKS-%' ORDER BY s.KOD")

Kaydet
Write-Host ""; Write-Host "Bitti. Sonuc: $Cikti  -> bu dosyayi gonder."
Read-Host "Kapatmak icin Enter"
