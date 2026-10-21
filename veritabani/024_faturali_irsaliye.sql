-- ============================================================
-- Faturalanmış irsaliye çift sayılmasın (tedarikçi siparişi). 022'den SONRA çalıştırılır; tekrar çalıştırmak güvenlidir.
-- ERP12'de irsaliye faturaya bağlanınca (FATRALANDIRILMIS_IRSALIYEMI) stok FATURADAN sayılır; cari-hareket-gonder.ps1
-- artık o irsaliye satırlarını giris = 0 gönderir. Burada da alış sayılırken bu satırlar atlanır
-- (yoksa irsaliye ve faturası farklı günlerdeyse "kaç kez alındı" ve geliş sıklığı iki kat çıkıyordu).
-- ============================================================

create or replace function tedarikci_oneri(p_cari_kod text, p_gun integer default 365, p_satis_gun integer default 60)
returns jsonb language sql stable as $$
  with a0 as (
    select case when stok_kodu <> '' then stok_kodu else barkod end as anahtar, stok_kodu, barkod, urun_adi, tarih, miktar,
           coalesce(net_fiyat, birim_fiyat) as fiyat, (net_fiyat is not null) as net, giris, detay_id
      from erp_fis_satir
     where cari_kod = coalesce(p_cari_kod, '') and fis_turu in (1, 5) and giris >= 0 and not (fis_turu = 5 and giris = 0) and miktar > 0
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

create or replace function tedarikci_genel(p_gun integer default 365, p_satis_gun integer default 60)
returns jsonb language sql stable as $$
  with a0 as (
    select case when stok_kodu <> '' then stok_kodu else barkod end as anahtar, stok_kodu, barkod, urun_adi, cari_kod,
           tarih, (tarih at time zone 'Europe/Istanbul')::date as gun, miktar, detay_id
      from erp_fis_satir
     where fis_turu in (1, 5) and giris >= 0 and not (fis_turu = 5 and giris = 0) and miktar > 0 and cari_kod <> ''
       and tarih >= now() - make_interval(days => greatest(coalesce(p_gun, 365), 1))
  ), a as (     -- aynı gün aynı miktar (irsaliye + faturası) tek alış
    select distinct on (anahtar, cari_kod, gun, miktar) * from a0 order by anahtar, cari_kod, gun, miktar, detay_id desc
  ), u as (
    select distinct on (anahtar) anahtar, stok_kodu, barkod, urun_adi, cari_kod, tarih, miktar from a order by anahtar, tarih desc, detay_id desc
  ), g as (
    select a.anahtar, (array_agg(a.miktar order by a.tarih desc, a.detay_id desc))[1:10] as miktarlar
      from a join u on u.anahtar = a.anahtar and u.cari_kod = a.cari_kod group by a.anahtar
  ), sk as (select distinct stok_kodu from u where stok_kodu <> ''
  ), s as (
    select h.stok_kodu, sum(h.miktar) as m
      from erp_fis_satir h join sk on sk.stok_kodu = h.stok_kodu
     where h.fis_turu in (2, 6, 12) and h.giris < 0
       and h.tarih >= now() - make_interval(days => greatest(coalesce(p_satis_gun, 60), 1))
     group by h.stok_kodu
  ), p as (
    select r.stok_kodu, -sum(r.miktar) as m
      from erp_stok_perakende r join sk on sk.stok_kodu = r.stok_kodu
     where r.gun >= (now() at time zone 'Europe/Istanbul')::date - greatest(coalesce(p_satis_gun, 60), 1)
     group by r.stok_kodu
  ), fg as (    -- firmanın alış yaptığı günler ve aradaki gün farkı
    select cari_kod, gun, gun - lag(gun) over (partition by cari_kod order by gun) as ara
      from (select distinct cari_kod, gun from a0) x
  ), f as (
    select cari_kod, max(gun) as son_gun, count(*) as kez,
           round((percentile_cont(0.5) within group (order by ara) filter (where ara is not null))::numeric) as aralik
      from fg group by cari_kod
  ), sb as (    -- son belge (fatura / irsaliye)
    select distinct on (cari_kod) cari_kod, kaynak, fis_id, belge_no, tur_ad, tarih
      from erp_fis_satir where fis_turu in (1, 5) and cari_kod <> ''
       and tarih >= now() - make_interval(days => greatest(coalesce(p_gun, 365), 1))
     order by cari_kod, tarih desc, fis_id desc
  ), ad as (
    select distinct on (cari_kod) cari_kod, cari_ad from erp_fis_satir
     where fis_turu in (1, 5) and cari_kod <> '' and cari_ad <> ''
       and tarih >= now() - make_interval(days => greatest(coalesce(p_gun, 365), 1))
     order by cari_kod, tarih desc
  )
  select jsonb_build_object(
    'status', 'ok', 'gun', p_gun, 'satisGun', p_satis_gun,
    'firmalar', coalesce((select jsonb_agg(jsonb_build_array(f.cari_kod, coalesce(ad.cari_ad, ''), to_char(f.son_gun, 'DD.MM.YYYY'), f.kez, f.aralik,
                    sb.fis_id, sb.kaynak, sb.belge_no, sb.tur_ad,
                    (select round(sum(coalesce(t.tutar, t.miktar * coalesce(t.birim_fiyat, 0))), 2) from erp_fis_satir t where t.kaynak = sb.kaynak and t.fis_id = sb.fis_id),
                    to_char(sb.tarih at time zone 'Europe/Istanbul', 'DD.MM.YYYY')) order by f.son_gun desc)
                   from f left join sb on sb.cari_kod = f.cari_kod left join ad on ad.cari_kod = f.cari_kod), '[]'::jsonb),
    'urunler', coalesce((select jsonb_agg(jsonb_build_array(u.stok_kodu, u.barkod, u.urun_adi, u.cari_kod,
                    to_char(u.tarih at time zone 'Europe/Istanbul', 'DD.MM.YYYY'), u.miktar, to_jsonb(g.miktarlar), coalesce(s.m, 0), coalesce(p.m, 0)))
                   from u left join g on g.anahtar = u.anahtar
                   left join s on s.stok_kodu = u.stok_kodu and u.stok_kodu <> ''
                   left join p on p.stok_kodu = u.stok_kodu and u.stok_kodu <> ''), '[]'::jsonb),
    'sonVeri', (select to_char(max(guncelleme) at time zone 'Europe/Istanbul', 'DD.MM.YYYY HH24:MI') from erp_fis_satir)
  )
$$;

create or replace function tedarikci_firma(p_cari_kod text)
returns jsonb language sql stable as $$
  with b as (   -- son belgeler
    select kaynak, fis_id, max(tarih) as tarih, max(tur_ad) as tur_ad, max(belge_no) as belge_no, count(*) as satir,
           round(sum(coalesce(tutar, miktar * coalesce(birim_fiyat, 0))), 2) as tutar
      from erp_fis_satir
     where cari_kod = coalesce(p_cari_kod, '') and fis_turu in (1, 5)
       and tarih >= now() - interval '400 days'
     group by kaynak, fis_id
  ), gunler as (
    select distinct (tarih at time zone 'Europe/Istanbul')::date as gun from erp_fis_satir
     where cari_kod = coalesce(p_cari_kod, '') and fis_turu in (1, 5) and miktar > 0 and tarih >= now() - interval '365 days' and not (fis_turu = 5 and giris = 0)
  ), ara as (select gun - lag(gun) over (order by gun) as a from gunler
  ), fy as (    -- her ürünün bu firmadan alış fiyatları (gün başına bir)
    select distinct on (anahtar, gun) anahtar, gun, fiyat from (
      select case when stok_kodu <> '' then stok_kodu else barkod end as anahtar, (tarih at time zone 'Europe/Istanbul')::date as gun,
             coalesce(net_fiyat, birim_fiyat) as fiyat, (net_fiyat is not null) as net, giris, detay_id
        from erp_fis_satir
       where cari_kod = coalesce(p_cari_kod, '') and fis_turu in (1, 5) and giris >= 0 and not (fis_turu = 5 and giris = 0) and miktar > 0
         and coalesce(net_fiyat, birim_fiyat) is not null and tarih >= now() - interval '730 days') x
     order by anahtar, gun, net desc, giris desc, detay_id desc
  ), fs as (
    select anahtar, gun, fiyat, row_number() over (partition by anahtar order by gun desc) as n from fy
  ), sf as (    -- her ürünün bu firmadan geldiği son belge (fatura varsa fatura, yoksa irsaliye)
    select distinct on (anahtar) anahtar, fis_id, kaynak, tarih, belge_no, tur_ad from (
      select case when stok_kodu <> '' then stok_kodu else barkod end as anahtar, fis_id, kaynak, tarih, belge_no, tur_ad, fis_turu
        from erp_fis_satir
       where cari_kod = coalesce(p_cari_kod, '') and fis_turu in (1, 5) and miktar > 0 and tarih >= now() - interval '400 days') x
     order by anahtar, (tarih at time zone 'Europe/Istanbul')::date desc, (fis_turu = 1) desc, fis_id desc
  )
  select tedarikci_oneri(p_cari_kod, 365, 60) || jsonb_build_object(
    'faturalar', coalesce((select jsonb_agg(jsonb_build_array(fis_id, kaynak, to_char(tarih at time zone 'Europe/Istanbul', 'DD.MM.YYYY'), tur_ad, belge_no, satir, tutar) order by tarih desc, fis_id desc)
                   from (select * from b order by tarih desc, fis_id desc limit 8) x), '[]'::jsonb),
    'gelis', (select count(*) from gunler),
    'aralik', (select round((percentile_cont(0.5) within group (order by a))::numeric) from ara where a is not null),
    'onceki', coalesce((select jsonb_agg(jsonb_build_array(anahtar, round(fiyat, 2), to_char(gun, 'DD.MM.YYYY'))) from fs where n = 2), '[]'::jsonb),
    'sonFis', coalesce((select jsonb_agg(jsonb_build_array(anahtar, fis_id, kaynak, to_char(tarih at time zone 'Europe/Istanbul', 'DD.MM.YYYY'), belge_no, tur_ad)) from sf), '[]'::jsonb),
    'siparisler', coalesce((select jsonb_agg(tedarik_siparis_json(t) order by t.olusturma desc)
                   from (select * from tedarik_siparis where cari_kod = coalesce(p_cari_kod, '') and durum <> 'iptal' order by olusturma desc limit 15) t), '[]'::jsonb)
  )
$$;

alter function tedarikci_oneri(text, integer, integer) security definer set search_path = public, extensions;
alter function tedarikci_genel(integer, integer) security definer set search_path = public, extensions;
alter function tedarikci_firma(text) security definer set search_path = public, extensions;
