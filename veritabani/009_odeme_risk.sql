-- ============================================================
-- Ödeme alışkanlığı ve risk (cari hareketlerinden). 008_vade.sql'den SONRA çalıştırılır; tekrar çalıştırılabilir.
--
-- Geçmiş ödemeler belgelerle FIFO eşleştirilir (ödeme en eski açık belgeyi kapatır). Her eşleşen tutar için:
--   ödeme günü  = ödeme tarihi − belge tarihi      → carinin GERÇEKTE kaç günde ödediği (ağırlıklı ortalama)
--   vade günü   = belge vadesi − belge tarihi      → anlaşılan vade (ağırlıklı ortalama)
-- Müşteri (bize borçlanan) için belgeler BORÇ, ödemeler ALACAK satırlarıdır; tedarikçi için tersi.
-- Son 2 yılın hareketleri kullanılır. Yalnızca TL; perakende hariç.
--
-- RİSK (0–100) — carinin KENDİ alışkanlığına göre:
--   1) Şu an açık en eski belge, carinin her zamanki ödeme gününü aştı mı?        (en çok 40 puan)
--   2) Son 90 günde gönderilen mala göre ödeme az mı? (ödeme / sevk oranı)        (en çok 30 puan)
--   3) Açık bakiyenin ne kadarı vadesini geçmiş?                                   (en çok 20 puan)
--   4) Genel olarak vadesinden geç ödeyen biri mi? (ödeme günü − vade günü)        (en çok 10 puan)
--   0–24: normal (yeşil) · 25–49: dikkat (sarı) · 50+: riskli (kırmızı)
-- Örn. vadesi 30 gün olup hep 35 günde ödeyen cari, 35 günü geçmedikçe normal sayılır.
-- ============================================================

create or replace function cari_odeme(p_cari_kod text)
returns jsonb language plpgsql stable as $$
declare
  v_kaynak text; v_musteri boolean; v_bugun date := (now() at time zone 'Europe/Istanbul')::date;
  inv record; pay record;
  i_tarih date[] := '{}'; i_vade date[] := '{}'; i_tutar numeric[] := '{}'; i_tur text[] := '{}'; i_belge text[] := '{}'; i_fis bigint[] := '{}';
  kapanan jsonb := '[]'::jsonb;
  p_tarih date[] := '{}'; p_tutar numeric[] := '{}';
  n int; m int; i int := 1; j int := 1; ri numeric; rp numeric; x numeric;
  eslesen numeric := 0; gun_top numeric := 0; vade_top numeric := 0; gec_top numeric := 0;
  ort_odeme numeric; ort_vade numeric; ort_gec numeric;
  sevk90 numeric := 0; odeme90 numeric := 0; oran numeric;
  acik numeric := 0; gecmis numeric := 0; en_eski date; yas int;
  r1 int := 0; r2 int := 0; r3 int := 0; r4 int := 0; risk int; seviye text; neden text[] := '{}';
begin
  select max(kaynak) into v_kaynak from erp_cari_hareket where cari_kod = coalesce(p_cari_kod, '');
  if v_kaynak is null then return jsonb_build_object('status', 'ok', 'bulundu', false); end if;
  select coalesce(sum(borc), 0) >= coalesce(sum(alacak), 0) into v_musteri
    from erp_cari_hareket where cari_kod = p_cari_kod and kaynak = v_kaynak and coalesce(doviz, '') in ('', 'TRY', 'TL');

  for inv in
    select (tarih at time zone 'Europe/Istanbul')::date as t, coalesce(vade, (tarih at time zone 'Europe/Istanbul')::date) as v,
           case when v_musteri then borc else alacak end as a, tur, belge_no, fis_id
      from erp_cari_hareket
     where cari_kod = p_cari_kod and kaynak = v_kaynak and coalesce(doviz, '') in ('', 'TRY', 'TL')
       and tarih >= now() - interval '730 days' and (case when v_musteri then borc else alacak end) > 0
     order by tarih, detay_id
  loop i_tarih := i_tarih || inv.t; i_vade := i_vade || inv.v; i_tutar := i_tutar || inv.a;
       i_tur := i_tur || inv.tur; i_belge := i_belge || inv.belge_no; i_fis := i_fis || inv.fis_id; end loop;
  for pay in
    select (tarih at time zone 'Europe/Istanbul')::date as t, case when v_musteri then alacak else borc end as a
      from erp_cari_hareket
     where cari_kod = p_cari_kod and kaynak = v_kaynak and coalesce(doviz, '') in ('', 'TRY', 'TL')
       and tarih >= now() - interval '730 days' and (case when v_musteri then alacak else borc end) > 0
     order by tarih, detay_id
  loop p_tarih := p_tarih || pay.t; p_tutar := p_tutar || pay.a; end loop;

  n := coalesce(array_length(i_tutar, 1), 0); m := coalesce(array_length(p_tutar, 1), 0);
  if n > 0 then ri := i_tutar[1]; end if;
  if m > 0 then rp := p_tutar[1]; end if;
  while i <= n and j <= m loop
    x := least(ri, rp);
    eslesen := eslesen + x;
    gun_top := gun_top + x * greatest(0, p_tarih[j] - i_tarih[i]);
    vade_top := vade_top + x * greatest(0, i_vade[i] - i_tarih[i]);
    gec_top := gec_top + x * greatest(0, p_tarih[j] - i_vade[i]);
    ri := ri - x; rp := rp - x;
    if ri <= 0.004 then
      kapanan := jsonb_build_array(jsonb_build_array(to_char(i_tarih[i], 'DD.MM.YYYY'), i_tur[i], i_belge[i], i_tutar[i], to_char(i_vade[i], 'DD.MM.YYYY'),
                   to_char(p_tarih[j], 'DD.MM.YYYY'), greatest(0, p_tarih[j] - i_tarih[i]), p_tarih[j] - i_vade[i], i_fis[i])) || kapanan;
      i := i + 1; if i <= n then ri := i_tutar[i]; end if;
    end if;
    if rp <= 0.004 then j := j + 1; if j <= m then rp := p_tutar[j]; end if; end if;
  end loop;
  if eslesen > 0 then
    ort_odeme := round(gun_top / eslesen); ort_vade := round(vade_top / eslesen); ort_gec := round(gec_top / eslesen);
  end if;

  select coalesce(sum(case when v_musteri then borc else alacak end), 0), coalesce(sum(case when v_musteri then alacak else borc end), 0)
    into sevk90, odeme90
    from erp_cari_hareket where cari_kod = p_cari_kod and kaynak = v_kaynak and coalesce(doviz, '') in ('', 'TRY', 'TL')
     and tarih >= now() - interval '90 days';
  if sevk90 > 0 then oran := round(odeme90 / sevk90, 2); end if;

  select coalesce(sum(a.acik), 0), coalesce(sum(case when a.vade < v_bugun then a.acik else 0 end), 0), min(a.tarih)
    into acik, gecmis, en_eski from _vade_acik(p_cari_kod) a;
  yas := case when en_eski is null then null else v_bugun - en_eski end;

  -- Puanlar (yalnızca açık bakiye bizim lehimize, yani cari bize borçluysa risk anlamlı)
  if acik > 0.01 and (v_musteri = (select (sum(borc) - sum(alacak)) > 0 from erp_cari_hareket where cari_kod = p_cari_kod and kaynak = v_kaynak and coalesce(doviz, '') in ('', 'TRY', 'TL'))) then
    if yas is not null and ort_odeme is not null and yas > ort_odeme + 5 then
      r1 := least(40, round((yas - ort_odeme) * 40.0 / greatest(ort_odeme, 15))::int);
      neden := neden || ('En eski açık belge ' || yas || ' gündür ödenmedi; normalde ' || ort_odeme || ' günde ödüyor');
    elsif yas is not null and ort_odeme is null and yas > 45 then
      r1 := least(40, (yas - 45)); neden := neden || ('En eski açık belge ' || yas || ' gündür ödenmedi (geçmiş ödeme yok)');
    end if;
    if gecmis > 0 then
      r3 := least(20, round(gecmis / acik * 20)::int);
      neden := neden || ('Açık bakiyenin %' || round(gecmis / acik * 100) || ' kadarı vadesini geçmiş');
    end if;
  end if;
  if sevk90 > 0 and oran < 0.8 then
    r2 := least(30, round((0.8 - oran) / 0.8 * 30)::int);
    neden := neden || ('Son 90 günde gönderilen mala karşılık yalnızca %' || round(oran * 100) || ' oranında ödeme yapılmış');
  end if;
  if ort_gec is not null and ort_gec > 3 then
    r4 := least(10, ort_gec::int / 3);
    neden := neden || ('Genelde vadesinden ' || ort_gec || ' gün geç ödüyor');
  end if;
  risk := r1 + r2 + r3 + r4;
  seviye := case when risk >= 50 then 'riskli' when risk >= 25 then 'dikkat' else 'normal' end;

  return jsonb_build_object(
    'status', 'ok', 'bulundu', true, 'musteri', v_musteri,
    'ortOdemeGun', ort_odeme, 'ortVadeGun', ort_vade, 'ortGecikme', ort_gec, 'eslesen', round(eslesen, 2),
    'sevk90', round(sevk90, 2), 'odeme90', round(odeme90, 2), 'oran90', oran,
    'acik', round(acik, 2), 'gecmis', round(gecmis, 2), 'enEskiGun', yas,
    'risk', risk, 'seviye', seviye, 'nedenler', to_jsonb(neden),
    'puan', jsonb_build_object('gecikme', r1, 'odemeOrani', r2, 'vadesiGecmis', r3, 'aliskanlik', r4),
    -- kapanan r: [belge tarihi, tür, no, tutar, vade, kapanış tarihi, kaç günde ödendi, vadeden kaç gün sonra (eksi: erken), fis_id] — yeniden eskiye, en çok 150
    'kapanan', (select coalesce(jsonb_agg(e), '[]'::jsonb) from (select e from jsonb_array_elements(kapanan) e limit 150) z)
  );
end $$;

-- Vade raporu: satırlara risk eklendi (yalnızca "alacak" — müşteriler).
-- satirlar r: [kod, ad, açık, geçmiş, 7 gün, ileri, ort. gecikme, ort. vade tarihi, risk, seviye, normal ödeme günü]
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
  ), r as (
    select c.*, case when coalesce(p_yon, 'alacak') = 'alacak' then cari_odeme(c.cari_kod) end as o from c where acik >= 0.01
  )
  select jsonb_build_object(
    'status', 'ok',
    'yon', coalesce(p_yon, 'alacak'),
    'toplam', (select coalesce(sum(acik), 0) from r),
    'gecmis', (select coalesce(sum(gecmis), 0) from r),
    'hafta', (select coalesce(sum(hafta), 0) from r),
    'ileri', (select coalesce(sum(ileri), 0) from r),
    'riskli', (select count(*) from r where o->>'seviye' = 'riskli'),
    'dikkat', (select count(*) from r where o->>'seviye' = 'dikkat'),
    'satirlar', coalesce((select jsonb_agg(jsonb_build_array(cari_kod, cari_ad, round(acik, 2), round(gecmis, 2), round(hafta, 2), round(ileri, 2), gecikme,
                    to_char(ort_vade, 'DD.MM.YYYY'), (o->>'risk')::int, o->>'seviye', (o->>'ortOdemeGun')::int)
                   order by coalesce((o->>'risk')::int, 0) desc, gecmis desc, acik desc) from r), '[]'::jsonb),
    'sonVeri', (select to_char(max(guncelleme) at time zone 'Europe/Istanbul', 'DD.MM.YYYY HH24:MI') from erp_cari_hareket)
  )
$$;

alter function cari_odeme(text)  security definer set search_path = public, extensions;
alter function vade_raporu(text) security definer set search_path = public, extensions;
revoke execute on function cari_odeme(text) from public;
revoke execute on function vade_raporu(text) from public;
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke execute on function cari_odeme(text), vade_raporu(text) from anon, authenticated';
  end if;
end $$;
