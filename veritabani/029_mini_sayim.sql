-- ============================================================
-- 🎯 Günlük mini sayım: riskli ürünleri seçmek için ürün başına satış ve son sayım bilgisi.
-- 028'den SONRA çalıştırılır; tekrar çalıştırmak güvenlidir. Veriye dokunmaz, yalnız okur.
--
-- mini_sayim_aday(): { stok_kodu: [son 30 gün satış, son 90 gün satış, son sayım tarihi (YYYY-MM-DD) | null, son sayımdaki fark | null] }
--   Satış = toptan/fatura satışları + kasa (perakende) satışları, adet olarak.
--   Son sayım = sayım kayıtlarında ürünün en son okutulduğu dönem ve o dönemdeki toplam fark (sayılan − sistem).
-- ============================================================
create or replace function mini_sayim_aday()
returns jsonb language sql stable as $$
  with f as (
    select stok_kodu,
           sum(case when tarih >= now() - interval '30 days' then miktar else 0 end) as s30,
           sum(miktar) as s90
      from erp_fis_satir
     where fis_turu in (2, 6, 12) and giris < 0 and stok_kodu <> '' and tarih >= now() - interval '90 days'
     group by stok_kodu
  ), p as (
    select stok_kodu,
           -sum(case when gun >= current_date - 30 then miktar else 0 end) as s30,
           -sum(miktar) as s90
      from erp_stok_perakende
     where gun >= current_date - 90 and stok_kodu <> ''
     group by stok_kodu
  ), satis as (
    select stok_kodu, sum(s30) as s30, sum(s90) as s90 from (select * from f union all select * from p) x group by stok_kodu
  ), ss as (   -- her ürünün en son sayıldığı dönem
    select distinct on (stok_kodu) stok_kodu, donem_id, olusturma
      from sayim_kayitlari where stok_kodu <> '' and not gec_geldi
     order by stok_kodu, olusturma desc
  ), sf as (
    select ss.stok_kodu, to_char(ss.olusturma at time zone 'Europe/Istanbul', 'YYYY-MM-DD') as tarih,
           (select sum(k.adet) - max(k.eski_stok) from sayim_kayitlari k
             where k.stok_kodu = ss.stok_kodu and k.donem_id is not distinct from ss.donem_id and not k.gec_geldi) as fark
      from ss
  )
  select jsonb_build_object('status', 'ok',
    'urunler', coalesce((select jsonb_object_agg(k, v) from (
        select coalesce(s.stok_kodu, sf.stok_kodu) as k,
               jsonb_build_array(round(coalesce(s.s30, 0), 3), round(coalesce(s.s90, 0), 3), sf.tarih, round(sf.fark, 3)) as v
          from satis s full join sf on sf.stok_kodu = s.stok_kodu) x), '{}'::jsonb),
    'sonVeri', (select to_char(max(guncelleme) at time zone 'Europe/Istanbul', 'DD.MM.YYYY HH24:MI') from erp_fis_satir))
$$;

alter function mini_sayim_aday() security definer set search_path = public, extensions;
revoke execute on function mini_sayim_aday() from public;
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke execute on function mini_sayim_aday() from anon, authenticated';
  end if;
end $$;

-- Satışları ürün + tarihle hızlı bulmak için (zaten varsa atlanır).
create index if not exists erp_fis_satir_satis_stok on erp_fis_satir (stok_kodu, tarih) where fis_turu in (2, 6, 12) and giris < 0;
