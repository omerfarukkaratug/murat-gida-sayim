-- ============================================================
-- HIZ: Stok Hareketleri ekranı (ve "ERP verisi" saatini gösteren her ekran) hızlandırma.
-- 015'ten sonra çalıştırılır; tekrar çalıştırmak güvenlidir. Veriye dokunmaz.
--
--  1) stok_hareket: WHERE içindeki CASE (stok kodu mu barkod mu) indeksi devre dışı bırakıyor,
--     her aramada BÜTÜN fatura satırlarını tarıyordu. İki ayrı kola bölündü → indeks kullanılır.
--     (1,5 milyon satırlık denemede ~400 ms → ~2 ms.)
--  2) "ERP verisi: …" saati için max(guncelleme) her çağrıda tabloyu baştan sona okuyordu: indeks eklendi.
-- ============================================================

create index if not exists erp_fis_satir_guncelleme on erp_fis_satir (guncelleme);

create or replace function stok_hareket(p_stok_kodu text, p_barkod text, p_gun integer default 90, p_limit integer default 500)
returns jsonb language sql stable as $$
  with s as (
    select (case when coalesce(p_gun, 0) > 0 then (date_trunc('day', now() at time zone 'Europe/Istanbul') - make_interval(days => p_gun)) at time zone 'Europe/Istanbul' end) as bas
  ), b as (
    select h.tarih, h.tur_ad, h.belge_no, h.cari_ad, h.miktar * (case when h.giris < 0 then -1 else 1 end) as miktar,
           h.birim_fiyat, coalesce(h.tutar, h.miktar * h.birim_fiyat) as tutar, h.fis_id, h.kaynak, h.detay_id
      from erp_fis_satir h, s
     where coalesce(p_stok_kodu, '') <> '' and h.stok_kodu = p_stok_kodu
       and h.giris <> 0
       and (s.bas is null or h.tarih >= s.bas)
    union all
    select h.tarih, h.tur_ad, h.belge_no, h.cari_ad, h.miktar * (case when h.giris < 0 then -1 else 1 end) as miktar,
           h.birim_fiyat, coalesce(h.tutar, h.miktar * h.birim_fiyat) as tutar, h.fis_id, h.kaynak, h.detay_id
      from erp_fis_satir h, s
     where coalesce(p_stok_kodu, '') = '' and coalesce(p_barkod, '') <> '' and h.barkod = p_barkod
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
alter function stok_hareket(text, text, integer, integer) security definer set search_path = public, extensions;

revoke execute on function stok_hareket(text, text, integer, integer) from public;
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke execute on function stok_hareket(text, text, integer, integer) from anon, authenticated';
  end if;
end $$;

analyze erp_fis_satir;
