-- ============================================================
-- Ürün Hareketleri: ERP12'den gelen alış ve satış satırları.
-- 001_sema.sql'den SONRA çalıştırılır; tekrar çalıştırmak güvenlidir.
--
--  erp_hareket          : tek tek listelenecek belgeler (alış 1/5, firma satışı 2/6/12)
--  erp_perakende_gunluk : kasa (11) + Peşin Satış Carisi — sadece günlük toplam
--
-- Telefon bu tablolara DOĞRUDAN erişemez: veriyi Apps Script, kullanıcının
-- "hareket" yetkisini kontrol ettikten sonra gizli anahtarla okur.
-- ============================================================

create table if not exists erp_hareket (
  detay_id     bigint primary key,            -- ERP12 FIS_DETAY.ID
  fis_id       bigint not null,
  fis_turu     integer not null,
  yon          text not null check (yon in ('gelen', 'satilan')),
  tarih        timestamptz not null,
  belge_no     text not null default '',
  cari         text not null default '',
  stok_kodu    text not null default '',
  barkod       text not null default '',
  urun_adi     text not null default '',
  miktar       numeric not null,
  birim        text not null default '',
  birim_fiyat  numeric,                       -- KDV DAHİL birim fiyat
  guncelleme   timestamptz not null default now()
);
create index if not exists erp_hareket_stok on erp_hareket (stok_kodu, tarih desc);
create index if not exists erp_hareket_barkod on erp_hareket (barkod, tarih desc);
create index if not exists erp_hareket_tarih on erp_hareket (tarih);

create table if not exists erp_perakende_gunluk (
  stok_kodu  text not null,
  gun        date not null,
  miktar     numeric not null,
  primary key (stok_kodu, gun)
);

alter table erp_hareket enable row level security;
alter table erp_perakende_gunluk enable row level security;

-- ------------------------------------------------------------
-- Yükleme (ERP bilgisayarındaki hareket-gonder.ps1 çağırır).
-- Bir tarih ARALIĞI baştan gönderilir: ilk parçada (p_temizle = true) o
-- aralıktaki eski satırlar silinir, sonra parçalar eklenir. Böylece ERP'de
-- silinen/düzeltilen belgeler de bir sonraki gönderimde düzelir.
-- ------------------------------------------------------------
create or replace function hareket_yukle(p_satirlar jsonb, p_bas timestamptz, p_bit timestamptz, p_temizle boolean default false)
returns jsonb language plpgsql as $$
declare v_silinen integer := 0; v_eklenen integer;
begin
  if p_bas is null or p_bit is null or p_bit <= p_bas then
    return jsonb_build_object('status', 'error', 'message', 'Geçersiz tarih aralığı');
  end if;
  if p_temizle then
    delete from erp_hareket where tarih >= p_bas and tarih < p_bit;
    get diagnostics v_silinen = row_count;
  end if;
  insert into erp_hareket as h (detay_id, fis_id, fis_turu, yon, tarih, belge_no, cari, stok_kodu, barkod, urun_adi, miktar, birim, birim_fiyat, guncelleme)
  select x.detay_id, x.fis_id, x.fis_turu, x.yon, x.tarih, coalesce(x.belge_no, ''), coalesce(x.cari, ''),
         coalesce(x.stok_kodu, ''), coalesce(x.barkod, ''), coalesce(x.urun_adi, ''), coalesce(x.miktar, 0),
         coalesce(x.birim, ''), x.birim_fiyat, now()
    from jsonb_to_recordset(coalesce(p_satirlar, '[]'::jsonb)) as x(
         detay_id bigint, fis_id bigint, fis_turu integer, yon text, tarih timestamptz, belge_no text, cari text,
         stok_kodu text, barkod text, urun_adi text, miktar numeric, birim text, birim_fiyat numeric)
   where x.detay_id is not null and x.yon in ('gelen', 'satilan') and x.tarih >= p_bas and x.tarih < p_bit
  on conflict (detay_id) do update set
    fis_id = excluded.fis_id, fis_turu = excluded.fis_turu, yon = excluded.yon, tarih = excluded.tarih,
    belge_no = excluded.belge_no, cari = excluded.cari, stok_kodu = excluded.stok_kodu, barkod = excluded.barkod,
    urun_adi = excluded.urun_adi, miktar = excluded.miktar, birim = excluded.birim, birim_fiyat = excluded.birim_fiyat,
    guncelleme = now();
  get diagnostics v_eklenen = row_count;
  return jsonb_build_object('status', 'ok', 'silinen', v_silinen, 'eklenen', v_eklenen);
end $$;

create or replace function perakende_yukle(p_satirlar jsonb, p_bas date, p_bit date, p_temizle boolean default false)
returns jsonb language plpgsql as $$
declare v_silinen integer := 0; v_eklenen integer;
begin
  if p_bas is null or p_bit is null or p_bit <= p_bas then
    return jsonb_build_object('status', 'error', 'message', 'Geçersiz tarih aralığı');
  end if;
  if p_temizle then
    delete from erp_perakende_gunluk where gun >= p_bas and gun < p_bit;
    get diagnostics v_silinen = row_count;
  end if;
  insert into erp_perakende_gunluk as g (stok_kodu, gun, miktar)
  select x.stok_kodu, x.gun, sum(coalesce(x.miktar, 0))
    from jsonb_to_recordset(coalesce(p_satirlar, '[]'::jsonb)) as x(stok_kodu text, gun date, miktar numeric)
   where coalesce(x.stok_kodu, '') <> '' and x.gun >= p_bas and x.gun < p_bit
   group by x.stok_kodu, x.gun
  on conflict (stok_kodu, gun) do update set miktar = excluded.miktar;
  get diagnostics v_eklenen = row_count;
  return jsonb_build_object('status', 'ok', 'silinen', v_silinen, 'eklenen', v_eklenen);
end $$;

-- ------------------------------------------------------------
-- Sorgu (Apps Script çağırır): bir ürünün son p_gun gündeki hareketleri.
-- Ürün stok koduyla aranır; stok kodu yoksa barkodla.
-- ------------------------------------------------------------
create or replace function urun_hareket(p_stok_kodu text, p_barkod text, p_gun integer default 365, p_limit integer default 200)
returns jsonb language sql stable as $$
  with h as (
    select * from erp_hareket
     where (case when coalesce(p_stok_kodu, '') <> '' then stok_kodu = p_stok_kodu else barkod = coalesce(p_barkod, '') end)
       and (coalesce(p_gun, 0) <= 0 or tarih >= now() - make_interval(days => p_gun))
  ), p as (
    select coalesce(sum(miktar), 0) as miktar from erp_perakende_gunluk
     where coalesce(p_stok_kodu, '') <> '' and stok_kodu = p_stok_kodu
       and (coalesce(p_gun, 0) <= 0 or gun >= (now() - make_interval(days => p_gun))::date)
  )
  select jsonb_build_object(
    'status', 'ok',
    'gelenToplam',  (select coalesce(sum(miktar), 0) from h where yon = 'gelen'),
    'firmaToplam',  (select coalesce(sum(miktar), 0) from h where yon = 'satilan'),
    'perakende',    (select miktar from p),
    'gelen',   coalesce((select jsonb_agg(jsonb_build_array(to_char(tarih at time zone 'Europe/Istanbul', 'DD.MM.YYYY'), cari, belge_no, miktar, birim, birim_fiyat, fis_turu) order by tarih desc)
                          from (select * from h where yon = 'gelen' order by tarih desc limit p_limit) a), '[]'::jsonb),
    'satilan', coalesce((select jsonb_agg(jsonb_build_array(to_char(tarih at time zone 'Europe/Istanbul', 'DD.MM.YYYY'), cari, belge_no, miktar, birim, birim_fiyat, fis_turu) order by tarih desc)
                          from (select * from h where yon = 'satilan' order by tarih desc limit p_limit) b), '[]'::jsonb),
    'sonVeri', (select to_char(max(guncelleme) at time zone 'Europe/Istanbul', 'DD.MM.YYYY HH24:MI') from erp_hareket)
  )
$$;

alter function hareket_yukle(jsonb, timestamptz, timestamptz, boolean) security definer set search_path = public, extensions;
alter function perakende_yukle(jsonb, date, date, boolean)            security definer set search_path = public, extensions;
alter function urun_hareket(text, text, integer, integer)               security definer set search_path = public, extensions;

-- Telefon anahtarına (anon) KAPALI: sadece gizli anahtar (Apps Script / ERP) çağırabilir.
revoke execute on function hareket_yukle(jsonb, timestamptz, timestamptz, boolean) from public;
revoke execute on function perakende_yukle(jsonb, date, date, boolean) from public;
revoke execute on function urun_hareket(text, text, integer, integer) from public;
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke all on erp_hareket, erp_perakende_gunluk from anon, authenticated';
    execute 'revoke execute on function hareket_yukle(jsonb, timestamptz, timestamptz, boolean), perakende_yukle(jsonb, date, date, boolean), urun_hareket(text, text, integer, integer) from anon, authenticated';
  end if;
end $$;
