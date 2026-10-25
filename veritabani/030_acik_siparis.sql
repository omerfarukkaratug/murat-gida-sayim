-- ============================================================
-- Açık tedarikçi siparişleri: "📨 Sipariş verildi" denmiş, malı henüz gelmemiş siparişler + firmanın teslim süresi.
-- 029'dan SONRA çalıştırılır; tekrar çalıştırmak güvenlidir. Veriye dokunmaz, yalnız okur.
--
-- tedarik_acik_siparis(cari, çarpan):
--   çarpan: { koli barkodu: koli içi adet } — telefondan koli barkoduyla girilen mal adede çevrilir (sunucu katalogdan verir).
--   Gelen = sipariş verildiği GÜNDEN itibaren o firmadan gelen miktar; ERP alış irsaliyeleri, ERP alış faturaları ve
--   telefondan girilen mal girişlerinden EN BÜYÜĞÜ (aynı mal irsaliye + fatura + telefon kaydı olarak iki kez sayılmasın).
--   Bir sipariş "açık" sayılır:
--     · hiç mal gelmediyse 21 gün boyunca,
--     · mal gelmeye başladıysa ilk gelişten sonra 3 gün daha (parça parça gelebilir); sonra eksikler "gelmedi" sayılır.
--   siparisler: [{ id, gonderim, olusturan, gelmeye_basladi, satirlar: [[barkod, stok kodu, ad, sipariş, gelen]] }]
--   yolda:      { anahtar (stok kodu ya da barkod): henüz gelmemiş miktar }  — tedarik önerisinden düşülür
--   teslim:     son 180 günde sipariş verilmesi → ilk mal gelişi arası ortalama gün (null: bilinmiyor); sayi: kaç siparişten
-- ============================================================
drop function if exists tedarik_acik_siparis(text);
create or replace function tedarik_acik_siparis(p_cari_kod text, p_carpan jsonb default '{}'::jsonb)
returns jsonb language sql stable as $$
  with t as (
    select t.id, t.gonderim, t.olusturan, t.satirlar,
           ((t.gonderim at time zone 'Europe/Istanbul')::date)::timestamp at time zone 'Europe/Istanbul' as gun   -- ERP fiş tarihi gün başıdır
      from tedarik_siparis t
     where t.cari_kod = coalesce(p_cari_kod, '') and t.durum = 'gonder' and t.gonderim >= now() - interval '180 days'
  ), ilk as (   -- her siparişten sonra firmadan İLK mal geliş zamanı (sonraki siparişin gününe kadar)
    select t.id, t.gonderim, t.olusturan, t.satirlar, t.gun,
      least(
        (select min(e.tarih) from erp_fis_satir e where e.cari_kod = p_cari_kod and e.fis_turu in (1, 5) and e.tarih >= t.gun and e.tarih < t.gun + interval '30 days'),
        (select min(m.olusturma) from mal_hareketleri m where m.cari_kodu = p_cari_kod and m.tip = 'Giriş' and m.belge_turu ilike 'al%'
            and m.olusturma >= t.gonderim and m.olusturma < t.gonderim + interval '30 days')
      ) as ilk_gelis
      from t
  ), a as (
    select * from ilk
     where (ilk_gelis is null and gonderim >= now() - interval '21 days') or (ilk_gelis >= now() - interval '3 days')
  ), s as (
    select a.id, a.gonderim, a.olusturan, a.gun, a.ilk_gelis, x.ord,
           coalesce(x.e->>'barkod', '') as barkod, coalesce(x.e->>'stok_kodu', '') as stok_kodu,
           coalesce(x.e->>'urun_adi', '') as ad, coalesce(nullif(x.e->>'miktar', '')::numeric, 0) as siparis
      from a cross join lateral jsonb_array_elements(a.satirlar) with ordinality as x(e, ord)
  ), g as (
    select s.*,
      greatest(
        coalesce((select sum(e.miktar) from erp_fis_satir e where e.cari_kod = p_cari_kod and e.fis_turu = 5 and e.tarih >= s.gun
                    and ((s.stok_kodu <> '' and e.stok_kodu = s.stok_kodu) or (s.stok_kodu = '' and s.barkod <> '' and e.barkod = s.barkod))), 0),
        coalesce((select sum(e.miktar) from erp_fis_satir e where e.cari_kod = p_cari_kod and e.fis_turu = 1 and e.tarih >= s.gun
                    and ((s.stok_kodu <> '' and e.stok_kodu = s.stok_kodu) or (s.stok_kodu = '' and s.barkod <> '' and e.barkod = s.barkod))), 0),
        coalesce((select sum(m.miktar * coalesce(nullif(coalesce(p_carpan, '{}'::jsonb)->>m.barkod, '')::numeric, 1)) from mal_hareketleri m where m.cari_kodu = p_cari_kod and m.tip = 'Giriş'
                    and m.belge_turu ilike 'al%' and m.olusturma >= s.gonderim
                    and ((s.stok_kodu <> '' and m.stok_kodu = s.stok_kodu) or (s.barkod <> '' and m.barkod = s.barkod))), 0)
      ) as gelen
      from s
  ), acik as (   -- en az bir satırı tam gelmemiş siparişler
    select distinct id from g where gelen < siparis
  ), sure as (
    select round(avg(greatest(extract(epoch from (ilk_gelis - gonderim)) / 86400, 0))::numeric, 1) as gun, count(*) as sayi
      from ilk where ilk_gelis is not null
  )
  select jsonb_build_object('status', 'ok',
    'siparisler', coalesce((select jsonb_agg(jsonb_build_object('id', o.id,
        'gonderim', to_char(o.gonderim at time zone 'Europe/Istanbul', 'DD.MM.YYYY HH24:MI'), 'olusturan', o.olusturan,
        'gelmeye_basladi', o.ilk_gelis is not null,
        'satirlar', (select jsonb_agg(jsonb_build_array(g.barkod, g.stok_kodu, g.ad, g.siparis, round(g.gelen, 3)) order by g.ord) from g where g.id = o.id))
        order by o.gonderim)
      from (select distinct g.id, g.gonderim, g.olusturan, g.ilk_gelis from g join acik on acik.id = g.id) o), '[]'::jsonb),
    'yolda', coalesce((select jsonb_object_agg(k, kalan) from (
        select case when stok_kodu <> '' then stok_kodu else barkod end as k, sum(greatest(siparis - gelen, 0)) as kalan
          from g join acik using (id) group by 1 having sum(greatest(siparis - gelen, 0)) > 0) y), '{}'::jsonb),
    'teslim', (select case when sayi > 0 then greatest(gun, 0) end from sure),
    'teslimSayi', (select sayi from sure))
$$;

alter function tedarik_acik_siparis(text, jsonb) security definer set search_path = public, extensions;
revoke execute on function tedarik_acik_siparis(text, jsonb) from public;
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke execute on function tedarik_acik_siparis(text, jsonb) from anon, authenticated';
  end if;
end $$;

-- Firmadan telefonla girilen malı hızlı bulmak için (zaten varsa atlanır).
create index if not exists mal_hareketleri_cari_giris on mal_hareketleri (cari_kodu, olusturma) where tip = 'Giriş';
