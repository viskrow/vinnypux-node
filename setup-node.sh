#!/bin/bash
# =============================================================================
# Remnawave VPN Node — автоматическая установка
#
# Установка одной командой:
#   bash <(curl -fsSL https://raw.githubusercontent.com/vinnypux/vinnypux-node/main/setup-node.sh) \
#     --secret-key "SECRET_KEY_ИЗ_ПАНЕЛИ"
#
# Флаги:
#   --secret-key "..."   SECRET_KEY ноды (обязательный, из панели Remnawave)
#   --with-bridges       открыть порты 7443-7447 для мостов RU→Foreign
#   --with-wl            открыть порты 80, 2083, 2085 для WL-схемы (CDN)
#   --no-update          пропустить apt upgrade
#   --ssh-port 2222      если SSH на нестандартном порту
# =============================================================================

set -euo pipefail

# ─── Константы ────────────────────────────────────────────────────────────────
REPO_URL="https://github.com/viskrow/vinnypux-node.git"
INSTALL_DIR="/opt/vinnypux-node"
NODE_PORT="2222"
NODE_EXPORTER_PORT="9100"

# ─── Цвета ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

ok()     { echo -e "${GREEN}✓${NC} $*"; }
info()   { echo -e "${CYAN}→${NC} $*"; }
warn()   { echo -e "${YELLOW}⚠${NC} $*"; }
die()    { echo -e "${RED}✗ ОШИБКА:${NC} $*" >&2; exit 1; }
header() {
  echo ""
  echo -e "${BOLD}${CYAN}══════════════════════════════════════════${NC}"
  echo -e "${BOLD}  $*${NC}"
  echo -e "${BOLD}${CYAN}══════════════════════════════════════════${NC}"
}

# ─── Проверка root ────────────────────────────────────────────────────────────
[[ $EUID -ne 0 ]] && die "Запустите от root: sudo bash $0"

# ─── Параметры ────────────────────────────────────────────────────────────────
SECRET_KEY=""
SSH_PORT="22"
SKIP_UPDATE="false"
WITH_BRIDGES="false"
WITH_WL="false"

while [[ $# -gt 0 ]]; do
  case $1 in
    --secret-key)     SECRET_KEY="$2";    shift 2 ;;
    --ssh-port)       SSH_PORT="$2";      shift 2 ;;
    --no-update)      SKIP_UPDATE="true"; shift ;;
    --with-bridges)   WITH_BRIDGES="true"; shift ;;
    --with-wl)        WITH_WL="true";     shift ;;
    *) die "Неизвестный аргумент: $1" ;;
  esac
done

# Интерактивный ввод SECRET_KEY если не передан
if [[ -z "$SECRET_KEY" ]]; then
  echo ""
  echo -e "  ${BOLD}Откуда взять SECRET_KEY:${NC}"
  echo -e "  Веб-панель Remnawave → Nodes → создай ноду → скопируй SECRET_KEY"
  echo ""
  read -rsp "  SECRET_KEY ноды: " SECRET_KEY
  echo ""
  [[ -z "$SECRET_KEY" ]] && die "SECRET_KEY не может быть пустым"
fi

# ─── Автоопределение IP ───────────────────────────────────────────────────────
SERVER_IP=$(curl -4 -s --max-time 5 https://ifconfig.me 2>/dev/null \
         || curl -4 -s --max-time 5 https://api.ipify.org 2>/dev/null \
         || curl -s --max-time 5 https://ifconfig.me 2>/dev/null \
         || hostname -I | awk '{print $1}')
[[ -z "$SERVER_IP" ]] && die "Не удалось определить внешний IP"

# ─── Шапка ────────────────────────────────────────────────────────────────────
header "Remnawave Node Setup"
echo -e "  ${BOLD}IP:${NC} $SERVER_IP"
echo ""

# =============================================================================
# 1. Обновление системы
# =============================================================================
header "1/6 — Обновление системы"

if [[ "$SKIP_UPDATE" == "true" ]]; then
  warn "Пропущено (--no-update)"
else
  info "apt update + upgrade..."
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold"
  ok "Система обновлена"
fi

if [[ -f /var/run/reboot-required ]]; then
  warn "Требуется ребут после обновления ядра."
  warn "После ребута запусти скрипт повторно — он продолжит с того места где остановился."
  reboot
  exit 0
fi

# =============================================================================
# 2. XanMod / BBR3
# =============================================================================
header "2/6 — Ядро XanMod / BBR3"

BBR_VER=$(modinfo tcp_bbr 2>/dev/null | awk '/^version:/{print $2}' || echo "1")

if [[ "$BBR_VER" == "3" ]]; then
  ok "BBR3 уже доступен (ядро: $(uname -r))"
else
  info "BBR версия: $BBR_VER (ядро: $(uname -r))"
  info "Устанавливаем XanMod..."

  # CPU level
  if grep -q "avx512" /proc/cpuinfo; then CPU_LEVEL="x64v4"
  elif grep -q "avx2" /proc/cpuinfo; then CPU_LEVEL="x64v3"
  elif grep -q "sse4_2" /proc/cpuinfo; then CPU_LEVEL="x64v2"
  else CPU_LEVEL="x64v1"; fi
  info "CPU: $CPU_LEVEL"

  # Установка GPG ключа XanMod (несколько источников — dl.xanmod.org блокирует некоторые хостинги)
  apt-get install -y -qq gnupg
  rm -f /etc/apt/trusted.gpg.d/xanmod*.gpg /tmp/xanmod.key
  local GPG_OUT="/etc/apt/trusted.gpg.d/xanmod-archive.gpg"
  local key_ok=false
  local KEY_URLS=(
    "https://dl.xanmod.org/archive.key"
    "https://dl.xanmod.org/gpg.key"
    "https://gitlab.com/xanmod/linux/-/raw/main/keys/signing.key"
  )
  for url in "${KEY_URLS[@]}"; do
    if curl -fsSL -A "Mozilla/5.0" --max-time 10 "$url" -o /tmp/xanmod.key 2>/dev/null && [[ -s /tmp/xanmod.key ]]; then
      if gpg --yes --dearmor -o "$GPG_OUT" < /tmp/xanmod.key 2>/dev/null; then
        key_ok=true; ok "GPG ключ получен: $url"; break
      fi
    fi
  done
  rm -f /tmp/xanmod.key
  [[ "$key_ok" != "true" ]] && die "Не удалось скачать GPG ключ XanMod ни из одного источника"
  echo "deb [signed-by=/etc/apt/trusted.gpg.d/xanmod-archive.gpg] http://deb.xanmod.org releases main" \
    > /etc/apt/sources.list.d/xanmod-release.list
  apt-get update -qq

  XANMOD_PKG=""
  for lvl in "$CPU_LEVEL" x64v3 x64v2 x64v1; do
    XANMOD_PKG=$(apt-cache search "linux-image.*${lvl}.*xanmod" 2>/dev/null \
      | grep -v "\-rt\-" | sort -V | tail -1 | awk '{print $1}')
    [[ -n "$XANMOD_PKG" ]] && { info "Пакет: $XANMOD_PKG ($lvl)"; break; }
  done
  [[ -z "$XANMOD_PKG" ]] && die "Не найден пакет XanMod"

  apt-get install -y "$XANMOD_PKG"
  ok "$XANMOD_PKG установлен — нужен ребут"
  warn "После ребута запусти скрипт повторно."
  reboot
  exit 0
fi

# =============================================================================
# 3. Сетевая оптимизация (BBR3 + sysctl + ulimits)
# =============================================================================
header "3/6 — Сетевая оптимизация"

RAM_MB=$(awk '/MemTotal/{print int($2/1024)}' /proc/meminfo)
if   [[ "$RAM_MB" -ge 8192 ]]; then BUF=67108864   # 64MB — 8+ GB RAM
elif [[ "$RAM_MB" -ge 4096 ]]; then BUF=33554432   # 32MB — 4-8 GB RAM
elif [[ "$RAM_MB" -ge 2048 ]]; then BUF=16777216   # 16MB — 2-4 GB RAM
else                                BUF=8388608; fi #  8MB — < 2 GB RAM
info "RAM: ${RAM_MB}MB → TCP буфер: $((BUF/1024/1024))MB"

cat > /etc/sysctl.d/99-vpn-perf.conf << EOF
# ── BBR3 ──────────────────────────────────────
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
# ── TCP буферы (под RAM: ${RAM_MB}MB) ─────────
net.core.rmem_max = ${BUF}
net.core.wmem_max = ${BUF}
net.core.optmem_max = 65536
net.ipv4.tcp_rmem = 4096 87380 ${BUF}
net.ipv4.tcp_wmem = 4096 65536 ${BUF}
# ── Скорость соединений ──────────────────────
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_notsent_lowat = 131072
# ── Переиспользование сокетов ─────────────────
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_max_tw_buckets = 500000
net.ipv4.tcp_fin_timeout = 15
# ── Keepalive (обнаружение мёртвых соединений) ─
net.ipv4.tcp_keepalive_time = 120
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 5
# ── Очереди и лимиты ─────────────────────────
net.ipv4.tcp_syncookies = 1
net.core.netdev_max_backlog = 250000
net.ipv4.tcp_max_syn_backlog = 8192
net.core.somaxconn = 65535
net.ipv4.ip_local_port_range = 1024 65535
fs.file-max = 1000000
EOF
sysctl -p /etc/sysctl.d/99-vpn-perf.conf > /dev/null

# Conntrack
if modprobe nf_conntrack 2>/dev/null || lsmod | grep -q nf_conntrack; then
  cat > /etc/sysctl.d/99-conntrack.conf << EOF
net.netfilter.nf_conntrack_max = 1000000
net.netfilter.nf_conntrack_tcp_timeout_established = 1800
net.netfilter.nf_conntrack_tcp_timeout_time_wait = 15
EOF
  sysctl -p /etc/sysctl.d/99-conntrack.conf > /dev/null 2>&1 || true
fi

# ulimits
if ! grep -q "1048576" /etc/security/limits.conf 2>/dev/null; then
  cat >> /etc/security/limits.conf << EOF
*    soft nofile 1048576
*    hard nofile 1048576
root soft nofile 1048576
root hard nofile 1048576
EOF
fi
sed -i 's/^#*DefaultLimitNOFILE=.*/DefaultLimitNOFILE=1048576/' /etc/systemd/system.conf
grep -q "^DefaultLimitNOFILE=1048576" /etc/systemd/system.conf \
  || echo "DefaultLimitNOFILE=1048576" >> /etc/systemd/system.conf
sed -i 's/^#*DefaultLimitNOFILE=.*/DefaultLimitNOFILE=1048576/' /etc/systemd/user.conf
grep -q "^DefaultLimitNOFILE=1048576" /etc/systemd/user.conf \
  || echo "DefaultLimitNOFILE=1048576" >> /etc/systemd/user.conf
systemctl daemon-reexec > /dev/null 2>&1 || true

# fq qdisc
IFACE=$(ip route | awk '/^default/{print $5; exit}')
if [[ -n "$IFACE" ]]; then
  tc qdisc replace dev "$IFACE" root fq flow_limit 250 2>/dev/null || true
  cat > /etc/systemd/system/set-qdisc-fq.service << SVCEOF
[Unit]
Description=Set fq qdisc for BBR on ${IFACE}
After=network.target
[Service]
Type=oneshot
ExecStart=/sbin/tc qdisc replace dev ${IFACE} root fq flow_limit 250
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
SVCEOF
  systemctl daemon-reload
  systemctl enable set-qdisc-fq.service > /dev/null 2>&1
fi

ok "BBR3 + sysctl + ulimits + fq настроены"

# =============================================================================
# 4. Firewall (UFW)
# =============================================================================
header "4/6 — Firewall"

command -v ufw &>/dev/null || apt-get install -y -qq ufw
ufw default deny incoming > /dev/null
ufw default allow outgoing > /dev/null
ufw allow "$SSH_PORT"/tcp   comment "SSH"          > /dev/null
ufw allow "$NODE_PORT"/tcp  comment "remnanode"     > /dev/null
ufw allow 443/tcp           comment "HTTPS/Reality" > /dev/null
ufw allow "$NODE_EXPORTER_PORT"/tcp comment "NodeExporter" > /dev/null

if [[ "$WITH_BRIDGES" == "true" ]]; then
  ufw allow 7443:7447/tcp comment "Bridges" > /dev/null
  ok "Мосты 7443-7447 открыты"
fi
if [[ "$WITH_WL" == "true" ]]; then
  ufw allow 80/tcp   comment "CDN HTTP (WL)"  > /dev/null
  ufw allow 2083/tcp comment "xray WS (WL)"   > /dev/null
  ufw allow 2085/tcp comment "xray XHTTP (WL)" > /dev/null
  ok "WL порты 80, 2083, 2085 открыты"
fi

ufw --force enable > /dev/null
ok "UFW: SSH($SSH_PORT), remnanode($NODE_PORT), HTTPS(443), NodeExporter($NODE_EXPORTER_PORT)"

# =============================================================================
# 5. Docker + контейнеры
# =============================================================================
header "5/6 — Docker + контейнеры"

# Docker
if command -v docker &>/dev/null; then
  ok "Docker: $(docker --version | cut -d' ' -f3 | tr -d ',')"
else
  info "Устанавливаем Docker..."
  curl -fsSL https://get.docker.com | sh > /dev/null 2>&1
  systemctl enable --now docker > /dev/null
  ok "Docker установлен"
fi
systemctl is-active --quiet docker || systemctl start docker

# Git (нужен для клонирования репы)
command -v git &>/dev/null || apt-get install -y -qq git

# Remnanode
if docker ps --format '{{.Names}}' | grep -q "^remnanode$"; then
  ok "remnanode уже запущен"
else
  info "Запускаем remnanode..."
  docker rm -f remnanode > /dev/null 2>&1 || true

  printf 'NODE_PORT=%s\nSECRET_KEY=%s\n' "$NODE_PORT" "$SECRET_KEY" > /tmp/remnanode.env
  chmod 600 /tmp/remnanode.env

  docker run -d \
    --name remnanode \
    --hostname remnanode \
    --network host \
    --restart always \
    --cap-add NET_ADMIN \
    --ulimit nofile=1048576:1048576 \
    --env-file /tmp/remnanode.env \
    -v /var/log/remnanode:/var/log/remnanode \
    remnawave/node:latest > /dev/null

  rm -f /tmp/remnanode.env
  sleep 5

  if docker ps --format '{{.Names}}' | grep -q "^remnanode$"; then
    ok "remnanode запущен"
  else
    warn "remnanode не запустился — проверь: docker logs remnanode"
  fi
fi

# Сохраняем docker-compose для remnanode (для удобства управления)
mkdir -p /opt/remnanode
cat > /opt/remnanode/docker-compose.yml << EOF
services:
  remnanode:
    container_name: remnanode
    hostname: remnanode
    image: remnawave/node:latest
    network_mode: host
    restart: always
    cap_add:
      - NET_ADMIN
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
    environment:
      - NODE_PORT=${NODE_PORT}
      - SECRET_KEY=${SECRET_KEY}
    volumes:
      - '/var/log/remnanode:/var/log/remnanode'
EOF

# Node Exporter
if docker ps --format '{{.Names}}' | grep -q "^node-exporter$"; then
  ok "node-exporter уже запущен"
else
  docker rm -f node-exporter > /dev/null 2>&1 || true
  if docker run -d \
      --name node-exporter \
      --network host \
      --pid host \
      --restart always \
      -v /:/host:ro,rslave \
      prom/node-exporter:latest \
      --path.rootfs=/host \
      --web.listen-address=":$NODE_EXPORTER_PORT" > /dev/null 2>&1; then
    ok "node-exporter на порту $NODE_EXPORTER_PORT"
  else
    warn "node-exporter не запустился"
  fi
fi

# Logrotate (ежечасно через cron, size 100M)
command -v logrotate &>/dev/null || apt-get install -y -qq logrotate
cat > /etc/logrotate.d/remnanode << 'LOGROTATE'
/var/log/remnanode/*.log {
    size 100M
    rotate 5
    compress
    missingok
    notifempty
    copytruncate
}
LOGROTATE
cat > /etc/cron.d/remnanode-logrotate << 'CRON'
0 * * * * root /usr/sbin/logrotate -f /etc/logrotate.d/remnanode > /dev/null 2>&1
CRON

mkdir -p /opt/node-exporter
cat > /opt/node-exporter/docker-compose.yml << EOF
services:
  node-exporter:
    image: prom/node-exporter:latest
    container_name: node-exporter
    network_mode: host
    pid: host
    restart: always
    volumes:
      - '/:/host:ro,rslave'
    command:
      - '--path.rootfs=/host'
      - '--web.listen-address=:${NODE_EXPORTER_PORT}'
EOF

# =============================================================================
# 6. Клонирование репы + nginx (docker compose)
# =============================================================================
header "6/6 — Nginx + лендинг"

if [[ -d "$INSTALL_DIR/.git" ]]; then
  info "Обновляем репозиторий..."
  git -C "$INSTALL_DIR" pull --ff-only 2>/dev/null || true
  ok "Репозиторий обновлён"
else
  if [[ -d "$INSTALL_DIR" ]]; then
    # Папка есть но не git — бэкапим
    mv "$INSTALL_DIR" "${INSTALL_DIR}.bak.$(date +%s)"
    warn "Старая папка перемещена в ${INSTALL_DIR}.bak.*"
  fi
  info "Клонируем репозиторий..."
  git clone "$REPO_URL" "$INSTALL_DIR"
  ok "Репозиторий склонирован в $INSTALL_DIR"
fi

info "Собираем и запускаем nginx..."
cd "$INSTALL_DIR"
docker compose down 2>/dev/null || true
docker compose up -d --build

if docker compose ps --format '{{.Names}}' | grep -q nginx; then
  ok "nginx запущен"
else
  warn "nginx не запустился — проверь: cd $INSTALL_DIR && docker compose logs"
fi

# ─── Готово ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${GREEN}║            УСТАНОВКА ЗАВЕРШЕНА                   ║${NC}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${BOLD}Контейнеры:${NC}"
docker ps --format "  {{.Names}}\t{{.Status}}" \
  | grep -E "remnanode|node-exporter|nginx" || true
echo ""

echo -e "${BOLD}Prometheus (prometheus.yml):${NC}"
cat << EOF
  - job_name: 'node-${SERVER_IP}'
    static_configs:
      - targets: ['${SERVER_IP}:${NODE_EXPORTER_PORT}']
EOF
echo ""

echo -e "${BOLD}Порты:${NC}"
ufw status 2>/dev/null | grep "ALLOW" | awk '{print "  " $0}' || true
echo ""
