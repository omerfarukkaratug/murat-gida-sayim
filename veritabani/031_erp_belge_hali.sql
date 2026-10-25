-- ============================================================
-- Telefondan ERP'ye giden irsaliyenin ERP'deki GÜNCEL hâli (muhasebe ERP'de satır ekleyip/silip/miktar düzeltmiş olabilir).
-- 030'dan SONRA çalıştırılır; tekrar çalıştırmak güvenlidir. Veriye dokunmaz, yalnız okur.
--
-- erp_belge_hali(belge no, cari kodu): o carinin o numaralı irsaliyesi (alış/satış/iade irsaliyesi).
--   { bulundu, kaynak, fisId, tur, tarih, guncelleme, satirlar: [[stok kodu, barkod, ürün adı, miktar]] }  (ERP'deki satır sırasıyla)
--   ERP verisi saatte bir gelir: ERP'de yapılan düzeltme en geç ~1 saat sonra görünür.
-- ============================================================
create or replace function erp_belge_hali(p_belge_no text, p_cari_kod text)
returns jsonb language sql stable as $$
  with fis as (   -- aynı numara birden çok yılda/kaynakta olabilir: en yenisi
    select kaynak, fis_id from erp_fis_satir
     where belge_no = coalesce(p_belge_no, '') and cari_kod = coalesce(p_cari_kod, '') and fis_turu in (5, 6, 7, 8)
     order by tarih desc, fis_id desc limit 1
  ), f as (
    select e.* from erp_fis_satir e join fis on fis.kaynak = e.kaynak and fis.fis_id = e.fis_id
  )
  select jsonb_build_object('status', 'ok',
    'bulundu', exists (select 1 from f),
    'kaynak', (select kaynak from fis), 'fisId', (select fis_id from fis),
    'tur', (select tur_ad from f limit 1),
    'tarih', (select to_char(tarih at time zone 'Europe/Istanbul', 'DD.MM.YYYY') from f limit 1),
    'guncelleme', (select to_char(max(guncelleme) at time zone 'Europe/Istanbul', 'DD.MM.YYYY HH24:MI') from f),
    'satirlar', coalesce((select jsonb_agg(jsonb_build_array(stok_kodu, barkod, urun_adi, abs(miktar)) order by detay_id) from f), '[]'::jsonb))
$$;

alter function erp_belge_hali(text, text) security definer set search_path = public, extensions;
revoke execute on function erp_belge_hali(text, text) from public;
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke execute on function erp_belge_hali(text, text) from anon, authenticated';
  end if;
end $$;

-- Belge numarasıyla hızlı bulmak için (zaten varsa atlanır).
create index if not exists erp_fis_satir_belge on erp_fis_satir (cari_kod, belge_no) where fis_turu in (5, 6, 7, 8);
