# =====================================================================
#  KRT Saha - ERP12 SQL Server veri tabanlarinin GUNLUK YEDEGI
#
#  Ne yapar:
#   1) Once mevcut durumu raporlar: hangi veri tabaninin en son ne zaman yedeklendigi (msdb kaydi).
#   2) ERP12 veri tabanlarini (ERP12 ile baslayan, cevrimici olanlar) SQL Server'in kendi yedek
#      klasorune yedekler: COPY_ONLY (muhasebe programinin / baska yedeklerin zincirini BOZMAZ),
#      CHECKSUM ile; sonra RESTORE VERIFYONLY ile yedegin okunabilir oldugu dogrulanir.
#   3) Yedekleri $IkinciKlasor'e kopyalar (BASKA disk / USB / Google Drive klasoru) - disk bozulursa yedek kurtulsun.
#   4) Her klasorde son $Sakla gunu tutar, eskileri siler.
#   5) Sonucu KRT Saha'ya bildirir: telefonda / yonetici panelinde ve uyari e-postasinda gorunur.
#
#  ERP verisini DEGISTIRMEZ; yalniz yedek alir.
#  Kullanim:
#    ERP-YEDEK-KONTROL.bat  -> sadece rapor (yedek almaz)
#    ERP-YEDEK-SIMDI.bat    -> simdi bir yedek al
#    ERP-YEDEK-GOREV.bat    -> her gece 23:30 otomatik (Yonetici olarak calistir)
# =====================================================================
$SqlServer        = "SERVER\ERP12"
$VeriTabaniDesen  = "ERP12%"              # yedeklenecek veri tabanlari (LIKE deseni)
# Birinci kopya SQL Server'in kendi yedek klasorunde durur (SQL'in yazma izni orada var).
$IkinciKlasor     = ""                     # IKINCI kopya: ornek "E:\ERP-Yedek" (2. disk / USB) ya da Google Drive klasoru. Bos: yok
$Sakla            = 7                      # her klasorde kac gunluk yedek kalsin
$DbUrl            = "https://wjyqempcmyrmruhdpcwk.supabase.co"
$DbAnahtarDosyasi = "C:\Scripts\db-anahtar.txt"
$LogFile          = "C:\Scripts\erp-sql-yedek-log.txt"
# -----------------------------------------------------

$Kontrol = $args -contains "KONTROL"
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}
function Yaz-Log($m) { $s = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $m"; Write-Host $s; try { Add-Content -Path $LogFile -Value $s } catch {} }
function Bildir($durum, $mesaj) {
    try {
        if (-not (Test-Path $DbAnahtarDosyasi)) { return }
        $anahtar = (Get-Content -Path $DbAnahtarDosyasi -TotalCount 1).Trim()
        $govde = @{ p_ad = "erp_sql_yedek"; p_mesaj = ($durum + ": " + $mesaj); p_baslangic = $null } | ConvertTo-Json -Compress
        [void](Invoke-RestMethod -Uri "$DbUrl/rest/v1/rpc/erp_nabiz_yaz" -Method Post -Body ([Text.Encoding]::UTF8.GetBytes($govde)) `
            -ContentType "application/json; charset=utf-8" -Headers @{ apikey = $anahtar } -TimeoutSec 60 -UserAgent "MK-Sayim/1.0")
    } catch { Yaz-Log "Not: KRT Saha'ya bildirilemedi ($($_.Exception.Message))" }
}

$baglanti = $null
try {
    $baglanti = New-Object System.Data.SqlClient.SqlConnection("Server=$SqlServer;Database=master;Integrated Security=SSPI;")
    $baglanti.Open()
    function Sorgu($sql) {
        $c = $baglanti.CreateCommand(); $c.CommandText = $sql; $c.CommandTimeout = 0
        $t = New-Object System.Data.DataTable; $t.Load($c.ExecuteReader()); return ,$t
    }
    function Calistir($sql) { $c = $baglanti.CreateCommand(); $c.CommandText = $sql; $c.CommandTimeout = 0; [void]$c.ExecuteNonQuery() }

    $surum = (Sorgu "SELECT CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(50)) AS V, CAST(SERVERPROPERTY('Edition') AS nvarchar(100)) AS E").Rows[0]
    Yaz-Log "SQL Server $($surum.V) ($($surum.E))"

    # ---- 1) Mevcut durum ----
    $dblar = Sorgu "SELECT d.name AS AD, CAST(SUM(CAST(m.size AS bigint)) * 8 / 1024 AS int) AS MB,
        (SELECT MAX(b.backup_finish_date) FROM msdb.dbo.backupset b WHERE b.database_name = d.name AND b.type = 'D') AS SON_TAM,
        (SELECT TOP 1 mf.physical_device_name FROM msdb.dbo.backupset b JOIN msdb.dbo.backupmediafamily mf ON mf.media_set_id = b.media_set_id
            WHERE b.database_name = d.name AND b.type = 'D' ORDER BY b.backup_finish_date DESC) AS NEREYE
        FROM sys.databases d JOIN sys.master_files m ON m.database_id = d.database_id
        WHERE d.name LIKE '$VeriTabaniDesen' AND d.state = 0 GROUP BY d.name ORDER BY d.name"
    if ($dblar.Rows.Count -eq 0) { throw "Yedeklenecek veri tabani bulunamadi ($VeriTabaniDesen)" }
    Yaz-Log "MEVCUT YEDEK DURUMU:"
    $toplamMb = 0
    foreach ($r in $dblar.Rows) {
        $toplamMb += [int]$r.MB
        $son = if ($r.SON_TAM -is [DBNull]) { "HIC YEDEK YOK" } else { ([datetime]$r.SON_TAM).ToString("yyyy-MM-dd HH:mm") + " -> " + [string]$r.NEREYE }
        Yaz-Log ("   {0,-14} {1,8} MB   son tam yedek: {2}" -f $r.AD, $r.MB, $son)
    }
    if ($Kontrol) { Yaz-Log "KONTROL modu: yedek alinmadi."; exit 0 }

    # ---- 2) Yedek al ----
    $sqlKlasor = [string](Sorgu "DECLARE @d nvarchar(4000); EXEC master.dbo.xp_instance_regread N'HKEY_LOCAL_MACHINE', N'Software\Microsoft\MSSQLServer\MSSQLServer', N'BackupDirectory', @d OUTPUT; SELECT ISNULL(@d, '') AS D").Rows[0].D
    if (-not $sqlKlasor) { throw "SQL Server'in yedek klasoru okunamadi" }
    Yaz-Log "SQL Server yedek klasoru: $sqlKlasor"
    if ($IkinciKlasor -and -not (Test-Path $IkinciKlasor)) { New-Item -ItemType Directory -Path $IkinciKlasor -Force | Out-Null }
    $bos = (Get-PSDrive -Name $sqlKlasor.Substring(0, 1)).Free / 1MB
    if ($bos -lt $toplamMb * 1.2) { throw ("Diskte yer yok: {0:N0} MB bos, yaklasik {1:N0} MB gerekli ({2})" -f $bos, $toplamMb, $sqlKlasor) }

    $damga = Get-Date -Format "yyyyMMdd_HHmm"
    $alinan = @(); $hatalar = @()
    foreach ($r in $dblar.Rows) {
        $ad = [string]$r.AD
        $dosya = Join-Path $sqlKlasor ("KRT_{0}_{1}.bak" -f $ad, $damga)
        try {
            $sure = [Diagnostics.Stopwatch]::StartNew()
            try { Calistir "BACKUP DATABASE [$ad] TO DISK = N'$dosya' WITH COPY_ONLY, CHECKSUM, INIT, COMPRESSION" }
            catch { Calistir "BACKUP DATABASE [$ad] TO DISK = N'$dosya' WITH COPY_ONLY, CHECKSUM, INIT" }   # Express: sikistirma yok
            Calistir "RESTORE VERIFYONLY FROM DISK = N'$dosya' WITH CHECKSUM"
            $boy = 0; try { $boy = [int]((Get-Item $dosya).Length / 1MB) } catch {}
            Yaz-Log ("YEDEK TAMAM: {0} ({1} MB, {2} sn, dogrulandi)" -f $ad, $boy, [int]$sure.Elapsed.TotalSeconds)
            $alinan += $dosya
        } catch { $hatalar += "$ad : $($_.Exception.Message)"; Yaz-Log "HATA: $ad yedeklenemedi: $($_.Exception.Message)" }
    }

    # ---- 3) Kopyala + 4) temizle ----
    $kopyaHata = @()
    foreach ($k in @($IkinciKlasor)) {
        if (-not $k) { continue }
        foreach ($f in $alinan) {
            try { Copy-Item -Path $f -Destination $k -Force; Yaz-Log "Kopyalandi: $(Split-Path $f -Leaf) -> $k" }
            catch { $kopyaHata += "$k : $($_.Exception.Message)"; Yaz-Log "HATA: $k klasorune kopyalanamadi: $($_.Exception.Message)" }
        }
        Get-ChildItem -Path $k -Filter "KRT_*.bak" -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$Sakla) } |
            ForEach-Object { Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue; Yaz-Log "Eski yedek silindi: $($_.FullName)" }
    }
    # SQL klasorundeki kopyalar da $Sakla gunden eski olunca silinir (kopyalari zaten disarida).
    Get-ChildItem -Path $sqlKlasor -Filter "KRT_*.bak" -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$Sakla) } |
        ForEach-Object { Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue }

    $ozet = "$($alinan.Count)/$($dblar.Rows.Count) veri tabani yedeklendi ($toplamMb MB)" + $(if ($IkinciKlasor) { ", 2 kopya" } else { ", tek kopya (ikinci klasor ayarlanmadi)" })
    if ($hatalar.Count -or $kopyaHata.Count) { Bildir "HATA" ($ozet + " | " + (($hatalar + $kopyaHata) -join " | ")); Yaz-Log "BITTI (HATALI): $ozet"; exit 1 }
    Bildir "OK" $ozet
    Yaz-Log "BITTI: $ozet"
}
catch {
    Yaz-Log "HATA: $($_.Exception.Message)"
    Bildir "HATA" $_.Exception.Message
    exit 1
}
finally { if ($baglanti -ne $null) { $baglanti.Close() } }
