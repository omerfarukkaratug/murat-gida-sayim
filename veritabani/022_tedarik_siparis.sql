-- ============================================================
-- 🛒 Tedarikçi Siparişi — 2. adım: sipariş kaydı ve ERP'ye "Verilen Sipariş" aktarımı.
-- 021'den SONRA çalıştırılır; tekrar çalıştırmak güvenlidir.
--
-- tedarik_siparis: telefonda hazırlanan tedarikçi siparişleri (taslak → ERP'ye gönder → aktarıldı).
--   ERP'ye bu veri tabanından YAZILMAZ: ERP bilgisayarındaki siparis-aktar.ps1 (-Tedarik) "gonder"
--   durumundakileri alır, ERP12'ye Verilen Sipariş (stoğa/cariye etki etmez) olarak yazar, sonucu bildirir.
--   satirlar: [{ barkod, stok_kodu, urun_adi, miktar }]
-- ============================================================

create table if not exists tedarik_siparis (
  id           text primary key,
  cari_kod     text not null,
  cari_ad      text not null default '',
  satirlar     jsonb not null default '[]'::jsonb,
  aciklama     text not null default '',
  olusturan    text not null default '',
  durum        text not null default 'taslak',   -- taslak / gonder / iptal
  olusturma    timestamptz not null default now(),
  guncelleme   timestamptz not null default now(),
  gonderim     timestamptz,
  erp_durum    text not null default '',          -- '' / ok / hata
  erp_belge_no text not null default '',
  erp_id       bigint,
  erp_mesaj    text not null default '',
  erp_zaman    timestamptz
);
create index if not exists tedarik_siparis_cari on tedarik_siparis (cari_kod, olusturma desc);
create index if not exists tedarik_siparis_bekleyen on tedarik_siparis (gonderim) where durum = 'gonder' and erp_durum <> 'ok';
alter table tedarik_siparis enable row level security;

create or replace function tedarik_siparis_json(t tedarik_siparis) returns jsonb language sql stable as $$
  select jsonb_build_object('id', t.id, 'cariKod', t.cari_kod, 'cariAd', t.cari_ad, 'satirlar', t.satirlar, 'aciklama', t.aciklama,
    'olusturan', t.olusturan, 'durum', t.durum, 'erpDurum', t.erp_durum, 'erpBelgeNo', t.erp_belge_no, 'erpMesaj', t.erp_mesaj,
    'olusturma', to_char(t.olusturma at time zone 'Europe/Istanbul', 'DD.MM.YYYY HH24:MI'),
    'guncelleme', to_char(t.guncelleme at time zone 'Europe/Istanbul', 'DD.MM.YYYY HH24:MI'),
    'gonderim', to_char(t.gonderim at time zone 'Europe/Istanbul', 'DD.MM.YYYY HH24:MI'),
    'erpZaman', to_char(t.erp_zaman at time zone 'Europe/Istanbul', 'DD.MM.YYYY HH24:MI'))
$$;

-- Kaydet (yeni ya da güncelle). ERP'ye aktarılmış ya da aktarım için alınmış sipariş değiştirilemez.
create or replace function tedarik_siparis_yaz(p jsonb) returns jsonb language plpgsql as $$
declare v tedarik_siparis; v_id text := left(coalesce(p->>'id', ''), 60); v_durum text := coalesce(p->>'durum', 'taslak');
begin
  if v_id = '' or coalesce(p->>'cari_kod', '') = '' then return jsonb_build_object('status', 'error', 'message', 'Sipariş ya da firma eksik'); end if;
  if v_durum not in ('taslak', 'gonder', 'iptal') then return jsonb_build_object('status', 'error', 'message', 'Geçersiz durum'); end if;
  if jsonb_typeof(coalesce(p->'satirlar', '[]'::jsonb)) <> 'array' then return jsonb_build_object('status', 'error', 'message', 'Satırlar hatalı'); end if;
  select * into v from tedarik_siparis where id = v_id for update;
  if found and v.erp_durum = 'ok' then
    return jsonb_build_object('status', 'error', 'message', 'Bu sipariş ERP''ye aktarıldı (' || v.erp_belge_no || ') — değişiklik ERP''de yapılmalı', 'siparis', tedarik_siparis_json(v));
  end if;
  insert into tedarik_siparis as t (id, cari_kod, cari_ad, satirlar, aciklama, olusturan, durum, gonderim, erp_durum, erp_mesaj)
  values (v_id, p->>'cari_kod', coalesce(p->>'cari_ad', ''), coalesce(p->'satirlar', '[]'::jsonb), left(coalesce(p->>'aciklama', ''), 300),
          coalesce(p->>'olusturan', ''), v_durum, case when v_durum = 'gonder' then now() end, '', '')
  on conflict (id) do update set
    satirlar = excluded.satirlar, aciklama = excluded.aciklama, durum = excluded.durum, guncelleme = now(),
    gonderim = case when excluded.durum = 'gonder' then now() else null end, erp_durum = '', erp_mesaj = ''
  returning * into v;
  return jsonb_build_object('status', 'ok', 'siparis', tedarik_siparis_json(v));
end $$;

-- ERP bilgisayarı: aktarılacak siparişler (aktarilacak_mal ile aynı biçim; tip 'Giriş' = Verilen Sipariş).
-- Telefonda "ERP'ye gönder"den sonra p_bekle_dk dakika beklenir (yanlışlıkla basıldıysa geri alınabilsin).
create or replace function aktarilacak_tedarik(p_bekle_dk integer default 2, p_limit integer default 20)
returns jsonb language sql stable as $$
  select jsonb_build_object('status', 'ok', 'degisen', '[]'::jsonb,
    'belgeler', coalesce((select jsonb_agg(jsonb_build_object(
        'batch_id', t.id, 'imza', md5(t.satirlar::text), 'tip', 'Giriş', 'belge_turu', 'Tedarikçi siparişi', 'belge_no', '',
        'cari', t.cari_ad, 'cari_kodu', t.cari_kod, 'sebep', '', 'personel', t.olusturan, 'aciklama', t.aciklama, 'tarih', t.gonderim,
        'satirlar', (select coalesce(jsonb_agg(jsonb_build_object('kayit_id', t.id || '-' || x.n, 'barkod', coalesce(x.s->>'barkod', ''),
                       'stok_kodu', coalesce(x.s->>'stok_kodu', ''), 'urun_adi', coalesce(x.s->>'urun_adi', ''), 'miktar', (x.s->>'miktar')::numeric,
                       'fiyat', null, 'kdv', null) order by x.n), '[]'::jsonb)
                       from jsonb_array_elements(t.satirlar) with ordinality as x(s, n) where coalesce((x.s->>'miktar')::numeric, 0) > 0)
      ) order by t.gonderim)
      from (select * from tedarik_siparis where durum = 'gonder' and erp_durum <> 'ok'
              and gonderim < now() - make_interval(mins => greatest(coalesce(p_bekle_dk, 2), 0))
            order by gonderim limit greatest(coalesce(p_limit, 20), 1)) t), '[]'::jsonb))
$$;

create or replace function tedarik_aktarildi(p_id text, p_siparis_id bigint, p_belge_no text, p_durum text, p_mesaj text)
returns jsonb language plpgsql as $$
begin
  if p_durum not in ('ok', 'hata') then return jsonb_build_object('status', 'error', 'message', 'Geçersiz durum'); end if;
  update tedarik_siparis set erp_durum = p_durum, erp_id = coalesce(p_siparis_id, erp_id),
         erp_belge_no = case when coalesce(p_belge_no, '') <> '' then p_belge_no else erp_belge_no end,
         erp_mesaj = left(coalesce(p_mesaj, ''), 1000), erp_zaman = now()
   where id = p_id;
  if not found then return jsonb_build_object('status', 'error', 'message', 'Sipariş bulunamadı'); end if;
  insert into sistem_gunlugu (tur, kaynak, detay, hata)
  values ('siparis', 'ERP aktarım (tedarikçi)', p_durum || ': ' || coalesce(p_belge_no, '') || ' ' || left(coalesce(p_mesaj, ''), 300), p_durum <> 'ok');
  return jsonb_build_object('status', 'ok');
end $$;

create or replace function tedarikci_firma(p_cari_kod text)
returns jsonb language sql stable as $$
  with b as (   -- son belgeler
    select kaynak, fis_id, max(tarih) as tarih, max(tur_ad) as tur_ad, max(belge_no) as belge_no, count(*) as satir,
           round(sum(coalesce(tutar, miktar * coalesce(birim_fiyat, 0))), 2) as tutar
      from erp_fis_satir
     where cari_kod = coalesce(p_cari_kod, '') and fis_turu in (1, 5)
       and tarih >= now() - interval '400 days'
     group by kaynak, fis_id
  ), gunler as (
    select distinct (tarih at time zone 'Europe/Istanbul')::date as gun from erp_fis_satir
     where cari_kod = coalesce(p_cari_kod, '') and fis_turu in (1, 5) and miktar > 0 and tarih >= now() - interval '365 days'
  ), ara as (select gun - lag(gun) over (order by gun) as a from gunler
  ), fy as (    -- her ürünün bu firmadan alış fiyatları (gün başına bir)
    select distinct on (anahtar, gun) anahtar, gun, fiyat from (
      select case when stok_kodu <> '' then stok_kodu else barkod end as anahtar, (tarih at time zone 'Europe/Istanbul')::date as gun,
             coalesce(net_fiyat, birim_fiyat) as fiyat, (net_fiyat is not null) as net, giris, detay_id
        from erp_fis_satir
       where cari_kod = coalesce(p_cari_kod, '') and fis_turu in (1, 5) and giris >= 0 and miktar > 0
         and coalesce(net_fiyat, birim_fiyat) is not null and tarih >= now() - interval '730 days') x
     order by anahtar, gun, net desc, giris desc, detay_id desc
  ), fs as (
    select anahtar, gun, fiyat, row_number() over (partition by anahtar order by gun desc) as n from fy
  ), sf as (    -- her ürünün bu firmadan geldiği son belge (fatura varsa fatura, yoksa irsaliye)
    select distinct on (anahtar) anahtar, fis_id, kaynak, tarih, belge_no, tur_ad from (
      select case when stok_kodu <> '' then stok_kodu else barkod end as anahtar, fis_id, kaynak, tarih, belge_no, tur_ad, fis_turu
        from erp_fis_satir
       where cari_kod = coalesce(p_cari_kod, '') and fis_turu in (1, 5) and miktar > 0 and tarih >= now() - interval '400 days') x
     order by anahtar, (tarih at time zone 'Europe/Istanbul')::date desc, (fis_turu = 1) desc, fis_id desc
  )
  select tedarikci_oneri(p_cari_kod, 365, 60) || jsonb_build_object(
    'faturalar', coalesce((select jsonb_agg(jsonb_build_array(fis_id, kaynak, to_char(tarih at time zone 'Europe/Istanbul', 'DD.MM.YYYY'), tur_ad, belge_no, satir, tutar) order by tarih desc, fis_id desc)
                   from (select * from b order by tarih desc, fis_id desc limit 8) x), '[]'::jsonb),
    'gelis', (select count(*) from gunler),
    'aralik', (select round((percentile_cont(0.5) within group (order by a))::numeric) from ara where a is not null),
    'onceki', coalesce((select jsonb_agg(jsonb_build_array(anahtar, round(fiyat, 2), to_char(gun, 'DD.MM.YYYY'))) from fs where n = 2), '[]'::jsonb),
    'sonFis', coalesce((select jsonb_agg(jsonb_build_array(anahtar, fis_id, kaynak, to_char(tarih at time zone 'Europe/Istanbul', 'DD.MM.YYYY'), belge_no, tur_ad)) from sf), '[]'::jsonb),
    'siparisler', coalesce((select jsonb_agg(tedarik_siparis_json(t) order by t.olusturma desc)
                   from (select * from tedarik_siparis where cari_kod = coalesce(p_cari_kod, '') and durum <> 'iptal' order by olusturma desc limit 15) t), '[]'::jsonb)
  )
$$;

alter function tedarik_siparis_json(tedarik_siparis) security definer set search_path = public, extensions;
alter function tedarik_siparis_yaz(jsonb) security definer set search_path = public, extensions;
alter function aktarilacak_tedarik(integer, integer) security definer set search_path = public, extensions;
alter function tedarik_aktarildi(text, bigint, text, text, text) security definer set search_path = public, extensions;
alter function tedarikci_firma(text) security definer set search_path = public, extensions;
revoke execute on function tedarik_siparis_json(tedarik_siparis), tedarik_siparis_yaz(jsonb), aktarilacak_tedarik(integer, integer),
  tedarik_aktarildi(text, bigint, text, text, text), tedarikci_firma(text) from public;
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke all on tedarik_siparis from anon, authenticated';
    execute 'revoke execute on function tedarik_siparis_json(tedarik_siparis), tedarik_siparis_yaz(jsonb), aktarilacak_tedarik(integer, integer), tedarik_aktarildi(text, bigint, text, text, text), tedarikci_firma(text) from anon, authenticated';
  end if;
end $$;
