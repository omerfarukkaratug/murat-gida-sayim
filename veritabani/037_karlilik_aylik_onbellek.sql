-- ============================================================
-- 💹 Kârlılık raporu: AYLIK ÖNBELLEK ("statement timeout" kalıcı çözümü). 036'dan sonra çalıştırılır;
-- tekrar çalıştırmak güvenlidir. ERP verisine dokunmaz, yalnız okur (yalnız kendi önbellek tablolarına yazar).
--
-- Neden: rapor her açılışta 13 ayın bütün kasa ve firma satışlarını baştan topluyordu; veri büyüdükçe
-- veri tabanının süre sınırını aştı ("canceling statement due to statement timeout").
-- Şimdi:
--  - KAPANMIŞ her ay ürün bazında BİR KERE toplanır ve karlilik_ay tablosunda saklanır
--    (satış miktarı/tutarı, kasada satış günü, o ayın maliyeti). Geçen ay ERP'de düzeltme olabilir diye
--    sık, daha eski aylar günde birkaç kez tazelenir.
--  - Rapor yalnız bu ayı, dönemin yarım kalan ilk ayını ve son 30 gün / geçen yılın aynı 60 günü canlı okur.
--  - Hazırlık parça parça yapılır: bir çağrı en fazla ~12 sn ay hazırlar; bitmezse rapor
--    {status:'hazirlaniyor'} döner, uygulama kendiliğinden tekrar sorar (ilk açılışta birkaç tur).
-- Çıktı biçimi 035/036 ile birebir aynıdır.
-- ============================================================

create index if not exists erp_stok_perakende_gun on erp_stok_perakende (gun);
create index if not exists erp_fis_satir_tarih_tek on erp_fis_satir (tarih);

create table if not exists karlilik_ay (
  ay         date not null,
  stok_kodu  text not null,
  kasa_m     double precision not null default 0,   -- kasa: satış + / iade − (ayın tamamı)
  kasa_t     double precision not null default 0,
  firma_m    double precision not null default 0,   -- firma satışı − satıştan iade
  firma_t    double precision not null default 0,
  ilk        date,                                  -- ayın ilk satış günü (kasa ya da firma)
  gs         integer not null default 0,            -- kasada satış olan gün sayısı
  maliyet    double precision,                      -- ay sonuna kadarki son net alış (yoksa ilk alış), KDV dahil
  primary key (ay, stok_kodu)
);
create table if not exists karlilik_ay_durum (
  ay     date primary key,
  zaman  timestamptz not null
);
alter table karlilik_ay enable row level security;
alter table karlilik_ay_durum enable row level security;

-- Bir kapanmış ayı ürün bazında toplar (eski satırları silip yeniden yazar).
create or replace function karlilik_ay_hesapla(p_ay date) returns integer language plpgsql volatile as $$
declare
  v_ay date := date_trunc('month', p_ay)::date;
  v_son date := (date_trunc('month', p_ay) + interval '1 month')::date;
  v_n integer;
begin
  delete from karlilik_ay where ay = v_ay;
  insert into karlilik_ay (ay, stok_kodu, kasa_m, kasa_t, firma_m, firma_t, ilk, gs, maliyet)
  with
  ks as (
    select stok_kodu, -sum(miktar::float8) as m, -sum(tutar::float8) as t,
           min(gun) filter (where miktar < 0) as ilk, count(*) filter (where miktar < 0) as gs
      from erp_stok_perakende
     where gun >= v_ay and gun < v_son and stok_kodu <> ''
     group by stok_kodu
  ),
  fs as (
    select stok_kodu, sum(sm) as m, sum(st) as t, min(g) filter (where sm > 0) as ilk
      from (select stok_kodu, (tarih at time zone 'Europe/Istanbul')::date as g,
                   (case when giris < 0 then miktar else -miktar end)::float8 as sm,
                   ((case when giris < 0 then 1 else -1 end) * miktar * coalesce(net_fiyat, birim_fiyat, 0))::float8 as st
              from erp_fis_satir
             where tarih >= v_ay::timestamp at time zone 'Europe/Istanbul' and tarih < v_son::timestamp at time zone 'Europe/Istanbul'
               and stok_kodu <> '' and miktar > 0
               and ((fis_turu in (2, 6, 12) and giris < 0) or (giris > 0 and tur_ad ilike '%iade%' and fis_turu not in (1, 5)))) x
     group by stok_kodu
  ),
  u as (
    select coalesce(k.stok_kodu, f.stok_kodu) as stok_kodu,
           coalesce(k.m, 0) as kasa_m, coalesce(k.t, 0) as kasa_t, coalesce(f.m, 0) as firma_m, coalesce(f.t, 0) as firma_t,
           least(k.ilk, f.ilk) as ilk, coalesce(k.gs, 0) as gs
      from ks k full join fs f on f.stok_kodu = k.stok_kodu
  )
  select v_ay, u.stok_kodu, u.kasa_m, u.kasa_t, u.firma_m, u.firma_t, u.ilk, u.gs, coalesce(
      (select coalesce(h.net_fiyat, h.birim_fiyat)::float8 from erp_fis_satir h
        where h.stok_kodu = u.stok_kodu and h.fis_turu in (1, 5) and h.giris >= 0 and h.miktar > 0 and coalesce(h.net_fiyat, h.birim_fiyat, 0) > 0
          and h.tarih < v_son::timestamp at time zone 'Europe/Istanbul'
        order by h.tarih desc limit 1),
      (select coalesce(h.net_fiyat, h.birim_fiyat)::float8 from erp_fis_satir h
        where h.stok_kodu = u.stok_kodu and h.fis_turu in (1, 5) and h.giris >= 0 and h.miktar > 0 and coalesce(h.net_fiyat, h.birim_fiyat, 0) > 0
        order by h.tarih asc limit 1))
    from u;
  get diagnostics v_n = row_count;
  insert into karlilik_ay_durum (ay, zaman) values (v_ay, now()) on conflict (ay) do update set zaman = excluded.zaman;
  return v_n;
end $$;

-- Eksik ya da bayat kapanmış ayları, süre bütçesi içinde hazırlar. Döner: hâlâ HİÇ hazırlanmamış ay sayısı.
-- Geçen ay 30 dakikada bir, daha eskiler 12 saatte bir tazelenir (ERP'ye geç girilen belge için).
create or replace function karlilik_aylari_hazirla(p_butce_sn integer default 12) returns integer language plpgsql volatile as $$
declare
  v_bugun date := (now() at time zone 'Europe/Istanbul')::date;
  v_bu_ay date := date_trunc('month', v_bugun)::date;
  v_ilk date := (date_trunc('month', v_bugun) - interval '12 months')::date;
  v_basla timestamptz := clock_timestamp();
  r record;
  v_eksik integer;
begin
  for r in
    select a.ay, d.zaman
      from generate_series(v_bu_ay - interval '1 month', v_ilk, interval '-1 month') as a(ay)
      left join karlilik_ay_durum d on d.ay = a.ay::date
     where d.zaman is null
        or (a.ay::date = (v_bu_ay - interval '1 month')::date and d.zaman < now() - interval '30 minutes')
        or d.zaman < now() - interval '12 hours'
     order by (d.zaman is null) desc, a.ay desc
  loop
    exit when clock_timestamp() - v_basla > make_interval(secs => p_butce_sn);
    perform karlilik_ay_hesapla(r.ay::date);
  end loop;
  select count(*) into v_eksik
    from generate_series(v_ilk, v_bu_ay - interval '1 month', interval '1 month') as a(ay)
   where not exists (select 1 from karlilik_ay_durum d where d.ay = a.ay::date);
  return v_eksik;
end $$;

create or replace function karlilik_veri(p_gun integer default 90, p_kdv jsonb default '{}'::jsonb)
returns jsonb language plpgsql volatile as $$
declare
  v_gun int := least(greatest(coalesce(p_gun, 90), 7), 365);
  v_bugun date := (now() at time zone 'Europe/Istanbul')::date;
  v_bas date := v_bugun - v_gun;                         -- dönem: (v_bas, v_bugun]
  v_ilk_gun date := v_bugun - v_gun + 1;                 -- dönemin ilk günü
  v_ay_bas date := (date_trunc('month', v_bugun) - interval '12 months')::date;
  v_bu_ay date := date_trunc('month', v_bugun)::date;
  v_a date := date_trunc('month', v_bugun - v_gun + 1)::date;   -- dönemin ilk günündeki ay
  v_yarim boolean;                                       -- dönemin ilk ayı kapanmış ama yarım mı
  v_imza text := md5(coalesce(p_kdv, '{}'::jsonb)::text);
  v_sonuc jsonb;
  v_eksik integer;
begin
  select veri into v_sonuc from karlilik_onbellek where gun = v_gun and imza = v_imza and zaman > now() - interval '30 minutes';
  if v_sonuc is not null then return v_sonuc || jsonb_build_object('onbellek', true); end if;

  v_eksik := karlilik_aylari_hazirla(12);
  if v_eksik > 0 then
    return jsonb_build_object('status', 'hazirlaniyor', 'kalan', v_eksik, 'toplam', 12,
      'message', 'Rapor ilk kez hazırlanıyor (' || (12 - v_eksik) || '/12 ay hazır)');
  end if;
  v_yarim := v_a < v_bu_ay and v_ilk_gun > v_a;

  with
  kk as (select key as stok_kodu, coalesce(nullif(value #>> '{}', '')::float8, 0) as kdv from jsonb_each(coalesce(p_kdv, '{}'::jsonb))),
  -- CANLI günlük satırlar: dönemin yarım ilk ayının dönem içi günleri + bu ayın tamamı
  kc as (
    select stok_kodu, date_trunc('month', gun)::date as ay, gun, miktar::float8 as m, tutar::float8 as t
      from erp_stok_perakende
     where stok_kodu <> ''
       and ((gun >= v_bu_ay and gun <= v_bugun) or (v_yarim and gun >= v_ilk_gun and gun < (v_a + interval '1 month')::date))
  ),
  fc as (
    select stok_kodu, date_trunc('month', g)::date as ay, g, sm, st
      from (select stok_kodu, (tarih at time zone 'Europe/Istanbul')::date as g,
                   (case when giris < 0 then miktar else -miktar end)::float8 as sm,
                   ((case when giris < 0 then 1 else -1 end) * miktar * coalesce(net_fiyat, birim_fiyat, 0))::float8 as st
              from erp_fis_satir
             where stok_kodu <> '' and miktar > 0
               and ((tarih >= v_bu_ay::timestamp at time zone 'Europe/Istanbul')
                    or (v_yarim and tarih >= v_ilk_gun::timestamp at time zone 'Europe/Istanbul' and tarih < (v_a + interval '1 month')::date::timestamp at time zone 'Europe/Istanbul'))
               and ((fis_turu in (2, 6, 12) and giris < 0) or (giris > 0 and tur_ad ilike '%iade%' and fis_turu not in (1, 5)))) x
  ),
  ksc as (
    select stok_kodu, ay,
           -sum(m) as m, -sum(t) as t, -sum(m) filter (where gun > v_bas) as pm, -sum(t) filter (where gun > v_bas) as pt,
           min(gun) filter (where gun > v_bas and m < 0) as ilk, count(*) filter (where gun > v_bas and m < 0) as gs
      from kc group by stok_kodu, ay
  ),
  fsc as (
    select stok_kodu, ay, sum(sm) as m, sum(st) as t, sum(sm) filter (where g > v_bas) as pm, sum(st) filter (where g > v_bas) as pt,
           min(g) filter (where g > v_bas and sm > 0) as ilk
      from fc group by stok_kodu, ay
  ),
  canli as (    -- canlı (ürün, ay); yarım ay için yalnız dönem değerleri anlamlı (ay toplamı önbellekten)
    select coalesce(k.stok_kodu, f.stok_kodu) as stok_kodu, coalesce(k.ay, f.ay) as ay,
           coalesce(k.m, 0) as kasa_m, coalesce(f.m, 0) as firma_m, coalesce(k.t, 0) as kasa_t, coalesce(f.t, 0) as firma_t,
           coalesce(k.pm, 0) as p_kasa_m, coalesce(f.pm, 0) as p_firma_m, coalesce(k.pt, 0) + coalesce(f.pt, 0) as p_t,
           least(k.ilk, f.ilk) as ilk, coalesce(k.gs, 0) as gs
      from ksc k full join fsc f on f.stok_kodu = k.stok_kodu and f.ay = k.ay
  ),
  ua as (
    -- kapanmış aylar (önbellek); dönemin tamamen içindeki aylarda dönem değeri = ay toplamı
    select c.stok_kodu, c.ay, c.kasa_m, c.firma_m, c.kasa_t, c.firma_t,
           case when c.ay >= v_ilk_gun then c.kasa_m else coalesce(y.p_kasa_m, 0) end as p_kasa_m,
           case when c.ay >= v_ilk_gun then c.firma_m else coalesce(y.p_firma_m, 0) end as p_firma_m,
           case when c.ay >= v_ilk_gun then c.kasa_t + c.firma_t else coalesce(y.p_t, 0) end as p_t,
           case when c.ay >= v_ilk_gun then c.ilk else y.ilk end as ilk,
           case when c.ay >= v_ilk_gun then c.gs else coalesce(y.gs, 0) end as gs,
           c.maliyet
      from karlilik_ay c
      left join canli y on y.stok_kodu = c.stok_kodu and y.ay = c.ay and c.ay = v_a and v_yarim
     where c.ay >= v_ay_bas and c.ay < v_bu_ay
    union all
    -- yarım ilk ayda satılıp o ayın önbelleğine (en çok 30 dk bayat) henüz girmemiş ürün
    select y.stok_kodu, y.ay, y.kasa_m, y.firma_m, y.kasa_t, y.firma_t, y.p_kasa_m, y.p_firma_m, y.p_t, y.ilk, y.gs,
           (select coalesce(h.net_fiyat, h.birim_fiyat)::float8 from erp_fis_satir h
             where h.stok_kodu = y.stok_kodu and h.fis_turu in (1, 5) and h.giris >= 0 and h.miktar > 0 and coalesce(h.net_fiyat, h.birim_fiyat, 0) > 0
             order by h.tarih desc limit 1) as maliyet
      from canli y
     where v_yarim and y.ay = v_a and not exists (select 1 from karlilik_ay c where c.ay = v_a and c.stok_kodu = y.stok_kodu)
    union all
    -- bu ay canlı:
    select y.stok_kodu, y.ay, y.kasa_m, y.firma_m, y.kasa_t, y.firma_t, y.p_kasa_m, y.p_firma_m, y.p_t, y.ilk, y.gs,
           coalesce(
             (select coalesce(h.net_fiyat, h.birim_fiyat)::float8 from erp_fis_satir h
               where h.stok_kodu = y.stok_kodu and h.fis_turu in (1, 5) and h.giris >= 0 and h.miktar > 0 and coalesce(h.net_fiyat, h.birim_fiyat, 0) > 0
               order by h.tarih desc limit 1),
             null) as maliyet
      from canli y where y.ay = v_bu_ay
  ),
  um as (
    select * from ua
     where kasa_m <> 0 or firma_m <> 0 or p_kasa_m <> 0 or p_firma_m <> 0
  ),
  -- son 30 gün ve bir yıl önceki aynı 60 günün kasa birim fiyatı (ürün)
  kb as (
    select stok_kodu,
           -sum(miktar::float8) filter (where gun > v_bugun - 30 and miktar < 0) as m30, -sum(tutar::float8) filter (where gun > v_bugun - 30 and miktar < 0) as t30,
           -sum(miktar::float8) filter (where gun <= v_bugun - 335 and miktar < 0) as m1y, -sum(tutar::float8) filter (where gun <= v_bugun - 335 and miktar < 0) as t1y
      from erp_stok_perakende
     where stok_kodu <> '' and ((gun > v_bugun - 30 and gun <= v_bugun) or (gun > v_bugun - 395 and gun <= v_bugun - 335))
     group by stok_kodu
  ),
  d as (        -- dönem toplamı (ürün)
    select u.stok_kodu, sum(u.p_kasa_m) as kasa_m, sum(u.p_firma_m) as firma_m, sum(u.p_t) as ciro_d,
           sum(case when u.maliyet is not null then (u.p_kasa_m + u.p_firma_m) * u.maliyet else 0 end) as maliyet_d,
           sum(case when u.maliyet is null then u.p_t else 0 end) as maliyetsiz_d,
           min(u.ilk) as ilk_gun, sum(u.gs) as gun_say
      from um u group by u.stok_kodu
     having sum(u.p_kasa_m) <> 0 or sum(u.p_firma_m) <> 0 or sum(u.p_t) <> 0
  ),
  dk as (
    select d.*, kb.t30 / nullif(kb.m30, 0) as kb_simdi, kb.t1y / nullif(kb.m1y, 0) as kb_once
      from d left join kb on kb.stok_kodu = d.stok_kodu
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
      from dk d left join kk k on k.stok_kodu = d.stok_kodu left join son on son.stok_kodu = d.stok_kodu
             left join once on once.stok_kodu = d.stok_kodu), '[]'::jsonb),
    'aylar', coalesce((select jsonb_agg(jsonb_build_array(to_char(ay, 'YYYY-MM'), karlilik_yuv(ciro, 2), karlilik_yuv(maliyet, 2), karlilik_yuv(maliyetsiz, 2), karlilik_yuv(kasa, 2), karlilik_yuv(firma, 2)) order by ay) from aylik), '[]'::jsonb),
    'sonVeri', (select to_char(max(guncelleme) at time zone 'Europe/Istanbul', 'DD.MM.YYYY HH24:MI') from erp_fis_satir where tarih > now() - interval '3 days')
  ) into v_sonuc;

  delete from karlilik_onbellek where zaman < now() - interval '1 day' or (gun = v_gun and imza = v_imza);
  insert into karlilik_onbellek (gun, imza, veri) values (v_gun, v_imza, v_sonuc);
  return v_sonuc;
end $$;

alter function karlilik_ay_hesapla(date) security definer set search_path = public, extensions set work_mem = '128MB';
alter function karlilik_aylari_hazirla(integer) security definer set search_path = public, extensions set work_mem = '128MB';
alter function karlilik_veri(integer, jsonb) security definer set search_path = public, extensions set work_mem = '128MB';
revoke execute on function karlilik_ay_hesapla(date) from public;
revoke execute on function karlilik_aylari_hazirla(integer) from public;
revoke execute on function karlilik_veri(integer, jsonb) from public;
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke execute on function karlilik_ay_hesapla(date) from anon, authenticated';
    execute 'revoke execute on function karlilik_aylari_hazirla(integer) from anon, authenticated';
    execute 'revoke execute on function karlilik_veri(integer, jsonb) from anon, authenticated';
    execute 'revoke all on karlilik_ay from anon, authenticated';
    execute 'revoke all on karlilik_ay_durum from anon, authenticated';
  end if;
end $$;
-- Eski (036) biçimde hesaplanmış sonuçlar silinir; yeni hesap aylık önbellekten gelir.
delete from karlilik_onbellek;
notify pgrst, 'reload config';
