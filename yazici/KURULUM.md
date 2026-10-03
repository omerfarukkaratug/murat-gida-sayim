# Baskı programı — telefondan yazıcıya doğrudan baskı

Yazıcının bağlı olduğu bilgisayarda çalışan küçük bir programdır. Telefonda Etiket ekranında
**📡 Yazıcıya gönder** denince iş sunucuya yazılır; program birkaç saniye içinde işi alır ve
seçilen yazıcıya basar. Bilgisayarın başında kimsenin bir şey yapması gerekmez (yazıcı
"manuel" moddaysa bilgisayardaki kişi uygulamadan onaylar).

## Gerekenler

- Windows 10 ya da 11, mesai boyunca açık ve internete bağlı, uykuya geçmeyen bir bilgisayar.
- Yazıcılar bu bilgisayara kurulu olmalı (Windows'un yazıcı listesinde görünmeli, deneme sayfası basabilmeli).
- Chrome ya da Edge kurulu olmalı.
- Sunucu (`Code.gs`) build 124 ya da üstü olmalı.

## Kurulum (bir kez)

1. `C:\MKBaski` adında klasör aç.
2. Depodaki `yazici/baski-ajani.ps1` ve `yazici/kur.ps1` dosyalarını bu klasöre indir.
3. sumatrapdfreader.org adresinden **portable** SumatraPDF'i indir, adını `SumatraPDF.exe` yapıp aynı klasöre koy.
4. `kur.ps1` dosyasına sağ tık > **PowerShell ile çalıştır**. Anahtar sorarsa uygulamadaki ERP anahtarını yapıştır
   (Ayarlar > Veri Güvenliği; ERP bilgisayarındaki `erp-anahtar.txt` ile aynı anahtar).
5. Uygulamada Etiket > **Yazıcılar ve baskı işleri** kartına bak: bu bilgisayarın yazıcıları "● açık" görünmeli.
6. Yönetici olarak yazıcılara ad ver ("Ad" düğmesi; ör. "Zebra raf etiketi", "Depo A3") ve istersen "Manuel yap".

## Kullanım

- Telefonda ürünleri okut, biçimi seç, **📡 Yazıcıya gönder**, yazıcıyı seç.
- **Otomatik** yazıcı: iş birkaç saniyede basılır; telefonda "Etiketler basıldı ✅" görünür.
- **Manuel** yazıcı: iş "onay bekliyor" olur; bilgisayardaki kişi Etiket > Yazıcılar ve baskı işleri'nde
  listeyi görür, **Yazdır** deyince basılır.
- Bilgisayar kapalıysa iş sırada bekler, açılınca basılır.
- "✅ basıldı" işin yazıcıya teslim edildiği anlamına gelir; kâğıt bitmişse ya da yazıcı kapalıysa
  iş Windows'un yazdırma kuyruğunda bekler.

## Sorun olursa

- `C:\MKBaski\baski-log.txt` dosyasının son satırlarına bak.
- Yazıcılar uygulamada görünmüyorsa: anahtar yanlış olabilir ya da `Code.gs` eski sürümdedir.
- Kâğıt boyutu yanlış çıkıyorsa: Windows'ta yazıcının "Yazdırma tercihleri"nde varsayılan kâğıdı kontrol et
  (Zebra'da etiket ölçüsü buradan ayarlanır).
- Programı yeniden başlatmak için bilgisayarda oturumu kapatıp aç ya da `kur.ps1`'i yeniden çalıştır.
