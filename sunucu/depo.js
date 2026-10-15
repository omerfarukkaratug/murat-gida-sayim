// =====================================================================
//  Veritabanı (PostgreSQL): sekmeler, satırlar, ayarlar, e-posta kuyruğu.
//  Her istekte değişenler TEK işlemde (BEGIN…COMMIT) yazılır: ya hepsi ya hiçbiri.
// =====================================================================
'use strict';
const { Pool } = require('./pgistemci');

const SEMA = `
create schema if not exists mk;
create table if not exists mk.sekme (
  ad text primary key, sira int not null default 0, gizli boolean not null default false,
  donmus int not null default 0, max_satir int not null default 1000, max_sutun int not null default 26,
  guncelleme timestamptz not null default now());
create table if not exists mk.satir (
  sekme text not null references mk.sekme(ad) on delete cascade on update cascade,
  satir int not null, deger jsonb not null, primary key (sekme, satir));
create table if not exists mk.ozellik (anahtar text primary key, deger text not null, guncelleme timestamptz not null default now());
create table if not exists mk.eposta (
  id bigserial primary key, zaman timestamptz not null default now(), alici text not null, konu text not null,
  metin text not null default '', html text not null default '', ekler jsonb not null default '[]',
  durum text not null default 'bekliyor', deneme int not null default 0, hata text not null default '');
create table if not exists mk.olay (id bigserial primary key, zaman timestamptz not null default now(), tur text not null, detay text not null);
`;

function depoOlustur(baglanti) {
  const havuz = new Pool(typeof baglanti === 'string' ? { connectionString: baglanti, max: 4 } : Object.assign({ max: 4 }, baglanti));
  havuz.on('error', (e) => console.error('[veritabanı] bağlantı hatası:', e.message));

  async function kur() { await havuz.query(SEMA); }

  async function yukle() {
    const s = await havuz.query('select ad, sira, gizli, donmus, max_satir, max_sutun from mk.sekme order by sira, ad');
    const r = await havuz.query('select sekme, satir, deger from mk.satir order by sekme, satir');
    const harita = {};
    const sekmeler = s.rows.map((x) => (harita[x.ad] = { ad: x.ad, gizli: x.gizli, donmus: x.donmus, maxSatir: x.max_satir, maxSutun: x.max_sutun, satirlar: [] }));
    r.rows.forEach((x) => { const k = harita[x.sekme]; if (k) k.satirlar[x.satir] = x.deger; });
    sekmeler.forEach((k) => { for (let i = 0; i < k.satirlar.length; i++) if (!k.satirlar[i]) k.satirlar[i] = []; });
    const o = await havuz.query('select anahtar, deger from mk.ozellik');
    const ozellikler = {}; o.rows.forEach((x) => { ozellikler[x.anahtar] = x.deger; });
    return { sekmeler, ozellikler };
  }

  async function kaydet(d) {
    const c = await havuz.connect();
    try {
      await c.query('begin');
      for (const ad of d.silinen || []) await c.query('delete from mk.sekme where ad = $1', [ad]);
      for (const k of d.sekmeler || []) {
        await c.query(`insert into mk.sekme (ad, sira, gizli, donmus, max_satir, max_sutun, guncelleme) values ($1,$2,$3,$4,$5,$6, now())
          on conflict (ad) do update set sira = excluded.sira, gizli = excluded.gizli, donmus = excluded.donmus,
          max_satir = excluded.max_satir, max_sutun = excluded.max_sutun, guncelleme = now()`, [k.ad, k.sira, k.gizli, k.donmus, k.maxSatir, k.maxSutun]);
        if (k.hepsi) {
          await c.query('delete from mk.satir where sekme = $1', [k.ad]);
          // Büyük sekmeler (ör. 20 bin ürünlük katalog) parça parça
          for (let i = 0; i < k.hepsi.length; i += 5000) {
            await c.query(`insert into mk.satir (sekme, satir, deger)
              select $1, (x.n - 1 + $3)::int, x.v from jsonb_array_elements($2::jsonb) with ordinality as x(v, n)`, [k.ad, JSON.stringify(k.hepsi.slice(i, i + 5000)), i]);
          }
        } else {
          if (k.satirlar && k.satirlar.length) {
            await c.query(`insert into mk.satir (sekme, satir, deger)
              select $1, (x->>0)::int, x->1 from jsonb_array_elements($2::jsonb) as x
              on conflict (sekme, satir) do update set deger = excluded.deger`, [k.ad, JSON.stringify(k.satirlar)]);
          }
          if (k.uzunluk < k.eskiUzunluk) await c.query('delete from mk.satir where sekme = $1 and satir >= $2', [k.ad, k.uzunluk]);
        }
      }
      for (const [anahtar, deger] of Object.entries(d.ozellikler || {})) {
        if (deger === null) await c.query('delete from mk.ozellik where anahtar = $1', [anahtar]);
        else await c.query(`insert into mk.ozellik (anahtar, deger, guncelleme) values ($1, $2, now())
          on conflict (anahtar) do update set deger = excluded.deger, guncelleme = now()`, [anahtar, deger]);
      }
      await c.query('commit');
    } catch (e) {
      try { await c.query('rollback'); } catch (e2) { /* bağlantı koptu */ }
      throw e;
    } finally { c.release(); }
  }

  // Taşıma: her şeyi SİLİP verilen tam kopyayı yazar (tek işlem; yarıda kalırsa eski hali durur).
  async function tamYaz(veri) {
    const c = await havuz.connect();
    try {
      await c.query('begin');
      await c.query('delete from mk.satir'); await c.query('delete from mk.sekme'); await c.query('delete from mk.ozellik');
      for (const k of veri.sekmeler) {
        await c.query('insert into mk.sekme (ad, sira, gizli, donmus, max_satir, max_sutun) values ($1,$2,$3,$4,$5,$6)', [k.ad, k.sira || 0, !!k.gizli, k.donmus || 0, k.maxSatir || 1000, k.maxSutun || 26]);
        for (let i = 0; i < k.satirlar.length; i += 5000) {
          await c.query(`insert into mk.satir (sekme, satir, deger) select $1, (x.n - 1 + $3)::int, x.v from jsonb_array_elements($2::jsonb) with ordinality as x(v, n)`,
            [k.ad, JSON.stringify(k.satirlar.slice(i, i + 5000)), i]);
        }
      }
      for (const [a, d] of Object.entries(veri.ozellikler || {})) await c.query('insert into mk.ozellik (anahtar, deger) values ($1, $2)', [a, String(d)]);
      await c.query('commit');
    } catch (e) { try { await c.query('rollback'); } catch (e2) { /* */ } throw e; } finally { c.release(); }
  }
  // Yerel veritabanı fonksiyonu (Supabase RPC yerine): select fn(ad => değer, …)
  async function rpc(fn, govde) {
    if (!/^[a-z_][a-z0-9_]*$/i.test(fn)) throw new Error('geçersiz fonksiyon adı');
    const anahtarlar = Object.keys(govde || {}).filter((k) => /^[a-z_][a-z0-9_]*$/i.test(k));
    const r = await havuz.query('select ' + fn + '(' + anahtarlar.map((k, i) => k + ' => $' + (i + 1)).join(', ') + ') as r', anahtarlar.map((k) => govde[k]));
    return r.rows.length === 1 ? r.rows[0].r : r.rows.map((x) => x.r);
  }

  async function epostaEkle(m) {
    await havuz.query('insert into mk.eposta (alici, konu, metin, html, ekler) values ($1,$2,$3,$4,$5)', [m.alici, m.konu, m.metin || '', m.html || '', JSON.stringify(m.ekler || [])]);
  }
  async function olay(tur, detay) { try { await havuz.query('insert into mk.olay (tur, detay) values ($1, $2)', [tur, String(detay).slice(0, 4000)]); } catch (e) { /* önemli değil */ } }

  return { havuz, kur, yukle, kaydet, tamYaz, rpc, epostaEkle, olay, kapat: () => havuz.end() };
}
module.exports = { depoOlustur };
