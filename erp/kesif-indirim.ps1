# =====================================================================
#  KRT Saha - ERP12 KESIF: "Indirim gruplari" (suresi bitince fiyati kendiliginden geri donen urunler)
#  ERP12'de indirimdeki urunleri bir grupta toplayip bitis tarihinde eski fiyata donduruyorsunuz.
#  Bu grubun hangi tabloda durdugunu bulur:
#   1) Adinda KAMPANYA / INDIRIM / PROMOSYON / FIYAT / GRUP / PLAN gecen tablolar (satir sayisi, kolonlar)
#   2) Bu tablolardan tarih kolonu olanlarin son 5 satiri
#   3) Sorulan barkodun (indirim grubundaki bir urun) ADI GECEN BUTUN tablolar
#  ERP12'ye HICBIR SEY YAZMAZ, sadece okur. Sonuc ekranda ve C:\Scripts\kesif-indirim.txt
# =====================================================================
$SqlServer = "SERVER\ERP12"
$Cikti     = "C:\Scripts\kesif-indirim.txt"
Import-Module SqlServer -ErrorAction SilentlyContinue
$sb = New-Object System.Text.StringBuilder
function Yaz($m) { [void]$sb.AppendLine([string]$m); Write-Host $m }
function Kaydet { try { [System.IO.File]::WriteAllText($Cikti, $sb.ToString(), [System.Text.Encoding]::UTF8) } catch {} }
function Sor($db, $q, $sn = 120) { try { return @(Invoke-Sqlcmd -ServerInstance $SqlServer -Database $db -Query $q -QueryTimeout $sn -MaxCharLength 4000 -ErrorAction Stop) } catch { Yaz "  HATA: $($_.Exception.Message)"; return @() } }
function Deger($v) { if ($v -is [DBNull]) { return "NULL" } elseif ($v -is [byte[]]) { return "0x.." } elseif ($v -is [datetime]) { return $v.ToString("yyyy-MM-dd HH:mm") } else { $s = [string]$v; if ($s.Length -gt 60) { $s = $s.Substring(0, 60) + ".." }; return $s } }
function Dok($satirlar, $on) { foreach ($r in $satirlar) { $p = @(); foreach ($c in $r.Table.Columns) { $p += "$($c.ColumnName)=$(Deger $r[$c.ColumnName])" }; Yaz ("  $on" + ($p -join " | ")) } }
function Tirnak($s) { return "'" + ([string]$s).Replace("'", "''") + "'" }

$dbler = @(Sor "master" "SELECT name FROM sys.databases WHERE name LIKE 'ERP12[0-9][0-9][0-9][0-9]' AND state = 0 ORDER BY name DESC")
$db = $null
foreach ($d in $dbler) { $n = @(Sor ([string]$d.name) "SELECT COUNT(*) AS n FROM dbo.FIS WITH (NOLOCK) WHERE FIS_TARIHI >= DATEADD(day, -7, GETDATE())"); if ($n.Count -and [int]$n[0].n -gt 0) { $db = [string]$d.name; break } }
if (-not $db) { $db = [string]$dbler[0].name }
Yaz "KESIF-INDIRIM $(Get-Date -Format 'yyyy-MM-dd HH:mm')  veri tabani: $db"
$barkod = (Read-Host "ERP'de indirim grubuna eklediginiz BIR urunun barkodu (bos: atla)").Trim()
$grupAd = (Read-Host "O grubun ERP'deki adi ya da adindan bir parca (bos: atla)").Trim()

Yaz ""; Yaz "== 1) Adaylar: tablolar =="
$aday = @(Sor $db @"
SELECT t.name AS TABLO, SUM(p.rows) AS SATIR,
  STUFF((SELECT ', ' + c.name FROM sys.columns c WHERE c.object_id = t.object_id ORDER BY c.column_id FOR XML PATH('')), 1, 2, '') AS KOLONLAR
FROM sys.tables t JOIN sys.partitions p ON p.object_id = t.object_id AND p.index_id IN (0, 1)
WHERE t.name LIKE '%KAMPANYA%' OR t.name LIKE '%INDIRIM%' OR t.name LIKE '%PROMOSYON%' OR t.name LIKE '%FIYAT%'
   OR t.name LIKE '%GRUP%' OR t.name LIKE '%PLAN%' OR t.name LIKE '%ISKONTO%' OR t.name LIKE '%DEGISIM%' OR t.name LIKE '%ETIKET%'
GROUP BY t.name, t.object_id ORDER BY t.name
"@)
foreach ($a in $aday) { Yaz ("  {0}  ({1} satir): {2}" -f $a.TABLO, $a.SATIR, $a.KOLONLAR) }
Kaydet

Yaz ""; Yaz "== 2) Tarih kolonu olan dolu adaylarin son 5 satiri =="
foreach ($a in $aday) {
    if ([long]$a.SATIR -le 0) { continue }
    $tk = @(Sor $db "SELECT c.name FROM sys.columns c JOIN sys.types ty ON ty.user_type_id = c.user_type_id WHERE c.object_id = OBJECT_ID('dbo.$($a.TABLO)') AND ty.name IN ('date','datetime','datetime2','smalldatetime')")
    if (-not $tk.Count) { continue }
    $sirala = if (@(Sor $db "SELECT 1 AS x FROM sys.columns WHERE object_id = OBJECT_ID('dbo.$($a.TABLO)') AND name = 'ID'").Count) { "ID DESC" } else { "[" + $tk[0].name + "] DESC" }
    Yaz "  -- $($a.TABLO) (tarih: $(($tk | ForEach-Object { $_.name }) -join ', '))"
    Dok (Sor $db "SELECT TOP 5 * FROM dbo.[$($a.TABLO)] WITH (NOLOCK) ORDER BY $sirala") "    "
}
Kaydet

if ($grupAd) {
    Yaz ""; Yaz "== 2b) Grup adi '$grupAd' gecen tablolar (AD / ADI / ACIKLAMA kolonlari) =="
    $kol = @(Sor $db "SELECT t.name AS T, c.name AS C FROM sys.columns c JOIN sys.tables t ON t.object_id = c.object_id JOIN sys.types ty ON ty.user_type_id = c.user_type_id WHERE ty.name IN ('nvarchar','varchar','nchar','char') AND (c.name LIKE '%AD%' OR c.name LIKE '%ACIKLAMA%' OR c.name LIKE '%KOD%' OR c.name LIKE '%ISIM%')")
    foreach ($k in $kol) {
        $r = @(Sor $db "SELECT TOP 3 * FROM dbo.[$($k.T)] WITH (NOLOCK) WHERE [$($k.C)] LIKE N'%' + $(Tirnak $grupAd) + N'%'" 60)
        if ($r.Count) { Yaz "  -- $($k.T).$($k.C)"; Dok $r "    " }
    }
    Kaydet
}

if ($barkod) {
    Yaz ""; Yaz "== 3) Barkod $barkod : urun kimlikleri =="
    $st = @(Sor $db "SELECT TOP 1 bb.STOK, bb.STOK_STOK_BIRIM, s.KOD, s.AD FROM dbo.STOK_BARKOD_BIRIM bb JOIN dbo.STOK s ON s.ID = bb.STOK WHERE bb.BARKOD = $(Tirnak $barkod)")
    if (-not $st.Count) { Yaz "  Barkod ERP'de bulunamadi." } else {
        $sid = [long]$st[0].STOK; $ssb = [long]$st[0].STOK_STOK_BIRIM
        Yaz "  STOK=$sid STOK_STOK_BIRIM=$ssb KOD=$($st[0].KOD) AD=$($st[0].AD)"
        $bid = @(Sor $db "SELECT ID FROM dbo.STOK_BARKOD WITH (NOLOCK) WHERE BARKOD = $(Tirnak $barkod)" | ForEach-Object { [long]$_.ID })
        $ssbler = @(Sor $db "SELECT ID FROM dbo.STOK_STOK_BIRIM WITH (NOLOCK) WHERE STOK = $sid" | ForEach-Object { [long]$_.ID })
        $fid = @(); if ($ssbler.Count) { $fid = @(Sor $db "SELECT ID FROM dbo.STOK_STOK_BIRIM_FIYAT WITH (NOLOCK) WHERE STOK_STOK_BIRIM IN ($($ssbler -join ','))" | ForEach-Object { [long]$_.ID }) }
        $hepsi = @(@($sid) + $ssbler + $bid + $fid | Sort-Object -Unique)
        Yaz "  kimlikler: $($hepsi -join ',')"
        Yaz ""; Yaz "== 3b) Bu urune bagli satiri olan tablolar (FIS / SATIS gibi hareket tablolari haric) =="
        $kol = @(Sor $db @"
SELECT t.name AS T, c.name AS C FROM sys.columns c JOIN sys.tables t ON t.object_id = c.object_id JOIN sys.types ty ON ty.user_type_id = c.user_type_id
WHERE ty.name IN ('int','bigint','numeric','decimal') AND c.name <> 'ID'
  AND (c.name LIKE '%STOK%' OR c.name LIKE '%BARKOD%' OR c.name LIKE '%FIYAT%' OR c.name LIKE '%BIRIM%' OR c.name LIKE '%URUN%' OR c.name LIKE '%SEQUNCES%')
  AND t.name NOT LIKE 'FIS%' AND t.name NOT LIKE '%HAREKET%' AND t.name NOT LIKE 'SEQUNCES%' AND t.name NOT LIKE '%LOG%'
ORDER BY t.name
"@)
        foreach ($k in $kol) {
            $r = @(Sor $db "SELECT TOP 5 * FROM dbo.[$($k.T)] WITH (NOLOCK) WHERE [$($k.C)] IN ($($hepsi -join ','))" 60)
            if ($r.Count) { Yaz "  -- $($k.T).$($k.C)"; Dok $r "    " }
        }
        Yaz ""; Yaz "== 3c) Bu urunun son fiyat degisimleri (STOK_STOK_BIRIM_DEGISIM) =="
        if ($ssbler.Count) { Dok (Sor $db "SELECT TOP 8 * FROM dbo.STOK_STOK_BIRIM_DEGISIM WITH (NOLOCK) WHERE STOK_STOK_BIRIM IN ($($ssbler -join ',')) ORDER BY ID DESC") "    " }
    }
}
Kaydet
Write-Host ""; Write-Host "Bitti. $Cikti dosyasini gonderin."
Read-Host "Kapatmak icin Enter"
