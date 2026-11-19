-- ============================================================
-- ERP aktarım sorgusunu hafiflet (Disk G/Ç bütçesi tükeniyordu).
-- Eski aktarilacak_mal her çağrıda (≈15 sn'de bir) BÜTÜN mal_hareketleri tablosunu gruplayıp
-- ve aktarılmış BÜTÜN belgelerin imzasını yeniden hesaplıyordu. Tablo büyüdükçe Nano sunucunun
-- disk okuma kotası bitti, proje "Sağlıksız" oldu.
-- Yeni: yalnızca son 45 günde değişen belgelere bakar (guncelleme indeksi), kurallar AYNI.
-- 033'ten SONRA çalıştırılır; tekrar çalıştırmak güvenlidir. Veri silmez, değiştirmez.
-- ============================================================

create index if not exists erp_siparis_aktarim_zaman on erp_siparis_aktarim (zaman);

create or replace function aktarilacak_mal(p_baslangic timestamptz, p_bekle_dk integer default 10, p_limit integer default 50)
returns jsonb language sql stable as $$
  with aday as (
    -- Son 45 günde (ve başlangıçtan sonra) satırı eklenen/değişen belgeler
    select distinct batch_id from mal_hareketleri
     where guncelleme >= greatest(p_baslangic, now() - interval '45 days')
  ), aday2 as (
    select aday.batch_id from aday
     where not exists (select 1 from erp_siparis_aktarim a where a.batch_id = aday.batch_id and a.durum in ('ok', 'degisti'))
  ), b as (
    select m.batch_id, min(m.olusturma) as ilk, max(m.guncelleme) as son
      from mal_hareketleri m join aday2 on aday2.batch_id = m.batch_id
     group by m.batch_id
    having min(m.olusturma) >= p_baslangic and max(m.guncelleme) < now() - make_interval(mins => p_bekle_dk)
  ), bekleyen as (
    select b.* from b
     where exists (select 1 from mal_hareketleri x where x.batch_id = b.batch_id and x.belge_turu ilike '%rsaliye%')
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
    -- Aktarıldıktan sonra telefonda değişen: yalnız son 45 günde aktarılanlar ve satırı yakın zamanda değişenler
    'degisen', coalesce((select jsonb_agg(jsonb_build_object('batch_id', a.batch_id, 'belge_no', a.belge_no))
                           from erp_siparis_aktarim a
                          where a.durum = 'ok' and a.zaman >= now() - interval '45 days'
                            and (exists (select 1 from mal_hareketleri m where m.batch_id = a.batch_id and m.guncelleme > a.zaman)
                                 or exists (select 1 from mal_silinenler s where s.batch_id = a.batch_id and s.zaman > a.zaman))
                            and exists (select 1 from mal_hareketleri m where m.batch_id = a.batch_id)
                            and a.imza <> mal_batch_imza(a.batch_id)), '[]'::jsonb))
$$;

alter function aktarilacak_mal(timestamptz, integer, integer) security definer set search_path = public, extensions;
revoke execute on function aktarilacak_mal(timestamptz, integer, integer) from public;
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke execute on function aktarilacak_mal(timestamptz, integer, integer) from anon, authenticated';
  end if;
end $$;

select 'Tamam: aktarim sorgusu hafifletildi' as sonuc;
