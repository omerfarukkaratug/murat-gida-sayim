-- ============================================================
-- 💹 Kârlılık raporu HIZ düzeltmesi ("statement timeout"). 035'ten sonra çalıştırılır; tekrar çalıştırmak güvenlidir.
-- Veriye dokunmaz, yalnız okur (yalnız kendi önbellek tablosuna yazar).
--  - Ara tablolar kaldırıldı: kasa ve firma satışları TEK geçişte ürün + ay bazında toplanır
--    (aylık tablo, dönem toplamı, son 30 gün ve bir yıl önceki 30 günün kasa fiyatı aynı geçişte).
--  - Maliyet ürün + ay başına bir kez, indeksten okunur.
--  - Sonuç 30 dakika önbellekte tutulur (aynı dönem tekrar açılınca anında gelir).
--  - Uygulama sunucusunun rolünde (service_role) sorgu süre sınırı 30 sn yapılır.
-- Çıktı biçimi 035 ile aynıdır.
-- ============================================================

create index if not exists erp_fis_satir_alis_stok on erp_fis_satir (stok_kodu, tarih desc) where fis_turu in (1, 5) and giris >= 0 and miktar > 0;

create table if not exists karlilik_onbellek (
  gun     integer not null,
  imza    text not null,
  veri    jsonb not null,
  zaman   timestamptz not null default now(),
  primary key (gun, imza)
);
alter table karlilik_onbellek enable row level security;

create or replace function karlilik_yuv(v double precision, n integer) returns numeric language sql immutable as $$ select round(v::numeric, n) $$;

create or replace function karlilik_veri(p_gun integer default 90, p_kdv jsonb default '{}'::jsonb)
returns jsonb language plpgsql volatile as $$
declare
  v_gun int := least(greatest(coalesce(p_gun, 90), 7), 365);
  v_bugun date := (now() at time zone 'Europe/Istanbul')::date;
  v_bas date := v_bugun - v_gun;
  v_ay_bas date := (date_trunc('month', v_bugun) - interval '12 months')::date;
  v_tara date;
  v_imza text := md5(coalesce(p_kdv, '{}'::jsonb)::text);
  v_sonuc jsonb;
begin
  v_tara := least(v_ay_bas, v_bugun - 395);
  select veri into v_sonuc from karlilik_onbellek where gun = v_gun and imza = v_imza and zaman > now() - interval '30 minutes';
  if v_sonuc is not null then return v_sonuc || jsonb_build_object('onbellek', true); end if;

  with
  kk as (select key as stok_kodu, coalesce(nullif(value #>> '{}', '')::float8, 0) as kdv from jsonb_each(coalesce(p_kdv, '{}'::jsonb))),
  -- kasa: ürün + ay (satış +)
  ks as (
    select stok_kodu, date_trunc('month', gun)::date as ay,
           -sum(miktar::float8) filter (where gun >= v_ay_bas) as m, -sum(tutar::float8) filter (where gun >= v_ay_bas) as t,
           -sum(miktar::float8) filter (where gun > v_bas) as pm, -sum(tutar::float8) filter (where gun > v_bas) as pt,
           min(gun) filter (where gun > v_bas and miktar < 0) as ilk,
           count(*) filter (where gun > v_bas and miktar < 0) as gs,
           -sum(miktar::float8) filter (where gun > v_bugun - 30 and miktar < 0) as m30, -sum(tutar::float8) filter (where gun > v_bugun - 30 and miktar < 0) as t30,
           -sum(miktar::float8) filter (where gun > v_bugun - 395 and gun <= v_bugun - 335 and miktar < 0) as m1y,
           -sum(tutar::float8) filter (where gun > v_bugun - 395 and gun <= v_bugun - 335 and miktar < 0) as t1y
      from erp_stok_perakende
     where gun >= v_tara and stok_kodu <> ''
     group by stok_kodu, date_trunc('month', gun)::date
  ),
  -- firma satışı − satıştan iade: ürün + ay
  fs as (
    select stok_kodu, date_trunc('month', g)::date as ay,
           sum(sm) filter (where g >= v_ay_bas) as m, sum(st) filter (where g >= v_ay_bas) as t,
           sum(sm) filter (where g > v_bas) as pm, sum(st) filter (where g > v_bas) as pt,
           min(g) filter (where g > v_bas and sm > 0) as ilk
      from (select stok_kodu, (tarih at time zone 'Europe/Istanbul')::date as g,
                   (case when giris < 0 then miktar else -miktar end)::float8 as sm,
                   ((case when giris < 0 then 1 else -1 end) * miktar * coalesce(net_fiyat, birim_fiyat, 0))::float8 as st
              from erp_fis_satir
             where tarih >= v_ay_bas::timestamp at time zone 'Europe/Istanbul' and stok_kodu <> '' and miktar > 0
               and ((fis_turu in (2, 6, 12) and giris < 0) or (giris > 0 and tur_ad ilike '%iade%' and fis_turu not in (1, 5)))) x
     group by stok_kodu, date_trunc('month', g)::date
  ),
  ua as (       -- ürün + ay birleşik
    select coalesce(k.stok_kodu, f.stok_kodu) as stok_kodu, coalesce(k.ay, f.ay) as ay,
           coalesce(k.m, 0) as kasa_m, coalesce(f.m, 0) as firma_m, coalesce(k.t, 0) as kasa_t, coalesce(f.t, 0) as firma_t,
           coalesce(k.pm, 0) as p_kasa_m, coalesce(f.pm, 0) as p_firma_m, coalesce(k.pt, 0) + coalesce(f.pt, 0) as p_t,
           least(k.ilk, f.ilk) as ilk, coalesce(k.gs, 0) as gs,
           k.m30, k.t30, k.m1y, k.t1y
      from ks k full join fs f on f.stok_kodu = k.stok_kodu and f.ay = k.ay
  ),
  -- o ayda geçerli maliyet (ay sonuna kadarki son net alış; yoksa ilk alış)
  um as (
    select u.*, coalesce(
      (select coalesce(h.net_fiyat, h.birim_fiyat)::float8 from erp_fis_satir h
        where h.stok_kodu = u.stok_kodu and h.fis_turu in (1, 5) and h.giris >= 0 and h.miktar > 0 and coalesce(h.net_fiyat, h.birim_fiyat, 0) > 0
          and h.tarih < ((u.ay + interval '1 month')::date)::timestamp at time zone 'Europe/Istanbul'
        order by h.tarih desc limit 1),
      (select coalesce(h.net_fiyat, h.birim_fiyat)::float8 from erp_fis_satir h
        where h.stok_kodu = u.stok_kodu and h.fis_turu in (1, 5) and h.giris >= 0 and h.miktar > 0 and coalesce(h.net_fiyat, h.birim_fiyat, 0) > 0
        order by h.tarih asc limit 1)) as maliyet
      from ua u
     where u.kasa_m <> 0 or u.firma_m <> 0 or u.p_kasa_m <> 0 or u.p_firma_m <> 0 or u.m30 is not null or u.m1y is not null
  ),
  d as (        -- dönem toplamı (ürün)
    select stok_kodu, sum(p_kasa_m) as kasa_m, sum(p_firma_m) as firma_m, sum(p_t) as ciro_d,
           sum(case when maliyet is not null then (p_kasa_m + p_firma_m) * maliyet else 0 end) as maliyet_d,
           sum(case when maliyet is null then p_t else 0 end) as maliyetsiz_d,
           min(ilk) as ilk_gun, sum(gs) as gun_say,
           sum(t30) / nullif(sum(m30), 0) as kb_simdi, sum(t1y) / nullif(sum(m1y), 0) as kb_once
      from um group by stok_kodu
     having sum(p_kasa_m) <> 0 or sum(p_firma_m) <> 0 or sum(p_t) <> 0
  ),
  son as (
    select d.stok_kodu, x.* from d cross join lateral (
      select coalesce(h.net_fiyat, h.birim_fiyat) as fiyat, h.tarih, h.cari_kod, h.cari_ad, h.urun_adi from erp_fis_satir h
       where h.stok_kodu = d.stok_kodu and h.fis_turu in (1, 5) and h.giris >= 0 and h.miktar > 0 and coalesce(h.net_fiyat, h.birim_fiyat, 0) > 0
       order by h.tarih desc limit 1) x
  ),
  once as (
    select d.stok_kodu, x.fiyat from d cross join lateral (
      select coalesce(h.net_fiyat, h.birim_fiyat) as fiyat from erp_fis_satir h
       where h.stok_kodu = d.stok_kodu and h.fis_turu in (1, 5) and h.giris >= 0 and h.miktar > 0 and coalesce(h.net_fiyat, h.birim_fiyat, 0) > 0
         and h.tarih < ((v_bugun - 335)::timestamp at time zone 'Europe/Istanbul') and h.tarih >= ((v_bugun - 430)::timestamp at time zone 'Europe/Istanbul')
       order by h.tarih desc limit 1) x
  ),
  aylik as (
    select u.ay,
           sum((u.kasa_t + u.firma_t) / (1 + coalesce(k.kdv, 0) / 100)) as ciro,
           sum(case when u.maliyet is not null then (u.kasa_m + u.firma_m) * u.maliyet / (1 + coalesce(k.kdv, 0) / 100) else 0 end) as maliyet,
           sum(case when u.maliyet is null then (u.kasa_t + u.firma_t) / (1 + coalesce(k.kdv, 0) / 100) else 0 end) as maliyetsiz,
           sum(u.kasa_t / (1 + coalesce(k.kdv, 0) / 100)) as kasa, sum(u.firma_t / (1 + coalesce(k.kdv, 0) / 100)) as firma
      from um u left join kk k on k.stok_kodu = u.stok_kodu
     where u.ay >= v_ay_bas
     group by u.ay
  )
  select jsonb_build_object(
    'status', 'ok', 'gun', v_gun, 'bas', to_char(v_bas, 'DD.MM.YYYY'), 'bugun', to_char(v_bugun, 'DD.MM.YYYY'),
    'urunler', coalesce((select jsonb_agg(jsonb_build_array(
        d.stok_kodu, coalesce(son.urun_adi, ''),
        karlilik_yuv(d.kasa_m, 3), karlilik_yuv(d.firma_m, 3),
        karlilik_yuv(d.ciro_d / (1 + coalesce(k.kdv, 0) / 100), 2), karlilik_yuv(d.maliyet_d / (1 + coalesce(k.kdv, 0) / 100), 2),
        karlilik_yuv(d.maliyetsiz_d / (1 + coalesce(k.kdv, 0) / 100), 2),
        karlilik_yuv(son.fiyat / (1 + coalesce(k.kdv, 0) / 100), 4), to_char(son.tarih at time zone 'Europe/Istanbul', 'DD.MM.YYYY'),
        coalesce(son.cari_kod, ''), coalesce(son.cari_ad, ''),
        karlilik_yuv(once.fiyat / (1 + coalesce(k.kdv, 0) / 100), 4),
        karlilik_yuv(d.kb_simdi / (1 + coalesce(k.kdv, 0) / 100), 4), karlilik_yuv(d.kb_once / (1 + coalesce(k.kdv, 0) / 100), 4),
        coalesce(k.kdv, 0), to_char(d.ilk_gun, 'DD.MM.YYYY'), d.gun_say))
      from d left join kk k on k.stok_kodu = d.stok_kodu left join son on son.stok_kodu = d.stok_kodu
             left join once on once.stok_kodu = d.stok_kodu), '[]'::jsonb),
    'aylar', coalesce((select jsonb_agg(jsonb_build_array(to_char(ay, 'YYYY-MM'), karlilik_yuv(ciro, 2), karlilik_yuv(maliyet, 2), karlilik_yuv(maliyetsiz, 2), karlilik_yuv(kasa, 2), karlilik_yuv(firma, 2)) order by ay) from aylik), '[]'::jsonb),
    'sonVeri', (select to_char(max(guncelleme) at time zone 'Europe/Istanbul', 'DD.MM.YYYY HH24:MI') from erp_fis_satir where tarih > now() - interval '3 days')
  ) into v_sonuc;

  delete from karlilik_onbellek where zaman < now() - interval '1 day' or (gun = v_gun and imza = v_imza);
  insert into karlilik_onbellek (gun, imza, veri) values (v_gun, v_imza, v_sonuc);
  return v_sonuc;
end $$;

alter function karlilik_veri(integer, jsonb) security definer set search_path = public, extensions set work_mem = '128MB';
revoke execute on function karlilik_veri(integer, jsonb) from public;
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke execute on function karlilik_veri(integer, jsonb) from anon, authenticated';
    execute 'revoke all on karlilik_onbellek from anon, authenticated';
  end if;
  -- Uygulama sunucusunun kullandığı rolde sorgu süre sınırı 30 sn (varsayılan 8 sn rapor için kısa kalıyordu).
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    execute 'alter role service_role set statement_timeout = ''30s''';
  end if;
end $$;
notify pgrst, 'reload config';
