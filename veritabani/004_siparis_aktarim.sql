-- ============================================================
-- Mal Giriş / Mal Çıkış → ERP12 SİPARİŞ aktarımı (bulut tarafı).
-- 001_sema.sql'den SONRA çalıştırılır; tekrar çalıştırmak güvenlidir.
-- ERP bilgisayarındaki siparis-aktar.ps1:
--   1) aktarilacak_mal() ile bekleyen belgeleri alır,
--   2) ERP12'ye sipariş olarak yazar,
--   3) siparis_aktarildi() ile sonucu buraya bildirir.
-- Telefon anahtarına KAPALI (sadece gizli anahtar).
-- ============================================================

create table if not exists erp_siparis_aktarim (
  batch_id    text primary key,          -- telefondaki Mal Giriş/Çıkış belgesi
  tip         text not null default '',  -- 'Giriş' / 'Çıkış'
  kaynak      text not null default '',  -- ERP veri tabanı adı
  siparis_id  bigint,                    -- ERP12 SIPARIS.ID
  belge_no    text not null default '',  -- ERP12 BELGENO (örn. MOB VRLN-000001)
  durum       text not null default '',  -- ok / hata / degisti
  mesaj       text not null default '',
  imza        text not null default '',  -- aktarıldığı andaki içerik özeti
  zaman       timestamptz not null default now()
);
alter table erp_siparis_aktarim enable row level security;

-- Belgenin içerik özeti (miktar/fiyat/satır değişirse değişir).
create or replace function mal_batch_imza(p_batch text) returns text
language sql stable as $$
  select md5(coalesce(string_agg(kayit_id || ':' || miktar::text || ':' || coalesce(fiyat::text, '') || ':' || barkod, '|' order by kayit_id), ''))
    from mal_hareketleri where batch_id = p_batch
$$;

-- Bekleyen belgeler: p_baslangic'tan sonra oluşturulmuş, son değişikliğinin
-- üzerinden p_bekle_dk geçmiş (telefonda hâlâ düzenleniyor olabilir) ve henüz
-- başarıyla aktarılmamış olanlar. Ayrıca aktarıldıktan SONRA telefonda
-- değiştirilen belgeler 'degisen' listesinde döner (ERP'ye dokunulmaz, uyarı).
create or replace function aktarilacak_mal(p_baslangic timestamptz, p_bekle_dk integer default 10, p_limit integer default 50)
returns jsonb language sql stable as $$
  with b as (
    select batch_id, min(olusturma) as ilk, max(guncelleme) as son
      from mal_hareketleri
     group by batch_id
    having min(olusturma) >= p_baslangic and max(guncelleme) < now() - make_interval(mins => p_bekle_dk)
  ), bekleyen as (
    select b.* from b
     where not exists (select 1 from erp_siparis_aktarim a where a.batch_id = b.batch_id and a.durum in ('ok', 'degisti'))
     order by b.ilk limit p_limit
  )
  select jsonb_build_object('status', 'ok',
    'belgeler', coalesce((select jsonb_agg(jsonb_build_object(
        'batch_id', k.batch_id, 'imza', mal_batch_imza(k.batch_id),
        'tip', h.tip, 'belge_turu', h.belge_turu, 'belge_no', h.belge_no, 'cari', h.cari, 'cari_kodu', h.cari_kodu,
        'sebep', h.sebep, 'personel', h.personel, 'aciklama', h.aciklama, 'tarih', k.ilk,
        'satirlar', (select jsonb_agg(jsonb_build_object('kayit_id', m.kayit_id, 'barkod', m.barkod, 'stok_kodu', m.stok_kodu,
                                       'urun_adi', m.urun_adi, 'miktar', m.miktar, 'fiyat', m.fiyat, 'kdv', m.kdv) order by m.olusturma, m.kayit_id)
                       from mal_hareketleri m where m.batch_id = k.batch_id)) order by k.ilk)
      from bekleyen k
      cross join lateral (select * from mal_hareketleri x where x.batch_id = k.batch_id order by x.olusturma limit 1) h), '[]'::jsonb),
    'degisen', coalesce((select jsonb_agg(jsonb_build_object('batch_id', a.batch_id, 'belge_no', a.belge_no))
                           from erp_siparis_aktarim a
                          where a.durum = 'ok' and a.imza <> mal_batch_imza(a.batch_id)
                            and exists (select 1 from mal_hareketleri m where m.batch_id = a.batch_id)), '[]'::jsonb))
$$;

create or replace function siparis_aktarildi(p_batch text, p_tip text, p_kaynak text, p_siparis_id bigint, p_belge_no text,
                                              p_imza text, p_durum text, p_mesaj text)
returns jsonb language plpgsql as $$
begin
  if p_durum not in ('ok', 'hata', 'degisti') then
    return jsonb_build_object('status', 'error', 'message', 'Geçersiz durum');
  end if;
  insert into erp_siparis_aktarim as a (batch_id, tip, kaynak, siparis_id, belge_no, durum, mesaj, imza, zaman)
  values (p_batch, coalesce(p_tip, ''), coalesce(p_kaynak, ''), p_siparis_id, coalesce(p_belge_no, ''), p_durum,
          left(coalesce(p_mesaj, ''), 1000), coalesce(p_imza, ''), now())
  on conflict (batch_id) do update set
    tip = excluded.tip, kaynak = excluded.kaynak,
    siparis_id = coalesce(excluded.siparis_id, a.siparis_id),
    belge_no = case when excluded.belge_no <> '' then excluded.belge_no else a.belge_no end,
    durum = excluded.durum, mesaj = excluded.mesaj,
    imza = case when excluded.durum = 'degisti' then a.imza else excluded.imza end,
    zaman = now();
  insert into sistem_gunlugu (tur, kaynak, detay, hata)
  values ('siparis', 'ERP aktarım', p_durum || ': ' || coalesce(p_belge_no, '') || ' ' || left(coalesce(p_mesaj, ''), 300), p_durum <> 'ok');
  return jsonb_build_object('status', 'ok');
end $$;

alter function mal_batch_imza(text) security definer set search_path = public, extensions;
alter function aktarilacak_mal(timestamptz, integer, integer) security definer set search_path = public, extensions;
alter function siparis_aktarildi(text, text, text, bigint, text, text, text, text) security definer set search_path = public, extensions;
revoke execute on function mal_batch_imza(text) from public;
revoke execute on function aktarilacak_mal(timestamptz, integer, integer) from public;
revoke execute on function siparis_aktarildi(text, text, text, bigint, text, text, text, text) from public;
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke all on erp_siparis_aktarim from anon, authenticated';
    execute 'revoke execute on function mal_batch_imza(text), aktarilacak_mal(timestamptz, integer, integer), siparis_aktarildi(text, text, text, bigint, text, text, text, text) from anon, authenticated';
  end if;
end $$;
