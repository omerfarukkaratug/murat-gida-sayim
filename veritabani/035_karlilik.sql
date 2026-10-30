-- ============================================================
-- 💰 KÂRLILIK RAPORU verisi. 034'ten sonra çalıştırılır; tekrar çalıştırmak güvenlidir.
-- Veriye dokunmaz, yalnız okur.
--
-- karlilik_veri(p_gun, p_kdv):
--   p_gun : ürün tablosunun dönemi (son kaç gün; 7–400)
--   p_kdv : { "<stok kodu>": KDV oranı (%), … }  — katalogdan; tutarlar KDV HARİÇ'e çevrilir (yoksa 0 sayılır)
--
--   Satış  = kasa (erp_stok_perakende; iade düşülmüş) + firmalara satış (fiş türü 2, 6, 12) − firmadan satıştan iade.
--   Maliyet = satılan miktar × O AYDA GEÇERLİ son NET alış (iskontolar düşülmüş; ay sonuna kadarki son alış,
--            hiç yoksa ilk alış). Alışı hiç olmayan ürünün satışı "maliyetsiz" ayrı toplanır, kâra katılmaz.
--
--   urunler r: [0 stok kodu, 1 ad, 2 kasa miktar, 3 firma miktar, 4 ciro (KDV hariç), 5 maliyet (hariç),
--               6 maliyetsiz ciro, 7 son net alış (hariç), 8 son alış tarihi, 9 son alış cari kodu, 10 son alış cari adı,
--               11 ~1 yıl önceki net alış (hariç), 12 son 30 gün kasa birim fiyatı (hariç), 13 ~1 yıl önce kasa birim fiyatı (hariç),
--               14 KDV %, 15 ilk satış günü (dönem içinde), 16 satış yapılan gün sayısı]
--   aylar   r: [0 'YYYY-MM', 1 ciro (hariç), 2 maliyet (hariç), 3 maliyetsiz ciro, 4 kasa ciro, 5 firma ciro]   (son 13 ay)
-- ============================================================

create index if not exists erp_fis_satir_alis_stok on erp_fis_satir (stok_kodu, tarih desc) where fis_turu in (1, 5) and giris >= 0 and miktar > 0;

create or replace function karlilik_veri(p_gun integer default 90, p_kdv jsonb default '{}'::jsonb)
returns jsonb language plpgsql volatile as $$
declare
  v_gun int := least(greatest(coalesce(p_gun, 90), 7), 400);
  v_bugun date := (now() at time zone 'Europe/Istanbul')::date;
  v_bas date := v_bugun - v_gun;
  v_ay_bas date := (date_trunc('month', v_bugun) - interval '12 months')::date;
  v_sonuc jsonb;
begin
  -- KDV haritası
  create temp table if not exists _kk (stok_kodu text primary key, kdv numeric) on commit drop;
  truncate _kk;
  insert into _kk select key, coalesce(nullif(value #>> '{}', '')::numeric, 0) from jsonb_each(coalesce(p_kdv, '{}'::jsonb)) on conflict do nothing;

  -- Satışlar: ürün + gün (KDV dahil, işareti düzeltilmiş: satış +)
  create temp table if not exists _ks (stok_kodu text, gun date, kasa_m numeric, firma_m numeric, kasa_t numeric, firma_t numeric) on commit drop;
  truncate _ks;
  insert into _ks
  select stok_kodu, gun, -sum(miktar), 0, -sum(tutar), 0
    from erp_stok_perakende
   where gun >= least(v_bas, v_ay_bas) and stok_kodu <> ''
   group by stok_kodu, gun;
  insert into _ks
  select stok_kodu, (tarih at time zone 'Europe/Istanbul')::date,
         0, sum(case when giris < 0 then miktar else -miktar end), 0,
         sum((case when giris < 0 then 1 else -1 end) * miktar * coalesce(net_fiyat, birim_fiyat, 0))
    from erp_fis_satir
   where tarih >= least(v_bas, v_ay_bas)::timestamp at time zone 'Europe/Istanbul' and stok_kodu <> '' and miktar > 0
     and ((fis_turu in (2, 6, 12) and giris < 0) or (giris > 0 and tur_ad ilike '%iade%' and fis_turu not in (1, 5)))
   group by stok_kodu, (tarih at time zone 'Europe/Istanbul')::date;

  -- Ay bazında satış + o ayın maliyeti (ay sonuna kadarki son net alış; yoksa ilk alış)
  create temp table if not exists _ka (stok_kodu text, ay date, kasa_m numeric, firma_m numeric, kasa_t numeric, firma_t numeric, maliyet numeric) on commit drop;
  truncate _ka;
  insert into _ka
  select s.stok_kodu, date_trunc('month', s.gun)::date, sum(s.kasa_m), sum(s.firma_m), sum(s.kasa_t), sum(s.firma_t), null
    from _ks s group by s.stok_kodu, date_trunc('month', s.gun)::date;
  update _ka a set maliyet = (
      select coalesce(net_fiyat, birim_fiyat) from erp_fis_satir h
       where h.stok_kodu = a.stok_kodu and h.fis_turu in (1, 5) and h.giris >= 0 and h.miktar > 0 and coalesce(net_fiyat, birim_fiyat, 0) > 0
         and h.tarih < ((a.ay + interval '1 month')::date)::timestamp at time zone 'Europe/Istanbul'
       order by h.tarih desc, h.detay_id desc limit 1);
  update _ka a set maliyet = (
      select coalesce(net_fiyat, birim_fiyat) from erp_fis_satir h
       where h.stok_kodu = a.stok_kodu and h.fis_turu in (1, 5) and h.giris >= 0 and h.miktar > 0 and coalesce(net_fiyat, birim_fiyat, 0) > 0
       order by h.tarih asc, h.detay_id asc limit 1)
   where a.maliyet is null;

  with
  -- dönem içindeki satışlar (ürün tablosu): gün bazından, maliyet o günün ayından
  d as (
    select s.stok_kodu, sum(s.kasa_m) as kasa_m, sum(s.firma_m) as firma_m, sum(s.kasa_t + s.firma_t) as ciro_d,
           sum(case when a.maliyet is not null then (s.kasa_m + s.firma_m) * a.maliyet else 0 end) as maliyet_d,
           sum(case when a.maliyet is null then s.kasa_t + s.firma_t else 0 end) as maliyetsiz_d,
           min(s.gun) as ilk_gun, count(distinct s.gun) filter (where s.kasa_m + s.firma_m > 0) as gun_say
      from _ks s left join _ka a on a.stok_kodu = s.stok_kodu and a.ay = date_trunc('month', s.gun)::date
     where s.gun >= v_bas
     group by s.stok_kodu
  ),
  son as (      -- son net alış + firması
    select distinct on (h.stok_kodu) h.stok_kodu, coalesce(h.net_fiyat, h.birim_fiyat) as fiyat, h.tarih, h.cari_kod, h.cari_ad, h.urun_adi
      from erp_fis_satir h join d on d.stok_kodu = h.stok_kodu
     where h.fis_turu in (1, 5) and h.giris >= 0 and h.miktar > 0 and coalesce(h.net_fiyat, h.birim_fiyat, 0) > 0
     order by h.stok_kodu, h.tarih desc, h.detay_id desc
  ),
  once as (     -- ~1 yıl önce geçerli net alış
    select distinct on (h.stok_kodu) h.stok_kodu, coalesce(h.net_fiyat, h.birim_fiyat) as fiyat
      from erp_fis_satir h join d on d.stok_kodu = h.stok_kodu
     where h.fis_turu in (1, 5) and h.giris >= 0 and h.miktar > 0 and coalesce(h.net_fiyat, h.birim_fiyat, 0) > 0
       and h.tarih < ((v_bugun - 335)::timestamp at time zone 'Europe/Istanbul')
       and h.tarih >= ((v_bugun - 430)::timestamp at time zone 'Europe/Istanbul')
     order by h.stok_kodu, h.tarih desc, h.detay_id desc
  ),
  kb as (       -- kasa birim fiyatı: son 30 gün ve bir yıl önceki 30 gün
    select r.stok_kodu,
           sum(-r.tutar) filter (where r.gun > v_bugun - 30) / nullif(sum(-r.miktar) filter (where r.gun > v_bugun - 30), 0) as simdi,
           sum(-r.tutar) filter (where r.gun > v_bugun - 395 and r.gun <= v_bugun - 335) / nullif(sum(-r.miktar) filter (where r.gun > v_bugun - 395 and r.gun <= v_bugun - 335), 0) as once
      from erp_stok_perakende r join d on d.stok_kodu = r.stok_kodu
     where r.gun > v_bugun - 395 and r.miktar < 0
     group by r.stok_kodu
  ),
  ad as (       -- ürün adı: son satış/alış satırından
    select distinct on (h.stok_kodu) h.stok_kodu, h.urun_adi from erp_fis_satir h join d on d.stok_kodu = h.stok_kodu
     where h.urun_adi <> '' order by h.stok_kodu, h.tarih desc
  ),
  aylik as (
    select a.ay,
           sum((a.kasa_t + a.firma_t) / (1 + coalesce(k.kdv, 0) / 100)) as ciro,
           sum(case when a.maliyet is not null then (a.kasa_m + a.firma_m) * a.maliyet / (1 + coalesce(k.kdv, 0) / 100) else 0 end) as maliyet,
           sum(case when a.maliyet is null then (a.kasa_t + a.firma_t) / (1 + coalesce(k.kdv, 0) / 100) else 0 end) as maliyetsiz,
           sum(a.kasa_t / (1 + coalesce(k.kdv, 0) / 100)) as kasa, sum(a.firma_t / (1 + coalesce(k.kdv, 0) / 100)) as firma
      from _ka a left join _kk k on k.stok_kodu = a.stok_kodu
     where a.ay >= v_ay_bas
     group by a.ay
  )
  select jsonb_build_object(
    'status', 'ok', 'gun', v_gun, 'bas', to_char(v_bas, 'DD.MM.YYYY'), 'bugun', to_char(v_bugun, 'DD.MM.YYYY'),
    'urunler', coalesce((select jsonb_agg(jsonb_build_array(
        d.stok_kodu, coalesce(ad.urun_adi, son.urun_adi, ''),
        round(d.kasa_m, 3), round(d.firma_m, 3),
        round(d.ciro_d / (1 + coalesce(k.kdv, 0) / 100), 2), round(d.maliyet_d / (1 + coalesce(k.kdv, 0) / 100), 2),
        round(d.maliyetsiz_d / (1 + coalesce(k.kdv, 0) / 100), 2),
        round(son.fiyat / (1 + coalesce(k.kdv, 0) / 100), 4), to_char(son.tarih at time zone 'Europe/Istanbul', 'DD.MM.YYYY'),
        coalesce(son.cari_kod, ''), coalesce(son.cari_ad, ''),
        round(once.fiyat / (1 + coalesce(k.kdv, 0) / 100), 4),
        round(kb.simdi / (1 + coalesce(k.kdv, 0) / 100), 4), round(kb.once / (1 + coalesce(k.kdv, 0) / 100), 4),
        coalesce(k.kdv, 0), to_char(d.ilk_gun, 'DD.MM.YYYY'), d.gun_say))
      from d left join _kk k on k.stok_kodu = d.stok_kodu left join son on son.stok_kodu = d.stok_kodu
             left join once on once.stok_kodu = d.stok_kodu left join kb on kb.stok_kodu = d.stok_kodu left join ad on ad.stok_kodu = d.stok_kodu
     where d.kasa_m + d.firma_m <> 0 or d.ciro_d <> 0), '[]'::jsonb),
    'aylar', coalesce((select jsonb_agg(jsonb_build_array(to_char(ay, 'YYYY-MM'), round(ciro, 2), round(maliyet, 2), round(maliyetsiz, 2), round(kasa, 2), round(firma, 2)) order by ay) from aylik), '[]'::jsonb),
    'sonVeri', (select to_char(max(guncelleme) at time zone 'Europe/Istanbul', 'DD.MM.YYYY HH24:MI') from erp_fis_satir)
  ) into v_sonuc;
  return v_sonuc;
end $$;

alter function karlilik_veri(integer, jsonb) security definer set search_path = public, extensions;
revoke execute on function karlilik_veri(integer, jsonb) from public;
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke execute on function karlilik_veri(integer, jsonb) from anon, authenticated';
  end if;
end $$;
