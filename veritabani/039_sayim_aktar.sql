-- ============================================================
-- 📦 Bölüm bölüm sayımı ERP12'ye aktarma (erp/sayim-aktar.ps1). 038'den sonra çalıştırılır; tekrar çalıştırmak güvenlidir.
-- Veriye dokunmaz, yalnız okur: ERP bilgisayarındaki program bir sayım döneminin bütün okutmalarını buradan alır,
-- depo + raf sayımlarını ürün (stok kodu) bazında birleştirip ERP'nin kendi SAYIM belgesine yazar.
--
-- sayim_donemleri_ver(): son 20 sayım dönemi [id, başlangıç (ISO), açıklama, okutma sayısı]
-- sayim_kayitlari_ver(p_donem): dönemin okutmaları (geç gelenler hariç)
--   [kayit_id, stok_kodu, barkod, urun_adi, adet, birim, reyon, okutma zamanı (epoch ms), personel]
--   adet: ADET olarak (koli okutulduysa telefon koli × içindeki adet olarak kaydeder).
-- ============================================================
create or replace function sayim_donemleri_ver() returns jsonb language sql stable as $$
  select jsonb_build_object('status', 'ok', 'donemler', coalesce((
    select jsonb_agg(jsonb_build_array(d.id, to_char(d.baslangic at time zone 'Europe/Istanbul', 'YYYY-MM-DD"T"HH24:MI:SS'), d.aciklama,
                     (select count(*) from sayim_kayitlari k where k.donem_id = d.id and not k.gec_geldi)) order by d.id desc)
      from (select * from sayim_donemleri order by id desc limit 20) d), '[]'::jsonb));
$$;

create or replace function sayim_kayitlari_ver(p_donem bigint) returns jsonb language sql stable as $$
  select jsonb_build_object('status', 'ok', 'donem', p_donem,
    'baslangic', (select to_char(baslangic at time zone 'Europe/Istanbul', 'YYYY-MM-DD"T"HH24:MI:SS') from sayim_donemleri where id = p_donem),
    'satirlar', coalesce((
      select jsonb_agg(jsonb_build_array(k.kayit_id, k.stok_kodu, k.barkod, k.urun_adi, k.adet, k.birim, k.reyon,
                       floor(extract(epoch from coalesce(k.okutma_zamani, k.olusturma)) * 1000)::bigint, k.personel) order by k.okutma_zamani)
        from sayim_kayitlari k where k.donem_id = p_donem and not k.gec_geldi), '[]'::jsonb));
$$;

alter function sayim_donemleri_ver() security definer set search_path = public, extensions;
alter function sayim_kayitlari_ver(bigint) security definer set search_path = public, extensions;
revoke execute on function sayim_donemleri_ver() from public;
revoke execute on function sayim_kayitlari_ver(bigint) from public;
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke execute on function sayim_donemleri_ver(), sayim_kayitlari_ver(bigint) from anon, authenticated';
  end if;
end $$;
notify pgrst, 'reload config';
