-- ============================================================
-- Vade Raporu "Veri tabanına ulaşılamadı" düzeltmesi. 033'ten sonra çalıştırılır; tekrar çalıştırmak güvenlidir.
--  - Bir carinin ödeme riski hesaplanırken hata çıkarsa bütün rapor düşüyordu: artık o cari atlanır.
--  - Bir açılışta risk hesabına en fazla 10 sn ayrılır (eskiden 20 sn; zaman aşımına yaklaşıyordu).
--    Yetişmeyen cariler sonraki açılışlarda tamamlanır (risk 6 saat saklanır).
-- ============================================================
create or replace function vade_raporu(p_yon text)
returns jsonb language plpgsql volatile as $$
declare
  v_yon text := coalesce(p_yon, 'alacak');
  v_bas timestamptz := clock_timestamp();
  v_eksik int := 0;
  r record;
  v_sonuc jsonb;
begin
  create temp table if not exists _vr (cari_kod text, cari_ad text, acik numeric, gecmis numeric, hafta numeric, ileri numeric, gecikme numeric, ort_vade date) on commit drop;
  truncate _vr;
  insert into _vr
  select a.cari_kod, max(a.cari_ad), sum(acik),
         sum(case when a.vade < g.bugun then acik else 0 end),
         sum(case when a.vade >= g.bugun and a.vade <= g.bugun + 7 then acik else 0 end),
         sum(case when a.vade > g.bugun + 7 then acik else 0 end),
         round(sum(case when a.vade < g.bugun then acik * (g.bugun - a.vade) else 0 end) / nullif(sum(case when a.vade < g.bugun then acik else 0 end), 0)),
         g.bugun + round(sum(acik * (a.vade - g.bugun)) / nullif(sum(acik), 0))::int
    from _vade_acik(null) a, (select (now() at time zone 'Europe/Istanbul')::date as bugun) g
   where a.yon = v_yon
   group by a.cari_kod, g.bugun
  having sum(acik) >= 0.01;

  if v_yon = 'alacak' then
    for r in select v.cari_kod from _vr v
              where not exists (select 1 from cari_odeme_onbellek o where o.cari_kod = v.cari_kod and o.zaman > now() - interval '6 hours')
              order by v.gecmis desc, v.acik desc
    loop
      if clock_timestamp() - v_bas > interval '10 seconds' then v_eksik := v_eksik + 1; continue; end if;
      begin
        insert into cari_odeme_onbellek (cari_kod, o, zaman) values (r.cari_kod, cari_odeme(r.cari_kod), now())
          on conflict (cari_kod) do update set o = excluded.o, zaman = excluded.zaman;
      exception when others then
        -- Tek bir carinin verisi hesaplanamazsa (bozuk / beklenmedik kayıt) BÜTÜN rapor düşmesin: o cari risksiz gösterilir.
        insert into cari_odeme_onbellek (cari_kod, o, zaman) values (r.cari_kod, jsonb_build_object('hata', left(sqlerrm, 200)), now())
          on conflict (cari_kod) do update set o = excluded.o, zaman = excluded.zaman;
      end;
    end loop;
  end if;

  with x as (
    select v.*, case when v_yon = 'alacak' then (select o.o from cari_odeme_onbellek o where o.cari_kod = v.cari_kod and o.zaman > now() - interval '6 hours') end as o from _vr v
  )
  select jsonb_build_object(
    'status', 'ok',
    'yon', v_yon,
    'toplam', (select coalesce(sum(acik), 0) from x),
    'gecmis', (select coalesce(sum(gecmis), 0) from x),
    'hafta', (select coalesce(sum(hafta), 0) from x),
    'ileri', (select coalesce(sum(ileri), 0) from x),
    'riskli', (select count(*) from x where o->>'seviye' = 'riskli'),
    'dikkat', (select count(*) from x where o->>'seviye' = 'dikkat'),
    'eksik', v_eksik,
    'satirlar', coalesce((select jsonb_agg(jsonb_build_array(cari_kod, cari_ad, round(acik, 2), round(gecmis, 2), round(hafta, 2), round(ileri, 2), gecikme,
                    to_char(ort_vade, 'DD.MM.YYYY'), (o->>'risk')::int, o->>'seviye', (o->>'ortOdemeGun')::int)
                   order by coalesce((o->>'risk')::int, 0) desc, gecmis desc, acik desc) from x), '[]'::jsonb),
    'sonVeri', (select to_char(max(guncelleme) at time zone 'Europe/Istanbul', 'DD.MM.YYYY HH24:MI') from erp_cari_hareket)
  ) into v_sonuc;
  return v_sonuc;
end $$;

alter function vade_raporu(text) security definer set search_path = public, extensions;
revoke execute on function vade_raporu(text) from public;
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke execute on function vade_raporu(text) from anon, authenticated';
    execute 'revoke all on cari_odeme_onbellek from anon, authenticated';
  end if;
end $$;
