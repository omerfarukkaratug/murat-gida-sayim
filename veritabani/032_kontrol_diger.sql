-- SADECE KONTROL (hiçbir şeyi değiştirmez):
-- 21.10'dan beri kaydedilmiş, "Satış İrsaliyesi" olduğu halde sebebi "Satış" OLMADIĞI için ERP'ye gitmeyen belgeler.
select min(m.olusturma at time zone 'Europe/Istanbul')::timestamp(0) as kayit_zamani,
       max(m.cari) as cari, max(m.sebep) as sebep, max(m.personel) as personel,
       count(*) as satir, max(m.belge_no) as belge_no
  from mal_hareketleri m
 where m.belge_turu ilike 'sat%' and m.belge_turu not ilike '%ade%' and m.belge_turu ilike '%rsaliye%'
   and coalesce(m.sebep, '') not in ('', 'Satış')
   and m.olusturma >= '2026-10-21'
   and not exists (select 1 from erp_siparis_aktarim a where a.batch_id = m.batch_id and a.durum in ('ok', 'degisti'))
 group by m.batch_id
 order by 1;
