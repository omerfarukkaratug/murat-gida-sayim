-- ============================================================
-- HIZ (3): Cari ve Plasiyer ekranları. 017'den sonra çalıştırılır; tekrar çalıştırmak güvenlidir. Veriye dokunmaz.
--
--  1) "ERP verisi" saati için max(guncelleme) erp_cari_hareket'i baştan sona okuyordu: indeks.
--  2) _vade_acik (cari Vade sekmesi, ödeme alışkanlığı ve Vade Raporu'ndaki her satır): "tek cari mi bütün
--     cariler mi" koşulu indeksi kapatıyordu; HER cari için bütün cari hareketleri okunuyordu. İki kola bölündü.
--  3) plasiyer_son_fiyat (plasiyerde müşteri açılınca son fiyatlar / öneri fiyatı): her ürün için alış fiyatı
--     ararken "stok kodu mu barkod mu" CASE'i yüzünden bütün fatura satırları taranıyordu. İki kola bölündü.
--  Sonuçlar birebir aynı. (Denemede: müşteri son fiyatları ~4,5 sn → milisaniyeler; Vade ~110 ms → birkaç ms.)
-- ============================================================

create index if not exists erp_cari_hareket_guncelleme on erp_cari_hareket (guncelleme);

create or replace function _vade_acik(p_cari_kod text)
returns table (cari_kod text, cari_ad text, yon text, tarih date, vade date, tur text, belge_no text, tutar numeric, acik numeric, fis_id bigint)
language plpgsql stable as $$
#variable_conflict use_column
begin
  -- Tek cari (Vade sekmesi, ödeme alışkanlığı): yalnız o carinin satırları indeksle okunur.
  if p_cari_kod is not null then
    return query
with k as (
    select h.cari_kod, max(h.kaynak) as kaynak from erp_cari_hareket h
     where h.cari_kod <> '__PERAKENDE__' and h.cari_kod = p_cari_kod
       and coalesce(h.doviz, '') in ('', 'TRY', 'TL')
     group by h.cari_kod
  ), t as (
    select h.* from erp_cari_hareket h join k on k.cari_kod = h.cari_kod and k.kaynak = h.kaynak
     where h.cari_kod = p_cari_kod and coalesce(h.doviz, '') in ('', 'TRY', 'TL')
  ), b as (
    select cari_kod, max(cari_ad) as cari_ad, sum(borc - alacak) as bakiye from t group by cari_kod
  ), s as (
    select t.cari_kod, b.cari_ad, case when b.bakiye > 0 then 'alacak' else 'borc' end as yon,
           (t.tarih at time zone 'Europe/Istanbul')::date as tarih,
           coalesce(t.vade, (t.tarih at time zone 'Europe/Istanbul')::date) as vade,
           t.tur, t.belge_no, case when b.bakiye > 0 then t.borc else t.alacak end as tutar, abs(b.bakiye) as kalan,
           t.fis_id, t.detay_id
      from t join b on b.cari_kod = t.cari_kod
     where abs(b.bakiye) >= 0.01 and (case when b.bakiye > 0 then t.borc else t.alacak end) > 0
  ), c as (
    select s.*, sum(tutar) over (partition by cari_kod order by tarih desc, detay_id desc) - tutar as onceki from s
  )
  select c.cari_kod, c.cari_ad, c.yon, c.tarih, c.vade, c.tur, c.belge_no, c.tutar, least(tutar, kalan - onceki) as acik, fis_id
    from c where kalan - onceki > 0.004;
  else
    return query
with k as (
    select h.cari_kod, max(h.kaynak) as kaynak from erp_cari_hareket h
     where h.cari_kod <> '__PERAKENDE__' and true
       and coalesce(h.doviz, '') in ('', 'TRY', 'TL')
     group by h.cari_kod
  ), t as (
    select h.* from erp_cari_hareket h join k on k.cari_kod = h.cari_kod and k.kaynak = h.kaynak
     where coalesce(h.doviz, '') in ('', 'TRY', 'TL')
  ), b as (
    select cari_kod, max(cari_ad) as cari_ad, sum(borc - alacak) as bakiye from t group by cari_kod
  ), s as (
    select t.cari_kod, b.cari_ad, case when b.bakiye > 0 then 'alacak' else 'borc' end as yon,
           (t.tarih at time zone 'Europe/Istanbul')::date as tarih,
           coalesce(t.vade, (t.tarih at time zone 'Europe/Istanbul')::date) as vade,
           t.tur, t.belge_no, case when b.bakiye > 0 then t.borc else t.alacak end as tutar, abs(b.bakiye) as kalan,
           t.fis_id, t.detay_id
      from t join b on b.cari_kod = t.cari_kod
     where abs(b.bakiye) >= 0.01 and (case when b.bakiye > 0 then t.borc else t.alacak end) > 0
  ), c as (
    select s.*, sum(tutar) over (partition by cari_kod order by tarih desc, detay_id desc) - tutar as onceki from s
  )
  select c.cari_kod, c.cari_ad, c.yon, c.tarih, c.vade, c.tur, c.belge_no, c.tutar, least(tutar, kalan - onceki) as acik, fis_id
    from c where kalan - onceki > 0.004;
  end if;
end $$;

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
          from (select * from erp_fis_satir where o.stok_kodu <> '' and stok_kodu = o.stok_kodu
                union all
                select * from erp_fis_satir where o.stok_kodu = '' and barkod = o.barkod) h
         where h.fis_turu in (1, 5) and h.giris >= 0 and coalesce(h.net_fiyat, h.birim_fiyat, 0) > 0
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
          from (select * from erp_fis_satir where s.stok_kodu <> '' and stok_kodu = s.stok_kodu
                union all
                select * from erp_fis_satir where s.stok_kodu = '' and barkod = s.barkod) h
         where h.fis_turu in (1, 5) and h.giris >= 0 and coalesce(h.net_fiyat, h.birim_fiyat, 0) > 0
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

alter function _vade_acik(text) security definer set search_path = public, extensions;
alter function plasiyer_son_fiyat(text, integer) security definer set search_path = public, extensions;
revoke execute on function _vade_acik(text) from public;
revoke execute on function plasiyer_son_fiyat(text, integer) from public;
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke execute on function _vade_acik(text), plasiyer_son_fiyat(text, integer) from anon, authenticated';
  end if;
end $$;

analyze erp_cari_hareket;
