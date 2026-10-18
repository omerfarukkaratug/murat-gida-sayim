// E-posta ayarını dener: node eposta-dene.js alici@ornek.com
'use strict';
const { ayarOku } = require('./ana');
const smtp = require('./smtp');
const alici = process.argv[2];
const ayar = ayarOku();
if (!ayar.smtp) { console.log('✗ E-posta ayarı yok (krtsaha eposta ile gir)'); process.exit(1); }
if (!alici) { console.log('Kullanım: node eposta-dene.js alici@ornek.com'); process.exit(2); }
smtp.gonder(ayar.smtp, { to: alici, subject: 'KRT Saha — deneme e-postası', text: 'Bu e-posta KRT Saha sunucusundan gönderildi.\nSayım raporları ve mal giriş Excel\'leri bundan sonra buradan gidecek.',
  attachments: [{ filename: 'deneme-ç.txt', contentType: 'text/plain', content: Buffer.from('Ek dosya denemesi: ğüşıöç ĞÜŞİÖÇ\n') }] })
  .then(() => console.log('✓ Gönderildi → ' + alici + ' (gelen kutusuna ve Gereksiz klasörüne bak)'))
  .catch((e) => { console.log('✗ Gönderilemedi: ' + e.message); if (/535|Username and Password/i.test(e.message)) console.log('  → Gmail adresi ya da 16 harflik uygulama şifresi yanlış.'); process.exit(1); });
