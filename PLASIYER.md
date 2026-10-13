# 🚚 Plasiyer (saha satış) — build 210 / Code.gs build177

Uygulamanın menüsünde **🚚 Plasiyer** (ve üstteki hızlı geçişte). Kodu ayrı dosyada (`plasiyer.html`)
durur, uygulamanın içinde açılır. **ERP12'ye hiçbir şey yazmaz.** Sipariş, araçtan satış ve tahsilat
notları Google Sheets'te yeni sekmelerde durur: `PlasiyerBelge`, `PlasiyerTahsilat`, `PlasiyerMusteri`,
`PlasiyerOzelFiyat`. Ayarlar Apps Script özelliğinde (`PLASIYER_AYAR`).

## Yetkiler (Yönetici Paneli → kullanıcı)
| Yetki | Ne yapar |
|---|---|
| **🚚 Plasiyer** | Kendi müşterileri, sipariş, araçtan satış, tahsilat notu, kendi gün sonu ve primi |
| **🚚 Plasiyer: maliyet/tedarikçi görür** | Ürüne basılı tutunca tedarikçi, alış fiyatı, maliyet, taban, kâr marjı; siparişte kalem kalem marj |
| **🚚 Plasiyer Yönetimi** | Ayarlar, müşteri atama, müşteriye özel fiyat, herkesin kaydı/primi, iptal ve iptali geri alma |
| **💲 Alış Fiyatı (maliyet) Görme** | Mal girişte son alış fiyatı ve toplamlar (plasiyer dışı, genel yetki) |
| Yönetici | Hepsi (otomatik) |

Plasiyer ekranı **şube konumu istemez** (sahada çalışır). Her istek giriş + yetki ister — "Kimlik zorunlu"
kapalıyken bile.

## Neler var
- **🏢 Tüm cariler (yönetici / Plasiyer Yönetimi, build 212):** "Müşterilerim"de **Tüm cariler** süzgeciyle
  atanmamış dahil bütün carilere (telefondaki cari listesinden, internetsiz de) sipariş, araçtan satış ve
  tahsilat notu girilir. Kayıt **girenin adına** yazılır (primi ona sayılır).
- **👥 Müşterilerim:** atanan müşteriler; bakiye (ERP cari listesinden, B/A), vadesi geçmiş tutar, risk
  (yeşil/sarı/kırmızı, `009_odeme_risk.sql`); dokununca risk nedenleri ve bugün o müşteriye girilenler.
- **🛒 Sipariş al / 🚚 Araçtan satış:** ürün ada, barkoda, stok koduna göre aranır ya da 📷 ile okutulur
  (koli barkodu çarpanıyla adede çevrilir). Fiyat: **müşteriye özel fiyat**, yoksa **liste fiyatı**.
  Her kalemde liste / özel / **bu müşteriye son satılan fiyat ve tarihi** (ERP faturalarından) görünür,
  tek dokunuşla seçilir. "Daha önce aldıkları" ve "Özel fiyatlı" süzgeçleri var. Riskli müşteride kırmızı
  uyarı. Yarım kalan sipariş taslak olarak saklanır.
- **Taban fiyat:** fiyat, maliyetin yönetici ayarladığı yüzde kadar altına (varsayılan **%10**)
  **yazılamaz**; yazılırsa eski fiyat geri gelir. Maliyet yetkisi olan anında telefonda kontrol edilir.
  Maliyet yetkisi olmayanın telefonunda maliyet hiç yoktur: liste/özel fiyat ve üstü doğrudan kabul edilir,
  altı **sunucuya sorulur** ve cevap yalnızca "uygun / değil" olur (sınırın kendisi söylenmez; deneme-yanılma
  için kişi başına 10 dakikada 40 soru sınırı). İnternet yoksa fiyat kabul edilir, kalem "kontrol edilemedi"
  diye işaretlenir. Maliyet = katalogdaki son alış (KDV hariç) × (1 + KDV). Maliyeti bilinmeyen
  üründe sınır yoktur. Sunucu da kontrol eder: eski katalogla girilmiş taban altı satır **reddedilmez**
  (sahadaki sipariş kaybolmasın), "taban altı" diye işaretlenir; yönetici gün sonunda ve primde görür.
- **Ürüne basılı tut:** liste, KDV, özel ve son satış fiyatı; maliyet yetkisiyle son alış, maliyet,
  taban, liste fiyatında ve bu siparişteki fiyatta marj, **tedarikçiler** (son alış fiyatı/tarihi) ve son alışlar.
- **💵 Tahsilat notu:** tutar, yöntem (nakit, kart, havale/EFT, çek, senet), not. **ERP'ye yazılmaz.**
  Araçtan satışta "Peşin tahsil edildi" işaretlenirse tahsilat notu da yazılır ve belgeye bağlanır
  (belge iptal edilince o da iptal olur).
- **🧾 Gün sonu:** gün ya da ay; sipariş / araç satışı / tahsilat toplamları, yönteme göre tahsilat,
  ziyaret edilen müşteri, kayıt listesi (dokununca kalemler). **📤 Paylaş** (WhatsApp metni) ve
  **🖨️ Yazdır** (imza alanlı). "Aynısından yeni" eski siparişi güncel fiyatlarla yeniden açar.
- **🏆 Prim:** ay seçilir; uygulamaya girilen siparişler + araçtan satışlar (satış) ve tahsilat notları
  üzerinden. Prim = satış × satış% + tahsilat × tahsilat% (oranları yönetici girer, varsayılan 0).
  İptaller sayılmaz. ERP faturaları bu hesaba girmez.
- **🚫 İptal:** kayıt silinmez, "iptal" işaretlenir (neden zorunlu). Plasiyer yalnız kendi kaydını ve
  yalnız kayıt günü iptal eder; yönetim her kaydı iptal eder ve iptali geri alır.
- **⚙️ Yönetim:** taban yüzdesi, "plasiyer fiyatı değiştirebilir" (kapalıysa liste/özel fiyat sabit),
  prim oranları; müşteri atama (ERP cari listesinden, plasiyer süzgeçli); müşteriye özel fiyat
  (taban altına girilemez).

## İnternetsiz çalışma
Ürünler telefondaki katalogdan (sayım uygulamasının kataloğu), müşteriler ve son satış fiyatları son
çekilen hâlinden gelir. Kayıt önce telefona yazılır, sonra gönderilir ve sunucuda **gerçekten göründüğü
doğrulanınca** kuyruktan çıkar (aynı kayıt iki kez gelirse çift yazılmaz). Üstteki çubuk bekleyenleri
gösterir. İnternetsiz girilen kayıt kendi gününe yazılır; telefon saati ileri ya da 7 günden eski
görünürse sunucu günü kullanılır ve kayda uyarı düşülür.

## Kurulum (sırayla)
1. **Supabase → SQL Editor:** `veritabani/010_plasiyer.sql` (tekrar çalıştırmak güvenli). Yeni tablo yok;
   `erp_fis_satir`'dan (cari-hareket-gonder.ps1 zaten dolduruyor) okur. Çalıştırılmazsa uygulama yine
   çalışır, sadece son satış fiyatı ve tedarikçi gelmez.
2. **Apps Script:** `Code.gs`'in tamamını yapıştır → **Dağıt → Dağıtımları yönet → yeni sürüm**
   (adres değişmesin). `/exec` boş açılınca `build177` görünmeli.
3. **GitHub Pages:** `index.html`, `plasiyer.html`, `hazirla.html`, `sw.js` yüklenir; uygulamada **build 210** görünmeli.
4. **Kullanıcılar:** plasiyerlere **🚚 Plasiyer** (gerekirse maliyet) yetkisi.
5. **Plasiyer → ⚙️ Yönetim:** ayarlar, müşteri atama, gerekirse özel fiyatlar.

## Bilinmesi gerekenler
- **Müşteriye özel fiyat** uygulamada tanımlanır (ERP12'de böyle bir kayıt yok).
- **Siparişler ERP'ye aktarılmaz.** `erp/siparis-aktar.ps1` (Alınan Sipariş, "MOB LNN-") ileride
  `PlasiyerBelge`'yi de okuyacak şekilde bağlanabilir.
- **Maliyet gizliliği (build 209 / build176):** son alış fiyatı kataloğa yalnızca yöneticiye, **💲 Alış Fiyatı**
  ve **🚚 Plasiyer: maliyet** yetkililerine konur; kimliksiz (eski sürüm) telefonlara hiç gitmez.
  Telefonda katalog tektir: yetkisiz biri giriş yapınca ya da çıkış yapılınca telefondaki alış fiyatları
  hemen silinir (internet gerekmez); yetkili girince yeniden iner. Gün sonu listesinde maliyetsiz
  plasiyere maliyet/taban değeri gitmez (sadece "taban altı" işareti).
- **Mal girişte fiyat:** alış fiyatı yetkisi olmayan personelin telefonu fiyatı boş gönderir, **sunucu
  katalogdaki son alıştan doldurur** — ERP'ye aktarılan Excel yine fiyatlıdır. Ekranda alış fiyatı ve
  toplamlar yalnızca yetkiliye görünür. **Mal kabulde fiyatı görmesi gerekenlere 💲 Alış Fiyatı yetkisi ver.**
- Ürün / Stok / Cari Hareketleri ekranları kendi yetkileriyle alış fiyatlarını göstermeye devam eder;
  maliyet gizli kalacaksa o yetkiler de verilmemeli.
- Risk listesi sunucuda 20 dakika önbellekte tutulur.

## 📦 Sipariş Hazırlama (depo) — build 210 / Code.gs build177
Menüde **📦 Sipariş Hazırlama** (`hazirla.html`). Plasiyerin aldığı **siparişler** (araçtan satış değil)
depoda okutularak toplanır. ERP'ye yazmaz; `SiparisHazirlik` sekmesinde durur. Depocu **fiyat görmez**.

| Yetki | Ne yapar |
|---|---|
| **📦 Sipariş Hazırlama (depo)** | Siparişleri hazırlar, sevk fişi basar, teslim eder (stok yetkisi varsa sistem stoğunu da görür) |
| **🚚 Plasiyer Yönetimi** | Ayrıca başkasının hazırlığını devralır, hazır/teslim edilmiş siparişi yeniden açar |

**Akış:** ⏳ Bekleyen → **▶ Hazırlamaya başla** (sipariş o kişiye kilitlenir) → 🔧 Hazırlanıyor →
**✅ Hazır** (koli/paket sayısı) → **🚚 Teslim edildi** (teslim alan; varsayılan plasiyer).
- **Okutma:** barkod okutunca o kalem 1 artar; ürünün diğer barkodu da tanınır, **koli barkodu koli
  çarpanı kadar** sayar. Siparişte olmayan ürün okutulursa kalın sesli hata; istenenden fazlası kırmızı uyarı.
  Kaleme dokununca miktar yazılır ("Tamamı", "Yok"); satırdaki ✓ / ✗ tek dokunuşla tamam / yok.
  "Kalanlar üstte" görünümünde bitenler aşağı iner. İlerleme çubuğu: tam / eksik / fazla.
- **Kayıt:** okutmalar önce telefona yazılır, 3 sn içinde sunucuya gider; internet yoksa telefonda bekler
  ("gönderilmedi"), internet gelince ya da ekran kapanınca gider.
- **Bitirirken** her kalem işaretlenmiş olmalı ("Kalanları yok say" düğmesi var). Eksik/fazla kalemler
  sevk fişinde ve plasiyerin gün sonunda görünür. **Hazırlık notu** plasiyere gider.
- **Bırak:** hazırlayan bırakırsa okuttukları kalır, sipariş "bekleyen"e döner, başkası devam eder.
- **Sevk fişi** (yazdır): müşteri, plasiyer, hazırlayan, koli; kalem kalem istenen / hazırlanan / eksik;
  fiyatsız, imza alanlı. ERP belgesi değildir.
- **İptal:** depo hazırlamaya başladıktan sonra plasiyer siparişi iptal edemez (yöneticiye söyler).
  Hazırlanırken iptal edilen sipariş depoda kırmızı **İPTAL** görünür, hazır yapılamaz.
- **Plasiyer** gün sonunda her siparişin durumunu görür: depoda bekliyor / hazırlanıyor (kim) /
  hazır · N koli / teslim edildi, eksik/fazla kalem sayısı.
- Liste: son 30 günün teslim edilmemiş siparişleri + bugün teslim edilenler; en eski üstte; dakikada bir tazelenir.

## build 213 / Code.gs build179 — net fiyat ve kullanım kolaylığı
- **Net fiyat:** "Son alışlar", "Tedarikçiler" ve müşteriye "son satış" artık **tüm iskontolar (satır + fiş/dip)
  düşülmüş, KDV dahil** birim fiyattır: ERP12 FIS_DETAY'dan (TOPLAM_KDV_MATRAHI + TOPLAM_KDV) / miktar.
  Son alışlarda liste fiyatı ve iskonto oranı da yazar. Ürün penceresinde **son net alış** ve ona göre marj.
  Net bilgisi henüz gelmemiş eski satırlarda "brüt" yazar (iskontosuz).
  Kurulum: Supabase'de `veritabani/011_net_fiyat.sql`, ERP bilgisayarında `C:\Scripts\cari-hareket-gonder.ps1`
  yenisiyle değiştirilir. Program günde bir tüm geçmişi yeniden gönderdiği için eski belgeler de netleşir.
- **Aramada adet kutusu:** her ürünün yanında; adet yaz + Enter → siparişe girer (0 = çıkar), imleç aramaya
  döner, sıradaki ürün yazılır. Siparişteki ürünün adedi kutuda görünür. Adetli ürüne küsurat yazılamaz,
  KG ürüne yazılır.
- **⭐ Sık aldıkları:** arama boşken müşterinin ERP'deki satışlarından en sık aldığı ürünler hazır gelir
  (son net fiyat, tarih, kaç kez, ortalama adet). **🛒 Siparişteki** süzgeci.
- **Stok:** 📦 Stok Görme yetkisi olan plasiyer aramada ve kalemde stoğu görür; stoktan fazlasına uyarı.
- Arama kutusu kaydırınca üstte kalır; altta kalem ve toplam adet.
- Not: Maliyet / taban hâlâ katalogdaki son alış fiyatıyla (STOK.SON_ALIS_FIYAT) hesaplanır.
