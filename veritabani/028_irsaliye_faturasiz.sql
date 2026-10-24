-- ============================================================
-- İrsaliyeler ekranı: FATURALANMIŞ irsaliyeler ve eski sipariş aktarımları (MK SAHA G-/C-) listelenmez.
-- 027'den SONRA çalıştırılır; tekrar çalıştırmak güvenlidir. Veriye dokunmaz, yalnız okur.
-- ============================================================
create or replace function erp_aktarim_durum(p_gun integer default 7)
returns jsonb language sql stable as $$
  with n as (select * from erp_nabiz where ad = 'mal_aktarim'),
  b as (
    select batch_id, min(olusturma) as ilk, max(guncelleme) as son, count(*) as satir,
           min(belge_turu) as belge_turu, min(cari) as cari, min(personel) as personel, min(tip) as tip, min(cari_kodu) as cari_kodu
      from mal_hareketleri
     group by batch_id
    having min(olusturma) >= now() - make_interval(days => greatest(coalesce(p_gun, 7), 1))
       and min(olusturma) >= coalesce((select baslangic from n), '-infinity'::timestamptz)
  ), u as (
    select b.* from b
     where exists (select 1 from mal_hareketleri x where x.batch_id = b.batch_id and x.belge_turu ilike '%rsaliye%')
       and not exists (select 1 from mal_hareketleri x where x.batch_id = b.batch_id
                         and x.belge_turu ilike 'sat%' and x.belge_turu not ilike '%ade%'
                         and coalesce(x.sebep, '') not in ('', 'Satış'))
  ), s0 as (
    select u.*, a.durum as a_durum, a.belge_no, a.mesaj, a.zaman as a_zaman,
           case when a.durum = 'ok' and a.imza <> mal_batch_imza(u.batch_id) then 'degisti'
                when a.durum = 'degisti' then 'degisti_bildirildi'
                when a.durum in ('ok', 'hata') then a.durum
                else 'bekliyor' end as durum
      from u left join erp_siparis_aktarim a on a.batch_id = u.batch_id
  ), s as (
    -- Gösterilmez: ERP'de FATURALANMIŞ irsaliyeler ve eski sipariş aktarımları (MK SAHA G-/C-).
    select s0.* from s0
     where coalesce(s0.belge_no, '') not like 'MK SAHA %'
       and not (s0.durum = 'ok' and s0.belge_no <> ''
                and exists (select 1 from erp_fis_satir e where e.belge_no = s0.belge_no and e.cari_kod = s0.cari_kodu and e.fis_turu in (5, 6, 7, 8))
                and not exists (select 1 from erp_fis_satir e where e.belge_no = s0.belge_no and e.cari_kod = s0.cari_kodu and e.fis_turu in (5, 6, 7, 8) and e.giris <> 0))
  )
  select jsonb_build_object('status', 'ok', 'gun', p_gun,
    'nabiz', (select jsonb_build_object('zaman', to_char(zaman at time zone 'Europe/Istanbul', 'DD.MM.YYYY HH24:MI'),
                                        'dk', floor(extract(epoch from now() - zaman) / 60), 'mesaj', mesaj) from n),
    'nabizlar', coalesce((select jsonb_object_agg(ad, jsonb_build_object('zaman', to_char(zaman at time zone 'Europe/Istanbul', 'DD.MM.YYYY HH24:MI'),
                                        'dk', floor(extract(epoch from now() - zaman) / 60), 'mesaj', mesaj)) from erp_nabiz), '{}'::jsonb),
    'ozet', jsonb_build_object(
       'ok', (select count(*) from s where durum = 'ok'),
       'bekliyor', (select count(*) from s where durum = 'bekliyor'),
       'hata', (select count(*) from s where durum = 'hata'),
       'degisti', (select count(*) from s where durum in ('degisti', 'degisti_bildirildi'))),
    'belgeler', coalesce((select jsonb_agg(jsonb_build_array(batch_id, belge_turu, cari, personel,
                    to_char(ilk at time zone 'Europe/Istanbul', 'DD.MM HH24:MI'), durum, coalesce(belge_no, ''), coalesce(mesaj, ''),
                    floor(extract(epoch from now() - son) / 60), satir, tip) order by ilk desc)
                   from (select * from s order by ilk desc limit 200) x), '[]'::jsonb)
  )
$$;

create or replace function erp_irsaliyeler(p_gun integer default 30, p_ara text default '')
returns jsonb language sql stable as $$
  with f as (
    select kaynak, fis_id, max(tarih) as tarih, max(fis_turu) as fis_turu, max(tur_ad) as tur_ad, max(belge_no) as belge_no,
           max(cari_kod) as cari_kod, max(cari_ad) as cari_ad, count(*) as satir,
           round(sum(coalesce(tutar, miktar * coalesce(birim_fiyat, 0))), 2) as tutar,
           bool_and(giris = 0) as faturali
      from erp_fis_satir
     where fis_turu in (5, 6, 7, 8)
       and tarih >= now() - make_interval(days => least(greatest(coalesce(p_gun, 30), 1), 400))
     group by kaynak, fis_id
  )
  select jsonb_build_object('status', 'ok',
    'irsaliyeler', coalesce((select jsonb_agg(jsonb_build_array(fis_id, kaynak, to_char(tarih at time zone 'Europe/Istanbul', 'DD.MM.YYYY'),
                    fis_turu, tur_ad, belge_no, cari_kod, cari_ad, satir, tutar, faturali) order by tarih desc, fis_id desc)
                   from (select * from f
                          where not faturali and (coalesce(p_ara, '') = ''
                             or belge_no ilike '%' || p_ara || '%' or cari_ad ilike '%' || p_ara || '%' or cari_kod ilike '%' || p_ara || '%')
                          order by tarih desc, fis_id desc limit 300) x), '[]'::jsonb),
    'sonVeri', (select to_char(max(guncelleme) at time zone 'Europe/Istanbul', 'DD.MM.YYYY HH24:MI') from erp_fis_satir)
  )
$$;

alter function erp_aktarim_durum(integer) security definer set search_path = public, extensions;
alter function erp_irsaliyeler(integer, text) security definer set search_path = public, extensions;
revoke execute on function erp_aktarim_durum(integer) from public;
revoke execute on function erp_irsaliyeler(integer, text) from public;
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke execute on function erp_aktarim_durum(integer), erp_irsaliyeler(integer, text) from anon, authenticated';
  end if;
end $$;
