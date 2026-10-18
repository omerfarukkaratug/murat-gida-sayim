# MK Sunucu — kendi sunucumuzda çalıştırma

Google Tablo + Apps Script yerine **kendi bilgisayarımızda** (SERVER) çalışır. Aynı Code.gs, altında
gerçek veritabanı (PostgreSQL). ERP12'ye **dokunmaz**.

| | Google (eski) | MK Sunucu |
|---|---|---|
| İstek süresi | 1–3 sn | 2–60 ms |
| Veri | Google Tablo | PostgreSQL (her işlem tek seferde, yarım kayıt yok) |
| Yedek | Drive kopyası | 3 kat: uygulama yedeği + pg_dump + (isteğe bağlı) ikinci disk |
| Kesinti | Google'a bağlı | Bilgisayar/internet kapanırsa telefonlar kayıtları saklar, açılınca gönderir |

## ★ Kiralık sunucu (Hetzner, Linux) — SEÇİLEN YÖNTEM
1. Hetzner Cloud'da sunucu: **Ubuntu 24.04**, **CX23** (2 çekirdek, 4 GB), konum Almanya, **Backups açık**.
   Root şifresi e-postayla gelir.
2. Windows'ta PowerShell: `ssh root@SUNUCU-IP` (ilk girişte şifreyi değiştirir).
3. Tek komut:
   ```
   curl -fsSL https://raw.githubusercontent.com/omerfarukkaratug/murat-gida-sayim/main/sunucu/linux/kur.sh | bash
   ```
   Node 22, PostgreSQL, Caddy (https), servis, gece yedeği, güvenlik duvarı, otomatik güncellemeler kurulur.
4. Cloudflare → krtsaha.com → DNS → **A** kaydı: `sunucu` → SUNUCU-IP, **gri bulut**.
5. `https://sunucu.krtsaha.com/saglik` → `{"durum":"ok"}`
6. Prova: `krtsaha prova` · Gerçek taşıma: `krtsaha tasi` · Diğerleri: `krtsaha yardim`
Ayarlar `/etc/krtsaha/ayar.json`, kod `/opt/krtsaha`, yedekler `/var/lib/krtsaha`. Yönetim uçları dışarıya kapalıdır.

## 0. Önce PROVA (geçici bir dizüstü bilgisayarda)
Kalıcı bilgisayar gelene kadar her şeyi bir dizüstünde **gerçek verinin kopyasıyla** deneriz. Google'a dokunulmaz,
telefonlar Google'da çalışmaya devam eder; dizüstü istediğin zaman kapatılabilir.
1. Node.js LTS ve PostgreSQL 16 kur (Adım 2).
2. https://github.com/omerfarukkaratug/murat-gida-sayim → **Code → Download ZIP** → `C:\MK-ERP` olarak çıkar.
3. Yönetici PowerShell: `cd C:\MK-ERP\sunucu\windows` →
   `powershell -ExecutionPolicy Bypass -File kur.ps1 -PostgresSifresi "…" -YedekDizini "C:\MK-Yedek" -Deneme`
4. `windows\baslat.cmd`'ye çift tıkla (siyah pencere açık kaldığı sürece sunucu çalışır).
5. İkinci bir PowerShell: `cd C:\MK-ERP\sunucu` → `node tasi.js --kaynak "<Google /exec adresi>" --kullanici <yönetici> --sifre "…" --deneme`
6. Tarayıcıda `http://localhost:8080` → giriş yap, ekranları dene. Kopyayı tazelemek için 5. adımı tekrar çalıştır.
Not: provada yapılan kayıtlar Google'a GİTMEZ (deneme kopyası).

## 1. Gereksinimler
- Windows 10/11 (64 bit) ya da Windows Server 2016 ve üstü; 7/24 açık, **UPS'li**.
- En az 4 GB boş RAM, 20 GB boş disk (yedekler için D: önerilir).

## 2. Programlar (bir kez)
1. **Node.js LTS** — https://nodejs.org → "LTS" → Windows Installer (.msi) → İleri, İleri.
2. **PostgreSQL 16** — https://www.postgresql.org/download/windows/ → Installer.
   Kurulumda sorulan **postgres şifresini bir yere yaz** (sadece kurulumda lazım). Port 5432 kalsın.

## 3. MK Sunucu'yu kur
1. Bu depo klasörünü `C:\MK-ERP` olarak kopyala (içinde `Code.gs`, `index.html`, `sunucu\` olmalı).
2. **Yönetici** PowerShell aç:
   ```
   cd C:\MK-ERP\sunucu\windows
   powershell -ExecutionPolicy Bypass -File kur.ps1 -PostgresSifresi "POSTGRES-SIFRESI" -Adres "https://ADRES"
   ```
   Veritabanını, ayarları ve iki zamanlanmış görevi kurar: **MK Sunucu** (bilgisayar açılınca başlar,
   kapanırsa kendini yeniden başlatır) ve **MK Yedek** (her gece 02:30, 30 gün).
3. Kontrol: tarayıcıda `http://localhost:8080/saglik` → `{"durum":"ok"}`.

## 4. İnternetten erişim (https)
Telefonlar mobil veriyle de bağlanacağı için güvenli bir https adresi gerekir — modemde port açmadan:
- **Alan adımız varsa (önerilen): Cloudflare Tunnel** (ücretsiz). Alan adı Cloudflare'e eklenir,
  `cloudflared` SERVER'a servis olarak kurulur, `erp.alanadimiz.com → http://localhost:8080`.
- **Alan adı yoksa: Tailscale Funnel** (ücretsiz). `https://server.<ad>.ts.net` gibi sabit bir adres verir.

## 5. Taşıma
Google'daki Code.gs **build189 veya üstü** olmalı.

**Önce prova** (Google'a dokunmaz, sadece kopyalar):
```
cd C:\MK-ERP\sunucu
node tasi.js --kaynak "https://script.google.com/macros/s/…/exec" --kullanici admin --sifre "…" --deneme
```
`✓ Doğrulandı` görünmeli. Sonra `https://ADRES/` adresinden bir bilgisayarda giriş yapıp bakılabilir
(bu provada yazılanlar gerçek taşımada silinir).

**Gerçek taşıma** (sakin bir saatte, ~2–3 dk):
```
node tasi.js --kaynak "https://script.google.com/macros/s/…/exec" --kullanici admin --sifre "…" --adres "https://ADRES"
```
1. Google yazmayı durdurur (telefonlar kayıtları saklar), 2. her şey kopyalanır ve birebir karşılaştırılır,
3. Google bundan sonra gelen her isteği bize aktarır. Telefonlar ilk bağlantıda yeni adrese **kendiliğinden geçer**,
kimse yeniden giriş yapmaz. ERP bilgisayarının programları eski adresle çalışmaya devam eder (Google aktarır).

**Geri dönüş** (gerekirse): tarayıcıda
`https://script.google.com/macros/s/…/exec?action=tasima&ne=geri&user=admin&pass=…`
→ Google eskisi gibi çalışır (taşımadan sonra yeni sunucuya yazılanlar Google'a geri gelmez).
Telefonları da Google'a geri çevirmek için yeni sunucu açıkken: `node ozellik.js SUNUCU_ADRESI "https://script.google.com/macros/s/…/exec"`

## 6. Yedekler ve geri yükleme
- Uygulama yedeği: her gece 03:00, `D:\MK-Yedek\MK ERP Yedekleri\` (30 gün + 12 ay ayda bir).
- Veritabanı yedeği: her gece 02:30, `D:\MK-Yedek\pg\` (pg_dump, 30 gün).
- Geri yükleme: `node geri-yukle.js "D:\MK-Yedek\MK ERP Yedekleri\Yedek … .json.gz" --evet`
  (şu anki veri önce ayrıca yedeklenir).
- Öneri: `D:\MK-Yedek` klasörünü haftada bir harici diske / buluta kopyalayın.

## 7. Günlük kullanım
- Kayıt dosyası: `C:\MK-ERP\sunucu\sunucu.log`.
- Yeni Code.gs geldiğinde: dosyayı değiştir, **MK Sunucu** görevini Görev Zamanlayıcı'dan durdur/başlat
  (ya da bilgisayarı yeniden başlat).
- E-posta (sayım raporu, mal giriş Excel'i): Linux'ta `krtsaha eposta` (Gmail + uygulama şifresi). Girilmezse e-postalar veritabanında bekler, kaybolmaz.
  (örnek: `ayar.ornek.json`); girilmezse e-postalar veritabanında bekler, kaybolmaz.
