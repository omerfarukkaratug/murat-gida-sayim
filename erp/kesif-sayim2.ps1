# =====================================================================
#  KRT Saha - ERP12 KESIF SAYIM 2: sayim kesinlestirme NASIL hesapliyor?
#  1. kesifte bulunanlar: SAYIM + SAYIM_DETAY (sayilan), kesinlestirince "Stok sayim fisi" (FIS_TURU 17).
#  ERP'de "satir tarihli" kesinlestirme ve "sifirlama" (gruplu / ozel kodlu) programlari var. Bu kesif:
#   1) Sayim gorunumlerinin, fonksiyonlarinin ve kesinlestirme / sifirlama programlarinin METNI
#   2) Kesinlesmis bir sayimda: sayilan miktar ile olusan sayim fisi satiri ve o gunku stok (fark mi, sayilan mi?)
#   3) Bolum ayirmak icin urun siniflari: RAPOR_GRUP agaci, STOK kartindaki grup / ozel kod alanlari
#  ERP12'ye HICBIR SEY YAZMAZ, sadece okur. Sonuc: C:\Scripts\kesif-sayim2.txt
# =====================================================================
$SqlServer = "SERVER\ERP12"
$Cikti     = "C:\Scripts\kesif-sayim2.txt"
Import-Module SqlServer -ErrorAction SilentlyContinue
$sb = New-Object System.Text.StringBuilder
function Yaz($m) { [void]$sb.AppendLine([string]$m); Write-Host $m }
function Kaydet { try { [System.IO.File]::WriteAllText($Cikti, $sb.ToString(), [System.Text.Encoding]::UTF8) } catch {} }
function Sor($db, $q, $sn = 300) { try { return @(Invoke-Sqlcmd -ServerInstance $SqlServer -Database $db -Query $q -QueryTimeout $sn -MaxCharLength 200000 -ErrorAction Stop) } catch { Yaz "  HATA: $($_.Exception.Message)"; return @() } }
function Deger($v) { if ($v -is [DBNull]) { return "NULL" } elseif ($v -is [byte[]]) { return "0x.." } elseif ($v -is [datetime]) { return $v.ToString("yyyy-MM-dd HH:mm") } else { $s = [string]$v; if ($s.Length -gt 60) { $s = $s.Substring(0, 60) + ".." }; return $s } }
function Dok($satirlar, $on) { foreach ($r in $satirlar) { $p = @(); foreach ($c in $r.Table.Columns) { $p += "$($c.ColumnName)=$(Deger $r[$c.ColumnName])" }; Yaz ("  $on" + ($p -join " | ")) } }

$db = "ERP122025"
$dbler = @(Sor "master" "SELECT name FROM sys.databases WHERE name LIKE 'ERP12[0-9][0-9][0-9][0-9]' AND state = 0 ORDER BY name DESC")
if ($dbler.Count) { $db = [string]$dbler[0].name }
Yaz "KESIF-SAYIM2 $(Get-Date -Format 'yyyy-MM-dd HH:mm')  veri tabani: $db"

Yaz ""; Yaz "== 1) Sayim nesnelerinin metni =="
$adlar = @('SAYIM_DETAY_V', 'SAYIM_DETAY_V_SATIR_TARIHLI', 'SAYIM_LISTE', 'SAYIM_MIKTARI_VER', 'SAYIM_MIKTARI_VER_TARIHLI',
           'STOK_SAYIM_KESINLESTIRME', 'STOK_SAYIM_KESINLESTIRMEYE_ADET_VER', 'STOK_SAYIM_KESINLESTIRMEYE_ADET_VER_SATIR_TARIHI',
           'STOK_SAYIM_SIFIRLAMAYA_ADET_VER', 'STOK_SAYIM_SIFIRLAMAYA_ADET_VER_GRUPLU', 'STOK_SAYIM_SIFIRLAMAYA_ADET_VER_OZEL_KOD',
           'STOK_SAYIM_SIFIRLAMAYA_ADET_VER_STOK_BARKODLARI', 'STOK_SAYIM_FIS_UPDATE', 'STOK_SAYIM_FISLERI', 'STOK_SAYIM_FISLERI_ONAYSIZ',
           'FIS_TENSONRA_SAYIM_VARMI', 'SAYIM_ONAY_TARIH_VER', 'RAP_SAYIM_STOK_DURUMU', 'STOK_DOLDUR_SAYIM')
foreach ($a in $adlar) {
    $m = @(Sor $db "SELECT OBJECT_DEFINITION(OBJECT_ID('dbo.$a')) AS M")
    Yaz ""; Yaz "---------- $a ----------"
    if (-not $m.Count -or $m[0].M -is [DBNull]) { Yaz "  (metin okunamadi: yok ya da sifreli)"; continue }
    Yaz ([string]$m[0].M)
    Kaydet
}

Yaz ""; Yaz "== 2) Kesinlesmis sayim ornegi: sayilan / sayim fisi satiri / stok =="
$ks = @(Sor $db "SELECT TOP 3 s.ID, s.FIS, s.TARIH FROM dbo.SAYIM s WHERE s.FIS > 0 AND EXISTS (SELECT 1 FROM dbo.FIS f WHERE f.ID = s.FIS) AND (SELECT COUNT(*) FROM dbo.SAYIM_DETAY d WHERE d.SAYIM = s.ID) >= 20 ORDER BY s.ID DESC")
Yaz "  -- FIS_DETAY kolonlari: $((Sor $db "SELECT c.name FROM sys.columns c WHERE c.object_id = OBJECT_ID('dbo.FIS_DETAY') ORDER BY c.column_id" | ForEach-Object { $_.name }) -join ', ')"
Yaz "  -- FIS kolonlari: $((Sor $db "SELECT c.name FROM sys.columns c WHERE c.object_id = OBJECT_ID('dbo.FIS') ORDER BY c.column_id" | ForEach-Object { $_.name }) -join ', ')"
foreach ($s in $ks) {
    Yaz ""; Yaz "  ## SAYIM $($s.ID) ($(Deger $s.TARIH)) -> FIS $($s.FIS)"
    Dok (Sor $db "SELECT TOP 1 * FROM dbo.FIS WHERE ID = $($s.FIS)") "    FIS: "
    Dok (Sor $db "SELECT COUNT(*) AS SATIR, SUM(CAST(MIKTAR_FIS AS float)) AS TOPLAM, SUM(CASE WHEN MIKTAR_FIS < 0 THEN 1 ELSE 0 END) AS EKSI_SATIR FROM dbo.FIS_DETAY WHERE FIS = $($s.FIS)") "    fis ozeti: "
    Dok (Sor $db "SELECT COUNT(*) AS SATIR, COUNT(DISTINCT STOK) AS URUN, SUM(CAST(MIKTAR AS float)) AS TOPLAM FROM dbo.SAYIM_DETAY WHERE SAYIM = $($s.ID)") "    sayim ozeti: "
    # 6 urun: sayilan, fis satiri, sayim tarihindeki stok (o ana kadarki butun stok hareketleri)
    foreach ($u in (Sor $db "SELECT TOP 6 STOK, SUM(CAST(MIKTAR AS float) * ISNULL(NULLIF(CARPAN, 0), 1)) AS SAYILAN, MAX(TARIH) AS T FROM dbo.SAYIM_DETAY WHERE SAYIM = $($s.ID) GROUP BY STOK ORDER BY NEWID()")) {
        $fs = @(Sor $db "SELECT SUM(CAST(d.MIKTAR_FIS AS float) * ISNULL(NULLIF(d.CARPAN, 0), 1)) AS M FROM dbo.FIS_DETAY d WHERE d.FIS = $($s.FIS) AND d.STOK = $($u.STOK)")
        $tarih = ([datetime]$u.T).ToString("yyyy-MM-dd HH:mm:ss")
        $st = @(Sor $db @"
SELECT SUM(CASE WHEN f.FIS_TURU = 17 THEN 0 ELSE FT.GIRIS END * CAST(d.MIKTAR_FIS AS float) * ISNULL(NULLIF(d.CARPAN, 0), 1)) AS ONCE,
       SUM(CASE WHEN f.FIS_TURU = 17 THEN CAST(d.MIKTAR_FIS AS float) * ISNULL(NULLIF(d.CARPAN, 0), 1) ELSE 0 END) AS SAYIMFIS_ONCE
FROM dbo.FIS f JOIN dbo.FIS_DETAY d ON d.FIS = f.ID JOIN dbo.FIS_TURU FT ON FT.ID = f.FIS_TURU
WHERE d.STOK = $($u.STOK) AND ISNULL(f.AKTIF, 1) = 1 AND f.FIS_TARIHI <= '$tarih' AND f.ID <> $($s.FIS) AND ISNULL(d.FATRALANDIRILMIS_IRSALIYEMI, 0) = 0
"@)
        $bugun = @(Sor $db "SELECT SUM(CAST(COALESCE(um.MIKTAR, ubar.MIKTAR) AS float)) AS M FROM dbo.STOK_BARKOD_BIRIM ub LEFT JOIN dbo.STOK_BARKOD ubar ON ubar.BARKOD = ub.BARKOD LEFT JOIN dbo.STOK_MIKTAR_BARKODLU um ON um.BARKOD = ub.BARKOD WHERE ub.STOK = $($u.STOK)")
        Yaz ("    STOK {0}: sayilan={1} | sayim fisindeki={2} | sayimdan once hareket toplami={3} (onceki sayim fisleri {4}) | bugunku stok={5}" -f $u.STOK, (Deger $u.SAYILAN), $(if ($fs.Count) { Deger $fs[0].M } else { '-' }), $(if ($st.Count) { Deger $st[0].ONCE } else { '-' }), $(if ($st.Count) { Deger $st[0].SAYIMFIS_ONCE } else { '-' }), $(if ($bugun.Count) { Deger $bugun[0].M } else { '-' }))
    }
    Kaydet
}

Yaz ""; Yaz "== 3) Bolum ayirmak icin urun siniflari =="
Yaz "  -- STOK kartinda GRUP / OZEL / KATEGORI / REYON / RAPOR gecen kolonlar ve dolu olanlarin farkli deger sayisi:"
foreach ($k in (Sor $db "SELECT c.name FROM sys.columns c WHERE c.object_id = OBJECT_ID('dbo.STOK') AND (c.name LIKE '%GRUP%' OR c.name LIKE '%OZEL%' OR c.name LIKE '%KATEGORI%' OR c.name LIKE '%REYON%' OR c.name LIKE '%RAPOR%' OR c.name LIKE '%MARKA%' OR c.name LIKE '%SINIF%' OR c.name LIKE '%TUR%') ORDER BY c.column_id")) {
    Dok (Sor $db "SELECT '$($k.name)' AS KOLON, COUNT(DISTINCT [$($k.name)]) AS FARKLI, SUM(CASE WHEN [$($k.name)] IS NULL OR CAST([$($k.name)] AS nvarchar(100)) IN ('', '0') THEN 0 ELSE 1 END) AS DOLU, COUNT(*) AS TUM FROM dbo.STOK") "    "
}
Yaz "  -- RAPOR_GRUP agaci (ID, USTID, AD) ve bagli urun sayisi (STOK'ta RAPOR_GRUP kolonu varsa):"
$rk = @(Sor $db "SELECT c.name FROM sys.columns c WHERE c.object_id = OBJECT_ID('dbo.STOK') AND c.name LIKE '%RAPOR%GRUP%'")
if ($rk.Count) { $kol = $rk[0].name; Dok (Sor $db "SELECT g.ID, g.USTID, ISNULL(u.AD, '') AS UST, g.AD, (SELECT COUNT(*) FROM dbo.STOK s WHERE s.[$kol] = g.ID) AS URUN FROM dbo.RAPOR_GRUP g LEFT JOIN dbo.RAPOR_GRUP u ON u.ID = g.USTID ORDER BY ISNULL(u.AD, g.AD), g.AD") "    " }
else { Dok (Sor $db "SELECT g.ID, g.USTID, g.AD FROM dbo.RAPOR_GRUP g ORDER BY g.USTID, g.AD") "    "; Yaz "    (STOK kartinda RAPOR_GRUP kolonu yok; baglanti baska tabloda olabilir)"; Dok (Sor $db "SELECT t.name AS TABLO, c.name AS KOLON FROM sys.columns c JOIN sys.tables t ON t.object_id = c.object_id WHERE c.name LIKE '%RAPOR_GRUP%' ORDER BY t.name") "      " }
Yaz "  -- Ozel kod tablolari:"
foreach ($t in (Sor $db "SELECT name FROM sys.tables WHERE name LIKE 'STOK_OZEL_KOD%' OR name LIKE '%KATEGORI%' OR name LIKE 'STOK_MARKA' ORDER BY name")) {
    $n = @(Sor $db "SELECT COUNT(*) AS N FROM dbo.[$($t.name)]")
    Yaz "    $($t.name): $($n[0].N) satir"; Dok (Sor $db "SELECT TOP 15 * FROM dbo.[$($t.name)]") "      "
}
Kaydet
Write-Host ""; Write-Host "Bitti. $Cikti dosyasini gonderin."
Read-Host "Kapatmak icin Enter"
