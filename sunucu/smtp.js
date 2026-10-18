// Ek paket gerektirmeyen küçük SMTP istemcisi (Gmail: smtp.gmail.com:465, uygulama şifresi).
// Ayar: { host, port, secure (465 → true), auth: { user, pass }, gonderen }
'use strict';
const net = require('net');
const tls = require('tls');
const crypto = require('crypto');

const b64 = (s) => Buffer.from(s, 'utf8').toString('base64');
const kodla = (s) => (/^[\x20-\x7e]*$/.test(s) ? s : '=?UTF-8?B?' + b64(s) + '?=');
const satirla = (s) => s.replace(/.{1,76}/g, '$&\r\n');
function adres(s) { const m = /<([^>]+)>/.exec(s); return (m ? m[1] : s).trim(); }
function baslikAdres(s) {
  const m = /^\s*(.*?)\s*<([^>]+)>\s*$/.exec(s);
  return m && m[1] ? kodla(m[1].replace(/^"|"$/g, '')) + ' <' + m[2] + '>' : adres(s);
}

function mesajYap(gonderen, m) {
  const sinir = () => '=_krt_' + crypto.randomBytes(9).toString('hex');
  const alicilar = String(m.to || '').split(/[,;]/).map((x) => x.trim()).filter(Boolean);
  const govdeMetin = 'Content-Type: text/plain; charset=UTF-8\r\nContent-Transfer-Encoding: base64\r\n\r\n' + satirla(b64(m.text || ''));
  let govde = govdeMetin;
  if (m.html) {
    const s = sinir();
    govde = 'Content-Type: multipart/alternative; boundary="' + s + '"\r\n\r\n--' + s + '\r\n' + govdeMetin + '--' + s +
      '\r\nContent-Type: text/html; charset=UTF-8\r\nContent-Transfer-Encoding: base64\r\n\r\n' + satirla(b64(m.html)) + '--' + s + '--\r\n';
  }
  const ekler = m.attachments || [];
  if (ekler.length) {
    const s = sinir();
    let x = 'Content-Type: multipart/mixed; boundary="' + s + '"\r\n\r\n--' + s + '\r\n' + govde;
    ekler.forEach((e) => {
      const ad = kodla(String(e.filename || 'ek'));
      x += '--' + s + '\r\nContent-Type: ' + (e.contentType || 'application/octet-stream') + '; name="' + ad + '"\r\nContent-Transfer-Encoding: base64\r\n' +
        'Content-Disposition: attachment; filename="' + ad + '"\r\n\r\n' + satirla(Buffer.from(e.content).toString('base64'));
    });
    govde = x + '--' + s + '--\r\n';
  }
  const ust = [
    'From: ' + baslikAdres(gonderen),
    'To: ' + alicilar.join(', '),
    'Subject: ' + kodla(String(m.subject || '')),
    'Date: ' + new Date().toUTCString().replace('GMT', '+0000'),
    'Message-ID: <' + crypto.randomBytes(12).toString('hex') + '@' + (adres(gonderen).split('@')[1] || 'krtsaha') + '>',
    'MIME-Version: 1.0'
  ].join('\r\n');
  return { alicilar, veri: ust + '\r\n' + govde };
}

function baglan(ayar) {
  return new Promise((coz, red) => {
    const port = Number(ayar.port || (ayar.secure === false ? 587 : 465));
    const sok = ayar.secure === false ? net.connect(port, ayar.host) : tls.connect({ port, host: ayar.host, servername: ayar.host });
    sok.setTimeout(30000, () => sok.destroy(new Error('SMTP zaman aşımı')));
    sok.once(ayar.secure === false ? 'connect' : 'secureConnect', () => coz(sok));
    sok.once('error', red);
  });
}

function konusma(sok) {
  let tampon = '', bekleyen = null, hata = null;
  const dene = () => {
    if (!bekleyen) return;
    if (hata) { const b = bekleyen; bekleyen = null; return b.red(hata); }
    const satirlar = tampon.split('\r\n');
    for (let i = 0; i < satirlar.length - 1; i++) {
      if (/^\d{3} /.test(satirlar[i])) {
        const cevap = satirlar.slice(0, i + 1).join('\n'); tampon = satirlar.slice(i + 1).join('\r\n');
        const b = bekleyen; bekleyen = null; return b.coz({ kod: Number(satirlar[i].slice(0, 3)), metin: cevap });
      }
    }
  };
  sok.on('data', (d) => { tampon += d.toString('utf8'); dene(); });
  sok.on('error', (e) => { hata = e; dene(); });
  sok.on('close', () => { hata = hata || new Error('SMTP bağlantısı kapandı'); dene(); });
  const oku = () => new Promise((coz, red) => { bekleyen = { coz, red }; dene(); });
  return async function komut(satir, beklenen) {
    if (satir !== null) sok.write(satir + '\r\n');
    const c = await oku();
    if (!beklenen.includes(c.kod)) throw new Error('SMTP ' + (satir ? satir.split(' ')[0] : 'karşılama') + ': ' + c.metin.replace(/\n/g, ' '));
    return c;
  };
}

async function gonder(ayar, m) {
  const gonderen = ayar.gonderen || (ayar.auth && ayar.auth.user);
  const { alicilar, veri } = mesajYap(gonderen, m);
  if (!alicilar.length) throw new Error('Alıcı yok');
  let sok = await baglan(ayar), komut = konusma(sok);
  try {
    await komut(null, [220]);
    let ehlo = await komut('EHLO krtsaha', [250]);
    if (ayar.secure === false && /STARTTLS/i.test(ehlo.metin)) {
      await komut('STARTTLS', [220]);
      sok.removeAllListeners('data'); sok.removeAllListeners('close'); sok.removeAllListeners('error');
      sok = await new Promise((coz, red) => { const t = tls.connect({ socket: sok, servername: ayar.host }, () => coz(t)); t.once('error', red); });
      komut = konusma(sok);
      await komut('EHLO krtsaha', [250]);
    }
    if (ayar.auth && ayar.auth.user) {
      await komut('AUTH PLAIN ' + Buffer.from('\0' + ayar.auth.user + '\0' + ayar.auth.pass, 'utf8').toString('base64'), [235]);
    }
    await komut('MAIL FROM:<' + adres(gonderen) + '>', [250]);
    for (const a of alicilar) await komut('RCPT TO:<' + adres(a) + '>', [250, 251]);
    await komut('DATA', [354]);
    await komut(veri.replace(/\r\n\./g, '\r\n..') + '\r\n.', [250]);
    try { await komut('QUIT', [221]); } catch (e) { /* önemsiz */ }
  } finally { sok.destroy(); }
}

module.exports = { gonder, mesajYap };
