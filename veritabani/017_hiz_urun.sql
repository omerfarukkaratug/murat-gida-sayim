-- ============================================================
-- HIZ (2): Ürün Hareketleri ekranı. 016'dan sonra çalıştırılır; tekrar çalıştırmak güvenlidir. Veriye dokunmaz.
--
--  1) urun_hareket: "stok kodu VEYA barkod" koşulu indeksleri devre dışı bırakıyor, her aramada
--     erp_hareket ve erp_fis_satir tablolarının TAMAMINI okuyordu. İki ayrı kola bölündü
--     (sonuç birebir aynı; aynı satır iki kez sayılmaz).
--  2) "ERP verisi" saati için max(guncelleme) erp_hareket'i baştan sona okuyordu: indeks.
--  3) Perakende toplamı stok koduyla aranıyor ama tablonun anahtarı (kaynak, stok_kodu, gun): indeks.
--  (Denemede ~150 ms → ~3 ms.)
-- ============================================================

create index if not exists erp_hareket_guncelleme on erp_hareket (guncelleme);
create index if not exists erp_perakende_gunluk_stok on erp_perakende_gunluk (stok_kodu, gun);

create or replace function urun_hareket(p_stok_kodu text, p_barkod text, p_gun integer default 365, p_limit integer default 200)
returns jsonb language sql stable as $$
  with a as (
    select coalesce(p_stok_kodu, '') as sk, coalesce(p_barkod, '') as bk,
           case when coalesce(p_gun, 0) > 0 then now() - make_interval(days => p_gun) end as bas
  ), u as (     -- alış (1, 5) ve firmalara satış (2, 6, 12): hareket aktarımı
    select h.tarih, h.cari, h.belge_no, h.miktar, h.birim, h.birim_fiyat, h.fis_turu, ''::text as tur_ad, h.yon, h.kaynak, h.detay_id
      from erp_hareket h
     where coalesce(p_stok_kodu, '') <> '' and h.stok_kodu = p_stok_kodu
    union all
    select h.tarih, h.cari, h.belge_no, h.miktar, h.birim, h.birim_fiyat, h.fis_turu, ''::text as tur_ad, h.yon, h.kaynak, h.detay_id
      from erp_hareket h
     where coalesce(p_barkod, '') <> '' and h.barkod = p_barkod
       and not (coalesce(p_stok_kodu, '') <> '' and h.stok_kodu = p_stok_kodu)
  ), f as (     -- diğer stok giriş / çıkışları + hareket aktarımında olmayan alışlar
    select s.tarih, coalesce(nullif(s.cari_ad, ''), s.cari_kod, '') as cari, s.belge_no, s.miktar, ''::text as birim,
           coalesce(s.net_fiyat, s.birim_fiyat) as birim_fiyat, s.fis_turu, s.tur_ad,
           case when s.giris > 0 then 'gelen' else 'satilan' end as yon, s.kaynak, s.detay_id
      from (select * from erp_fis_satir where coalesce(p_stok_kodu, '') <> '' and stok_kodu = p_stok_kodu
            union all
            select * from erp_fis_satir where coalesce(p_barkod, '') <> '' and barkod = p_barkod
               and not (coalesce(p_stok_kodu, '') <> '' and stok_kodu = p_stok_kodu)) s
     where s.giris <> 0
       and (s.fis_turu not in (1, 5, 2, 6, 12, 11)
            or (s.fis_turu in (1, 5) and not exists (select 1 from erp_hareket e where e.kaynak = s.kaynak and e.detay_id = s.detay_id)))
  ), t as (select * from u union all select * from f
  ), h as (
    select t.* from t, a where t.yon = 'gelen' or a.bas is null or t.tarih >= a.bas
  ), p as (
    select coalesce(sum(miktar), 0) as miktar from erp_perakende_gunluk, a
     where a.sk <> '' and stok_kodu = a.sk and (a.bas is null or gun >= a.bas::date)
  )
  select jsonb_build_object(
    'status', 'ok',
    'gelenToplam',  (select coalesce(sum(miktar), 0) from h where yon = 'gelen'),
    'firmaToplam',  (select coalesce(sum(miktar), 0) from h where yon = 'satilan'),
    'perakende',    (select miktar from p),
    'gelen',   coalesce((select jsonb_agg(jsonb_build_array(to_char(tarih at time zone 'Europe/Istanbul', 'DD.MM.YYYY'), cari, belge_no, miktar, birim, birim_fiyat, fis_turu, tur_ad) order by tarih desc)
                          from (select * from h where yon = 'gelen' order by tarih desc limit 2000) x), '[]'::jsonb),
    'satilan', coalesce((select jsonb_agg(jsonb_build_array(to_char(tarih at time zone 'Europe/Istanbul', 'DD.MM.YYYY'), cari, belge_no, miktar, birim, birim_fiyat, fis_turu, tur_ad) order by tarih desc)
                          from (select * from h where yon = 'satilan' order by tarih desc limit greatest(coalesce(p_limit, 200), 1)) y), '[]'::jsonb),
    'sonVeri', (select to_char(max(guncelleme) at time zone 'Europe/Istanbul', 'DD.MM.YYYY HH24:MI') from erp_hareket),
    'kaynaklar', coalesce((select jsonb_agg(distinct kaynak) from h), '[]'::jsonb),
    'gelenTumu', true
  )
$$;
alter function urun_hareket(text, text, integer, integer) security definer set search_path = public, extensions;
revoke execute on function urun_hareket(text, text, integer, integer) from public;
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke execute on function urun_hareket(text, text, integer, integer) from anon, authenticated';
  end if;
end $$;

analyze erp_hareket;
analyze erp_perakende_gunluk;
