-- ============================================================
-- Vade raporu (cari hareketlerinden). 005/006'dan SONRA çalıştırılır; tekrar çalıştırmak güvenlidir.
--
-- Açık kalem bulma (FIFO): carinin bakiyesi borç tarafındaysa (cari bize borçlu) ödemeler EN ESKİ
-- borçları kapatmış sayılır; açık kalan bakiye en YENİ borç satırlarından oluşur. Alacak tarafındaysa
-- (biz borçluyuz) aynısı alacak satırları için. Her açık kalemin vadesi: satırın vade tarihi, yoksa
-- belge tarihi.
-- Yalnızca TL (TRY) hareketleri; perakende (__PERAKENDE__) hariç.
-- ============================================================

create or replace function _vade_acik(p_cari_kod text)
returns table (cari_kod text, cari_ad text, yon text, tarih date, vade date, tur text, belge_no text, tutar numeric, acik numeric, fis_id bigint)
language sql stable as $$
  with k as (
    select h.cari_kod, max(h.kaynak) as kaynak from erp_cari_hareket h
     where h.cari_kod <> '__PERAKENDE__' and (p_cari_kod is null or h.cari_kod = p_cari_kod)
       and coalesce(h.doviz, '') in ('', 'TRY', 'TL')
     group by h.cari_kod
  ), t as (
    select h.* from erp_cari_hareket h join k on k.cari_kod = h.cari_kod and k.kaynak = h.kaynak
     where coalesce(h.doviz, '') in ('', 'TRY', 'TL')
  ), b as (
    select cari_kod, max(cari_ad) as cari_ad, sum(borc - alacak) as bakiye from t group by cari_kod
  ), s as (
    select t.cari_kod, b.cari_ad, case when b.bakiye > 0 then 'alacak' else 'borc' end as yon,
           (t.tarih at time zone 'Europe/Istanbul')::date as tarih,
           coalesce(t.vade, (t.tarih at time zone 'Europe/Istanbul')::date) as vade,
           t.tur, t.belge_no, case when b.bakiye > 0 then t.borc else t.alacak end as tutar, abs(b.bakiye) as kalan,
           t.fis_id, t.detay_id
      from t join b on b.cari_kod = t.cari_kod
     where abs(b.bakiye) >= 0.01 and (case when b.bakiye > 0 then t.borc else t.alacak end) > 0
  ), c as (
    select s.*, sum(tutar) over (partition by cari_kod order by tarih desc, detay_id desc) - tutar as onceki from s
  )
  select cari_kod, cari_ad, yon, tarih, vade, tur, belge_no, tutar, least(tutar, kalan - onceki) as acik, fis_id
    from c where kalan - onceki > 0.004
$$;

-- Bir carinin açık kalemleri ve vade özeti.
-- kalemler r: [belge tarihi, tür, belge no, belge tutarı, açık tutar, vade, gün (eksi: geçmiş), fis_id]
create or replace function cari_vade(p_cari_kod text)
returns jsonb language sql stable as $$
  with a as (select * from _vade_acik(coalesce(p_cari_kod, ''))),
  g as (select (now() at time zone 'Europe/Istanbul')::date as bugun),
  r as (
    select (case when h.borc > 0 then h.borc else h.alacak end) as tutar, (h.tarih at time zone 'Europe/Istanbul')::date as tarih, h.vade
      from erp_cari_hareket h
     where h.cari_kod = coalesce(p_cari_kod, '') and h.vade is not null and h.tarih >= now() - interval '365 days'
       and (h.borc > 0 or h.alacak > 0) and h.vade > (h.tarih at time zone 'Europe/Istanbul')::date
  )
  select jsonb_build_object(
    'status', 'ok',
    'yon', (select yon from a limit 1),
    'acik', (select coalesce(sum(acik), 0) from a),
    'gecmis', (select coalesce(sum(acik), 0) from a, g where a.vade < g.bugun),
    'hafta', (select coalesce(sum(acik), 0) from a, g where a.vade >= g.bugun and a.vade <= g.bugun + 7),
    'ileri', (select coalesce(sum(acik), 0) from a, g where a.vade > g.bugun + 7),
    'ortGecikme', (select round(sum(acik * (g.bugun - a.vade)) / nullif(sum(acik), 0)) from a, g where a.vade < g.bugun),
    'ortVadeTarihi', (select to_char(max(g.bugun) + round(sum(acik * (a.vade - g.bugun)) / nullif(sum(acik), 0))::int, 'DD.MM.YYYY') from a, g),
    'ortVadeGun', (select round(sum(tutar * (vade - tarih)) / nullif(sum(tutar), 0)) from r),
    'kalemler', coalesce((select jsonb_agg(jsonb_build_array(to_char(a.tarih, 'DD.MM.YYYY'), a.tur, a.belge_no, a.tutar, round(a.acik, 2),
                    to_char(a.vade, 'DD.MM.YYYY'), a.vade - g.bugun, a.fis_id) order by a.vade, a.tarih) from a, g), '[]'::jsonb)
  )
$$;

-- Bütün cariler: p_yon = 'alacak' (müşteriler bize borçlu) | 'borc' (biz tedarikçilere borçluyuz).
-- satirlar r: [cari kodu, cari adı, açık bakiye, vadesi geçmiş, 7 gün içinde, ileri vadeli, ort. gecikme (gün), ort. vade tarihi]
create or replace function vade_raporu(p_yon text)
returns jsonb language sql stable as $$
  with a as (select * from _vade_acik(null) where yon = coalesce(p_yon, 'alacak')),
  g as (select (now() at time zone 'Europe/Istanbul')::date as bugun),
  c as (
    select a.cari_kod, max(a.cari_ad) as cari_ad, sum(acik) as acik,
           sum(case when a.vade < g.bugun then acik else 0 end) as gecmis,
           sum(case when a.vade >= g.bugun and a.vade <= g.bugun + 7 then acik else 0 end) as hafta,
           sum(case when a.vade > g.bugun + 7 then acik else 0 end) as ileri,
           round(sum(case when a.vade < g.bugun then acik * (g.bugun - a.vade) else 0 end) / nullif(sum(case when a.vade < g.bugun then acik else 0 end), 0)) as gecikme,
           g.bugun + round(sum(acik * (a.vade - g.bugun)) / nullif(sum(acik), 0))::int as ort_vade
      from a, g group by a.cari_kod, g.bugun
  )
  select jsonb_build_object(
    'status', 'ok',
    'yon', coalesce(p_yon, 'alacak'),
    'toplam', (select coalesce(sum(acik), 0) from c),
    'gecmis', (select coalesce(sum(gecmis), 0) from c),
    'hafta', (select coalesce(sum(hafta), 0) from c),
    'ileri', (select coalesce(sum(ileri), 0) from c),
    'satirlar', coalesce((select jsonb_agg(jsonb_build_array(cari_kod, cari_ad, round(acik, 2), round(gecmis, 2), round(hafta, 2), round(ileri, 2), gecikme, to_char(ort_vade, 'DD.MM.YYYY'))
                   order by gecmis desc, acik desc) from c where acik >= 0.01), '[]'::jsonb),
    'sonVeri', (select to_char(max(guncelleme) at time zone 'Europe/Istanbul', 'DD.MM.YYYY HH24:MI') from erp_cari_hareket)
  )
$$;

alter function _vade_acik(text) security definer set search_path = public, extensions;
alter function cari_vade(text)  security definer set search_path = public, extensions;
alter function vade_raporu(text) security definer set search_path = public, extensions;
revoke execute on function _vade_acik(text) from public;
revoke execute on function cari_vade(text) from public;
revoke execute on function vade_raporu(text) from public;
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke execute on function _vade_acik(text), cari_vade(text), vade_raporu(text) from anon, authenticated';
  end if;
end $$;
