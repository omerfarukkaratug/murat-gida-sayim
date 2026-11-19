-- ============================================================
-- İrsaliyeler ekranı: ERP'ye GİTMEYEN ya da gitmiş görünüp ERP'de OLMAYAN belgeler de görünsün.
--  - fis          : "Alış Fişi / Satış Fişi" — bilerek ERP'ye gitmez (muhasebe faturadan girer)
--  - gitmez       : Satış İrsaliyesi + sebep fire / transfer / sayım farkı — bilerek ERP'ye gitmez
--  - iade_yanlis  : tedarikçiye iade "Satış İrsaliyesi" olarak işlenmiş — ERP'ye GİTMEDİ (Alıştan İade olmalıydı)
--  - erpde_yok    : aktarım "ok" dedi ama ERP verisinde (saatlik gelen) bu belge no 3 saattir yok — silinmiş olabilir
-- Eskiden ilk üçü listede hiç görünmüyordu; bu yüzden 7 iade fark edilmedi.
-- Ayrıca sorgu yalnız son günlerin belgelerine bakar (eskiden her çağrıda bütün tabloyu grupluyordu).
-- 040'tan SONRA çalıştırılır; tekrar çalıştırmak güvenlidir. Veri değiştirmez.
-- ============================================================

create index if not exists mal_hareketleri_olusturma on mal_hareketleri (olusturma);

create or replace function erp_aktarim_durum(p_gun integer default 7)
returns jsonb language sql stable as $$
  with n as (select * from erp_nabiz where ad = 'mal_aktarim'),
  sinir as (select greatest(now() - make_interval(days => greatest(coalesce(p_gun, 7), 1)),
                            coalesce((select baslangic from n), '-infinity'::timestamptz)) as t),
  son_erp as (select max(guncelleme) as t from erp_fis_satir),
  aday as (select distinct batch_id from mal_hareketleri where olusturma >= (select t from sinir)),
  b as (
    select m.batch_id, min(m.olusturma) as ilk, max(m.guncelleme) as son, count(*) as satir,
           min(m.belge_turu) as belge_turu, min(m.cari) as cari, min(m.personel) as personel, min(m.tip) as tip,
           min(m.cari_kodu) as cari_kodu, min(coalesce(m.sebep, '')) as sebep
      from mal_hareketleri m join aday on aday.batch_id = m.batch_id
     group by m.batch_id
    having min(m.olusturma) >= (select t from sinir)
  ), s0 as (
    select b.*, a.belge_no, a.zaman as a_zaman,
           case when a.belge_no = 'IPTAL' then 'iptal'
                when a.durum = 'ok' and a.imza <> mal_batch_imza(b.batch_id) then 'degisti'
                when a.durum = 'degisti' then 'degisti_bildirildi'
                when a.durum = 'hata' then 'hata'
                when a.durum = 'ok' then
                  case when a.zaman < now() - interval '3 hours' and coalesce(a.belge_no, '') <> '' and coalesce(b.cari_kodu, '') <> ''
                             and (select t from son_erp) > a.zaman + interval '15 minutes'
                             and not exists (select 1 from erp_fis_satir e where e.cari_kod = b.cari_kodu and e.belge_no = a.belge_no and e.fis_turu in (5, 6, 7, 8))
                       then 'erpde_yok' else 'ok' end
                when b.belge_turu not ilike '%rsaliye%' then 'fis'
                when b.belge_turu ilike 'sat%' and b.belge_turu not ilike '%ade%' and b.sebep = 'Tedarikçiye iade' then 'iade_yanlis'
                when b.belge_turu ilike 'sat%' and b.belge_turu not ilike '%ade%'
                     and b.sebep in ('Fire / zayi', 'Şubeler arası transfer', 'Sayım farkı / düzeltme') then 'gitmez'
                else 'bekliyor' end as durum,
           case when b.belge_turu not ilike '%rsaliye%' then 'Fiş türü ERP''ye gitmez (muhasebe faturadan girer). İrsaliyeyle geldiyse yöneticiye söyleyin.'
                when b.belge_turu ilike 'sat%' and b.belge_turu not ilike '%ade%' and b.sebep = 'Tedarikçiye iade'
                     then 'Tedarikçiye iade "Satış İrsaliyesi" olarak işlenmiş: ERP''ye GİTMEDİ. "Alıştan İade İrsaliyesi" olmalıydı — yöneticiye söyleyin.'
                when b.belge_turu ilike 'sat%' and b.belge_turu not ilike '%ade%' and b.sebep in ('Fire / zayi', 'Şubeler arası transfer', 'Sayım farkı / düzeltme')
                     then 'Sebep "' || b.sebep || '": ERP''ye irsaliye olarak gitmez (Excel ile işlenir).'
                else coalesce(a.mesaj, '') end as mesaj
      from b left join erp_siparis_aktarim a on a.batch_id = b.batch_id
  ), s as (
    -- Gösterilmez: elle iptal edilenler, ERP'de FATURALANMIŞ irsaliyeler ve eski sipariş aktarımları (MK SAHA G-/C-).
    select s0.* from s0
     where s0.durum <> 'iptal'
       and coalesce(s0.belge_no, '') not like 'MK SAHA %'
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
       'degisti', (select count(*) from s where durum in ('degisti', 'degisti_bildirildi')),
       'gitmedi', (select count(*) from s where durum in ('iade_yanlis', 'erpde_yok')),
       'fis', (select count(*) from s where durum in ('fis', 'gitmez'))),
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

select 'Tamam: irsaliyeler ekranı ERP''ye gitmeyenleri de gösterir' as sonuc;
