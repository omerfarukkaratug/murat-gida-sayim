# 🚚 Plasiyer (saha satış) — build 216 / Code.gs build181

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

## build 216 / Code.gs build181 — bekleyen sipariş, kâr gizleme, çeşitler

- **Bekleyen sipariş:** Depocu "Hazır" derken eksik kalem varsa "⏳ Eksikleri BEKLEYEN SİPARİŞ yap" kutusu çıkar
  (varsayılan işaretli). Eksikler `B<sipariş no>` numaralı yeni bir belgeye (çeşit `bekleyen`) yazılır;
  hazırlama listesine "⏳ BEKLEYEN" etiketiyle düşer, mal gelince normal sipariş gibi hazırlanır.
  - Plasiyer müşteri penceresinde, sipariş bandında ve ürün aramasında "⏳ bekleyende N" görür (çift yazmasın diye).
  - Gün sonunda ayrı gösterilir, toplamlara girmez. **Primde sayılmaz** (asıl sipariş zaten sayıldı).
  - Plasiyer kendi bekleyenini, hazırlık başlamadıysa her gün iptal edebilir.
- **Kâr gizli:** Sipariş ekranında marj/kâr artık görünmez. Maliyet yetkilisi alttaki "👁 Kâr" düğmesine
  **basılı tutunca** görünür, bırakınca kaybolur. Ürün penceresinde maliyet/tedarikçi bölümü kapalı gelir
  ("🔒 Maliyet, kâr ve tedarikçiler" — dokununca açılır). Taban altı fiyat uyarısında sayı yazmaz.
  Plasiyerin hiç görmemesi için `plasiyer_maliyet` yetkisi verilmez.
- **Çeşitler:** Siparişteki ürünün altında "🎨 N çeşit daha" — aynı fiyat, aynı boy (2.5 LT vb.) ve adın baştaki
  sözcükleri (marka + ürün) aynı olan ürünler. Pencerede her çeşide adet yazılır ya da "Hepsinden" ile hepsine aynı adet.

## build 219 — sipariş ekranı yenilendi

- **Üstte müşteri:** cari adı + rozetler (risk, vade geçmiş / bakiye, ⏳ bekleyen). Dokununca müşteri bilgisi,
  risk nedenleri ve **💵 Tahsilat Notu** açılır; sipariş arkada açık kalır.
- **İki sekme:** ➕ Ürün Ekle (en üstte arama + 📷, altında Sık aldıkları / Özel fiyatlı, satırda adet kutusu) ve
  🧺 Sepet (sayaçlı). Sepet tek satırlık liste: ad · miktar × fiyat · tutar; uyarılar satırın altında küçük yazı.
- **Sepette ürüne dokun:** düzenleme penceresi — −/+ ve miktar, fiyat, Liste / Özel / Son satış düğmeleri,
  🎨 çeşitler, ℹ️ ürün bilgisi, 🗑 Sil, Tamam. Basılı tutmak yine ürün bilgisini açar.
- Alt çubuk tek satır: kalem/adet, toplam, 👁 Kâr (basılı tut), 💾 Kaydet. Yarım sipariş sepet sekmesinde açılır.

## build 220 / Code.gs build182 — müşteriye özel ÖNERİ fiyatı (013_oneri_fiyat.sql)

- Siparişe ürün **raf (liste) fiyatıyla** girer; altında yeşil **💡 öneri** fiyatı görünür (arama satırında, sepette,
  düzenleme penceresinde "💡 Önerilen" düğmesi — dokununca fiyat o olur).
- Hesap (müşteri müşteri, ürün ürün): bu müşteriye bu ürünün son 6 satışında **satış fiyatı ÷ o günkü son alış**
  oranlarının ortalaması × **en son alış fiyatı** (net, iskontolar düşülmüş, KDV dahil). Mal zamlı geldiyse öneri de
  aynı oranla artar. 10 kuruşa yukarı yuvarlanır. 0,5–4 dışındaki oranlar veri hatası sayılıp atlanır.
- Ürün bu müşteriye hiç satılmadıysa: müşterinin genel oranı (ürün oranlarının ortancası) × son alış.
- Gizlilik: telefona yalnız öneri fiyatı gider; oran ve alış fiyatı sadece `plasiyer_maliyet` yetkilisine
  (o da yalnız 👁 Kâr basılıyken görür). Öneri taban fiyatın altındaysa yine yazılamaz.
- Kurulum: Supabase'de 011 → 012 → **013** sırayla; ardından Code.gs build182.

## build 221 / Code.gs build183 — güvenli hazırlama, kontrol-teslim, SEVKİYAT

Akış: bekliyor → hazırlanıyor → **hazır** → (başka biri kontrol eder) → **sevkiyat** → yolda → **müşteriye teslim edildi**.

- **Okutmadan işaretleme:** hiç okutulmamış kaleme ✓ / miktar yazılırsa neden sorulur (barkod okunmuyor,
  barkodsuz, koli içinde, dökme, diğer). Kalem "✋ elle" görünür (fiş, kontrol, rapor). Sunucu nedensiz okutmasız
  kalemle "Hazır"a izin vermez (eski sürüm telefon gönderirse geçmişe "kontrol yapılamadı" düşer).
- **↶ Son okutmayı geri al** düğmesi. Elle yazılan miktar siparişin %10'undan fazlaysa onay ister.
- **Stok uyarısı:** stoğu yetmeyebilecek kalemler listede "⚠️ N kalemde stok az", siparişte en üstte bant
  (stok yetkisi yoksa sayı gösterilmez).
- **Kontrol ve teslim:** hazırlayan kendi siparişini teslim EDEMEZ. Başka biri "🔍 Kontrol et ve teslim al" ile
  her kalemi yeniden okutur; hepsi hazırlananla tutar ve koli sayısı aynıysa teslim alır → Sevkiyat.
  Fark varsa "⚠️ Fark var" → sipariş açıklamayla hazırlayana geri döner. Kontrolsüz teslim yalnız yönetimde.
- **🚚 Sevkiyat bölümü:** 🚛 Yola çıktı → 🏁 Müşteriye teslim edildi (teslim alan kişi adı zorunlu) /
  ⚠️ Teslim edilemedi (neden). Teslim edilen sipariş yeniden açılamaz. Plasiyer durumu kendi ekranında görür.
- **Yeni yetki `sevkiyat`** (şoför): yalnız Hazır (kontrol) + Sevkiyat + Teslim edildi bölümleri.
- **🕘 Geçmiş:** her adım kim / ne zaman (başla, devral, bırak, hazır, kontrol, fark, yola çıktı, teslim…).
- **📊 Rapor (yönetim):** ay içinde kişi başı sipariş, kalem, ortalama süre, eksik/fazla, elle, kontrol farkı;
  sevkiyatçı başına müşteriye teslim sayısı.
- Sheets: SiparisHazirlik'e "Ek (JSON)" sütunu kendiliğinden eklenir.

## build 222 / Code.gs build184 — 🍲 Düğün / Mevlüt listesi, ürün notu

- Siparişte **Ürün Ekle → 🍲 Düğün / Mevlüt**: kaç kişilik, ne için (düğün/mevlüt/taziye), çorba (yayla /
  mercimek / ezogelin), ana yemek (etli nohut / kuru fasulye / keşkek / et kavurma / tavuk — çoklu),
  pilav (pirinç-kabune / bulgur), tatlı (irmik helvası / zerde / sütlaç), salata (söğüş / turşu / cacık — çoklu),
  ayran, ekmek, yemek yağı (sıvı / tereyağı / yarı yarıya), et-tavuk eklensin mi (varsayılan hayır),
  tek kullanımlık servis, pay/fire %.
- Kişi başı ortalama × kişi × (1 + pay) → malzeme toplamı; katalogdan ürün seçilir (önce bu telefonda o malzeme
  için en son seçilen, sonra müşterinin daha önce aldığı, sonra en büyük paket / dökme). Adet = toplam ÷ paket
  boyu (adındaki 5 KG, 500 GR, 5 LT, 30lu); KG birimli üründe kg. Paket boyu adda yoksa uyarı.
- Listede: 🔁 ürünü değiştir, adet değiştir, ✕ çıkar, 📝 not → "Sepete ekle". Sipariş notuna menü özeti yazılır.
- **Ürün notu:** sepette ürüne dokun → "📝 Ürün notu". Depo hazırlarken ve sevk fişinde görür.
- **Yönetim → 🍲 kişi başı miktarlar:** her yemeğin malzeme miktarı ve varsayılan pay değiştirilebilir
  (Script Properties: PLASIYER_MENU). Başlangıç: pirinç pilavı 70 g, irmik 15 g, nohut/fasulye 40 g …
  Eski düğün faturaları gelince bu değerler onlara göre güncellenecek.

## build 223 — Düğün / Mevlüt oranları faturalardan

Aşçı Fatih Sapan'ın Ağustos–Ekim 2026 faturaları (MGA…238, 267/268, 270, 281, 286, 320, 365) ve Yaylabel
"Düğün & Mevlüt Yemek Organizasyonu" formu esas alındı. Kişi sayısı faturada yok; **irmik 15 kg = 1000 kişi**
(kişi başı 15 g) kabul edildi. 1000 kişilik çıkan liste faturalarla örtüşür: pirinç 75 kg, fasulye 30 + nohut 4 kg,
irmik 15, şeker 30, kunar ~0,35, tereyağı ~19 kg, süzme yoğurt 10 kg, salça 4,5 kg, ayçiçek 5 lt, tuz 3×3 kg,
karabiber 0,25, toz biber 0,15, nane 0,15, limon tuzu 0,1 kg, un 5 kg, yumurta 15'li, turşu 3×15 kg,
bardak su 14×72, damacana 15, köpük tabak 10×100, kaşık 10×100, söğüş tabağı 3×100, masa kağıdı 12 kg,
ıslak mendil 20×56, sızdırmaz kap 2×100, karton tuz 18, kömür 12 kg, ispirto 3, temizlik seti, eldiven, çöp poşeti.
Varsayılan menü: yayla çorbası, etli kuru fasulye, pirinç pilavı, kunarlı irmik helvası, turşu, tereyağı; pay %0.
Yeni soru grupları: İçecek (bardak su, damacana, ayran, çay), Servis malzemesi, Mutfak ve temizlik, Tuz-baharat.
Ürün eşlemesi ERP adlarına göre (BALDO PIRINC KG, OBA IRMIK KG, GURTUZ, K KUNAR ICI, NAZLI BARDAK SU 72 LI …);
müşterinin daha önce aldığı ürün önce seçilir. "72 LI / 56 LI" paket adedi düzgün okunuyor.
- build 224: Tuz ve baharat'a kimyon (0,1 g) ve limon suyu (1 ml) eklendi (varsayılan seçili); servis malzemesinde
  5 gözlü (varsayılan) ve 3 gözlü tabldot ayrı seçenek; mutfak ve temizlikte tek kullanımlık önlük (1000 kişiye 10 adet).
- build 225: Düğün/Mevlüt listesi **reyon reyon** (bakliyat-pirinç, un-şeker-irmik, yağlar, salça-turşu-sos,
  baharat-tuz-kuruyemiş, süt ürünleri-yumurta, su-çay, manav, ekmek, et, ambalaj-servis, temizlik-mutfak);
  sepete ve depoya bu sırayla gider. Sipariş kalemleri depoya artık sepetteki sırayla gider (eskiden tersi).
- build 226: Yağlar ayrı grup (tereyağı, sıvı yağ 5 ml, margarin 3 g — üçü varsayılan seçili; yemek yağı tereyağı →
  sıvı → margarin sırasıyla çözülür). Baharatlar tek tek (tuz, karabiber, toz biber, pul biber, kimyon, limon suyu).
  Temizlik ayrı ayrı (krem, bulaşık det., ovma tozu, tel, sünger, bulaşık eldiveni). Nohut ayrı seçenek ("az", 4 g).
  Liste satırı: ürün + SATIR TUTARI; − miktar + (dökmede 0,5 kg adım) × birim fiyat; 💡 öneri fiyatına tek dokunuş;
  yazarken tutar ve toplam anında değişir; değiştirilen fiyat sepette taban kontrolünden geçer.

## build 228 / Code.gs build186 — iskontolu son NET alış maliyet bazı, prim plasiyere (015_son_net_alis.sql)
- Maliyet / taban / öneri artık ERP'deki son alış faturasının iskontolu NET fiyatından (KDV dahil) hesaplanır; yoksa eski "Alış Fiyatı + KDV".
- `son_net_alis_harita()` (015) her katalog aktarımında Katalog'un 14. sütununa ("Son Net Alış") yazılır; yetkisiz kullanıcıya gitmez.
- Yönetici, plasiyeri atanmış bir müşteriye kayıt girerse belge/tahsilat o plasiyer adına yazılır (prim onun), uyarı sütununa "giren: X".

## build 229 / Code.gs build187 — telefon şifre saklamaz (oturum anahtarı)
- Girişte sunucu HMAC imzalı oturum anahtarı verir (`tk1.<bitiş>.<şifre izi>.<imza>`, gizli `OTURUM_SIRRI`); telefon şifre yerine bunu saklar, tüm istekler (çerçeveler dahil) bununla gider.
- 30 gün geçerli, telefon kullanıldıkça haftada bir sessizce yenilenir. Şifre değişince / kullanıcı pasife alınınca eski anahtarlar çalışmaz.
- Eski telefonlarda düz saklanan şifre ilk internet bağlantısında sessizce anahtara çevrilir (yeniden giriş gerekmez).
- Çevrimdışı giriş şifrenin SHA-256 özetiyle yapılır; artık "Çıkış"tan sonra da çevrimdışı giriş çalışır.
- Yönetim → Güvenlik: "🚪 Tüm telefonlardaki oturumları kapat" (kaybolan telefon / ayrılan personel). 2 dk içinde herkes yeniden girer.
- Eski Code.gs ile de çalışır (anahtar gelmezse eskisi gibi).
