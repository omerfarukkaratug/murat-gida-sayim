-- ============================================================
-- Stoğa etki etmeyen belge satırları (irsaliyeden kesilen fatura gibi).
-- 011_net_fiyat.sql'den SONRA çalıştırılır; tekrar çalıştırmak güvenlidir.
--
-- cari-hareket-gonder.ps1 artık cariye kesilmiş, stoğa etki ETMEYEN belgelerin (FIS_TURU.GIRIS = 0)
-- satırlarını da gönderir (giris = 0). Eskiden bu faturaların içi cari ekstresinde "ürün satırı yok"
-- görünüyordu. Bu satırlar:
--   • fatura detayında (fis_detay) GÖRÜNÜR,
--   • stok hareketlerinde ve carinin stok hareketlerinde SAYILMAZ (mal irsaliyede zaten sayıldı),
--   • plasiyerin son satış / son alış fiyatında kullanılır; aynı gün aynı malın irsaliyesi + faturası
--     tek alış/satış sayılır ("kaç kez" çift artmaz).
-- ============================================================

create index if not exists erp_fis_satir_fis_giris on erp_fis_satir (kaynak, fis_id, giris);

-- Bir ürünün stok hareketleri: yalnızca stoğa etki eden satırlar (giris <> 0).
create or replace function stok_hareket(p_stok_kodu text, p_barkod text, p_gun integer default 90, p_limit integer default 500)
returns jsonb language sql stable as $$
  with s as (
    select (case when coalesce(p_gun, 0) > 0 then (date_trunc('day', now() at time zone 'Europe/Istanbul') - make_interval(days => p_gun)) at time zone 'Europe/Istanbul' end) as bas
  ), b as (
    select h.tarih, h.tur_ad, h.belge_no, h.cari_ad, h.miktar * (case when h.giris < 0 then -1 else 1 end) as miktar,
           h.birim_fiyat, coalesce(h.tutar, h.miktar * h.birim_fiyat) as tutar, h.fis_id, h.kaynak, h.detay_id
      from erp_fis_satir h, s
     where (case when coalesce(p_stok_kodu, '') <> '' then h.stok_kodu = p_stok_kodu else h.barkod = coalesce(p_barkod, '') end)
       and h.giris <> 0
       and (s.bas is null or h.tarih >= s.bas)
  ), p as (
    select (g.gun::timestamp + time '23:59') at time zone 'Europe/Istanbul' as tarih, 'Perakende (kasa)'::text as tur_ad,
           g.adet || ' satır' as belge_no, ''::text as cari_ad, g.miktar,
           case when g.miktar <> 0 then round(abs(g.tutar / g.miktar), 2) end as birim_fiyat, abs(g.tutar) as tutar,
           null::bigint as fis_id, g.kaynak, 0::bigint as detay_id
      from erp_stok_perakende g, s
     where coalesce(p_stok_kodu, '') <> '' and g.stok_kodu = p_stok_kodu
       and (s.bas is null or (g.gun::timestamp + time '23:59') at time zone 'Europe/Istanbul' >= s.bas)
  ), t as (select * from b union all select * from p)
  select jsonb_build_object(
    'status', 'ok',
    'adet', (select count(*) from t),
    'giris', (select coalesce(sum(miktar), 0) from t where miktar > 0),
    'cikis', (select coalesce(-sum(miktar), 0) from t where miktar < 0),
    'perakende', (select coalesce(-sum(miktar), 0) from p),
    'satirlar', coalesce((select jsonb_agg(jsonb_build_array(
                    to_char(tarih at time zone 'Europe/Istanbul', 'DD.MM.YYYY'), tur_ad, belge_no, cari_ad, miktar, birim_fiyat, tutar, fis_id, kaynak)
                    order by tarih desc, fis_id desc nulls first, detay_id)
                   from (select * from t order by tarih desc, fis_id desc nulls first, detay_id limit greatest(coalesce(p_limit, 500), 1)) x), '[]'::jsonb),
    'sonVeri', (select to_char(max(guncelleme) at time zone 'Europe/Istanbul', 'DD.MM.YYYY HH24:MI') from erp_fis_satir)
  )
$$;

-- Carinin stok hareketleri: yalnızca stoğa etki eden satırlar (giris <> 0).
create or replace function cari_stok(p_cari_kod text, p_gun integer default 90, p_limit integer default 500)
returns jsonb language sql stable as $$
  with k as (
    select max(kaynak) as kaynak from erp_fis_satir where cari_kod = coalesce(p_cari_kod, '')
  ), d as (
    select h.* from erp_fis_satir h, k
     where h.cari_kod = coalesce(p_cari_kod, '') and h.kaynak = k.kaynak and h.giris <> 0
       and (coalesce(p_gun, 0) <= 0 or h.tarih >= (date_trunc('day', now() at time zone 'Europe/Istanbul') - make_interval(days => p_gun)) at time zone 'Europe/Istanbul')
  )
  select jsonb_build_object(
    'status', 'ok',
    'kaynak', (select kaynak from k),
    'adet', (select count(*) from d),
    'girisTutar', (select coalesce(sum(coalesce(tutar, miktar * coalesce(birim_fiyat, 0))), 0) from d where giris > 0),
    'cikisTutar', (select coalesce(sum(coalesce(tutar, miktar * coalesce(birim_fiyat, 0))), 0) from d where giris < 0),
    'satirlar', coalesce((select jsonb_agg(jsonb_build_array(
                    to_char(tarih at time zone 'Europe/Istanbul', 'DD.MM.YYYY'), tur_ad, belge_no, stok_kodu, barkod, urun_adi,
                    miktar * (case when giris < 0 then -1 else 1 end), birim_fiyat, coalesce(tutar, miktar * birim_fiyat), fis_id) order by tarih desc, fis_id desc, detay_id)
                   from (select * from d order by tarih desc, fis_id desc, detay_id limit greatest(coalesce(p_limit, 500), 1)) x), '[]'::jsonb)
  )
$$;

-- Müşteriye son satış (NET, KDV dahil): stoğa etki etmeyen faturalar da dahil (giris <= 0).
-- Aynı gün aynı ürünün irsaliyesi + faturası tek satış sayılır.
-- satirlar r: [stok kodu, barkod, fiyat, tarih, miktar, kaç kez (gün), ortalama miktar, net mi (1/0)]
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
    select distinct on (d.anahtar) d.stok_kodu, d.barkod, d.fiyat, d.net, d.tarih, d.miktar, g.kez, g.ort
      from d join g on g.anahtar = d.anahtar
     order by d.anahtar, d.tarih desc, d.detay_id desc
  )
  select jsonb_build_object(
    'status', 'ok',
    'cariKod', coalesce(p_cari_kod, ''),
    'satirlar', coalesce((select jsonb_agg(jsonb_build_array(stok_kodu, barkod, round(fiyat, 2),
                    to_char(tarih at time zone 'Europe/Istanbul', 'DD.MM.YYYY'), miktar, kez, round(ort, 2), case when net then 1 else 0 end) order by kez desc, tarih desc) from s), '[]'::jsonb),
    'sonVeri', (select to_char(max(guncelleme) at time zone 'Europe/Istanbul', 'DD.MM.YYYY HH24:MI') from erp_fis_satir)
  )
$$;

-- Ürünün alışları / tedarikçileri (NET, KDV dahil): stoğa etki etmeyen alış faturaları da dahil (giris >= 0).
-- Aynı gün aynı tedarikçiden aynı miktar (irsaliye + faturası) tek alış sayılır.
create or replace function plasiyer_urun_alis(p_stok_kodu text, p_barkod text, p_limit integer default 8)
returns jsonb language sql stable as $$
  with d0 as (
    select tarih, cari_kod, cari_ad, coalesce(net_fiyat, birim_fiyat) as fiyat, birim_fiyat, (net_fiyat is not null) as net, miktar, belge_no, detay_id, giris
      from erp_fis_satir
     where fis_turu in (1, 5) and giris >= 0 and coalesce(net_fiyat, birim_fiyat, 0) > 0
       and ((coalesce(p_stok_kodu, '') <> '' and stok_kodu = p_stok_kodu)
         or (coalesce(p_stok_kodu, '') = '' and coalesce(p_barkod, '') <> '' and barkod = p_barkod))
  ), d as (
    select distinct on (cari_kod, (tarih at time zone 'Europe/Istanbul')::date, miktar) *
      from d0 order by cari_kod, (tarih at time zone 'Europe/Istanbul')::date, miktar, net desc, giris asc, detay_id desc
  ), t as (
    select distinct on (cari_kod) cari_kod, cari_ad, fiyat, tarih,
           count(*) over (partition by cari_kod) as kez
      from d order by cari_kod, tarih desc, detay_id desc
  )
  select jsonb_build_object(
    'status', 'ok',
    'alislar', coalesce((select jsonb_agg(jsonb_build_array(to_char(tarih at time zone 'Europe/Istanbul', 'DD.MM.YYYY'), cari_kod, cari_ad,
                    round(fiyat, 2), miktar, belge_no, round(birim_fiyat, 2), case when net then 1 else 0 end) order by tarih desc, detay_id desc)
                   from (select * from d order by tarih desc, detay_id desc limit greatest(coalesce(p_limit, 8), 1)) x), '[]'::jsonb),
    'tedarikciler', coalesce((select jsonb_agg(jsonb_build_array(cari_kod, cari_ad, round(fiyat, 2),
                    to_char(tarih at time zone 'Europe/Istanbul', 'DD.MM.YYYY'), kez) order by tarih desc) from t), '[]'::jsonb),
    'sonNet', (select round(fiyat, 2) from d where net order by tarih desc, detay_id desc limit 1)
  )
$$;

alter function stok_hareket(text, text, integer, integer) security definer set search_path = public, extensions;
alter function cari_stok(text, integer, integer)          security definer set search_path = public, extensions;
alter function plasiyer_son_fiyat(text, integer)          security definer set search_path = public, extensions;
alter function plasiyer_urun_alis(text, text, integer)    security definer set search_path = public, extensions;
revoke execute on function stok_hareket(text, text, integer, integer) from public;
revoke execute on function cari_stok(text, integer, integer) from public;
revoke execute on function plasiyer_son_fiyat(text, integer) from public;
revoke execute on function plasiyer_urun_alis(text, text, integer) from public;
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke execute on function stok_hareket(text, text, integer, integer), cari_stok(text, integer, integer), plasiyer_son_fiyat(text, integer), plasiyer_urun_alis(text, text, integer) from anon, authenticated';
  end if;
end $$;
