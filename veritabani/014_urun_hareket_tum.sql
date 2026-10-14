-- ============================================================
-- Ürün Hareketleri: eksik görünen girişler.
-- 012'den SONRA çalıştırılır; tekrar çalıştırmak güvenlidir.
--
-- Sorun: "Ürün Hareketleri" yalnız alış faturası/irsaliyesini (FIS_TURU 1, 5) ve STOK KODUYLA arıyordu.
--   • Ürün başka bir belge türüyle girdiyse (devir, depo transferi, sayım fazlası, iade, üretim…) hiç görünmüyordu.
--   • ERP satırında stok kartı boş / farklı ama BARKOD doğruysa da görünmüyordu.
-- Çözüm:
--   • stok kodu VEYA barkod eşleşmesi,
--   • erp_fis_satir'daki (cari-hareket-gonder.ps1 gönderir) stoğa GİREN diğer belgeler "gelen"e,
--     stoktan ÇIKAN diğer belgeler "satilan"a eklenir; satırda belge türünün ERP'deki adı yazar (8. alan),
--   • alış satırı erp_hareket'te yoksa (hareket aktarımı gecikti) erp_fis_satir'dan tamamlanır.
-- Satır: [tarih, cari, belge no, miktar, birim, birim fiyat, fiş türü, belge türü adı]
-- ============================================================

create or replace function urun_hareket(p_stok_kodu text, p_barkod text, p_gun integer default 365, p_limit integer default 200)
returns jsonb language sql stable as $$
  with a as (
    select coalesce(p_stok_kodu, '') as sk, coalesce(p_barkod, '') as bk,
           case when coalesce(p_gun, 0) > 0 then now() - make_interval(days => p_gun) end as bas
  ), u as (     -- alış (1, 5) ve firmalara satış (2, 6, 12): hareket aktarımı
    select h.tarih, h.cari, h.belge_no, h.miktar, h.birim, h.birim_fiyat, h.fis_turu, ''::text as tur_ad, h.yon, h.kaynak, h.detay_id
      from erp_hareket h, a
     where (a.sk <> '' and h.stok_kodu = a.sk) or (a.bk <> '' and h.barkod = a.bk)
  ), f as (     -- diğer stok giriş / çıkışları + hareket aktarımında olmayan alışlar
    select s.tarih, coalesce(nullif(s.cari_ad, ''), s.cari_kod, '') as cari, s.belge_no, s.miktar, ''::text as birim,
           coalesce(s.net_fiyat, s.birim_fiyat) as birim_fiyat, s.fis_turu, s.tur_ad,
           case when s.giris > 0 then 'gelen' else 'satilan' end as yon, s.kaynak, s.detay_id
      from erp_fis_satir s, a
     where ((a.sk <> '' and s.stok_kodu = a.sk) or (a.bk <> '' and s.barkod = a.bk))
       and s.giris <> 0
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
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke execute on function urun_hareket(text, text, integer, integer) from anon, authenticated';
  end if;
end $$;
