// Code.gs'i yükler: her istekte TAZE bir kapsam (Apps Script'te olduğu gibi her çalıştırma
// genel değişkenleri sıfırdan başlatır), ama derleme bir kez yapılır.
'use strict';
const fs = require('fs');
const vm = require('vm');

const SERVIS_ADLARI = ['SpreadsheetApp', 'PropertiesService', 'CacheService', 'LockService', 'Utilities', 'ContentService', 'HtmlService',
  'UrlFetchApp', 'MailApp', 'DriveApp', 'ScriptApp', 'Session', 'Logger', 'KRTSunucu'];

function derle(kodYolu) {
  const kaynak = fs.readFileSync(kodYolu, 'utf8');
  // Code.gs bir fonksiyonun gövdesine sarılır; sonunda isimle fonksiyon / sabit bulan bir yardımcı döner.
  const sarili = '(function (' + SERVIS_ADLARI.join(', ') + ') {\n' + kaynak +
    '\n;return function __mkBul(ad) { if (!/^[A-Za-z_$][A-Za-z0-9_$]*$/.test(ad)) throw new Error("geçersiz ad"); return eval(ad); };\n})';
  const fabrika = vm.runInThisContext(sarili, { filename: 'Code.gs', lineOffset: -1 });
  return function ornek(servisler) {
    return fabrika.apply(null, SERVIS_ADLARI.map((a) => servisler[a]));
  };
}
module.exports = { derle, SERVIS_ADLARI };
