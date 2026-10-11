-- ============================================================
-- Cari Hareketleri (cari hesap ekstresi): ERP12 FINANS_DETAY'dan.
-- 001_sema.sql'den SONRA çalıştırılır; tekrar çalıştırmak güvenlidir.
--
-- ERP12'de cari bakiyesi FINANS_DETAY'dan hesaplanır (CARI_BAKIYELER görünümü):
--   cari KART_BORCLU ise satır cariye BORÇ, KART_ALACAKLI ise ALACAK yazar.
--   Bakiye = borç − alacak  (artı: cari bize borçlu, eksi: biz cariye borçluyuz).
-- Bir finans satırı iki cariyi birden ilgilendirebilir (virman): her taraf ayrı
-- satırdır (taraf 'B' / 'A').
--
-- YIL DEVRİ: her satır geldiği ERP veri tabanını (kaynak) taşır. Yeni yıl veri
-- tabanı açılış (devir) kayıtlarını içerdiği için sorgu, o carinin EN YENİ
-- kaynağını kullanır; eski yıllar bakiyeyi iki kez saymaz.
--
-- Telefon bu tabloya DOĞRUDAN erişemez: Apps Script "cari_hareket" yetkisini
-- kontrol edip gizli anahtarla okur.
-- ============================================================

create table if not exists erp_cari_hareket (
  kaynak      text not null default '',       -- ERP veri tabanı adı (örn. ERP122025)
  detay_id    bigint not null,                -- ERP12 FINANS_DETAY.ID
  taraf       text not null check (taraf in ('B', 'A')),
  cari_kod    text not null default '',
  cari_ad     text not null default '',
  tarih       timestamptz not null,
  vade        date,
  tur         text not null default '',       -- FINANS_ISLEM_TURU.AD (Alış faturası, Tahsilat…)
  belge_no    text not null default '',
  aciklama    text not null default '',
  borc        numeric not null default 0,
  alacak      numeric not null default 0,
  doviz       text not null default '',
  fis_id      bigint,
  guncelleme  timestamptz not null default now(),
  primary key (kaynak, detay_id, taraf)
);
create index if not exists erp_cari_hareket_cari on erp_cari_hareket (cari_kod, kaynak, tarih);
create index if not exists erp_cari_hareket_tarih on erp_cari_hareket (kaynak, tarih);
alter table erp_cari_hareket enable row level security;

-- ------------------------------------------------------------
-- Yükleme (ERP bilgisayarındaki cari-hareket-gonder.ps1 çağırır).
-- Bir tarih ARALIĞI baştan gönderilir: ilk parçada (p_temizle = true) o
-- aralıktaki eski satırlar silinir; ERP'de silinen/düzeltilen kayıtlar düzelir.
-- ------------------------------------------------------------
create or replace function cari_hareket_yukle(p_kaynak text, p_satirlar jsonb, p_bas timestamptz, p_bit timestamptz, p_temizle boolean default false)
returns jsonb language plpgsql as $$
declare v_silinen integer := 0; v_eklenen integer;
begin
  if p_bas is null or p_bit is null or p_bit <= p_bas then
    return jsonb_build_object('status', 'error', 'message', 'Geçersiz tarih aralığı');
  end if;
  if coalesce(p_kaynak, '') = '' then
    return jsonb_build_object('status', 'error', 'message', 'Kaynak (ERP veri tabanı adı) eksik');
  end if;
  if p_temizle then
    delete from erp_cari_hareket where kaynak = p_kaynak and tarih >= p_bas and tarih < p_bit;
    get diagnostics v_silinen = row_count;
  end if;
  insert into erp_cari_hareket as h (kaynak, detay_id, taraf, cari_kod, cari_ad, tarih, vade, tur, belge_no, aciklama, borc, alacak, doviz, fis_id, guncelleme)
  select p_kaynak, x.detay_id, x.taraf, coalesce(x.cari_kod, ''), coalesce(x.cari_ad, ''), x.tarih, x.vade,
         coalesce(x.tur, ''), coalesce(x.belge_no, ''), coalesce(x.aciklama, ''), coalesce(x.borc, 0), coalesce(x.alacak, 0),
         coalesce(x.doviz, ''), x.fis_id, now()
    from jsonb_to_recordset(coalesce(p_satirlar, '[]'::jsonb)) as x(
         detay_id bigint, taraf text, cari_kod text, cari_ad text, tarih timestamptz, vade date, tur text,
         belge_no text, aciklama text, borc numeric, alacak numeric, doviz text, fis_id bigint)
   where x.detay_id is not null and x.taraf in ('B', 'A') and x.tarih >= p_bas and x.tarih < p_bit
  on conflict (kaynak, detay_id, taraf) do update set
    cari_kod = excluded.cari_kod, cari_ad = excluded.cari_ad, tarih = excluded.tarih, vade = excluded.vade,
    tur = excluded.tur, belge_no = excluded.belge_no, aciklama = excluded.aciklama, borc = excluded.borc,
    alacak = excluded.alacak, doviz = excluded.doviz, fis_id = excluded.fis_id, guncelleme = now();
  get diagnostics v_eklenen = row_count;
  return jsonb_build_object('status', 'ok', 'silinen', v_silinen, 'eklenen', v_eklenen);
end $$;

-- ------------------------------------------------------------
-- Sorgu (Apps Script çağırır): bir carinin ekstresi.
--  p_gun > 0  → son p_gun gün listelenir, öncesi "devreden" olarak tek satırda toplanır.
--  p_gun <= 0 → hepsi.
-- Satırlar YENİDEN ESKİYE döner; her satırda o satırdan SONRAKİ bakiye (yürüyen bakiye) vardır.
-- Döviz ayrı tutulur (bakiye her döviz için ayrı yürür).
-- ------------------------------------------------------------
create or replace function cari_hareket(p_cari_kod text, p_gun integer default 90, p_limit integer default 500)
returns jsonb language sql stable as $$
  with k as (
    select max(kaynak) as kaynak from erp_cari_hareket where cari_kod = coalesce(p_cari_kod, '')
  ), t as (
    select h.*, sum(h.borc - h.alacak) over (partition by h.doviz order by h.tarih, h.detay_id, h.taraf) as bakiye
      from erp_cari_hareket h, k
     where h.cari_kod = coalesce(p_cari_kod, '') and h.kaynak = k.kaynak
  ), s as (
    select (case when coalesce(p_gun, 0) > 0 then (date_trunc('day', now() at time zone 'Europe/Istanbul') - make_interval(days => p_gun)) at time zone 'Europe/Istanbul' end) as bas
  ), d as (
    select t.* from t, s where s.bas is null or t.tarih >= s.bas
  )
  select jsonb_build_object(
    'status', 'ok',
    'kaynak', (select kaynak from k),
    'cariAd', (select cari_ad from t order by tarih desc limit 1),
    'bakiye', coalesce((select jsonb_object_agg(doviz, b) from (select doviz, sum(borc - alacak) as b from t group by doviz) z), '{}'::jsonb),
    'devreden', coalesce((select jsonb_object_agg(doviz, b) from (select t.doviz, sum(t.borc - t.alacak) as b from t, s where s.bas is not null and t.tarih < s.bas group by t.doviz) z), '{}'::jsonb),
    'donemBorc', (select coalesce(sum(borc), 0) from d),
    'donemAlacak', (select coalesce(sum(alacak), 0) from d),
    'adet', (select count(*) from d),
    'satirlar', coalesce((select jsonb_agg(jsonb_build_array(
                    to_char(tarih at time zone 'Europe/Istanbul', 'DD.MM.YYYY'), tur, belge_no, aciklama, borc, alacak, bakiye, doviz,
                    coalesce(to_char(vade, 'DD.MM.YYYY'), '')) order by tarih desc, detay_id desc, taraf desc)
                   from (select * from d order by tarih desc, detay_id desc, taraf desc limit greatest(coalesce(p_limit, 500), 1)) x), '[]'::jsonb),
    'sonVeri', (select to_char(max(guncelleme) at time zone 'Europe/Istanbul', 'DD.MM.YYYY HH24:MI') from erp_cari_hareket)
  )
$$;

alter function cari_hareket_yukle(text, jsonb, timestamptz, timestamptz, boolean) security definer set search_path = public, extensions;
alter function cari_hareket(text, integer, integer)                              security definer set search_path = public, extensions;

-- Telefon anahtarına (anon) KAPALI: sadece gizli anahtar (Apps Script / ERP) çağırabilir.
revoke execute on function cari_hareket_yukle(text, jsonb, timestamptz, timestamptz, boolean) from public;
revoke execute on function cari_hareket(text, integer, integer) from public;
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke all on erp_cari_hareket from anon, authenticated';
    execute 'revoke execute on function cari_hareket_yukle(text, jsonb, timestamptz, timestamptz, boolean), cari_hareket(text, integer, integer) from anon, authenticated';
  end if;
end $$;
