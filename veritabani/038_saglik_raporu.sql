-- ============================================================
-- 🩺 Mağaza Sağlık Raporu uygulamada (Kârlılık → Sağlık). 037'den sonra çalıştırılır; tekrar çalıştırmak güvenlidir.
-- Rapor yine ERP bilgisayarında, ERP12'yi YALNIZ OKUYARAK hazırlanır (erp/saglik-raporu.ps1); sonucu buraya yazar.
--  - saglik_rapor_yaz: ERP bilgisayarı raporu bırakır (son 60 rapor saklanır).
--  - saglik_rapor_oku: uygulama son raporu (ya da seçilen eskisini) okur.
--  - saglik_istek_yaz: uygulamadan "yeniden hazırla" isteği. ERP bilgisayarındaki görev 30 dakikada bir
--    saglik_gerekli'ye bakar: istek varsa ya da son rapor 20 saatten eskiyse raporu yeniden hazırlar.
-- ============================================================

create table if not exists saglik_rapor (
  id     bigserial primary key,
  zaman  timestamptz not null default now(),
  veri   jsonb not null
);
create table if not exists saglik_istek (
  id     integer primary key default 1 check (id = 1),
  zaman  timestamptz not null default now(),
  kim    text not null default ''
);
alter table saglik_rapor enable row level security;
alter table saglik_istek enable row level security;

create or replace function saglik_rapor_yaz(p_veri jsonb) returns jsonb language plpgsql volatile as $$
declare v_id bigint;
begin
  if p_veri is null or jsonb_typeof(p_veri) <> 'object' then return jsonb_build_object('status', 'error', 'message', 'Boş rapor'); end if;
  insert into saglik_rapor (veri) values (p_veri) returning id into v_id;
  delete from saglik_rapor where id not in (select id from saglik_rapor order by id desc limit 60);
  delete from saglik_istek where zaman <= now();
  return jsonb_build_object('status', 'ok', 'id', v_id);
end $$;

create or replace function saglik_rapor_oku(p_id bigint default null) returns jsonb language sql stable as $$
  select jsonb_build_object(
    'status', 'ok',
    'rapor', (select jsonb_build_object('id', r.id, 'zaman', to_char(r.zaman at time zone 'Europe/Istanbul', 'DD.MM.YYYY HH24:MI'), 'veri', r.veri)
                from saglik_rapor r where p_id is null or r.id = p_id order by r.id desc limit 1),
    'liste', coalesce((select jsonb_agg(jsonb_build_array(id, to_char(zaman at time zone 'Europe/Istanbul', 'DD.MM.YYYY HH24:MI')) order by id desc)
                from (select id, zaman from saglik_rapor order by id desc limit 30) x), '[]'::jsonb),
    'istek', (select jsonb_build_object('zaman', to_char(zaman at time zone 'Europe/Istanbul', 'DD.MM.YYYY HH24:MI'), 'kim', kim) from saglik_istek),
    'gorev', (select to_char(zaman at time zone 'Europe/Istanbul', 'DD.MM.YYYY HH24:MI') from erp_nabiz where ad = 'saglik_raporu'));
$$;

create or replace function saglik_istek_yaz(p_kim text default '') returns jsonb language sql volatile as $$
  insert into saglik_istek (id, zaman, kim) values (1, now(), left(coalesce(p_kim, ''), 60))
  on conflict (id) do update set zaman = now(), kim = excluded.kim;
  select jsonb_build_object('status', 'ok');
$$;

-- ERP bilgisayarındaki görev sorar: rapor hazırlansın mı?
create or replace function saglik_gerekli() returns jsonb language sql stable as $$
  select jsonb_build_object('status', 'ok',
    'gerekli', (select count(*) from saglik_istek) > 0
               or not exists (select 1 from saglik_rapor where zaman > now() - interval '20 hours'),
    'neden', case when (select count(*) from saglik_istek) > 0 then 'istek' else 'sure' end);
$$;

alter function saglik_rapor_yaz(jsonb) security definer set search_path = public, extensions;
alter function saglik_rapor_oku(bigint) security definer set search_path = public, extensions;
alter function saglik_istek_yaz(text) security definer set search_path = public, extensions;
alter function saglik_gerekli() security definer set search_path = public, extensions;
revoke execute on function saglik_rapor_yaz(jsonb) from public;
revoke execute on function saglik_rapor_oku(bigint) from public;
revoke execute on function saglik_istek_yaz(text) from public;
revoke execute on function saglik_gerekli() from public;
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke all on saglik_rapor, saglik_istek from anon, authenticated';
    execute 'revoke execute on function saglik_rapor_yaz(jsonb), saglik_rapor_oku(bigint), saglik_istek_yaz(text), saglik_gerekli() from anon, authenticated';
  end if;
end $$;
notify pgrst, 'reload config';
