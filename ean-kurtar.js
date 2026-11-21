/* ean-kurtar.js — Mürekkebi taşmış / kalın çubuklu / parlak folyo EAN-13 / UPC-A / EAN-8 okuyucu.
 * zbar ve ZXing çubuk genişliklerini tek tek ölçer; çubuklar şişince (yaldızlı ambalaj, kalın baskı) çözemez.
 * Burada "benzer kenardan benzer kenara" ölçülür (çubuk başı → sonraki çubuk başı, boşluk başı → sonraki boşluk başı).
 * Bu mesafeler çubuk ne kadar şişerse şişsin değişmez. Belirsiz rakamlar (1/7, 2/8) düzeltilmiş çubuk genişliğiyle ayrılır.
 * Sonuç: sağlama hanesi doğru + en az 2 tarama çizgisi aynı sonucu vermeli. Aksi halde hiçbir şey dönmez (yanlış okuma yerine okumama).
 */
(function(g){
  'use strict';
  var LW = ['3211','2221','2122','1411','1132','1231','1114','1312','1213','3112'];
  var PAR = ['LLLLLL','LLGLGG','LLGGLG','LLGGGL','LGLLGG','LGGLLG','LGGGLL','LGLGLG','LGLGGL','LGGLGL'];
  // Her rakam için: [t1, t2, çubukToplamı(modül), rakam, parite]
  // Sol taraf (boşluk,çubuk,boşluk,çubuk): çubuklar 1 ve 3. eleman. Sağ taraf (çubuk,boşluk,çubuk,boşluk): çubuklar 0 ve 2.
  function tablo(sag){
    var t = [];
    for(var d=0; d<10; d++){
      var w = LW[d].split('').map(Number);
      var cesit = sag ? [['R', w]] : [['L', w], ['G', w.slice().reverse()]];
      cesit.forEach(function(c){
        var x = c[1];
        var bar = sag ? x[0]+x[2] : x[1]+x[3];
        t.push([x[0]+x[1], x[1]+x[2], bar, d, c[0]]);
      });
    }
    return t;
  }
  var SOL = tablo(false), SAG = tablo(true);

  // Bir satırı ikiliğe çevir: yerel min/max ortası eşik (parlak folyoda global eşik çöker)
  function kosular(sat, n){
    var p = 1, yum = new Float32Array(n), i, j;
    for(i=0;i<n;i++) yum[i]=sat[i];
    var W = Math.max(8, Math.round(n/24)), esik = new Float32Array(n), aralik = new Float32Array(n);
    // kayan min/max (basit, n küçük: ≤ 1000)
    for(i=0;i<n;i++){
      var mn=255, mx=0, a=Math.max(0,i-W), b=Math.min(n-1,i+W);
      for(j=a;j<=b;j+=p){ var v=yum[j]; if(v<mn) mn=v; if(v>mx) mx=v; }
      esik[i]=(mn+mx)/2; aralik[i]=mx-mn;
    }
    var kenar = [], koyu = [], onceki = null;
    for(i=0;i<n;i++){
      if(aralik[i] < 24){ // düz bölge: kenar yok, önceki durum sürer
        if(onceki === null) continue; else continue;
      }
      var k = yum[i] < esik[i];
      if(onceki === null){ onceki = k; kenar.push(i); koyu.push(k); continue; }
      if(k !== onceki){
        // alt piksel kenar: eşik geçişini doğrusal ara
        var y0 = yum[i-1]-esik[i-1], y1 = yum[i]-esik[i], f = (y0===y1) ? 0.5 : y0/(y0-y1);
        kenar.push(i-1+Math.max(0,Math.min(1,f))); koyu.push(k); onceki = k;
      }
    }
    kenar.push(n);
    var w = [], dk = [];
    for(i=0;i<koyu.length;i++){ w.push(kenar[i+1]-kenar[i]); dk.push(koyu[i]); }
    return { w: w, k: dk };
  }

  function sagla(kod){ // GTIN sağlama
    var s=0, L=kod.length;
    for(var i=0;i<L-1;i++){ var d=+kod[L-2-i]; s += (i%2===0) ? d*3 : d; }
    return (10 - s%10)%10 === +kod[L-1];
  }

  // w: genişlikler, i: sol koruma ilk çubuğu (koyu). Yön düz.
  function cozEAN13(w, i){
    if(i < 1 || i + 59 > w.length) return null;
    var top = 0; for(var k=i;k<i+59;k++) top += w[k];
    var m = top/95;
    if(m < 0.8) return null;
    // Sessiz bölge: ambalajda barkodun hemen yanında desen/yazı olabiliyor (ör. Torku Banada).
    // İki yanda en az 1.5 modül, en az bir yanda 3 modül yeter; asıl güvence koruma + parite + sağlama + çoklu çizgi.
    var solS = w[i-1], sagS = (i+59 < w.length) ? w[i+59] : 99*m;
    if(solS < m*1.5 || sagS < m*1.5 || Math.max(solS, sagS) < m*3) return null;
    // koruma kontrolü: benzer kenar mesafeleri 2 modül
    function kor(a){ var t1=(w[a]+w[a+1])/m, t2=(w[a+1]+w[a+2])/m; return Math.abs(t1-2)<0.7 && Math.abs(t2-2)<0.7; }
    if(!kor(i) || !kor(i+56) || !kor(i+28) || !kor(i+29)) return null;
    // şişme tahmini: koruma çubukları 1 modül olmalı
    var korCubuk = [w[i], w[i+2], w[i+29], w[i+31], w[i+56], w[i+58]];
    var sis = 0; korCubuk.forEach(function(x){ sis += x; }); sis = sis/korCubuk.length - m;
    var rak = [], par = '';
    for(var d=0; d<12; d++){
      var b = d<6 ? i+3+d*4 : i+32+(d-6)*4, sag = d>=6;
      var e = [w[b],w[b+1],w[b+2],w[b+3]];
      var mm = (e[0]+e[1]+e[2]+e[3])/7;
      if(Math.abs(mm-m) > m*0.3) return null;
      var t1 = (e[0]+e[1])/mm, t2 = (e[1]+e[2])/mm;
      var r1 = Math.round(t1), r2 = Math.round(t2);
      if(Math.abs(t1-r1) > 0.42 || Math.abs(t2-r2) > 0.42) return null;
      var cubuk = ((sag ? e[0]+e[2] : e[1]+e[3]) - 2*sis)/mm;
      var tb = sag ? SAG : SOL, en = null, enFark = 99;
      for(var z=0; z<tb.length; z++){
        var r = tb[z];
        if(r[0]!==r1 || r[1]!==r2) continue;
        var f = Math.abs(r[2]-cubuk);
        if(f < enFark){ enFark = f; en = r; }
      }
      if(!en) return null;
      rak.push(en[3]); if(!sag) par += en[4];
    }
    var ilk = PAR.indexOf(par);
    if(ilk < 0) return null;
    var kod = ilk + rak.join('');
    return sagla(kod) ? kod : null;
  }

  function satirOku(sat, n){
    var r = kosular(sat, n), w = r.w, k = r.k, sonuc = {};
    for(var yon=0; yon<2; yon++){
      var ww = yon ? w.slice().reverse() : w, kk = yon ? k.slice().reverse() : k;
      for(var i=1; i+59<=ww.length; i++){
        if(!kk[i] || kk[i-1]) continue;
        var kod = cozEAN13(ww, i);
        if(kod) sonuc[kod] = 1;
      }
    }
    return Object.keys(sonuc);
  }

  // gri: Uint8Array (w*h), görüntünün ortasından birkaç yatay çizgi taranır.
  // Dönen: kod (string) ya da null. En az 2 çizgi aynı kodu vermeli, farklı kod veren çizgi olmamalı.
  function oku(gri, gen, yuk, cizgi){
    cizgi = cizgi || 15;
    var say = {}, satir = new Uint8Array(gen);
    for(var c=0; c<cizgi; c++){
      var y = Math.round(yuk*(0.15 + 0.7*c/(cizgi-1)));
      var o = y*gen;
      for(var x=0;x<gen;x++) satir[x] = gri[o+x];
      satirOku(satir, gen).forEach(function(kod){ say[kod] = (say[kod]||0)+1; });
    }
    var kodlar = Object.keys(say);
    if(kodlar.length !== 1) return null;
    var kod = kodlar[0];
    if(say[kod] < 2) return null;
    if(kod[0] === '0') kod = kod; // UPC-A EAN-13 olarak (başta 0) — uygulama zaten 13 haneli arar
    return kod;
  }

  // Tuval (canvas) üzerinden: RGBA → gri
  function tuvaldenOku(tuval){
    var cx = tuval.getContext('2d', { willReadFrequently: true });
    var W = tuval.width, H = tuval.height;
    if(!W || !H) return null;
    var veri = cx.getImageData(0, 0, W, H).data, gri = new Uint8Array(W*H);
    for(var i=0,j=0;i<gri.length;i++,j+=4) gri[i] = (veri[j]*77 + veri[j+1]*150 + veri[j+2]*29) >> 8;
    return oku(gri, W, H);
  }

  g.MKEanKurtar = { kosular: kosular, oku: oku, tuvaldenOku: tuvaldenOku, satirOku: satirOku };
})(typeof window !== 'undefined' ? window : globalThis);
