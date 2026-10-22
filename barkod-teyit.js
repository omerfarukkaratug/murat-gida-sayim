// ============================================================
// Barkod TEYİT katmanı: kamera barkodu tek karede değil, art arda AYNI
// sonucu verince kabul edilir. Bütün kameralı ekranlar (sayım, mal giriş/
// çıkış, fiyat, stok, etiket, hazırlama, plasiyer) bunu kullanır.
//
//  1) Sağlama (checksum): EAN-13 / EAN-8 / UPC-A / UPC-E / ITF-14'ün son hanesi
//     kontrol edilir; tutmayan okuma hiç sayılmaz (yarım/yanlış okuma).
//  2) Teyit: aynı barkod art arda en az 2 karede görülmeli. Sağlaması olmayan
//     (Code-128/39 vb.) ve katalogda bulunmayan barkodlar 3 kare ister.
//     Android'de bir kare ~30-60 ms → gecikme gözle fark edilmez.
//  3) Çerçevede birden fazla barkod varsa ORTAYA en yakın olan seçilir
//     (raftaki yandaki ürünün barkodu okunmasın).
// ============================================================
(function(){
  function rakam(s){ return /^\d+$/.test(s); }
  // GTIN sağlaması (EAN-8, UPC-A(12), EAN-13, ITF-14): sağdan 3,1,3,1…
  function gtinSaglam(s){
    if(!rakam(s)) return false;
    var top = 0, n = s.length;
    for(var i = n - 2, k = 3; i >= 0; i--, k = (k === 3 ? 1 : 3)) top += Number(s[i]) * k;
    return (10 - (top % 10)) % 10 === Number(s[n - 1]);
  }
  // UPC-E (8 hane) → UPC-A'ya açılıp sağlaması kontrol edilir.
  function upcEAc(s){
    if(!rakam(s) || s.length !== 8) return null;
    var d = s.slice(1, 7), son = d[5], a;
    if(son <= '2') a = d.slice(0, 2) + son + '0000' + d.slice(2, 5);
    else if(son === '3') a = d.slice(0, 3) + '00000' + d.slice(3, 5);
    else if(son === '4') a = d.slice(0, 4) + '00000' + d[4];
    else a = d.slice(0, 5) + '0000' + son;
    return s[0] + a + s[7];
  }
  // Okumanın biçimine göre: true (sağlama tuttu), false (tutmadı → at), null (sağlaması yok).
  function sagla(kod, bicim){
    bicim = String(bicim || '').toLowerCase().replace(/[^a-z0-9]/g, '');
    if(bicim === 'ean13' || bicim === 'ean8' || bicim === 'upca') return (kod.length === 13 || kod.length === 8 || kod.length === 12) && gtinSaglam(kod);
    if(bicim === 'upce'){ var a = upcEAc(kod); return !!a && gtinSaglam(a); }
    if(bicim === 'itf' || bicim === 'itf14') return kod.length === 14 && gtinSaglam(kod);   // yarım okunan ITF çok sık hatalı çıkar
    if(bicim === 'codabar') return false;
    if(bicim === 'qrcode') return true;                                                     // QR kendi hata düzeltmesine sahip                                                   // gıda ürününde yok, yanlış okuma kaynağı
    if(!bicim && rakam(kod) && (kod.length === 13 || kod.length === 8)) return gtinSaglam(kod) ? true : null;
    return null;
  }
  function merkezUzaklik(d, W, H){
    var b = d && d.boundingBox; if(!b || !W || !H) return 0;
    var x = b.x + b.width / 2 - W / 2, y = b.y + b.height / 2 - H / 2;
    return x * x + y * y;
  }
  // Teyitçi: her karenin okuma listesi .kare(liste, W, H) ile verilir; barkod
  // teyit edilince kodu, edilmezse null döner. secenek.bilinen(kod): katalogda mı?
  function teyitci(secenek){
    secenek = secenek || {};
    var aday = null, sayi = 0, sonGorulme = 0;
    function gerekli(kod, sag){
      var bilinen = false;
      try { bilinen = !!(secenek.bilinen && secenek.bilinen(kod)); } catch(e){}
      if(sag === true) return 2;          // sağlaması tutan EAN/UPC: 2 kare yeter
      return bilinen ? 2 : 3;             // Code-128/39 vb.: katalogda yoksa 3 kare
    }
    return {
      kare: function(liste, W, H){
        var simdi = Date.now();
        var adaylar = [];
        (liste || []).forEach(function(d){
          var kod = String((d && (d.rawValue !== undefined ? d.rawValue : d.kod)) || '').trim();
          if(!kod) return;
          var sag = sagla(kod, d.format || d.bicim);
          if(sag === false) return;
          adaylar.push({ kod: kod, sag: sag, u: merkezUzaklik(d, W, H) });
        });
        if(!adaylar.length){
          if(simdi - sonGorulme > 450){ aday = null; sayi = 0; }   // kısa titremede sayaç sıfırlanmaz
          return null;
        }
        adaylar.sort(function(a, b){ return a.u - b.u; });
        var en = adaylar[0];
        sonGorulme = simdi;
        if(aday && aday.kod === en.kod) sayi++;
        else { aday = en; sayi = 1; }
        if(sayi >= gerekli(en.kod, en.sag)){ aday = null; sayi = 0; return en.kod; }
        return null;
      },
      sifirla: function(){ aday = null; sayi = 0; }
    };
  }
  window.MKBarkod = { teyitci: teyitci, sagla: sagla, gtinSaglam: gtinSaglam };
})();
