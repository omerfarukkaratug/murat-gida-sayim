-- ============================================================
-- Mal Giriş / Çıkış → ERP12 İRSALİYE (doğrudan). 023'ten SONRA çalıştırılır; tekrar çalıştırmak güvenlidir.
-- ERP'ye yalnız irsaliye türündeki belgeler aktarılır: Alış İrsaliyesi, Satış İrsaliyesi (sebep Satış),
-- Alıştan İade İrsaliyesi, Satıştan İade İrsaliyesi. Alış/Satış Fişi ve fire/transfer kayıtları Excel yolunda kalır.
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
       -- Fiş türleri ve fire / transfer / sayım farkı Excel yolunda kalır. Satış irsaliyesi sebebi Satış olmalı.
       and exists (select 1 from mal_hareketleri x where x.batch_id = b.batch_id and x.belge_turu ilike '%rsaliye%')
       and not exists (select 1 from mal_hareketleri x where x.batch_id = b.batch_id
                         and x.belge_turu ilike 'sat%' and x.belge_turu not ilike '%ade%'
                         and coalesce(x.sebep, '') not in ('', 'Satış'))
     order by b.ilk limit p_limit
  )
  select jsonb_build_object('status', 'ok',
    'belgeler', coalesce((select jsonb_agg(jsonb_build_object(
        'batch_id', k.batch_id, 'imza', mal_batch_imza(k.batch_id),
        'tip', h.tip, 'belge_turu', h.belge_turu, 'belge_no', h.belge_no, 'cari', h.cari, 'cari_kodu', h.cari_kodu,
        'sebep', h.sebep, 'personel', h.personel, 'aciklama', h.aciklama, 'tarih', k.ilk,
        'satirlar', (select jsonb_agg(jsonb_build_object('kayit_id', m.kayit_id, 'barkod', m.barkod, 'stok_kodu', m.stok_kodu,
                                       'urun_adi', m.urun_adi, 'miktar', m.miktar, 'fiyat', m.fiyat, 'kdv', m.kdv) order by m.olusturma, m.kayit_id)
                       from mal_hareketleri m where m.batch_id = k.batch_id)) order by k.ilk)
      from bekleyen k
      cross join lateral (select * from mal_hareketleri x where x.batch_id = k.batch_id order by x.olusturma limit 1) h), '[]'::jsonb),
    'degisen', coalesce((select jsonb_agg(jsonb_build_object('batch_id', a.batch_id, 'belge_no', a.belge_no))
                           from erp_siparis_aktarim a
                          where a.durum = 'ok' and a.imza <> mal_batch_imza(a.batch_id)
                            and exists (select 1 from mal_hareketleri m where m.batch_id = a.batch_id)), '[]'::jsonb))
$$;
