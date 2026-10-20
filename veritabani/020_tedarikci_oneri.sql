-- ============================================================
-- Tedarikçi sipariş önerisi (Cari Hareketleri → 🛒 Sipariş önerisi). 019'dan sonra çalıştırılır;
-- tekrar çalıştırmak güvenlidir. Veriye dokunmaz, yalnız okur.
--
-- Bir carinin (tedarikçi) son p_gun günde bize sattığı her ürün için:
--   son alış (tarih, miktar, NET fiyat varsa net), kaç kez alındığı, son 10 alış miktarı (paket tahmini için),
--   son p_satis_gun gündeki satış: firmalara (fiş türü 2, 6, 12; stoktan çıkan) + perakende (kasa) toplamı.
-- Stok ve öneri adedi telefonda hesaplanır (stok katalogda; hedef gün kullanıcı seçer).
-- Aynı gün aynı miktar (irsaliye + faturası) tek alış sayılır.
-- satirlar r: [stok kodu, barkod, ürün adı, son alış tarihi, son alış miktarı, son alış fiyatı, kaç kez,
--              son 10 alış miktarı (dizi), firma satışı, perakende satışı]
-- ============================================================
create or replace function tedarikci_oneri(p_cari_kod text, p_gun integer default 365, p_satis_gun integer default 60)
returns jsonb language sql stable as $$
  with a0 as (
    select case when stok_kodu <> '' then stok_kodu else barkod end as anahtar, stok_kodu, barkod, urun_adi, tarih, miktar,
           coalesce(net_fiyat, birim_fiyat) as fiyat, (net_fiyat is not null) as net, giris, detay_id
      from erp_fis_satir
     where cari_kod = coalesce(p_cari_kod, '') and fis_turu in (1, 5) and giris >= 0 and miktar > 0
       and tarih >= now() - make_interval(days => greatest(coalesce(p_gun, 365), 1))
  ), a as (
    select distinct on (anahtar, (tarih at time zone 'Europe/Istanbul')::date, miktar) *
      from a0 order by anahtar, (tarih at time zone 'Europe/Istanbul')::date, miktar, net desc, giris desc, detay_id desc
  ), u as (
    select distinct on (anahtar) anahtar, stok_kodu, barkod, urun_adi, tarih, miktar, fiyat
      from a order by anahtar, tarih desc, detay_id desc
  ), g as (
    select anahtar, count(*) as kez, (array_agg(miktar order by tarih desc, detay_id desc))[1:10] as miktarlar from a group by anahtar
  ), sk as (select distinct stok_kodu from u where stok_kodu <> ''
  ), s as (     -- firmalara satış (stoktan çıkan satış belgeleri)
    select h.stok_kodu, sum(h.miktar) as m
      from erp_fis_satir h join sk on sk.stok_kodu = h.stok_kodu
     where h.fis_turu in (2, 6, 12) and h.giris < 0
       and h.tarih >= now() - make_interval(days => greatest(coalesce(p_satis_gun, 60), 1))
     group by h.stok_kodu
  ), p as (     -- perakende (kasa): miktar işaretli, satış −
    select r.stok_kodu, -sum(r.miktar) as m
      from erp_stok_perakende r join sk on sk.stok_kodu = r.stok_kodu
     where r.gun >= (now() at time zone 'Europe/Istanbul')::date - greatest(coalesce(p_satis_gun, 60), 1)
     group by r.stok_kodu
  )
  select jsonb_build_object(
    'status', 'ok',
    'cariKod', coalesce(p_cari_kod, ''),
    'gun', p_gun, 'satisGun', p_satis_gun,
    'satirlar', coalesce((select jsonb_agg(jsonb_build_array(u.stok_kodu, u.barkod, u.urun_adi,
                    to_char(u.tarih at time zone 'Europe/Istanbul', 'DD.MM.YYYY'), u.miktar, round(u.fiyat, 2), g.kez, to_jsonb(g.miktarlar),
                    coalesce(s.m, 0), coalesce(p.m, 0)) order by u.tarih desc)
                   from u join g on g.anahtar = u.anahtar
                   left join s on s.stok_kodu = u.stok_kodu and u.stok_kodu <> ''
                   left join p on p.stok_kodu = u.stok_kodu and u.stok_kodu <> ''), '[]'::jsonb),
    'sonVeri', (select to_char(max(guncelleme) at time zone 'Europe/Istanbul', 'DD.MM.YYYY HH24:MI') from erp_fis_satir)
  )
$$;

alter function tedarikci_oneri(text, integer, integer) security definer set search_path = public, extensions;
revoke execute on function tedarikci_oneri(text, integer, integer) from public;
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke execute on function tedarikci_oneri(text, integer, integer) from anon, authenticated';
  end if;
end $$;

-- Tedarikçinin alışlarını hızlı bulmak için (cari + alış türü).
create index if not exists erp_fis_satir_cari_alis on erp_fis_satir (cari_kod, tarih desc) where fis_turu in (1, 5);
