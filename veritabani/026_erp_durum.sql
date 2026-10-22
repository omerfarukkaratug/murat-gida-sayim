-- ============================================================
-- ERP aktarım durumu, ERP irsaliyeleri, tedarikçi fiyat karşılaştırması / notları ve uygulama yedeği.
-- 025'ten SONRA çalıştırılır; tekrar çalıştırmak güvenlidir. ERP verisine dokunmaz.
--
-- erp_nabiz_yaz(ad, mesaj, baslangic): ERP bilgisayarındaki aktarım programı her çalışmada "yaşıyorum" der.
-- erp_aktarim_durum(gun): telefondan gelen irsaliye belgelerinin ERP'ye gidiş durumu + programın son nabzı.
-- erp_irsaliyeler(gun, ara): ERP'deki irsaliyeler (alış, satış, alıştan iade, satıştan iade), faturalandı mı.
-- tedarik_ek(cari): firmanın ürünlerinin DİĞER tedarikçilerdeki son fiyatı + firma / ürün notları.
-- tedarik_not_yaz(p): firma ya da ürün notu yaz / sil.
-- uygulama_yedek(): yalnız burada duran uygulama verisi (tedarikçi siparişleri, notlar, aktarım kayıtları) — sunucu her gece saklar.
-- ============================================================

create table if not exists erp_nabiz (
  ad         text primary key,
  zaman      timestamptz not null default now(),
  mesaj      text not null default '',
  baslangic  timestamptz
);
alter table erp_nabiz enable row level security;

create or replace function erp_nabiz_yaz(p_ad text, p_mesaj text, p_baslangic timestamptz default null)
returns jsonb language sql as $$
  insert into erp_nabiz as n (ad, zaman, mesaj, baslangic)
  values (left(coalesce(p_ad, ''), 40), now(), left(coalesce(p_mesaj, ''), 200), p_baslangic)
  on conflict (ad) do update set zaman = now(), mesaj = excluded.mesaj, baslangic = coalesce(excluded.baslangic, n.baslangic);
  select jsonb_build_object('status', 'ok');
$$;

-- belgeler r: [batch_id, belge türü, cari, personel, ilk kayıt (GG.AA SS:DD), durum, ERP belge no, mesaj,
--              son değişiklikten bu yana dakika, satır sayısı, tip (Giriş/Çıkış)]
--   durum: ok (ERP'de) · hata · bekliyor · degisti (ERP'ye gittikten sonra telefonda değişti) · degisti_bildirildi
create or replace function erp_aktarim_durum(p_gun integer default 7)
returns jsonb language sql stable as $$
  with n as (select * from erp_nabiz where ad = 'mal_aktarim'),
  b as (
    select batch_id, min(olusturma) as ilk, max(guncelleme) as son, count(*) as satir,
           min(belge_turu) as belge_turu, min(cari) as cari, min(personel) as personel, min(tip) as tip
      from mal_hareketleri
     group by batch_id
    having min(olusturma) >= now() - make_interval(days => greatest(coalesce(p_gun, 7), 1))
       and min(olusturma) >= coalesce((select baslangic from n), '-infinity'::timestamptz)
  ), u as (
    select b.* from b
     where exists (select 1 from mal_hareketleri x where x.batch_id = b.batch_id and x.belge_turu ilike '%rsaliye%')
       and not exists (select 1 from mal_hareketleri x where x.batch_id = b.batch_id
                         and x.belge_turu ilike 'sat%' and x.belge_turu not ilike '%ade%'
                         and coalesce(x.sebep, '') not in ('', 'Satış'))
  ), s as (
    select u.*, a.durum as a_durum, a.belge_no, a.mesaj, a.zaman as a_zaman,
           case when a.durum = 'ok' and a.imza <> mal_batch_imza(u.batch_id) then 'degisti'
                when a.durum = 'degisti' then 'degisti_bildirildi'
                when a.durum in ('ok', 'hata') then a.durum
                else 'bekliyor' end as durum
      from u left join erp_siparis_aktarim a on a.batch_id = u.batch_id
  )
  select jsonb_build_object('status', 'ok', 'gun', p_gun,
    'nabiz', (select jsonb_build_object('zaman', to_char(zaman at time zone 'Europe/Istanbul', 'DD.MM.YYYY HH24:MI'),
                                        'dk', floor(extract(epoch from now() - zaman) / 60), 'mesaj', mesaj) from n),
    'nabizlar', coalesce((select jsonb_object_agg(ad, jsonb_build_object('zaman', to_char(zaman at time zone 'Europe/Istanbul', 'DD.MM.YYYY HH24:MI'),
                                        'dk', floor(extract(epoch from now() - zaman) / 60), 'mesaj', mesaj)) from erp_nabiz), '{}'::jsonb),
    'ozet', jsonb_build_object(
       'ok', (select count(*) from s where durum = 'ok'),
       'bekliyor', (select count(*) from s where durum = 'bekliyor'),
       'hata', (select count(*) from s where durum = 'hata'),
       'degisti', (select count(*) from s where durum in ('degisti', 'degisti_bildirildi'))),
    'belgeler', coalesce((select jsonb_agg(jsonb_build_array(batch_id, belge_turu, cari, personel,
                    to_char(ilk at time zone 'Europe/Istanbul', 'DD.MM HH24:MI'), durum, coalesce(belge_no, ''), coalesce(mesaj, ''),
                    floor(extract(epoch from now() - son) / 60), satir, tip) order by ilk desc)
                   from (select * from s order by ilk desc limit 200) x), '[]'::jsonb)
  )
$$;

-- ERP irsaliyeleri. r: [fis_id, kaynak, tarih, fis_turu, tür adı, belge no, cari kodu, cari adı, satır, tutar (KDV dahil), faturalandı]
create or replace function erp_irsaliyeler(p_gun integer default 30, p_ara text default '')
returns jsonb language sql stable as $$
  with f as (
    select kaynak, fis_id, max(tarih) as tarih, max(fis_turu) as fis_turu, max(tur_ad) as tur_ad, max(belge_no) as belge_no,
           max(cari_kod) as cari_kod, max(cari_ad) as cari_ad, count(*) as satir,
           round(sum(coalesce(tutar, miktar * coalesce(birim_fiyat, 0))), 2) as tutar,
           bool_and(giris = 0) as faturali
      from erp_fis_satir
     where fis_turu in (5, 6, 7, 8)
       and tarih >= now() - make_interval(days => least(greatest(coalesce(p_gun, 30), 1), 400))
     group by kaynak, fis_id
  )
  select jsonb_build_object('status', 'ok',
    'irsaliyeler', coalesce((select jsonb_agg(jsonb_build_array(fis_id, kaynak, to_char(tarih at time zone 'Europe/Istanbul', 'DD.MM.YYYY'),
                    fis_turu, tur_ad, belge_no, cari_kod, cari_ad, satir, tutar, faturali) order by tarih desc, fis_id desc)
                   from (select * from f
                          where coalesce(p_ara, '') = ''
                             or belge_no ilike '%' || p_ara || '%' or cari_ad ilike '%' || p_ara || '%' or cari_kod ilike '%' || p_ara || '%'
                          order by tarih desc, fis_id desc limit 300) x), '[]'::jsonb),
    'sonVeri', (select to_char(max(guncelleme) at time zone 'Europe/Istanbul', 'DD.MM.YYYY HH24:MI') from erp_fis_satir)
  )
$$;

-- ---------------- Tedarikçi notları ----------------
create table if not exists tedarik_not (
  cari_kod   text not null,
  anahtar    text not null default '',   -- '' = firma notu; yoksa ürün (stok kodu ya da barkod)
  metin      text not null default '',
  yazan      text not null default '',
  zaman      timestamptz not null default now(),
  primary key (cari_kod, anahtar)
);
alter table tedarik_not enable row level security;

create or replace function tedarik_not_yaz(p jsonb)
returns jsonb language plpgsql as $$
declare v_cari text := left(coalesce(p->>'cari_kod', ''), 80); v_anahtar text := left(coalesce(p->>'anahtar', ''), 60);
        v_metin text := left(btrim(coalesce(p->>'metin', '')), 500);
begin
  if v_cari = '' then return jsonb_build_object('status', 'error', 'message', 'Firma seçilmedi'); end if;
  if v_metin = '' then
    delete from tedarik_not where cari_kod = v_cari and anahtar = v_anahtar;
  else
    insert into tedarik_not as t (cari_kod, anahtar, metin, yazan, zaman)
    values (v_cari, v_anahtar, v_metin, left(coalesce(p->>'yazan', ''), 60), now())
    on conflict (cari_kod, anahtar) do update set metin = excluded.metin, yazan = excluded.yazan, zaman = now();
  end if;
  return jsonb_build_object('status', 'ok');
end $$;

-- Firmanın ürünleri için DİĞER tedarikçilerin son alış fiyatı (son 365 gün, net, KDV dahil) + notlar.
--   fiyatlar: { anahtar: [[cari kodu, cari adı, fiyat, tarih], ...] } (en ucuzdan pahalıya, en çok 4)
--   notlar:   { '': firma notu, anahtar: ürün notu }  (her biri [metin, yazan, tarih])
--   urunNot:  bu ürün için BAŞKA firmalara yazılmış notlar { anahtar: [[cari adı, metin], ...] }
create or replace function tedarik_ek(p_cari_kod text)
returns jsonb language sql stable as $$
  with benim as (
    select distinct case when stok_kodu <> '' then stok_kodu else barkod end as anahtar
      from erp_fis_satir
     where cari_kod = coalesce(p_cari_kod, '') and fis_turu in (1, 5) and giris >= 0 and miktar > 0
       and tarih >= now() - interval '365 days'
  ), diger as (
    select distinct on (h.anahtar, h.cari_kod) h.anahtar, h.cari_kod, h.cari_ad, h.fiyat, h.tarih
      from (select case when stok_kodu <> '' then stok_kodu else barkod end as anahtar, cari_kod, cari_ad,
                   coalesce(net_fiyat, birim_fiyat) as fiyat, tarih, detay_id
              from erp_fis_satir
             where fis_turu in (1, 5) and giris >= 0 and miktar > 0 and cari_kod <> '' and cari_kod <> coalesce(p_cari_kod, '')
               and coalesce(net_fiyat, birim_fiyat) > 0 and tarih >= now() - interval '365 days') h
      join benim on benim.anahtar = h.anahtar
     order by h.anahtar, h.cari_kod, h.tarih desc, h.detay_id desc
  ), sirali as (
    select *, row_number() over (partition by anahtar order by fiyat) as n from diger
  )
  select jsonb_build_object('status', 'ok',
    'fiyatlar', coalesce((select jsonb_object_agg(anahtar, l) from (
        select anahtar, jsonb_agg(jsonb_build_array(cari_kod, cari_ad, round(fiyat, 2), to_char(tarih at time zone 'Europe/Istanbul', 'DD.MM.YYYY')) order by fiyat) as l
          from sirali where n <= 4 group by anahtar) x), '{}'::jsonb),
    'notlar', coalesce((select jsonb_object_agg(anahtar, jsonb_build_array(metin, yazan, to_char(zaman at time zone 'Europe/Istanbul', 'DD.MM.YYYY')))
                          from tedarik_not where cari_kod = coalesce(p_cari_kod, '')), '{}'::jsonb),
    'urunNot', coalesce((select jsonb_object_agg(anahtar, l) from (
        select t.anahtar, jsonb_agg(jsonb_build_array(coalesce((select max(cari_ad) from erp_fis_satir e where e.cari_kod = t.cari_kod and e.cari_ad <> ''), t.cari_kod), t.metin)) as l
          from tedarik_not t join benim on benim.anahtar = t.anahtar
         where t.cari_kod <> coalesce(p_cari_kod, '') and t.anahtar <> ''
         group by t.anahtar) y), '{}'::jsonb)
  )
$$;

-- Yalnız bu veri tabanında duran uygulama verisi (ERP'den yeniden gelemez). Sunucu her gece alır, saklar.
create or replace function uygulama_yedek()
returns jsonb language sql stable as $$
  select jsonb_build_object('status', 'ok', 'zaman', now(),
    'tedarik_siparis', coalesce((select jsonb_agg(to_jsonb(t)) from tedarik_siparis t), '[]'::jsonb),
    'tedarik_not', coalesce((select jsonb_agg(to_jsonb(t)) from tedarik_not t), '[]'::jsonb),
    'erp_siparis_aktarim', coalesce((select jsonb_agg(to_jsonb(t)) from erp_siparis_aktarim t), '[]'::jsonb),
    'erp_nabiz', coalesce((select jsonb_agg(to_jsonb(t)) from erp_nabiz t), '[]'::jsonb))
$$;

alter function erp_nabiz_yaz(text, text, timestamptz) security definer set search_path = public, extensions;
alter function erp_aktarim_durum(integer) security definer set search_path = public, extensions;
alter function erp_irsaliyeler(integer, text) security definer set search_path = public, extensions;
alter function tedarik_not_yaz(jsonb) security definer set search_path = public, extensions;
alter function tedarik_ek(text) security definer set search_path = public, extensions;
alter function uygulama_yedek() security definer set search_path = public, extensions;
revoke execute on function erp_nabiz_yaz(text, text, timestamptz) from public;
revoke execute on function erp_aktarim_durum(integer) from public;
revoke execute on function erp_irsaliyeler(integer, text) from public;
revoke execute on function tedarik_not_yaz(jsonb) from public;
revoke execute on function tedarik_ek(text) from public;
revoke execute on function uygulama_yedek() from public;
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke all on erp_nabiz, tedarik_not from anon, authenticated';
    execute 'revoke execute on function erp_nabiz_yaz(text, text, timestamptz), erp_aktarim_durum(integer), erp_irsaliyeler(integer, text), tedarik_not_yaz(jsonb), tedarik_ek(text), uygulama_yedek() from anon, authenticated';
  end if;
end $$;

-- İrsaliyeleri tarihle hızlı bulmak için.
create index if not exists erp_fis_satir_irsaliye_tarih on erp_fis_satir (tarih desc) where fis_turu in (5, 6, 7, 8);
