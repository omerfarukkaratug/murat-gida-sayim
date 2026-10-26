# 💵 Kasa Tahsilat

Kasadan veresiye mal alıp ay sonu ödeyen carilerin (yemekhane vb.) tahsilatı kasada uygulamadan girilir, makbuz basılır.

## Kurallar
- Tahsilat yalnız **elle** girilir; uygulama kendiliğinden tahsilat oluşturmaz.
- **ERP'ye yazılmaz.** Her tahsilatta muhasebeye e-posta gider (adres: `TAHSILAT_EMAIL` ayarı, yoksa mal mailiyle aynı).
  Muhasebe ERP'ye kasa tahsilatı olarak işler. ERP'de aynı carinin aynı tutarlı tahsilatı görününce (saatte bir) kayıt
  kendiliğinden "ERP'de" olur; muhasebe "✔ ERP'ye işlendi" ile elle de işaretleyebilir.
- Makbuzdaki bakiye = ERP bakiyesi − ERP'ye henüz işlenmemiş tahsilatlar (bakiye iki kez düşülmez).
- 1 günden eski, ERP'ye işlenmemiş tahsilatlar **Günün Özeti**'nde görünür.
- İptal: aynı gün makbuzu kesen ya da her zaman yönetici; neden zorunlu, muhasebeye "İPTAL" maili gider.

## Yetkiler
- Kasiyere Yönetici Paneli → Kullanıcılar'da **💵 Kasa Tahsilat** yetkisi verilir.
- Yönetici: Kasa Tahsilat → **🔐 Cari yetkileri** → personeli seç → tahsilat alabileceği carileri ekle → Kaydet.
  Kasiyer yalnız bu carileri, onların hesap hareketlerini ve kendi makbuzlarını görür.
- **Rapor** yetkisi olan (muhasebe) bütün tahsilatları görür, "ERP'ye işlendi" işaretler.

## Kasa bilgisayarında termal yazıcıdan makbuz
Yazıcının ağda paylaşılması gerekmez: uygulama kasa bilgisayarında Chrome'da açılır, makbuz oradan basılır.
1. Termal yazıcı kasa bilgisayarında Windows yazıcısı olarak kurulu olmalı (deneme sayfası basabilmeli).
2. Chrome'da `app.krtsaha.com` aç, kasiyer olarak giriş yap.
3. İlk makbuzda yazdır penceresinde: Hedef = termal yazıcı, Kenar boşlukları = **Yok**, Ölçek = Varsayılan. Chrome bunu hatırlar.
4. Tek tıkla (pencere açmadan) basması için: termal yazıcıyı Windows'ta **varsayılan yazıcı** yap, Chrome kısayoluna sağ tık →
   Özellikler → Hedef'in sonuna ` --kiosk-printing` ekle (önünde boşluk), Chrome'u tamamen kapatıp bu kısayoldan aç.
