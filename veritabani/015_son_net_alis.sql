-- ============================================================
-- Ürün başına SON NET ALIŞ (tüm iskontolar düşülmüş, KDV dahil) — maliyet / taban fiyat bunun üzerinden.
-- 012'den sonra çalıştırılır; tekrar çalıştırmak güvenlidir.
-- Apps Script katalog her güncellendiğinde bunu çağırır ve Katalog'un "Son Net Alış" sütununa yazar.
-- Dönüş: { "durum": "ok", "h": { "<stok kodu>": net, … } }  (net bilgisi gelmemiş ürün listede yok)
-- ============================================================
create index if not exists erp_fis_satir_alis_net on erp_fis_satir (stok_kodu, tarih desc) where fis_turu in (1, 5) and net_fiyat is not null;

create or replace function son_net_alis_harita()
returns jsonb language sql stable as $$
  select jsonb_build_object('status', 'ok', 'h', coalesce(jsonb_object_agg(stok_kodu, net), '{}'::jsonb))
    from (
      select distinct on (stok_kodu) stok_kodu, round(net_fiyat, 2) as net
        from erp_fis_satir
       where fis_turu in (1, 5) and giris >= 0 and net_fiyat > 0 and miktar > 0 and stok_kodu <> ''
       order by stok_kodu, (tarih at time zone 'Europe/Istanbul')::date desc, detay_id desc
    ) x
$$;

alter function son_net_alis_harita() security definer set search_path = public, extensions;
revoke execute on function son_net_alis_harita() from public;
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke execute on function son_net_alis_harita() from anon, authenticated';
  end if;
end $$;
