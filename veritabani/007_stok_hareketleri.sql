-- ============================================================
-- Stok Hareketleri: bir ürünün BÜTÜN giriş/çıkışları (ERP12 stok hareket raporu gibi).
-- 006_cari_detay.sql'den SONRA çalıştırılır; tekrar çalıştırmak güvenlidir.
--
--  erp_fis_satir      : artık stoğa etki eden TÜM belgelerin satırları (alış, satış, iade, depo
--                       giriş/çıkış, sarf, fire, sayım…). Perakende (kasa) fişleri HARİÇ.
--  erp_stok_perakende : perakende (kasa fişleri, perakende iade, Peşin Satış belgeleri)
--                       ürün + gün başına TOPLAM (miktar işaretli: satış −, iade +).
-- Her satıra dokununca belge detayı fis_detay ile açılır (006).
-- ============================================================

alter table erp_fis_satir add column if not exists cari_ad text not null default '';
create index if not exists erp_fis_satir_stok on erp_fis_satir (stok_kodu, tarih);
create index if not exists erp_fis_satir_barkod on erp_fis_satir (barkod, tarih);

create table if not exists erp_stok_perakende (
  kaynak     text not null default '',
  stok_kodu  text not null,
  gun        date not null,
  miktar     numeric not null default 0,    -- işaretli: satış −, iade +
  tutar      numeric not null default 0,    -- KDV dahil, işaretli
  adet       integer not null default 0,    -- kaç satırın toplamı
  primary key (kaynak, stok_kodu, gun)
);
create index if not exists erp_stok_perakende_stok on erp_stok_perakende (stok_kodu, gun);
alter table erp_stok_perakende enable row level security;

-- fis_satir_yukle: cari_ad alanı eklendi.
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
  insert into erp_fis_satir as h (kaynak, detay_id, fis_id, fis_turu, tur_ad, giris, tarih, belge_no, cari_kod, cari_ad, stok_kodu, barkod, urun_adi, miktar, birim_fiyat, tutar, guncelleme)
  select p_kaynak, x.detay_id, x.fis_id, coalesce(x.fis_turu, 0), coalesce(x.tur_ad, ''), coalesce(x.giris, 0), x.tarih,
         coalesce(x.belge_no, ''), coalesce(x.cari_kod, ''), coalesce(x.cari_ad, ''), coalesce(x.stok_kodu, ''), coalesce(x.barkod, ''),
         coalesce(x.urun_adi, ''), coalesce(x.miktar, 0), x.birim_fiyat, x.tutar, now()
    from jsonb_to_recordset(coalesce(p_satirlar, '[]'::jsonb)) as x(
         detay_id bigint, fis_id bigint, fis_turu integer, tur_ad text, giris integer, tarih timestamptz, belge_no text,
         cari_kod text, cari_ad text, stok_kodu text, barkod text, urun_adi text, miktar numeric, birim_fiyat numeric, tutar numeric)
   where x.detay_id is not null and x.fis_id is not null and x.tarih >= p_bas and x.tarih < p_bit
  on conflict (kaynak, detay_id) do update set
    fis_id = excluded.fis_id, fis_turu = excluded.fis_turu, tur_ad = excluded.tur_ad, giris = excluded.giris,
    tarih = excluded.tarih, belge_no = excluded.belge_no, cari_kod = excluded.cari_kod, cari_ad = excluded.cari_ad,
    stok_kodu = excluded.stok_kodu, barkod = excluded.barkod, urun_adi = excluded.urun_adi, miktar = excluded.miktar,
    birim_fiyat = excluded.birim_fiyat, tutar = excluded.tutar, guncelleme = now();
  get diagnostics v_eklenen = row_count;
  return jsonb_build_object('status', 'ok', 'silinen', v_silinen, 'eklenen', v_eklenen);
end $$;

create or replace function stok_perakende_yukle(p_kaynak text, p_satirlar jsonb, p_bas date, p_bit date, p_temizle boolean default false)
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
    delete from erp_stok_perakende where kaynak = p_kaynak and gun >= p_bas and gun < p_bit;
    get diagnostics v_silinen = row_count;
  end if;
  insert into erp_stok_perakende as g (kaynak, stok_kodu, gun, miktar, tutar, adet)
  select p_kaynak, x.stok_kodu, x.gun, sum(coalesce(x.miktar, 0)), sum(coalesce(x.tutar, 0)), sum(coalesce(x.adet, 0))
    from jsonb_to_recordset(coalesce(p_satirlar, '[]'::jsonb)) as x(stok_kodu text, gun date, miktar numeric, tutar numeric, adet integer)
   where coalesce(x.stok_kodu, '') <> '' and x.gun >= p_bas and x.gun < p_bit
   group by x.stok_kodu, x.gun
  on conflict (kaynak, stok_kodu, gun) do update set miktar = excluded.miktar, tutar = excluded.tutar, adet = excluded.adet;
  get diagnostics v_eklenen = row_count;
  return jsonb_build_object('status', 'ok', 'silinen', v_silinen, 'eklenen', v_eklenen);
end $$;

-- Bir ürünün stok hareketleri, yeniden eskiye. Stok koduyla aranır; stok kodu yoksa barkodla.
-- satirlar r: [tarih, belge türü, belge no, cari, miktar (+giriş / −çıkış), KDV dahil birim fiyat, tutar, fis_id, kaynak]
-- Perakende satırları gün başına tek satırdır (fis_id boş, belge no yerine "N satış").
create or replace function stok_hareket(p_stok_kodu text, p_barkod text, p_gun integer default 90, p_limit integer default 500)
returns jsonb language sql stable as $$
  with s as (
    select (case when coalesce(p_gun, 0) > 0 then (date_trunc('day', now() at time zone 'Europe/Istanbul') - make_interval(days => p_gun)) at time zone 'Europe/Istanbul' end) as bas
  ), b as (
    select h.tarih, h.tur_ad, h.belge_no, h.cari_ad, h.miktar * (case when h.giris < 0 then -1 else 1 end) as miktar,
           h.birim_fiyat, coalesce(h.tutar, h.miktar * h.birim_fiyat) as tutar, h.fis_id, h.kaynak, h.detay_id
      from erp_fis_satir h, s
     where (case when coalesce(p_stok_kodu, '') <> '' then h.stok_kodu = p_stok_kodu else h.barkod = coalesce(p_barkod, '') end)
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

-- fis_detay: cari adı da dönsün.
create or replace function fis_detay(p_kaynak text, p_fis_id bigint)
returns jsonb language sql stable as $$
  with f as (select * from erp_fis_satir where kaynak = coalesce(p_kaynak, '') and fis_id = p_fis_id)
  select jsonb_build_object(
    'status', 'ok',
    'bulundu', exists (select 1 from f),
    'tur', (select tur_ad from f limit 1),
    'belgeNo', (select belge_no from f limit 1),
    'cari', (select cari_ad from f limit 1),
    'tarih', (select to_char(tarih at time zone 'Europe/Istanbul', 'DD.MM.YYYY') from f limit 1),
    'toplam', (select coalesce(sum(coalesce(tutar, miktar * coalesce(birim_fiyat, 0))), 0) from f),
    'satirlar', coalesce((select jsonb_agg(jsonb_build_array(stok_kodu, barkod, urun_adi, miktar, birim_fiyat, coalesce(tutar, miktar * birim_fiyat)) order by detay_id) from f), '[]'::jsonb)
  )
$$;

alter function fis_satir_yukle(text, jsonb, timestamptz, timestamptz, boolean) security definer set search_path = public, extensions;
alter function stok_perakende_yukle(text, jsonb, date, date, boolean)        security definer set search_path = public, extensions;
alter function stok_hareket(text, text, integer, integer)                    security definer set search_path = public, extensions;
alter function fis_detay(text, bigint)                                       security definer set search_path = public, extensions;

revoke execute on function fis_satir_yukle(text, jsonb, timestamptz, timestamptz, boolean) from public;
revoke execute on function stok_perakende_yukle(text, jsonb, date, date, boolean) from public;
revoke execute on function stok_hareket(text, text, integer, integer) from public;
revoke execute on function fis_detay(text, bigint) from public;
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke all on erp_fis_satir, erp_stok_perakende from anon, authenticated';
    execute 'revoke execute on function fis_satir_yukle(text, jsonb, timestamptz, timestamptz, boolean), stok_perakende_yukle(text, jsonb, date, date, boolean), stok_hareket(text, text, integer, integer), fis_detay(text, bigint) from anon, authenticated';
  end if;
end $$;
