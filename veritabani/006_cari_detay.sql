-- ============================================================
-- Cari Hareketleri — EK: fatura/fiş detayı, carinin stok hareketleri, perakende.
-- 005_cari_hareketleri.sql'den SONRA çalıştırılır; tekrar çalıştırmak güvenlidir.
--
--  erp_fis_satir : carilerin belgelerinin (fatura, irsaliye, fiş, iade…) ürün satırları.
--                  Hem "fatura detayı" hem "carinin stok hareketleri" buradan gelir.
--  Perakende     : Peşin Satış (varsayılan cari) hareketleri erp_cari_hareket'e GÜNLÜK
--                  TOPLAM olarak, cari_kod = '__PERAKENDE__' ile yazılır (her fiş tek tek değil).
-- ============================================================

create table if not exists erp_fis_satir (
  kaynak       text not null default '',
  detay_id     bigint not null,               -- ERP12 FIS_DETAY.ID
  fis_id       bigint not null,
  fis_turu     integer not null,
  tur_ad       text not null default '',      -- FIS_TURU.AD (Alış faturası, Satış irsaliyesi…)
  giris        integer not null default 0,    -- +1 stoğa giriş, -1 çıkış
  tarih        timestamptz not null,
  belge_no     text not null default '',
  cari_kod     text not null default '',
  stok_kodu    text not null default '',
  barkod       text not null default '',
  urun_adi     text not null default '',
  miktar       numeric not null default 0,
  birim_fiyat  numeric,                       -- KDV DAHİL birim fiyat
  tutar        numeric,                       -- KDV DAHİL satır tutarı
  guncelleme   timestamptz not null default now(),
  primary key (kaynak, detay_id)
);
create index if not exists erp_fis_satir_fis on erp_fis_satir (kaynak, fis_id);
create index if not exists erp_fis_satir_cari on erp_fis_satir (cari_kod, kaynak, tarih);
create index if not exists erp_fis_satir_tarih on erp_fis_satir (kaynak, tarih);
alter table erp_fis_satir enable row level security;

create or replace function fis_satir_yukle(p_kaynak text, p_satirlar jsonb, p_bas timestamptz, p_bit timestamptz, p_temizle boolean default false)
returns jsonb language plpgsql as $$
declare v_silinen integer := 0; v_eklenen integer;
begin
  if p_bas is null or p_bit is null or p_bit <= p_bas then
    return jsonb_build_object('status', 'error', 'message', 'Geçersiz tarih aralığı');
  end if;
  if coalesce(p_kaynak, '') = '' then
    return jsonb_build_object('status', 'error', 'message', 'Kaynak (ERP veri tabanı adı) eksik');
  end if;
  if p_temizle then
    delete from erp_fis_satir where kaynak = p_kaynak and tarih >= p_bas and tarih < p_bit;
    get diagnostics v_silinen = row_count;
  end if;
  insert into erp_fis_satir as h (kaynak, detay_id, fis_id, fis_turu, tur_ad, giris, tarih, belge_no, cari_kod, stok_kodu, barkod, urun_adi, miktar, birim_fiyat, tutar, guncelleme)
  select p_kaynak, x.detay_id, x.fis_id, coalesce(x.fis_turu, 0), coalesce(x.tur_ad, ''), coalesce(x.giris, 0), x.tarih,
         coalesce(x.belge_no, ''), coalesce(x.cari_kod, ''), coalesce(x.stok_kodu, ''), coalesce(x.barkod, ''),
         coalesce(x.urun_adi, ''), coalesce(x.miktar, 0), x.birim_fiyat, x.tutar, now()
    from jsonb_to_recordset(coalesce(p_satirlar, '[]'::jsonb)) as x(
         detay_id bigint, fis_id bigint, fis_turu integer, tur_ad text, giris integer, tarih timestamptz, belge_no text,
         cari_kod text, stok_kodu text, barkod text, urun_adi text, miktar numeric, birim_fiyat numeric, tutar numeric)
   where x.detay_id is not null and x.fis_id is not null and x.tarih >= p_bas and x.tarih < p_bit
  on conflict (kaynak, detay_id) do update set
    fis_id = excluded.fis_id, fis_turu = excluded.fis_turu, tur_ad = excluded.tur_ad, giris = excluded.giris,
    tarih = excluded.tarih, belge_no = excluded.belge_no, cari_kod = excluded.cari_kod, stok_kodu = excluded.stok_kodu,
    barkod = excluded.barkod, urun_adi = excluded.urun_adi, miktar = excluded.miktar, birim_fiyat = excluded.birim_fiyat,
    tutar = excluded.tutar, guncelleme = now();
  get diagnostics v_eklenen = row_count;
  return jsonb_build_object('status', 'ok', 'silinen', v_silinen, 'eklenen', v_eklenen);
end $$;

-- Cari ekstresi: satır sonuna fiş no (detay açmak için) eklendi.
-- r: [tarih, tür, belge no, açıklama, borç, alacak, bakiye, döviz, vade, fis_id]
create or replace function cari_hareket(p_cari_kod text, p_gun integer default 90, p_limit integer default 500)
returns jsonb language sql stable as $$
  with k as (
    select max(kaynak) as kaynak from erp_cari_hareket where cari_kod = coalesce(p_cari_kod, '')
  ), t as (
    select h.*, sum(h.borc - h.alacak) over (partition by h.doviz order by h.tarih, h.detay_id, h.taraf) as bakiye
      from erp_cari_hareket h, k
     where h.cari_kod = coalesce(p_cari_kod, '') and h.kaynak = k.kaynak
  ), s as (
    select (case when coalesce(p_gun, 0) > 0 then (date_trunc('day', now() at time zone 'Europe/Istanbul') - make_interval(days => p_gun)) at time zone 'Europe/Istanbul' end) as bas
  ), d as (
    select t.* from t, s where s.bas is null or t.tarih >= s.bas
  )
  select jsonb_build_object(
    'status', 'ok',
    'kaynak', (select kaynak from k),
    'cariAd', (select cari_ad from t order by tarih desc limit 1),
    'bakiye', coalesce((select jsonb_object_agg(doviz, b) from (select doviz, sum(borc - alacak) as b from t group by doviz) z), '{}'::jsonb),
    'devreden', coalesce((select jsonb_object_agg(doviz, b) from (select t.doviz, sum(t.borc - t.alacak) as b from t, s where s.bas is not null and t.tarih < s.bas group by t.doviz) z), '{}'::jsonb),
    'donemBorc', (select coalesce(sum(borc), 0) from d),
    'donemAlacak', (select coalesce(sum(alacak), 0) from d),
    'adet', (select count(*) from d),
    'satirlar', coalesce((select jsonb_agg(jsonb_build_array(
                    to_char(tarih at time zone 'Europe/Istanbul', 'DD.MM.YYYY'), tur, belge_no, aciklama, borc, alacak, bakiye, doviz,
                    coalesce(to_char(vade, 'DD.MM.YYYY'), ''), fis_id) order by tarih desc, detay_id desc, taraf desc)
                   from (select * from d order by tarih desc, detay_id desc, taraf desc limit greatest(coalesce(p_limit, 500), 1)) x), '[]'::jsonb),
    'sonVeri', (select to_char(max(guncelleme) at time zone 'Europe/Istanbul', 'DD.MM.YYYY HH24:MI') from erp_cari_hareket)
  )
$$;

-- Bir belgenin (fatura/irsaliye/fiş) ürün satırları.
-- satirlar r: [stok kodu, barkod, ürün adı, miktar, KDV dahil birim fiyat, KDV dahil tutar]
create or replace function fis_detay(p_kaynak text, p_fis_id bigint)
returns jsonb language sql stable as $$
  with f as (select * from erp_fis_satir where kaynak = coalesce(p_kaynak, '') and fis_id = p_fis_id)
  select jsonb_build_object(
    'status', 'ok',
    'bulundu', exists (select 1 from f),
    'tur', (select tur_ad from f limit 1),
    'belgeNo', (select belge_no from f limit 1),
    'tarih', (select to_char(tarih at time zone 'Europe/Istanbul', 'DD.MM.YYYY') from f limit 1),
    'toplam', (select coalesce(sum(coalesce(tutar, miktar * coalesce(birim_fiyat, 0))), 0) from f),
    'satirlar', coalesce((select jsonb_agg(jsonb_build_array(stok_kodu, barkod, urun_adi, miktar, birim_fiyat, coalesce(tutar, miktar * birim_fiyat)) order by detay_id) from f), '[]'::jsonb)
  )
$$;

-- Carinin stok hareketleri (o cariden gelen / ona giden ürünler), yeniden eskiye.
-- satirlar r: [tarih, belge türü, belge no, stok kodu, barkod, ürün adı, miktar (+giriş / −çıkış), KDV dahil birim fiyat, tutar, fis_id]
create or replace function cari_stok(p_cari_kod text, p_gun integer default 90, p_limit integer default 500)
returns jsonb language sql stable as $$
  with k as (
    select max(kaynak) as kaynak from erp_fis_satir where cari_kod = coalesce(p_cari_kod, '')
  ), d as (
    select h.* from erp_fis_satir h, k
     where h.cari_kod = coalesce(p_cari_kod, '') and h.kaynak = k.kaynak
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

alter function fis_satir_yukle(text, jsonb, timestamptz, timestamptz, boolean) security definer set search_path = public, extensions;
alter function cari_hareket(text, integer, integer) security definer set search_path = public, extensions;
alter function fis_detay(text, bigint)              security definer set search_path = public, extensions;
alter function cari_stok(text, integer, integer)    security definer set search_path = public, extensions;

revoke execute on function fis_satir_yukle(text, jsonb, timestamptz, timestamptz, boolean) from public;
revoke execute on function cari_hareket(text, integer, integer) from public;
revoke execute on function fis_detay(text, bigint) from public;
revoke execute on function cari_stok(text, integer, integer) from public;
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke all on erp_fis_satir from anon, authenticated';
    execute 'revoke execute on function fis_satir_yukle(text, jsonb, timestamptz, timestamptz, boolean), cari_hareket(text, integer, integer), fis_detay(text, bigint), cari_stok(text, integer, integer) from anon, authenticated';
  end if;
end $$;
