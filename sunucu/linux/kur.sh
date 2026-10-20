#!/usr/bin/env bash
# =====================================================================
#  KRT Saha sunucusu — Linux (Ubuntu 24.04) kurulumu. Kiralık sunucuda root olarak:
#    curl -fsSL https://raw.githubusercontent.com/omerfarukkaratug/murat-gida-sayim/main/sunucu/linux/kur.sh | bash
#  Farklı adres için:  ... | bash -s -- baska.alanadi.com
#  Ne kurar:
#   - Node.js 22, PostgreSQL, Caddy (https sertifikasını kendisi alır ve yeniler)
#   - Uygulama: /opt/krtsaha   Ayarlar: /etc/krtsaha/ayar.json (yalnız root ve servis okur)
#   - Servis "krtsaha": açılışta başlar, kapanırsa 3 sn içinde yeniden başlar
#   - Gece yedeği (02:30, pg_dump, 30 gün): /var/lib/krtsaha/pg
#   - Güvenlik duvarı (yalnız SSH + https), otomatik güvenlik güncellemeleri, SSH saldırı engeli (fail2ban)
#  Tekrar çalıştırmak güvenlidir: mevcut veritabanı, şifre ve veri korunur.
#  ERP12'ye ve Google'a DOKUNMAZ.
# =====================================================================
set -euo pipefail
ALAN="${1:-sunucu.krtsaha.com}"
DEPO="https://github.com/omerfarukkaratug/murat-gida-sayim.git"
KOK=/opt/krtsaha; AYAR_DIZ=/etc/krtsaha; VERI=/var/lib/krtsaha
adim() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
[ "$(id -u)" = 0 ] || { echo "root olarak çalıştır"; exit 1; }
. /etc/os-release; [ "${ID:-}" = ubuntu ] || echo "Uyarı: Ubuntu dışı sistem ($PRETTY_NAME) — denenmedi."
export DEBIAN_FRONTEND=noninteractive

adim "Saat dilimi ve takas alanı"
timedatectl set-timezone Europe/Istanbul || true
if ! swapon --show | grep -q .; then
  fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile >/dev/null && swapon /swapfile
  grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

adim "Paketler"
apt-get update -q
apt-get install -yq ca-certificates curl gnupg git postgresql ufw fail2ban unattended-upgrades debian-keyring debian-archive-keyring apt-transport-https
if ! command -v node >/dev/null || [ "$(node -v | sed 's/^v\([0-9]*\).*/\1/')" -lt 20 ]; then
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  apt-get install -yq nodejs
fi
if ! command -v caddy >/dev/null; then
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --batch --yes --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' > /etc/apt/sources.list.d/caddy-stable.list
  apt-get update -q && apt-get install -yq caddy
fi
echo "Node $(node -v), $(psql --version), $(caddy version | cut -d' ' -f1)"

adim "Uygulama kodu ($KOK)"
if [ -d "$KOK/.git" ]; then git -C "$KOK" pull -q --ff-only; else git clone -q --depth 1 "$DEPO" "$KOK"; fi
id mk >/dev/null 2>&1 || useradd --system --home "$VERI" --shell /usr/sbin/nologin mk
install -d -o mk -g mk -m 750 "$VERI" "$VERI/yedek"
install -d -o postgres -g postgres -m 750 "$VERI/pg"
install -d -o root -g mk -m 750 "$AYAR_DIZ"

adim "Veritabanı"
systemctl enable --now postgresql >/dev/null
if [ -f "$AYAR_DIZ/ayar.json" ]; then
  SIFRE=$(node -e 'const a=require(process.argv[1]);console.log(decodeURIComponent(new URL(a.veritabani).password))' "$AYAR_DIZ/ayar.json")
else
  SIFRE=$(head -c 48 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 32)
fi
if runuser -u postgres -- psql -Atc "select 1 from pg_roles where rolname='mk'" | grep -q 1; then
  runuser -u postgres -- psql -qc "alter role mk with login password '$SIFRE'"
else
  runuser -u postgres -- psql -qc "create role mk with login password '$SIFRE'"
fi
runuser -u postgres -- psql -Atc "select 1 from pg_database where datname='mkerp'" | grep -q 1 ||
  runuser -u postgres -- psql -qc "create database mkerp owner mk encoding 'UTF8' template template0"

adim "Ayarlar ($AYAR_DIZ/ayar.json)"
if [ ! -f "$AYAR_DIZ/ayar.json" ]; then
  cat > "$AYAR_DIZ/ayar.json" <<EOF
{
  "port": 8080,
  "host": "127.0.0.1",
  "veritabani": "postgres://mk:$SIFRE@127.0.0.1:5432/mkerp",
  "kod": "$KOK/Code.gs",
  "statik": "$KOK",
  "yedekDizini": "$VERI/yedek",
  "adres": "https://$ALAN"
}
EOF
fi
chown root:mk "$AYAR_DIZ/ayar.json"; chmod 640 "$AYAR_DIZ/ayar.json"

adim "Servis"
cat > /etc/systemd/system/krtsaha.service <<EOF
[Unit]
Description=KRT Saha sunucusu
After=network-online.target postgresql.service
Wants=network-online.target postgresql.service

[Service]
User=mk
Group=mk
WorkingDirectory=$KOK/sunucu
Environment=MK_AYAR=$AYAR_DIZ/ayar.json NODE_ENV=production
ExecStart=/usr/bin/node ana.js
Restart=always
RestartSec=3
TimeoutStopSec=30
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
PrivateDevices=true
ProtectKernelTunables=true
ProtectControlGroups=true
ReadWritePaths=$VERI

[Install]
WantedBy=multi-user.target
EOF

cat > /usr/local/sbin/krtsaha-pg-yedek <<EOF
#!/bin/sh
set -e
D=$VERI/pg; F="\$D/mkerp-\$(date +%Y-%m-%d_%H%M).dump"
runuser -u postgres -- pg_dump -Fc -f "\$F.tmp" mkerp && mv "\$F.tmp" "\$F"
find "\$D" -name 'mkerp-*.dump' -mtime +30 -delete
echo "\$(date -Is) yedek tamam: \$F" >> "\$D/yedek-log.txt"
EOF
chmod 750 /usr/local/sbin/krtsaha-pg-yedek
cat > /etc/systemd/system/krtsaha-yedek.service <<'EOF'
[Unit]
Description=KRT Saha veritabani yedegi
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/krtsaha-pg-yedek
EOF
cat > /etc/systemd/system/krtsaha-yedek.timer <<'EOF'
[Unit]
Description=KRT Saha gece yedegi
[Timer]
OnCalendar=*-*-* 02:30:00
Persistent=true
[Install]
WantedBy=timers.target
EOF
systemctl daemon-reload
systemctl enable --now krtsaha-yedek.timer >/dev/null
bash "$KOK/sunucu/linux/yama.sh" >/dev/null
systemctl enable krtsaha >/dev/null
systemctl restart krtsaha

adim "https (Caddy) — $ALAN"
cat > /etc/caddy/Caddyfile <<EOF
$ALAN {
	encode gzip
	@ic path /__yonetim/* /__durum /__mal
	respond @ic 404
	header {
		Strict-Transport-Security "max-age=31536000"
		X-Content-Type-Options nosniff
		Referrer-Policy strict-origin-when-cross-origin
		-Server
	}
	reverse_proxy 127.0.0.1:8080
}
EOF
systemctl enable caddy >/dev/null; systemctl reload caddy 2>/dev/null || systemctl restart caddy

adim "Güvenlik"
ufw allow OpenSSH >/dev/null; ufw allow 80/tcp >/dev/null; ufw allow 443/tcp >/dev/null
ufw --force enable >/dev/null
systemctl enable --now fail2ban >/dev/null
printf 'APT::Periodic::Update-Package-Lists "1";\nAPT::Periodic::Unattended-Upgrade "1";\n' > /etc/apt/apt.conf.d/20auto-upgrades

adim "Yönetim komutu: krtsaha"
install -m 755 "$KOK/sunucu/linux/krtsaha" /usr/local/bin/krtsaha

adim "Kontrol"
for i in $(seq 1 20); do curl -fs http://127.0.0.1:8080/saglik >/dev/null && break; sleep 1; done
if curl -fs http://127.0.0.1:8080/saglik >/dev/null; then echo "✓ Sunucu çalışıyor"; else echo "✗ Sunucu cevap vermedi: krtsaha log"; fi
IP=$(curl -fs4 https://api.ipify.org || hostname -I | cut -d' ' -f1)
cat <<EOF

────────────────────────────────────────────────────────
 KURULUM TAMAM
 1) Cloudflare → krtsaha.com → DNS → Add record:
      Type A   Name: ${ALAN%%.krtsaha.com}   IPv4: $IP   Proxy: KAPALI (gri bulut)
 2) Birkaç dakika sonra:  https://$ALAN/saglik  → {"durum":"ok"}
 3) Prova (Google'a dokunmaz):  krtsaha prova
 Diğer komutlar:  krtsaha yardim
────────────────────────────────────────────────────────
EOF
