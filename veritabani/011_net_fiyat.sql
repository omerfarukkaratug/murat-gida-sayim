-- ============================================================
-- NET FİYAT: tüm iskontolar (satır + fiş/dip iskontosu) düşülmüş, KDV DAHİL birim fiyat.
-- 010_plasiyer.sql'den SONRA çalıştırılır; tekrar çalıştırmak güvenlidir.
--
-- Eskiden belge satırlarında yalnızca DAHIL_FIYAT (iskontosuz, KDV dahil liste/brüt fiyat) vardı;
-- plasiyerin gördüğü "son alışlar" ve "son satış fiyatı" iskontoları düşmüyordu.
-- ERP12 FIS_DETAY: net_fiyat = (TOPLAM_KDV_MATRAHI + TOPLAM_KDV) / MIKTAR_FIS
--   (KDV matrahı satır ve fiş iskontoları düşülmüş tutardır; cari-hareket-gonder.ps1 hesaplar).
-- net_fiyat boşsa (eski satırlar, script güncellenmeden önce) brüt birim_fiyat kullanılır;
-- script günde bir tüm hareketleri yeniden gönderdiği için geçmiş de kendiliğinden dolar.
-- ============================================================

alter table erp_fis_satir add column if not exists net_fiyat numeric;   -- KDV DAHİL, iskontolar düşülmüş birim fiyat

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
  insert into erp_fis_satir as h (kaynak, detay_id, fis_id, fis_turu, tur_ad, giris, tarih, belge_no, cari_kod, cari_ad, stok_kodu, barkod, urun_adi, miktar, birim_fiyat, tutar, net_fiyat, guncelleme)
  select p_kaynak, x.detay_id, x.fis_id, coalesce(x.fis_turu, 0), coalesce(x.tur_ad, ''), coalesce(x.giris, 0), x.tarih,
         coalesce(x.belge_no, ''), coalesce(x.cari_kod, ''), coalesce(x.cari_ad, ''), coalesce(x.stok_kodu, ''), coalesce(x.barkod, ''),
         coalesce(x.urun_adi, ''), coalesce(x.miktar, 0), x.birim_fiyat, x.tutar, x.net_fiyat, now()
    from jsonb_to_recordset(coalesce(p_satirlar, '[]'::jsonb)) as x(
         detay_id bigint, fis_id bigint, fis_turu integer, tur_ad text, giris integer, tarih timestamptz, belge_no text,
         cari_kod text, cari_ad text, stok_kodu text, barkod text, urun_adi text, miktar numeric, birim_fiyat numeric, tutar numeric, net_fiyat numeric)
   where x.detay_id is not null and x.fis_id is not null and x.tarih >= p_bas and x.tarih < p_bit
  on conflict (kaynak, detay_id) do update set
    fis_id = excluded.fis_id, fis_turu = excluded.fis_turu, tur_ad = excluded.tur_ad, giris = excluded.giris,
    tarih = excluded.tarih, belge_no = excluded.belge_no, cari_kod = excluded.cari_kod, cari_ad = excluded.cari_ad,
    stok_kodu = excluded.stok_kodu, barkod = excluded.barkod, urun_adi = excluded.urun_adi, miktar = excluded.miktar,
    birim_fiyat = excluded.birim_fiyat, tutar = excluded.tutar, net_fiyat = excluded.net_fiyat, guncelleme = now();
  get diagnostics v_eklenen = row_count;
  return jsonb_build_object('status', 'ok', 'silinen', v_silinen, 'eklenen', v_eklenen);
end $$;

-- Müşteriye son satış: NET (iskontolar düşülmüş) KDV dahil fiyat; yoksa brüt.
-- satirlar r: [stok kodu, barkod, fiyat, tarih, miktar, kaç kez, ortalama miktar, net mi (1/0)]
create or replace function plasiyer_son_fiyat(p_cari_kod text, p_gun integer default 365)
returns jsonb language sql stable as $$
  with d as (
    select stok_kodu, barkod, coalesce(net_fiyat, birim_fiyat) as fiyat, (net_fiyat is not null) as net, tarih, miktar, detay_id
      from erp_fis_satir
     where cari_kod = coalesce(p_cari_kod, '') and fis_turu in (2, 6, 12) and giris < 0
       and coalesce(net_fiyat, birim_fiyat, 0) > 0 and miktar > 0
       and (coalesce(p_gun, 0) <= 0 or tarih >= now() - make_interval(days => p_gun))
  ), s as (
    select distinct on (case when stok_kodu <> '' then stok_kodu else barkod end)
           stok_kodu, barkod, fiyat, net, tarih, miktar,
           count(*) over (partition by case when stok_kodu <> '' then stok_kodu else barkod end) as kez,
           avg(miktar) over (partition by case when stok_kodu <> '' then stok_kodu else barkod end) as ort
      from d
     order by case when stok_kodu <> '' then stok_kodu else barkod end, tarih desc, detay_id desc
  )
  select jsonb_build_object(
    'status', 'ok',
    'cariKod', coalesce(p_cari_kod, ''),
    'satirlar', coalesce((select jsonb_agg(jsonb_build_array(stok_kodu, barkod, round(fiyat, 2),
                    to_char(tarih at time zone 'Europe/Istanbul', 'DD.MM.YYYY'), miktar, kez, round(ort, 2), case when net then 1 else 0 end) order by kez desc, tarih desc) from s), '[]'::jsonb),
    'sonVeri', (select to_char(max(guncelleme) at time zone 'Europe/Istanbul', 'DD.MM.YYYY HH24:MI') from erp_fis_satir)
  )
$$;

-- Ürünün alışları ve tedarikçileri: NET (tüm iskontolar düşülmüş) KDV dahil birim fiyat; yoksa brüt.
-- alislar r:      [tarih, cari kodu, cari adı, net fiyat, miktar, belge no, brüt fiyat, net mi (1/0)]
-- tedarikciler r: [cari kodu, cari adı, son net fiyat, son tarih, kaç alış]
create or replace function plasiyer_urun_alis(p_stok_kodu text, p_barkod text, p_limit integer default 8)
returns jsonb language sql stable as $$
  with d as (
    select tarih, cari_kod, cari_ad, coalesce(net_fiyat, birim_fiyat) as fiyat, birim_fiyat, (net_fiyat is not null) as net, miktar, belge_no, detay_id
      from erp_fis_satir
     where fis_turu in (1, 5) and giris > 0 and coalesce(net_fiyat, birim_fiyat, 0) > 0
       and ((coalesce(p_stok_kodu, '') <> '' and stok_kodu = p_stok_kodu)
         or (coalesce(p_stok_kodu, '') = '' and coalesce(p_barkod, '') <> '' and barkod = p_barkod))
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

alter function fis_satir_yukle(text, jsonb, timestamptz, timestamptz, boolean) security definer set search_path = public, extensions;
alter function plasiyer_son_fiyat(text, integer)       security definer set search_path = public, extensions;
alter function plasiyer_urun_alis(text, text, integer) security definer set search_path = public, extensions;
revoke execute on function fis_satir_yukle(text, jsonb, timestamptz, timestamptz, boolean) from public;
revoke execute on function plasiyer_son_fiyat(text, integer) from public;
revoke execute on function plasiyer_urun_alis(text, text, integer) from public;
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke execute on function fis_satir_yukle(text, jsonb, timestamptz, timestamptz, boolean), plasiyer_son_fiyat(text, integer), plasiyer_urun_alis(text, text, integer) from anon, authenticated';
  end if;
end $$;
