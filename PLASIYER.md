# 🚚 Plasiyer (saha satış) — build 209 / Code.gs build176

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
   (adres değişmesin). `/exec` boş açılınca `build176` görünmeli.
3. **GitHub Pages:** `index.html`, `plasiyer.html`, `sw.js` yüklenir; uygulamada **build 209** görünmeli.
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
