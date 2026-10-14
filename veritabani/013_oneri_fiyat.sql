-- ============================================================
-- Müşteriye ÖNERİLEN satış fiyatı (müşteri müşteri, ürün ürün).
-- 012_fatura_satirlari.sql'den SONRA çalıştırılır; tekrar çalıştırmak güvenlidir.
--
-- Mantık: bu müşteriye bu ürünü geçmişte hangi KÂR ORANIYLA sattık?
--   oran = satış fiyatı / o satış günündeki son alış fiyatı   (ikisi de net, KDV dahil)
--   Son 6 satışın oranının ortalaması alınır.
--   Öneri = EN SON alış fiyatı × oran   → mal zamlı geldiyse öneri de aynı oranla artar.
-- Ürünün bu müşteriye satış geçmişi yoksa müşterinin genel oranı (ürün oranlarının ortancası) döner.
-- Uygulama telefona yalnızca öneri fiyatını gönderir; oran ve maliyet sadece maliyet yetkilisine gider.
--
-- plasiyer_son_fiyat satırları r:
--   [0 stok kodu, 1 barkod, 2 son fiyat, 3 tarih, 4 miktar, 5 kaç kez, 6 ort. miktar, 7 net mi,
--    8 ortalama oran (yoksa null), 9 güncel alış (net, KDV dahil; yoksa null), 10 oranın dayandığı satış sayısı]
-- Ayrıca 'genelOran': müşterinin tüm ürünlerdeki oranlarının ortancası.
-- ============================================================

create index if not exists erp_fis_satir_alis on erp_fis_satir (stok_kodu, tarih) where fis_turu in (1, 5);

create or replace function plasiyer_son_fiyat(p_cari_kod text, p_gun integer default 365)
returns jsonb language sql stable as $$
  with d0 as (
    select case when stok_kodu <> '' then stok_kodu else barkod end as anahtar, stok_kodu, barkod,
           coalesce(net_fiyat, birim_fiyat) as fiyat, (net_fiyat is not null) as net, tarih, miktar, detay_id, giris
      from erp_fis_satir
     where cari_kod = coalesce(p_cari_kod, '') and fis_turu in (2, 6, 12) and giris <= 0
       and coalesce(net_fiyat, birim_fiyat, 0) > 0 and miktar > 0
       and (coalesce(p_gun, 0) <= 0 or tarih >= now() - make_interval(days => p_gun))
  ), d as (   -- gün başına tek satış: faturalı (net) satır önce
    select distinct on (anahtar, (tarih at time zone 'Europe/Istanbul')::date) *
      from d0 order by anahtar, (tarih at time zone 'Europe/Istanbul')::date, net desc, giris desc, detay_id desc
  ), g as (
    select anahtar, count(*) as kez, avg(miktar) as ort from d group by anahtar
  ), s as (
    select distinct on (d.anahtar) d.anahtar, d.stok_kodu, d.barkod, d.fiyat, d.net, d.tarih, d.miktar, g.kez, g.ort
      from d join g on g.anahtar = d.anahtar
     order by d.anahtar, d.tarih desc, d.detay_id desc
  ), son6 as (   -- her ürünün son 6 satışı
    select * from (select d.*, row_number() over (partition by anahtar order by tarih desc, detay_id desc) as sira from d) x where sira <= 6
  ), oranlar as (  -- satış günündeki son alış (o gün net varsa net) → oran
    select o.anahtar, o.fiyat / a.alis as oran
      from son6 o
      cross join lateral (
        select coalesce(h.net_fiyat, h.birim_fiyat) as alis
          from erp_fis_satir h
         where h.fis_turu in (1, 5) and h.giris >= 0 and coalesce(h.net_fiyat, h.birim_fiyat, 0) > 0
           and (case when o.stok_kodu <> '' then h.stok_kodu = o.stok_kodu else h.barkod = o.barkod end)
           and h.tarih <= o.tarih + interval '1 day'
           and (h.tarih at time zone 'Europe/Istanbul')::date <= (o.tarih at time zone 'Europe/Istanbul')::date
         order by (h.tarih at time zone 'Europe/Istanbul')::date desc, (h.net_fiyat is not null) desc, h.detay_id desc
         limit 1
      ) a
  ), oran as (    -- aşırı uçlar (veri hatası: 0,5 altı / 4 üstü) sayılmaz
    select anahtar, avg(oran) as oran, count(*) as adet from oranlar where oran between 0.5 and 4 group by anahtar
  ), guncel as (  -- ürünün EN SON alışı (o gün net varsa net)
    select s.anahtar, a.alis
      from s
      cross join lateral (
        select coalesce(h.net_fiyat, h.birim_fiyat) as alis
          from erp_fis_satir h
         where h.fis_turu in (1, 5) and h.giris >= 0 and coalesce(h.net_fiyat, h.birim_fiyat, 0) > 0
           and (case when s.stok_kodu <> '' then h.stok_kodu = s.stok_kodu else h.barkod = s.barkod end)
         order by (h.tarih at time zone 'Europe/Istanbul')::date desc, (h.net_fiyat is not null) desc, h.detay_id desc
         limit 1
      ) a
  )
  select jsonb_build_object(
    'status', 'ok',
    'cariKod', coalesce(p_cari_kod, ''),
    'satirlar', coalesce((select jsonb_agg(jsonb_build_array(s.stok_kodu, s.barkod, round(s.fiyat, 2),
                    to_char(s.tarih at time zone 'Europe/Istanbul', 'DD.MM.YYYY'), s.miktar, s.kez, round(s.ort, 2), case when s.net then 1 else 0 end,
                    round(o.oran, 4), round(gu.alis, 2), coalesce(o.adet, 0)) order by s.kez desc, s.tarih desc)
                 from s left join oran o on o.anahtar = s.anahtar left join guncel gu on gu.anahtar = s.anahtar), '[]'::jsonb),
    'genelOran', (select round((percentile_cont(0.5) within group (order by oran))::numeric, 4) from oran),
    'sonVeri', (select to_char(max(guncelleme) at time zone 'Europe/Istanbul', 'DD.MM.YYYY HH24:MI') from erp_fis_satir)
  )
$$;

-- Satış geçmişi OLMAYAN ürün için güncel alış (genel oranla öneri hesaplanır). Yalnızca sunucu kullanır.
create or replace function plasiyer_guncel_alis(p_stok_kodu text, p_barkod text)
returns jsonb language sql stable as $$
  select jsonb_build_object('status', 'ok', 'alis', (
    select round(coalesce(h.net_fiyat, h.birim_fiyat), 2)
      from erp_fis_satir h
     where h.fis_turu in (1, 5) and h.giris >= 0 and coalesce(h.net_fiyat, h.birim_fiyat, 0) > 0
       and ((coalesce(p_stok_kodu, '') <> '' and h.stok_kodu = p_stok_kodu)
         or (coalesce(p_stok_kodu, '') = '' and coalesce(p_barkod, '') <> '' and h.barkod = p_barkod))
     order by (h.tarih at time zone 'Europe/Istanbul')::date desc, (h.net_fiyat is not null) desc, h.detay_id desc
     limit 1))
$$;

alter function plasiyer_son_fiyat(text, integer)   security definer set search_path = public, extensions;
alter function plasiyer_guncel_alis(text, text)    security definer set search_path = public, extensions;
revoke execute on function plasiyer_son_fiyat(text, integer) from public;
revoke execute on function plasiyer_guncel_alis(text, text) from public;
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke execute on function plasiyer_son_fiyat(text, integer), plasiyer_guncel_alis(text, text) from anon, authenticated';
  end if;
end $$;
