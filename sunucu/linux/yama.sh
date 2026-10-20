#!/usr/bin/env bash
# =====================================================================
#  KRT Saha sunucu yamalari. "krtsaha guncelle" her seferinde calistirir; tekrar calistirmak guvenlidir.
#  1) Gece yedekleri (pg_dump) uygulama kullanicisi (mk) tarafindan OKUNABILIR olsun:
#     bekci "son yedek ne zaman" der, ERP bilgisayari yedegi indirebilir (yedek-indir.ps1).
# =====================================================================
set -euo pipefail
VERI=/var/lib/krtsaha
if id mk >/dev/null 2>&1 && [ -d "$VERI/pg" ]; then
  chgrp mk "$VERI/pg"; chmod 2750 "$VERI/pg"
  find "$VERI/pg" -maxdepth 1 -name 'mkerp-*.dump' -exec chgrp mk {} + -exec chmod 640 {} +
fi
cat > /usr/local/sbin/krtsaha-pg-yedek <<'YEDEK'
#!/bin/sh
set -e
D=/var/lib/krtsaha/pg; F="$D/mkerp-$(date +%Y-%m-%d_%H%M).dump"
runuser -u postgres -- pg_dump -Fc -f "$F.tmp" mkerp && mv "$F.tmp" "$F"
chgrp mk "$F" 2>/dev/null || true; chmod 640 "$F"
find "$D" -name 'mkerp-*.dump' -mtime +30 -delete
echo "$(date -Is) yedek tamam: $F" >> "$D/yedek-log.txt"
YEDEK
chmod 750 /usr/local/sbin/krtsaha-pg-yedek
echo "✓ yamalar uygulandı"
