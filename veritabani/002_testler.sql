-- 001_sema.sql için senaryo testleri. BOŞ bir test veri tabanında çalıştırın:
--   createdb mkerp_test && psql -d mkerp_test -f 001_sema.sql && psql -d mkerp_test -f 002_testler.sql
-- Her test başarısızsa HATA verir; sonda "TÜM TESTLER GEÇTİ" yazar.
\set ON_ERROR_STOP on
do $$
declare r jsonb; t text;
begin
  perform yeni_donem('test');
  r := sayim_yaz('{"sessionId":"o1","personnel":"ali","rows":[{"id":"k1","v":1,"qty":"5"},{"id":"k2","qty":"3"}]}');
  assert r->'rows'->'k1' = '[1,5]', 'ilk yazım';
  r := sayim_yaz('{"sessionId":"o1","rows":[{"id":"k1","v":1,"qty":"9"},{"id":"k2","v":2,"qty":"4"}]}');
  assert r->'rows'->'k1' = '[1,5]', 'aynı sürüm tekrar gelince ezmemeli';
  assert r->'rows'->'k2' = '[2,4]', 'yeni sürüm yazmalı';
  r := sayim_yaz('{"sessionId":"o1","rows":[{"id":"k2","qty":"99"}]}');
  assert r->'rows'->'k2' = '[2,4]', 'sürümsüz gönderi düzeltilmiş satırı ezmemeli';
  perform sayim_guncelle('k1', 7, 'admin');
  r := sayim_yaz('{"sessionId":"o1","rows":[{"id":"k1","v":1,"qty":"5"}]}');
  assert r->'rows'->'k1' = '[2,7]', 'yönetici düzeltmesi korunmalı';
  perform sayim_yaz('{"sessionId":"o1","deletedIds":["k2"]}');
  r := sayim_yaz('{"sessionId":"o1","rows":[{"id":"k2","v":3,"qty":"1"}]}');
  assert not (r->'rows' ? 'k2') and r->'deleted' ? 'k2', 'silinen kayıt geri gelmemeli';
  select token into t from sayim_donemleri order by id desc limit 1;
  perform yeni_donem('yeni');
  r := sayim_yaz(jsonb_build_object('sessionId','o2','resetToken',t,'rows','[{"id":"k3","v":1,"qty":"2","ts":"1000"}]'::jsonb));
  assert (r->>'gecGelen')::int = 1, 'eski dönem kaydı geç gelen olarak işaretlenmeli';
  perform katalog_yukle('[{"barcode":"123","name":"Su"},{"barcode":"9","name":"Ekmek"}]');
  r := katalog_yukle('[]');
  assert r->>'status' = 'error' and (select count(*) from urunler) = 2, 'boş liste kataloğu silmemeli';
  perform mal_yaz('{"batchId":"b1","rows":[{"kayitId":"h1","v":1,"miktar":"2"}]}');
  update mal_hareketleri set aktarildi = now() where kayit_id = 'h1';
  r := mal_yaz('{"batchId":"b1","rows":[{"kayitId":"h1","v":2,"miktar":"5"}]}');
  assert r->'rows'->'h1' = '[1,2,1]' and (r->>'kilitli')::int = 1, 'ERP''ye aktarılan satır değişmemeli';
  raise notice 'TÜM TESTLER GEÇTİ';
end $$;
do $$
declare r jsonb;
begin
  r := cari_yukle('[{"name":"A","code":"C1","balance":"10.5"},{"name":"B","code":"","balance":null},{"name":"A2","code":"C1"}]');
  assert r->>'status' = 'ok' and (select count(*) from cariler) = 2, 'cari yükleme: ' || r::text;
  r := cari_yukle('[]');
  assert r->>'status' = 'error' and (select count(*) from cariler) = 2, 'boş cari listesi silmemeli';
  raise notice 'CARİ TESTLERİ GEÇTİ';
end $$;
do $$
declare r jsonb; g1 timestamptz;
begin
  perform mal_yaz('{"batchId":"B9","rows":[{"kayitId":"x1","v":1,"miktar":"1"},{"kayitId":"x2","v":1,"miktar":"2"}]}');
  select guncelleme into g1 from mal_hareketleri where kayit_id = 'x1';
  perform mal_yaz('{"batchId":"B9","rows":[{"kayitId":"x1","v":2,"miktar":"5"}]}');
  assert (select count(*) from mal_silinenler where kayit_id = 'x2') = 1, 'silinen mal kalemi işaretlenmeli';
  assert (select miktar from mal_hareketleri where kayit_id = 'x1') = 5, 'mal güncellenmeli';
  raise notice 'MAL KOPYA TESTLERİ GEÇTİ';
end $$;
