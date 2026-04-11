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
#   --with-wl            WL-схема под CDN:
#                          • UFW: открывает 80, 2083, 2085
#                          • docker-compose: публикует :443 наружу
#                          • nginx.conf: раскомментирует TLS в wl-блоках
#                          • ssl/wl-ws: генерирует self-signed серт на IP
#   --cf-token "xxx"     Cloudflare API token для выпуска wildcard cert
#                          *.vinnypuxtomoon.today через acme.sh + DNS-01.
#                          Опционально (для selfsteal/bridge нод).
#                          Альтернатива: env CF_Token=xxx bash setup-node.sh ...
#                          Без флага — placeholder cert (nginx стартует, но
#                          реальные клиенты на *.vinnypuxtomoon.today не пойдут).
#   --no-update          пропустить apt upgrade
#   --ssh-port 2222      если SSH на нестандартном порту
# =============================================================================

set -euo pipefail

# ─── Константы ────────────────────────────────────────────────────────────────
REPO_URL="https://github.com/viskrow/vinnypux-node.git"
SCRIPT_URL="https://raw.githubusercontent.com/viskrow/vinnypux-node/main/setup-node.sh"
INSTALL_DIR="/opt/vinnypux-node"
NODE_PORT="2222"
NODE_EXPORTER_PORT="9100"
STATE_DIR="/var/lib/node-setup"
STATE_FILE="$STATE_DIR/state.env"
LOG_FILE="$STATE_DIR/setup.log"
RESUME_SERVICE="node-setup-resume"
SCRIPT_PATH="/usr/local/sbin/node-setup.sh"

# ─── Логирование: дублируем весь вывод в $LOG_FILE ───────────────────────────
# Выполняется до проверки root — чтобы даже ошибка "не root" попала в файл.
[[ $EUID -eq 0 ]] && mkdir -p "$STATE_DIR" 2>/dev/null && {
  {
    echo ""
    echo "════════════════════════════════════════════════════════════"
    echo "  setup-node.sh запущен: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "  Аргументы: $*"
    echo "════════════════════════════════════════════════════════════"
  } >> "$LOG_FILE"
  exec > >(tee -a "$LOG_FILE") 2>&1
}

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

# ─── Resume: сохранение/восстановление параметров через ребут ─────────────────
save_state() {
  mkdir -p "$(dirname "$STATE_FILE")"
  cat > "$STATE_FILE" << EOF
SECRET_KEY=$(printf '%q' "$SECRET_KEY")
SSH_PORT=$(printf '%q' "$SSH_PORT")
SKIP_UPDATE=$(printf '%q' "$SKIP_UPDATE")
WITH_BRIDGES=$(printf '%q' "$WITH_BRIDGES")
WITH_WL=$(printf '%q' "$WITH_WL")
CF_Token=$(printf '%q' "$CF_Token")
EOF
  chmod 600 "$STATE_FILE"
}

install_resume_service() {
  # Сохраняем скрипт в $SCRIPT_PATH для systemd resume-сервиса.
  # При запуске через `bash <(curl ...)` локального файла нет (BASH_SOURCE=/dev/fd/63),
  # поэтому качаем свежую копию с GitHub. При обычном запуске копируем локальный файл.
  local src=""
  src=$(realpath "${BASH_SOURCE[0]}" 2>/dev/null || realpath "$0" 2>/dev/null || echo "")

  if [[ -n "$src" ]] && [[ -f "$src" ]] && [[ -s "$src" ]] \
     && [[ "$src" != /dev/fd/* ]] && [[ "$src" != /proc/*/fd/* ]]; then
    # Если скрипт уже запущен из $SCRIPT_PATH (resume после ребута) — cp не нужен
    if [[ "$src" != "$SCRIPT_PATH" ]] && ! [[ "$src" -ef "$SCRIPT_PATH" ]]; then
      cp "$src" "$SCRIPT_PATH"
    fi
  elif curl -fsSL "$SCRIPT_URL" -o "$SCRIPT_PATH" 2>/dev/null && [[ -s "$SCRIPT_PATH" ]]; then
    :  # успешно скачали
  else
    warn "Не удалось сохранить скрипт для resume-сервиса ($SCRIPT_PATH)."
    warn "После ребута запусти установку повторно вручную:"
    warn "  bash <(curl -fsSL $SCRIPT_URL) --with-wl"
    return 0
  fi

  chmod +x "$SCRIPT_PATH"
  cat > "/etc/systemd/system/${RESUME_SERVICE}.service" << EOF
[Unit]
Description=Node Setup — resume after reboot
After=network-online.target docker.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$SCRIPT_PATH
StandardOutput=journal+console
StandardError=journal+console

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable "${RESUME_SERVICE}.service" > /dev/null 2>&1
}

remove_resume_service() {
  systemctl disable "${RESUME_SERVICE}.service" > /dev/null 2>&1 || true
  rm -f "/etc/systemd/system/${RESUME_SERVICE}.service"
  rm -f "$STATE_FILE" "$SCRIPT_PATH"
  systemctl daemon-reload 2>/dev/null || true
}

do_reboot() {
  save_state
  install_resume_service
  echo ""
  warn "═══════════════════════════════════════════════════"
  warn "  $1"
  warn "  Скрипт автоматически продолжится после ребута."
  warn "═══════════════════════════════════════════════════"
  echo ""
  info "Логи установки:       $LOG_FILE"
  info "Логи после ребута:    journalctl -u $RESUME_SERVICE -f"
  info "Полный лог одним tail: tail -f $LOG_FILE"
  echo ""
  reboot
  exit 0
}

# ─── Детект BBR v3: модуль ИЛИ ядро >= 6.12 (upstream BBRv3) ──────────────────
detect_bbr3() {
  local mod_ver
  mod_ver=$(modinfo tcp_bbr 2>/dev/null | awk '/^version:/{print $2}')
  [[ "$mod_ver" == "3" ]] && return 0
  local kver_num
  kver_num=$(uname -r | awk -F'[.-]' '{printf "%d.%02d\n", $1, $2}')
  awk -v v="$kver_num" 'BEGIN { exit !(v >= 6.12) }'
}

# ─── Ждём освобождения apt-lock (unattended-upgrades, etc.) ──────────────────
wait_apt_lock() {
  local i=0
  while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 \
     || fuser /var/lib/dpkg/lock          >/dev/null 2>&1 \
     || fuser /var/lib/apt/lists/lock     >/dev/null 2>&1; do
    [[ $i -eq 0 ]] && info "Ждём освобождения apt-lock (другой apt процесс)..."
    sleep 2
    i=$((i+1))
    [[ $i -gt 60 ]] && die "apt-lock не освободился за 2 минуты"
  done
}

# ─── Активный polling: ждём пока контейнер реально стартует (вместо sleep) ───
wait_container_running() {
  local name=$1
  local max=${2:-10}
  local i=0
  while [[ $i -lt $max ]]; do
    if [[ "$(docker inspect -f '{{.State.Running}}' "$name" 2>/dev/null)" == "true" ]]; then
      return 0
    fi
    sleep 1
    i=$((i+1))
  done
  return 1
}

# ─── Wildcard cert через acme.sh + Cloudflare DNS-01 ────────────────────────
# Вызывается из ensure_vinnypuxtomoon_cert когда $CF_Token задан.
# Идемпотентно: если cert свежий — acme.sh ничего не делает.
issue_wildcard_acme() {
  local domain="vinnypuxtomoon.today"
  local cert_dir="$INSTALL_DIR/nginx/ssl/vinnypuxtomoon"
  local acme="/root/.acme.sh/acme.sh"

  info "Выпуск wildcard cert для *.$domain (acme.sh + Cloudflare DNS-01)..."

  # Установка acme.sh если ещё нет (вместе с daily cron на renewal)
  if [[ ! -x "$acme" ]]; then
    info "Устанавливаем acme.sh..."
    curl -fsSL https://get.acme.sh | sh -s email="admin@$domain" > /dev/null 2>&1 \
      || die "Не удалось установить acme.sh"
  fi

  # Default CA → Let's Encrypt
  "$acme" --set-default-ca --server letsencrypt > /dev/null 2>&1 || true

  # Issue (использует Cloudflare DNS-01 plugin dns_cf через CF_Token env)
  if CF_Token="$CF_Token" "$acme" --issue --dns dns_cf \
       -d "$domain" -d "*.$domain" --keylength 2048 \
       > /tmp/acme-issue.log 2>&1; then
    ok "Cert выпущен через Let's Encrypt"
  elif grep -q -E 'Domains not changed|Skip, Next renewal' /tmp/acme-issue.log; then
    ok "Cert уже валиден — обновление не требуется"
  else
    warn "acme.sh issue провалился:"
    tail -20 /tmp/acme-issue.log
    rm -f /tmp/acme-issue.log
    die "Не удалось выпустить cert через DNS-01 (проверь --cf-token)"
  fi
  rm -f /tmp/acme-issue.log

  # Деплой в nginx ssl + регистрация reload-hook для будущих автообновлений
  mkdir -p "$cert_dir"
  "$acme" --install-cert -d "$domain" \
    --key-file       "$cert_dir/key.pem" \
    --fullchain-file "$cert_dir/cert.pem" \
    --reloadcmd      "docker exec \$(docker ps -qf name=nginx | head -1) nginx -s reload 2>/dev/null || true" \
    > /dev/null 2>&1
  chmod 600 "$cert_dir/key.pem"

  ok "Cert установлен в $cert_dir"
  ok "Renewal: acme.sh cron проверяет ежедневно, обновляет за 30 дней до expiry"
}

# ─── Гарантирует наличие vinnypuxtomoon cert (нужен http-уровню nginx.conf) ──
# 3 пути:
#   1. CF_Token задан → реальный wildcard через acme.sh
#   2. Cert уже есть на ноде → не трогаем
#   3. Ничего нет → placeholder (nginx стартует, real клиенты не пойдут)
ensure_vinnypuxtomoon_cert() {
  local cert_dir="$INSTALL_DIR/nginx/ssl/vinnypuxtomoon"
  mkdir -p "$cert_dir"

  if [[ -n "$CF_Token" ]]; then
    issue_wildcard_acme
    return 0
  fi

  if [[ -s "$cert_dir/cert.pem" ]] && [[ -s "$cert_dir/key.pem" ]]; then
    ok "vinnypuxtomoon cert уже на месте — не трогаем"
    return 0
  fi

  warn "vinnypuxtomoon cert отсутствует и --cf-token не передан → ставим placeholder"
  warn "  для реального cert: запусти повторно с --cf-token \"\$CF_Token\""
  openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$cert_dir/key.pem" \
    -out    "$cert_dir/cert.pem" \
    -subj   "/CN=placeholder" \
    -addext "subjectAltName=DNS:vinnypuxtomoon.today,DNS:*.vinnypuxtomoon.today" > /dev/null 2>&1
  chmod 600 "$cert_dir/key.pem"
  ok "Placeholder cert сгенерирован"
}

# ─── WL-патчер: публикация :443 + раскомментирование TLS в wl-блоках ─────────
# Вызывается в фазе 5 ПОСЛЕ git pull (который откатывает локальные правки).
# Все операции идемпотентны — безопасно запускать повторно.
apply_wl_patches() {
  info "Применяем WL-патчи к docker-compose.yml и nginx.conf..."

  # 1. Публикация порта 443 наружу (для TLS от CDN)
  if ! grep -q '0.0.0.0:443:443' docker-compose.yml; then
    sed -i '/- "80:80"/a\      - "0.0.0.0:443:443"        # TLS: WL-ноды через CDN' \
      docker-compose.yml
    ok "docker-compose.yml: добавлен публичный :443"
  else
    ok "docker-compose.yml: :443 уже опубликован"
  fi

  # 2. Раскомментирование TLS во всех wl-блоках nginx (uno/wl1/wl2/cdn-2/...)
  sed -i -E 's|^(\s+)# (listen 443 ssl;)|\1\2|' nginx/nginx.conf
  sed -i -E 's|^(\s+)# (ssl_certificate\s+/etc/nginx/ssl/wl-ws/cert\.pem;)|\1\2|' nginx/nginx.conf
  sed -i -E 's|^(\s+)# (ssl_certificate_key /etc/nginx/ssl/wl-ws/key\.pem;)|\1\2|' nginx/nginx.conf
  ok "nginx.conf: TLS раскомментирован в WL-блоках"

  # 3. Self-signed серт для wl-ws (привязан к IP — генерируется per-node)
  mkdir -p nginx/ssl/wl-ws
  if [[ ! -s nginx/ssl/wl-ws/cert.pem ]] || [[ ! -s nginx/ssl/wl-ws/key.pem ]]; then
    info "Генерируем self-signed серт wl-ws для IP $SERVER_IP..."
    openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
      -keyout nginx/ssl/wl-ws/key.pem \
      -out    nginx/ssl/wl-ws/cert.pem \
      -subj   "/CN=$SERVER_IP" \
      -addext "subjectAltName=IP:$SERVER_IP" > /dev/null 2>&1
    chmod 600 nginx/ssl/wl-ws/key.pem
    ok "wl-ws серт сгенерирован (CN=$SERVER_IP)"
  else
    ok "wl-ws серт уже существует — пропускаем генерацию"
  fi
  # vinnypuxtomoon cert обрабатывается отдельной функцией ensure_vinnypuxtomoon_cert
}

# ─── Параметры ────────────────────────────────────────────────────────────────
SECRET_KEY=""
SSH_PORT="22"
SKIP_UPDATE="false"
WITH_BRIDGES="false"
WITH_WL="false"
CF_Token="${CF_Token:-}"  # Cloudflare API token для acme.sh DNS-01 (опционально)
PULL_PIDS=()  # фоновые docker pull (используется в фазе 4 и ожидается в фазе 5)

# Загружаем сохранённое состояние (resume после ребута)
if [[ -f "$STATE_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$STATE_FILE"
  info "Продолжаем после ребута..."
fi

while [[ $# -gt 0 ]]; do
  case $1 in
    --secret-key)     SECRET_KEY="$2";    shift 2 ;;
    --ssh-port)       SSH_PORT="$2";      shift 2 ;;
    --no-update)      SKIP_UPDATE="true"; shift ;;
    --with-bridges)   WITH_BRIDGES="true"; shift ;;
    --with-wl)        WITH_WL="true";     shift ;;
    --cf-token)       CF_Token="$2";      shift 2 ;;
    *) die "Неизвестный аргумент: $1" ;;
  esac
done

# Интерактивный ввод SECRET_KEY если не передан и нет state-файла
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
# 1. Пакеты + обновление системы + ядро (один ребут максимум)
# =============================================================================
header "1/5 — Пакеты + обновление + ядро"

NEED_REBOOT=false

# ── 1.1. Базовые пакеты одним вызовом ────────────────────────────────────────
wait_apt_lock
info "Устанавливаем базовые пакеты..."
apt-get update -qq > /dev/null 2>&1
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
  gnupg wget curl ca-certificates \
  ufw logrotate git openssl > /dev/null 2>&1
ok "Базовые пакеты установлены"

# ── 1.2. apt upgrade ─────────────────────────────────────────────────────────
if [[ "$SKIP_UPDATE" == "true" ]]; then
  warn "apt upgrade пропущен (--no-update)"
else
  wait_apt_lock
  info "apt upgrade..."
  DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" > /dev/null 2>&1
  ok "Система обновлена"
fi
[[ -f /var/run/reboot-required ]] && NEED_REBOOT=true

# ── 1.3. XanMod (если BBR3 ещё не доступен) ──────────────────────────────────
if detect_bbr3; then
  ok "BBR3 уже доступен (ядро: $(uname -r)) — XanMod не нужен"
else
  info "BBR3 недоступен (ядро: $(uname -r)) — ставим XanMod..."

  # CPU level
  if grep -q "avx512" /proc/cpuinfo; then CPU_LEVEL="x64v4"
  elif grep -q "avx2" /proc/cpuinfo; then CPU_LEVEL="x64v3"
  elif grep -q "sse4_2" /proc/cpuinfo; then CPU_LEVEL="x64v2"
  else CPU_LEVEL="x64v1"; fi
  info "CPU: $CPU_LEVEL"

  # GPG ключ XanMod (официальный метод: gitlab.com/afrd.gpg)
  wget -qO - https://gitlab.com/afrd.gpg | gpg --yes --dearmor \
    -o /usr/share/keyrings/xanmod-archive-keyring.gpg 2>/dev/null
  echo 'deb [signed-by=/usr/share/keyrings/xanmod-archive-keyring.gpg] http://deb.xanmod.org releases main' \
    > /etc/apt/sources.list.d/xanmod-release.list
  wait_apt_lock
  apt-get update -qq > /dev/null 2>&1

  # Подбираем пакет под CPU-уровень с фолбэком вниз
  XANMOD_PKG=""
  for lvl in "$CPU_LEVEL" x64v3 x64v2 x64v1; do
    XANMOD_PKG=$(apt-cache search "linux-image.*${lvl}.*xanmod" 2>/dev/null \
      | grep -v "\-rt\-" | sort -V | tail -1 | awk '{print $1}')
    [[ -n "$XANMOD_PKG" ]] && { info "Пакет: $XANMOD_PKG ($lvl)"; break; }
  done
  [[ -z "$XANMOD_PKG" ]] && die "Не найден пакет XanMod"

  wait_apt_lock
  apt-get install -y "$XANMOD_PKG" > /dev/null 2>&1 \
    || die "Установка XanMod провалилась — см. apt лог"
  ok "$XANMOD_PKG установлен"
  NEED_REBOOT=true

  # GRUB по умолчанию: 0 — самое верхнее в списке.
  # XanMod (6.19+) обычно > stock (6.8.x) по dpkg-version, поэтому окажется первым.
  # На всякий случай форсим update-grub.
  update-grub > /dev/null 2>&1 || true
fi

# ── 1.4. Один ребут (если apt upgrade обновил ядро ИЛИ установлен XanMod) ────
if [[ "$NEED_REBOOT" == "true" ]]; then
  do_reboot "Нужен ребут для активации нового ядра."
fi

# Если мы здесь — ребут не нужен (BBR3 уже был, ядро не обновлялось).
# Resume-сервис мог остаться от предыдущей попытки — чистим.
remove_resume_service

# =============================================================================
# 2. Сетевая оптимизация (BBR3 + sysctl + ulimits)
# =============================================================================
header "2/5 — Сетевая оптимизация"

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

# ulimits — system-wide nofile=1048576 (для всех кроме docker, у docker свой --ulimit)
cat > /etc/security/limits.d/99-vpn-nofile.conf << 'EOF'
*    soft nofile 1048576
*    hard nofile 1048576
root soft nofile 1048576
root hard nofile 1048576
EOF
for cfg in /etc/systemd/system.conf /etc/systemd/user.conf; do
  if grep -q '^DefaultLimitNOFILE=' "$cfg"; then
    sed -i 's/^DefaultLimitNOFILE=.*/DefaultLimitNOFILE=1048576/' "$cfg"
  else
    echo 'DefaultLimitNOFILE=1048576' >> "$cfg"
  fi
done
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
# 3. Firewall (UFW)
# =============================================================================
header "3/5 — Firewall"

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
# 4. Docker + контейнеры
# =============================================================================
header "4/5 — Docker + контейнеры"

# Docker
if command -v docker &>/dev/null; then
  ok "Docker: $(docker --version | cut -d' ' -f3 | tr -d ',')"
else
  info "Устанавливаем Docker..."
  curl -fsSL https://get.docker.com 2>/dev/null | sh > /dev/null 2>&1
  systemctl enable --now docker > /dev/null
  ok "Docker установлен"
fi
systemctl is-active --quiet docker || systemctl start docker

# Параллельный pull всех образов в фоне (~15-25с экономии)
info "Качаем docker-образы в фоне..."
PULL_PIDS=()
for img in remnawave/node:latest prom/node-exporter:latest nginx:alpine node:20-alpine; do
  ( docker pull "$img" > /dev/null 2>&1 || warn "pull $img failed" ) &
  PULL_PIDS+=($!)
done

# Remnanode
if docker ps --format '{{.Names}}' | grep -q "^remnanode$"; then
  ok "remnanode уже запущен"
else
  # Ждём только pull remnanode (первый PID), остальные продолжают качаться в фоне
  wait "${PULL_PIDS[0]}" 2>/dev/null || true

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

  if wait_container_running remnanode 10; then
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

# Logrotate (раз в сутки штатным cron.daily; size 100M триггерит ротацию раньше)
cat > /etc/logrotate.d/remnanode << 'LOGROTATE'
/var/log/remnanode/*.log {
    daily
    size 100M
    rotate 5
    compress
    missingok
    notifempty
    copytruncate
}
LOGROTATE
# /etc/cron.daily/logrotate уже идёт в пакете logrotate — отдельный cron не нужен
rm -f /etc/cron.d/remnanode-logrotate 2>/dev/null || true

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
# 5. Клонирование репы + nginx (docker compose)
# =============================================================================
header "5/5 — Nginx + лендинг"

if [[ -d "$INSTALL_DIR/.git" ]]; then
  info "Обновляем репозиторий..."
  # Откатываем локальные правки (патчи от прошлого --with-wl) перед pull
  git -C "$INSTALL_DIR" checkout -- docker-compose.yml nginx/nginx.conf 2>/dev/null || true
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

cd "$INSTALL_DIR"

# 1. Гарантируем наличие vinnypuxtomoon cert (реальный wildcard или placeholder)
ensure_vinnypuxtomoon_cert

# 2. Применяем WL-патчи (если --with-wl) ПОСЛЕ cert и ДО сборки контейнера
if [[ "$WITH_WL" == "true" ]]; then
  apply_wl_patches
fi

# Дожидаемся всех фоновых docker pull (если ещё не закончились)
if [[ ${#PULL_PIDS[@]} -gt 0 ]]; then
  wait "${PULL_PIDS[@]}" 2>/dev/null || true
fi

info "Собираем и запускаем nginx..."
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

echo -e "${BOLD}Логи установки:${NC} $LOG_FILE"
echo ""
