-- ============================================================
-- Plasiyer modülü — ERP12'den gelen belgelerden SALT OKUNUR bilgiler.
-- 007_stok_hareketleri.sql'den SONRA çalıştırılır; tekrar çalıştırmak güvenlidir.
-- Yeni tablo YOK: veri, cari-hareket-gonder.ps1'in zaten doldurduğu erp_fis_satir'den okunur.
-- Plasiyerin siparişleri / tahsilat notları ERP'ye ve buraya YAZILMAZ (Google Sheets'te durur).
--
-- Belge türleri (003_urun_hareketleri.sql ile aynı): alış 1/5, firma satışı 2/6/12.
-- Fiyatlar KDV DAHİL birim fiyattır (erp_fis_satir.birim_fiyat).
-- ============================================================

-- Müşteriye en son satılan fiyat: her ürün için son firma satışı.
-- satirlar r: [stok kodu, barkod, KDV dahil birim fiyat, tarih (DD.MM.YYYY), miktar, kaç kez satıldı]
create or replace function plasiyer_son_fiyat(p_cari_kod text, p_gun integer default 365)
returns jsonb language sql stable as $$
  with d as (
    select stok_kodu, barkod, birim_fiyat, tarih, miktar, detay_id
      from erp_fis_satir
     where cari_kod = coalesce(p_cari_kod, '') and fis_turu in (2, 6, 12) and giris < 0
       and coalesce(birim_fiyat, 0) > 0 and miktar > 0
       and (coalesce(p_gun, 0) <= 0 or tarih >= now() - make_interval(days => p_gun))
  ), s as (
    select distinct on (case when stok_kodu <> '' then stok_kodu else barkod end)
           stok_kodu, barkod, birim_fiyat, tarih, miktar,
           count(*) over (partition by case when stok_kodu <> '' then stok_kodu else barkod end) as kez
      from d
     order by case when stok_kodu <> '' then stok_kodu else barkod end, tarih desc, detay_id desc
  )
  select jsonb_build_object(
    'status', 'ok',
    'cariKod', coalesce(p_cari_kod, ''),
    'satirlar', coalesce((select jsonb_agg(jsonb_build_array(stok_kodu, barkod, round(birim_fiyat, 2),
                    to_char(tarih at time zone 'Europe/Istanbul', 'DD.MM.YYYY'), miktar, kez) order by tarih desc) from s), '[]'::jsonb),
    'sonVeri', (select to_char(max(guncelleme) at time zone 'Europe/Istanbul', 'DD.MM.YYYY HH24:MI') from erp_fis_satir)
  )
$$;

-- Ürünün tedarikçileri ve alış fiyatları (en yeni alışlar + tedarikçi başına son alış).
-- alislar r:      [tarih, cari kodu, cari adı, KDV dahil birim fiyat, miktar, belge no]
-- tedarikciler r: [cari kodu, cari adı, son KDV dahil fiyat, son tarih, kaç alış]
create or replace function plasiyer_urun_alis(p_stok_kodu text, p_barkod text, p_limit integer default 8)
returns jsonb language sql stable as $$
  with d as (
    select tarih, cari_kod, cari_ad, birim_fiyat, miktar, belge_no, detay_id
      from erp_fis_satir
     where fis_turu in (1, 5) and giris > 0 and coalesce(birim_fiyat, 0) > 0
       and ((coalesce(p_stok_kodu, '') <> '' and stok_kodu = p_stok_kodu)
         or (coalesce(p_stok_kodu, '') = '' and coalesce(p_barkod, '') <> '' and barkod = p_barkod))
  ), t as (
    select distinct on (cari_kod) cari_kod, cari_ad, birim_fiyat, tarih,
           count(*) over (partition by cari_kod) as kez
      from d order by cari_kod, tarih desc, detay_id desc
  )
  select jsonb_build_object(
    'status', 'ok',
    'alislar', coalesce((select jsonb_agg(jsonb_build_array(to_char(tarih at time zone 'Europe/Istanbul', 'DD.MM.YYYY'), cari_kod, cari_ad,
                    round(birim_fiyat, 2), miktar, belge_no) order by tarih desc, detay_id desc)
                   from (select * from d order by tarih desc, detay_id desc limit greatest(coalesce(p_limit, 8), 1)) x), '[]'::jsonb),
    'tedarikciler', coalesce((select jsonb_agg(jsonb_build_array(cari_kod, cari_ad, round(birim_fiyat, 2),
                    to_char(tarih at time zone 'Europe/Istanbul', 'DD.MM.YYYY'), kez) order by tarih desc) from t), '[]'::jsonb)
  )
$$;

alter function plasiyer_son_fiyat(text, integer)       security definer set search_path = public, extensions;
alter function plasiyer_urun_alis(text, text, integer) security definer set search_path = public, extensions;
revoke execute on function plasiyer_son_fiyat(text, integer) from public;
revoke execute on function plasiyer_urun_alis(text, text, integer) from public;
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke execute on function plasiyer_son_fiyat(text, integer), plasiyer_urun_alis(text, text, integer) from anon, authenticated';
  end if;
end $$;
