// Ana uygulamada seçilen KONSEPT tema (Büyü Okulu, Oyuncu Neon…) alt sayfalara da uygulanır:
// index.html renkleri 'mkKonsept' olarak saklar; bu dosya sayfanın renk değişkenlerini onlarla değiştirir.
// Sade temalarda (Aydınlık, Karanlık…) alt sayfalar kendi renkleriyle kalır.
(function(){
  function uygula(){
    var t = null; try { t = JSON.parse(localStorage.getItem('mkKonsept') || 'null'); } catch(e){ t = null; }
    var st = document.documentElement.style, ad = ['--bg','--panel','--panel2','--line','--text','--muted','--green','--amber','--red','--accent','--accent2','--sans','--blue'];
    document.documentElement.className = document.documentElement.className.replace(/\bk-[a-z]+\b/g, '').trim();
    if(!t || !t.v){ ad.forEach(function(k){ st.removeProperty(k); }); return; }
    Object.keys(t.v).forEach(function(k){ if(t.v[k]) st.setProperty(k, t.v[k]); });
    if(t.v['--accent']) st.setProperty('--blue', t.v['--accent']);
    if(t.key) document.documentElement.classList.add(t.key);
    var m = document.querySelector('meta[name="theme-color"]'); if(m && t.v['--bg']) m.setAttribute('content', t.v['--bg']);
  }
  uygula();
  window.addEventListener('storage', function(e){ if(e.key === 'mkKonsept') uygula(); });
})();
