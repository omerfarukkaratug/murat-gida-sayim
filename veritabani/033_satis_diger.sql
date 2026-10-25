-- ============================================================
-- Satış irsaliyesi sebebi "Diğer" olsa da ERP'ye gitsin (müşteriye kesilen irsaliye).
-- ERP'ye GİTMEYEN sebepler: Tedarikçiye iade, Fire / zayi, Şubeler arası transfer, Sayım farkı / düzeltme.
-- 031'den SONRA çalıştırılır; tekrar çalıştırmak güvenlidir. Bu dosya çalışınca 24.10'daki ATABEY irsaliyesi
-- (sebep Diğer, 13 satır) birkaç dakika içinde ERP'ye gider.
-- ============================================================
create or replace function aktarilacak_mal(p_baslangic timestamptz, p_bekle_dk integer default 10, p_limit integer default 50)
returns jsonb language sql stable as $$
  with b as (
    select batch_id, min(olusturma) as ilk, max(guncelleme) as son
      from mal_hareketleri
     group by batch_id
    having min(olusturma) >= p_baslangic and max(guncelleme) < now() - make_interval(mins => p_bekle_dk)
  ), bekleyen as (
    select b.* from b
     where not exists (select 1 from erp_siparis_aktarim a where a.batch_id = b.batch_id and a.durum in ('ok', 'degisti'))
       -- Yalnız İRSALİYE türleri ERP'ye irsaliye olarak gider (alış, satış, alıştan iade, satıştan iade).
       -- Fiş türleri ve fire / transfer / sayım farkı / tedarikçiye iade Excel yolunda kalır. Satış irsaliyesinde sebep
       -- "Satış" ya da "Diğer" ise (müşteriye kesilen irsaliye) ERP'ye gider.
       and exists (select 1 from mal_hareketleri x where x.batch_id = b.batch_id and x.belge_turu ilike '%rsaliye%')
       and not exists (select 1 from mal_hareketleri x where x.batch_id = b.batch_id
                         and x.belge_turu ilike 'sat%' and x.belge_turu not ilike '%ade%'
                         and coalesce(x.sebep, '') in ('Tedarikçiye iade', 'Fire / zayi', 'Şubeler arası transfer', 'Sayım farkı / düzeltme'))
     order by b.ilk limit p_limit
  )
  select jsonb_build_object('status', 'ok',
    'belgeler', coalesce((select jsonb_agg(jsonb_build_object(
        'batch_id', k.batch_id, 'imza', mal_batch_imza(k.batch_id),
        'tip', h.tip, 'belge_turu', h.belge_turu, 'belge_no', h.belge_no, 'cari', h.cari, 'cari_kodu', h.cari_kodu,
        'sebep', h.sebep, 'personel', h.personel, 'aciklama', h.aciklama, 'tarih', k.ilk,
        'satirlar', (select jsonb_agg(jsonb_build_object('kayit_id', m.kayit_id, 'barkod', m.barkod, 'stok_kodu', m.stok_kodu,
                                       'urun_adi', m.urun_adi, 'miktar', m.miktar, 'fiyat', m.fiyat, 'kdv', m.kdv) order by m.sira, m.olusturma, m.kayit_id)
                       from mal_hareketleri m where m.batch_id = k.batch_id)) order by k.ilk)
      from bekleyen k
      cross join lateral (select * from mal_hareketleri x where x.batch_id = k.batch_id order by x.sira, x.olusturma limit 1) h), '[]'::jsonb),
    'degisen', coalesce((select jsonb_agg(jsonb_build_object('batch_id', a.batch_id, 'belge_no', a.belge_no))
                           from erp_siparis_aktarim a
                          where a.durum = 'ok' and a.imza <> mal_batch_imza(a.batch_id)
                            and exists (select 1 from mal_hareketleri m where m.batch_id = a.batch_id)), '[]'::jsonb))
$$;

alter function aktarilacak_mal(timestamptz, integer, integer) security definer set search_path = public, extensions;
revoke execute on function aktarilacak_mal(timestamptz, integer, integer) from public;
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke execute on function aktarilacak_mal(timestamptz, integer, integer) from anon, authenticated';
  end if;
end $$;

-- İrsaliyeler ekranı da aynı kuralla listelesin.
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
                         and coalesce(x.sebep, '') in ('Tedarikçiye iade', 'Fire / zayi', 'Şubeler arası transfer', 'Sayım farkı / düzeltme'))
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

alter function erp_aktarim_durum(integer) security definer set search_path = public, extensions;
revoke execute on function erp_aktarim_durum(integer) from public;
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke execute on function erp_aktarim_durum(integer) from anon, authenticated';
  end if;
end $$;
