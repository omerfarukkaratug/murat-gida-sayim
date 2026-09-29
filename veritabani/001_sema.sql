-- ============================================================
-- MK ERP — Murat Gıda Sayım: veri tabanı şeması (PostgreSQL / Supabase)
--
-- DURUM: HAZIRLIK. Canlı uygulama büyük sayım bitene kadar Google Sheets ile
-- çalışmaya devam eder; bu şema paralelde hazırlanır ve test edilir.
--
-- Bugünkü Google Sheets sunucusundaki (Code.gs) veri güvenliği kuralları
-- burada VERİ TABANININ İÇİNDE, aynı mantıkla uygulanır:
--   * Sürüm kontrolü: bir kaydın daha yeni sürümü eskisiyle ezilemez.
--   * Silindi işareti: silinen kayıt eski bir gönderiyle geri gelemez.
--   * Geç gelen kayıt: sayım dosyası temizlendikten sonra ulaşan eski
--     döneme ait kayıtlar yeni sayıma karışmaz (ayrı işaretlenir).
--   * Onay: yazma fonksiyonu, telefonun gönderdiği her kaydın veri
--     tabanındaki sürümünü/adedini hemen döndürür.
-- ============================================================

create extension if not exists pgcrypto;

-- ---------- Şubeler (girişte konum kontrolü) ----------
create table if not exists subeler (
  id          bigint generated always as identity primary key,
  ad          text not null unique,
  enlem       double precision not null check (enlem between -90 and 90),
  boylam      double precision not null check (boylam between -180 and 180),
  yaricap_m   integer not null default 300 check (yaricap_m between 50 and 5000)
);

-- ---------- Kullanıcılar ----------
-- Şifreler düz metin DEĞİL, bcrypt özeti olarak saklanır (Sheets'teki
-- düz metin yerine). Rol 'yonetici' tüm yetkilere sahiptir.
create table if not exists kullanicilar (
  ad          text primary key,
  sifre_ozet  text not null,
  rol         text not null default 'kullanici' check (rol in ('kullanici', 'yonetici')),
  yetkiler    text[] not null default '{}',
  aktif       boolean not null default true,
  olusturma   timestamptz not null default now()
);

-- ---------- ERP'den gelen katalog ve cariler ----------
create table if not exists urunler (
  barkod      text primary key,
  ad          text not null,
  stok_kodu   text not null default '',
  eski_stok   numeric,
  fiyat       numeric,
  kdv         numeric,
  guncelleme  timestamptz not null default now()
);
create index if not exists urunler_stok_kodu on urunler (stok_kodu);

create table if not exists cariler (
  id          bigint generated always as identity primary key,
  kod         text not null default '',
  ad          text not null,
  bakiye      numeric,
  guncelleme  timestamptz not null default now()
);
create unique index if not exists cariler_kod on cariler (kod) where kod <> '';

-- ---------- Sayım dönemleri ("Dosyayı Temizle" = yeni dönem) ----------
create table if not exists sayim_donemleri (
  id          bigint generated always as identity primary key,
  token       text not null unique,          -- telefonlara giden sıfırlama damgası
  baslangic   timestamptz not null default now(),
  aciklama    text not null default ''
);

-- ---------- Sayım kayıtları (her okutma bir satır) ----------
create table if not exists sayim_kayitlari (
  kayit_id       text primary key,           -- telefonun ürettiği eşsiz kimlik
  oturum_id      text not null,
  donem_id       bigint references sayim_donemleri(id),
  gec_geldi      boolean not null default false,  -- temizlikten önce okutulmuş, sonra ulaşmış
  personel       text not null default '',
  urun_adi       text not null default '',
  stok_kodu      text not null default '',
  barkod         text not null default '',
  birim          text not null default 'Adet',
  eski_stok      numeric,
  adet           numeric not null,
  fark           numeric generated always as (adet - eski_stok) stored,
  reyon          text not null default '',
  sube           text not null default '',
  surum          integer not null default 1,
  okutma_tarihi  text not null default '',   -- telefonun yerel tarihi (rapor uyumu)
  okutma_saati   text not null default '',
  okutma_zamani  timestamptz,                -- telefonun ts'i
  olusturma      timestamptz not null default now(),
  guncelleme     timestamptz not null default now()
);
create index if not exists sayim_kayitlari_oturum on sayim_kayitlari (oturum_id);
create index if not exists sayim_kayitlari_donem on sayim_kayitlari (donem_id, gec_geldi);
create index if not exists sayim_kayitlari_barkod on sayim_kayitlari (barkod);

-- Silindi işaretleri: burada olan kimlik bir daha yazılamaz.
create table if not exists silinen_kayitlar (
  kayit_id    text primary key,
  oturum_id   text not null default '',
  silen       text not null default '',
  zaman       timestamptz not null default now()
);

-- ---------- Mal Giriş / Çıkış ----------
create table if not exists mal_hareketleri (
  kayit_id        text primary key,
  batch_id        text not null,
  tip             text not null check (tip in ('Giriş', 'Çıkış')),
  belge_turu      text not null default '',
  belge_no        text not null default '',
  cari            text not null default '',
  cari_kodu       text not null default '',
  sebep           text not null default '',
  personel        text not null default '',
  barkod          text not null default '',
  urun_adi        text not null default '',
  stok_kodu       text not null default '',
  miktar          numeric not null,
  birim           text not null default 'Adet',
  kdv             numeric,
  fiyat           numeric,
  surum           integer not null default 1,
  aciklama        text not null default '',
  konum           text not null default '',
  tarih           text not null default '',
  saat            text not null default '',
  aktarildi       timestamptz,               -- masaüstüne (ERP) aktarıldığı an; doluysa değiştirilemez
  olusturma       timestamptz not null default now()
);
create index if not exists mal_hareketleri_batch on mal_hareketleri (batch_id);
create index if not exists mal_hareketleri_bekleyen on mal_hareketleri (olusturma) where aktarildi is null;

-- ---------- Sistem günlüğü ----------
create table if not exists sistem_gunlugu (
  id          bigint generated always as identity primary key,
  zaman       timestamptz not null default now(),
  tur         text not null,
  kaynak      text not null default '',
  detay       text not null default '',
  hata        boolean not null default false
);
create index if not exists sistem_gunlugu_zaman on sistem_gunlugu (zaman desc);

-- ============================================================
-- FONKSİYONLAR
-- ============================================================

-- Aktif sayım dönemi (en son "Dosyayı Temizle").
create or replace function aktif_donem() returns sayim_donemleri
language sql stable as $$
  select * from sayim_donemleri order by baslangic desc, id desc limit 1
$$;

-- Yönetici: "Dosyayı Temizle" — yeni dönem açar. Eski kayıtlar SİLİNMEZ,
-- önceki dönemde kalır (Sheets'teki arşiv sekmesinin karşılığı).
create or replace function yeni_donem(p_aciklama text default '') returns text
language plpgsql as $$
declare v_token text := to_char(clock_timestamp() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"');
begin
  insert into sayim_donemleri (token, aciklama) values (v_token, coalesce(p_aciklama, ''));
  insert into sistem_gunlugu (tur, kaynak, detay) values ('yonetim', '', 'Yeni sayım dönemi: ' || v_token);
  return v_token;
end $$;

-- ------------------------------------------------------------
-- sayim_yaz: telefonun gönderdiği paketi yazar ve ONAYI döndürür.
-- Girdi (bugünkü uygulamanın gönderdiğiyle aynı):
--   { personnel, sessionId, resetToken, sube, deletedIds: [...],
--     rows: [ { id, v, ts, name, stockCode, barcode, unit, oldStock,
--               date, time, qty, reyon } ] }
-- Çıktı: { status:'ok', rows: { kayitId: [surum, adet] }, deleted: [...],
--          skipped: n, gecGelen: n }
-- Tek bir işlem (transaction) içinde çalışır; satır bazında kilitler,
-- Sheets'teki gibi tüm tabloyu kilitlemez — telefonlar birbirini beklemez.
-- ------------------------------------------------------------
create or replace function sayim_yaz(p jsonb) returns jsonb
language plpgsql as $$
declare
  v_donem      sayim_donemleri := aktif_donem();
  v_oturum     text := coalesce(p->>'sessionId', '');
  v_personel   text := coalesce(p->>'personnel', '');
  v_eski_donem boolean := coalesce(p->>'resetToken', '') <> '' and v_donem.token is not null and (p->>'resetToken') <> v_donem.token;
  r            jsonb;
  v_id         text;
  v_surum_var  boolean;
  v_surum      integer;
  v_ts         timestamptz;
  v_gec        boolean;
  v_yazildi    boolean;
  v_atlanan    integer := 0;
  v_gec_sayi   integer := 0;
  v_silinen    text[] := array(select jsonb_array_elements_text(coalesce(p->'deletedIds', '[]'::jsonb)));
  v_onay       jsonb := '{}'::jsonb;
  v_ids        text[] := '{}';
begin
  if v_oturum = '' then
    return jsonb_build_object('status', 'error', 'message', 'Oturum ID eksik');
  end if;

  for r in select * from jsonb_array_elements(coalesce(p->'rows', '[]'::jsonb)) loop
    v_id := coalesce(r->>'id', '');
    if v_id = '' then v_atlanan := v_atlanan + 1; continue; end if;
    if exists (select 1 from silinen_kayitlar s where s.kayit_id = v_id) then v_atlanan := v_atlanan + 1; continue; end if;
    v_surum_var := coalesce(r->>'v', '') <> '';
    v_surum := case when v_surum_var then greatest(1, (r->>'v')::integer) else 1 end;
    v_ts := case when coalesce(r->>'ts', '') ~ '^[0-9]+$' then to_timestamp((r->>'ts')::bigint / 1000.0) end;
    v_gec := v_eski_donem and (v_ts is null or v_ts < v_donem.baslangic);
    if v_gec then v_gec_sayi := v_gec_sayi + 1; end if;

    insert into sayim_kayitlari as k (kayit_id, oturum_id, donem_id, gec_geldi, personel, urun_adi, stok_kodu, barkod, birim,
        eski_stok, adet, reyon, sube, surum, okutma_tarihi, okutma_saati, okutma_zamani)
    values (v_id, v_oturum, v_donem.id, v_gec, v_personel, coalesce(r->>'name', ''), coalesce(r->>'stockCode', ''), coalesce(r->>'barcode', ''),
        coalesce(nullif(r->>'unit', ''), 'Adet'),
        case when coalesce(r->>'oldStock', '') ~ '^-?[0-9]+(\.[0-9]+)?$' then (r->>'oldStock')::numeric end,
        coalesce(nullif(r->>'qty', '')::numeric, 0), coalesce(r->>'reyon', ''), coalesce(p->>'sube', ''), v_surum,
        coalesce(r->>'date', ''), coalesce(r->>'time', ''), v_ts)
    on conflict (kayit_id) do update
      set adet = excluded.adet, eski_stok = excluded.eski_stok, urun_adi = excluded.urun_adi, stok_kodu = excluded.stok_kodu,
          barkod = excluded.barkod, birim = excluded.birim, reyon = excluded.reyon, surum = excluded.surum,
          okutma_tarihi = excluded.okutma_tarihi, okutma_saati = excluded.okutma_saati, guncelleme = now()
      -- SÜRÜM KONTROLÜ: sürümlü gönderi ancak daha yeniyse yazar; sürümsüz (eski
      -- uygulama) gönderi sadece hiç düzeltilmemiş (surum <= 1) satırın üzerine yazar.
      where (v_surum_var and excluded.surum > k.surum) or (not v_surum_var and k.surum <= 1)
    returning true into v_yazildi;
    if v_yazildi is null then v_atlanan := v_atlanan + 1; end if;
    v_yazildi := null;
    v_ids := v_ids || v_id;
  end loop;

  -- Telefonda silinenler: işaretle ve sil.
  if array_length(v_silinen, 1) > 0 then
    insert into silinen_kayitlar (kayit_id, oturum_id, silen)
      select unnest(v_silinen), v_oturum, coalesce(nullif(v_personel, ''), 'telefon')
      on conflict (kayit_id) do nothing;
    delete from sayim_kayitlari where kayit_id = any(v_silinen);
  end if;

  -- ONAY: gönderilen her kaydın veri tabanındaki güncel sürümü/adedi.
  select coalesce(jsonb_object_agg(kayit_id, jsonb_build_array(surum, adet)), '{}'::jsonb)
    into v_onay from sayim_kayitlari where kayit_id = any(v_ids);

  if array_length(v_ids, 1) > 0 or array_length(v_silinen, 1) > 0 then
    insert into sistem_gunlugu (tur, kaynak, detay)
    values ('sayim', 'telefon: ' || coalesce(nullif(v_personel, ''), '?'),
            coalesce(array_length(v_ids, 1), 0) || ' kayıt' ||
            case when array_length(v_silinen, 1) > 0 then ', ' || array_length(v_silinen, 1) || ' silme' else '' end ||
            case when v_atlanan > 0 then ', ' || v_atlanan || ' atlandı' else '' end ||
            case when v_gec_sayi > 0 then ', ' || v_gec_sayi || ' geç gelen' else '' end);
  end if;

  return jsonb_build_object('status', 'ok', 'rows', v_onay,
    'deleted', coalesce((select jsonb_agg(kayit_id) from silinen_kayitlar where oturum_id = v_oturum), '[]'::jsonb),
    'skipped', v_atlanan, 'gecGelen', v_gec_sayi);
end $$;

-- Tam kontrol: bir oturumun tüm kayıtları ve silinenleri (uygulamadaki
-- 10 dakikalık tam kontrolün karşılığı).
create or replace function sayim_kontrol(p_oturum text) returns jsonb
language sql stable as $$
  select jsonb_build_object('status', 'ok',
    'rows', coalesce((select jsonb_object_agg(kayit_id, jsonb_build_array(surum, adet)) from sayim_kayitlari where oturum_id = p_oturum), '{}'::jsonb),
    'deleted', coalesce((select jsonb_agg(kayit_id) from silinen_kayitlar where oturum_id = p_oturum), '[]'::jsonb))
$$;

-- Yönetici "Düzelt": adedi değiştirir ve SÜRÜMÜ ARTIRIR (telefondaki eski
-- sürüm artık bunun üzerine yazamaz; telefon yeni değeri onayda alır).
create or replace function sayim_guncelle(p_kayit text, p_adet numeric, p_yonetici text) returns jsonb
language plpgsql as $$
declare v_surum integer;
begin
  if p_adet is null or p_adet < 0 then return jsonb_build_object('status', 'error', 'message', 'Geçersiz adet'); end if;
  update sayim_kayitlari set adet = p_adet, surum = surum + 1, guncelleme = now()
   where kayit_id = p_kayit returning surum into v_surum;
  if v_surum is null then return jsonb_build_object('status', 'error', 'message', 'Kayıt bulunamadı (silinmiş olabilir)'); end if;
  insert into sistem_gunlugu (tur, kaynak, detay) values ('yonetim', coalesce(p_yonetici, ''), 'Kayıt düzeltildi: ' || p_kayit || ' → ' || p_adet);
  return jsonb_build_object('status', 'ok', 'v', v_surum);
end $$;

-- Yönetici "Sil": silindi işareti koyar ve siler.
create or replace function sayim_sil(p_kayit text, p_yonetici text) returns jsonb
language plpgsql as $$
declare v_oturum text;
begin
  delete from sayim_kayitlari where kayit_id = p_kayit returning oturum_id into v_oturum;
  if v_oturum is null then return jsonb_build_object('status', 'error', 'message', 'Kayıt bulunamadı (zaten silinmiş olabilir)'); end if;
  insert into silinen_kayitlar (kayit_id, oturum_id, silen) values (p_kayit, v_oturum, coalesce(p_yonetici, 'yonetici'))
    on conflict (kayit_id) do nothing;
  return jsonb_build_object('status', 'ok');
end $$;

-- ------------------------------------------------------------
-- mal_yaz: Mal Giriş/Çıkış kaydı (bugünkü saveMalHareket ile aynı kurallar):
-- yeni kalem eklenir; aynı batch'te daha yeni sürüm günceller; telefonda
-- silinen kalem silinir; masaüstüne aktarılmış satır DEĞİŞTİRİLMEZ/SİLİNMEZ.
-- ------------------------------------------------------------
create or replace function mal_yaz(p jsonb) returns jsonb
language plpgsql as $$
declare
  v_batch   text := coalesce(nullif(p->>'batchId', ''), gen_random_uuid()::text);
  v_tip     text := case when p->>'tip' = 'cikis' then 'Çıkış' else 'Giriş' end;
  r         jsonb;
  v_id      text;
  v_surum   integer;
  v_ids     text[] := '{}';
  v_kilitli integer := 0;
  v_mevcut  mal_hareketleri;
begin
  for r in select * from jsonb_array_elements(coalesce(p->'rows', '[]'::jsonb)) loop
    v_id := coalesce(nullif(r->>'kayitId', ''), gen_random_uuid()::text);
    v_surum := greatest(1, coalesce(nullif(r->>'v', '')::integer, 1));
    v_ids := v_ids || v_id;
    select * into v_mevcut from mal_hareketleri where kayit_id = v_id;
    if found and v_mevcut.batch_id = v_batch and v_mevcut.aktarildi is not null and v_surum > v_mevcut.surum then
      v_kilitli := v_kilitli + 1; continue;
    end if;
    insert into mal_hareketleri as m (kayit_id, batch_id, tip, belge_turu, belge_no, cari, cari_kodu, sebep, personel,
        barkod, urun_adi, stok_kodu, miktar, birim, kdv, fiyat, surum, aciklama, konum, tarih, saat)
    values (v_id, v_batch, v_tip, coalesce(p->>'belgeTuru', ''), coalesce(p->>'faturaNo', ''), coalesce(p->>'cari', ''),
        coalesce(p->>'cariKodu', ''), coalesce(p->>'sebep', ''), coalesce(p->>'personel', ''),
        coalesce(r->>'barkod', ''), coalesce(r->>'ad', ''), coalesce(r->>'stokKodu', ''),
        coalesce(nullif(r->>'miktar', '')::numeric, 0), coalesce(nullif(r->>'birim', ''), 'Adet'),
        nullif(r->>'kdv', '')::numeric, nullif(r->>'fiyat', '')::numeric, v_surum,
        left(coalesce(p->>'aciklama', ''), 500), left(coalesce(p->>'konum', ''), 120), coalesce(r->>'tarih', ''), coalesce(r->>'saat', ''))
    on conflict (kayit_id) do update
      set miktar = excluded.miktar, surum = excluded.surum, tarih = excluded.tarih, saat = excluded.saat,
          aciklama = excluded.aciklama, kdv = excluded.kdv, fiyat = excluded.fiyat
      where m.batch_id = excluded.batch_id and m.aktarildi is null and excluded.surum > m.surum;
    -- Aynı sürümde sadece açıklama değiştiyse (aktarılmamışsa) açıklamayı güncelle.
    update mal_hareketleri set aciklama = left(coalesce(p->>'aciklama', ''), 500)
     where kayit_id = v_id and batch_id = v_batch and aktarildi is null;
  end loop;

  -- Telefonda silinmiş kalemler (aktarılmamışsa).
  select v_kilitli + count(*) into v_kilitli from mal_hareketleri
   where batch_id = v_batch and not (kayit_id = any(v_ids)) and aktarildi is not null;
  delete from mal_hareketleri where batch_id = v_batch and not (kayit_id = any(v_ids)) and aktarildi is null;

  return jsonb_build_object('status', 'ok', 'batchId', v_batch, 'kilitli', v_kilitli,
    'rows', coalesce((select jsonb_object_agg(kayit_id, jsonb_build_array(surum, miktar, case when aktarildi is null then 0 else 1 end))
                      from mal_hareketleri where batch_id = v_batch), '{}'::jsonb));
end $$;

-- ------------------------------------------------------------
-- ERP aktarımı: katalog ve cari listesi TOPLU yenilenir; sadece değişen
-- satırlar yazılır (telefonlar da sadece değişenleri indirecek şekilde
-- "guncelleme" zamanına göre sorgulayabilir).
-- ------------------------------------------------------------
create or replace function katalog_yukle(p_urunler jsonb, p_kaynak text default 'ERP / dış program') returns jsonb
language plpgsql as $$
declare v_degisen integer; v_silinen integer;
begin
  drop table if exists gelen;
  create temporary table gelen on commit drop as
    select distinct on (x.barcode) x.barcode as barkod, coalesce(x.name, '') as ad, coalesce(x."stockCode", '') as stok_kodu,
           nullif(x."oldStock", '')::numeric as eski_stok, nullif(x.price, '')::numeric as fiyat, nullif(x.kdv, '')::numeric as kdv
      from jsonb_to_recordset(p_urunler) as x(barcode text, name text, "stockCode" text, "oldStock" text, price text, kdv text)
     where coalesce(x.barcode, '') <> '';
  -- GÜVENLİK: boş/bozuk liste gelirse katalog silinmesin.
  if (select count(*) from gelen) = 0 then
    return jsonb_build_object('status', 'error', 'message', 'Boş ürün listesi — katalog değiştirilmedi');
  end if;
  insert into urunler as u (barkod, ad, stok_kodu, eski_stok, fiyat, kdv)
    select barkod, ad, stok_kodu, eski_stok, fiyat, kdv from gelen
  on conflict (barkod) do update
    set ad = excluded.ad, stok_kodu = excluded.stok_kodu, eski_stok = excluded.eski_stok, fiyat = excluded.fiyat, kdv = excluded.kdv, guncelleme = now()
    where (u.ad, u.stok_kodu, u.eski_stok, u.fiyat, u.kdv) is distinct from (excluded.ad, excluded.stok_kodu, excluded.eski_stok, excluded.fiyat, excluded.kdv);
  get diagnostics v_degisen = row_count;
  delete from urunler where barkod not in (select barkod from gelen);
  get diagnostics v_silinen = row_count;
  insert into sistem_gunlugu (tur, kaynak, detay)
    values ('katalog', coalesce(p_kaynak, ''), jsonb_array_length(p_urunler) || ' ürün geldi — ' || v_degisen || ' değişen/yeni, ' || v_silinen || ' kaldırılan');
  return jsonb_build_object('status', 'ok', 'degisen', v_degisen, 'silinen', v_silinen);
end $$;
