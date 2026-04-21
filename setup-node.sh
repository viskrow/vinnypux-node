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
INSTALL_DIR="/opt/potato"
NODE_PORT="2222"
NODE_EXPORTER_PORT="9100"
STATE_DIR="/var/lib/sysboot"
STATE_FILE="$STATE_DIR/state.env"
LOG_FILE="$STATE_DIR/setup.log"
RESUME_SERVICE="sysboot-resume"
SCRIPT_PATH="/usr/local/sbin/sysboot.sh"

# ─── Логирование: дублируем весь вывод в $LOG_FILE ───────────────────────────
# Выполняется до проверки root — чтобы даже ошибка "не root" попала в файл.
# Секретные аргументы (--secret-key / --cf-token) маскируются: в лог идут только
# флаги без значений. Значения остаются в памяти процесса.
[[ $EUID -eq 0 ]] && mkdir -p "$STATE_DIR" 2>/dev/null && {
  _masked_args=""
  _skip_next=0
  for _arg in "$@"; do
    if [[ $_skip_next -eq 1 ]]; then _masked_args+=" ***"; _skip_next=0; continue; fi
    case "$_arg" in
      --secret-key|--cf-token) _masked_args+=" $_arg"; _skip_next=1 ;;
      *) _masked_args+=" $_arg" ;;
    esac
  done
  {
    echo ""
    echo "════════════════════════════════════════════════════════════"
    echo "  Setup запущен: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "  Args:$_masked_args"
    echo "════════════════════════════════════════════════════════════"
  } >> "$LOG_FILE"
  unset _masked_args _skip_next _arg
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
    warn "  bash <(curl -fsSL $SCRIPT_URL) --with-bridges"
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
    --reloadcmd      "docker exec \$(docker ps -qf name=wombat | head -1) nginx -s reload 2>/dev/null || true; docker restart potato >/dev/null 2>&1 || true" \
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

# ─── Параметры ────────────────────────────────────────────────────────────────
SECRET_KEY=""
SSH_PORT="22"
SKIP_UPDATE="false"
WITH_BRIDGES="false"
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
ufw allow "$SSH_PORT"/tcp   comment "SSH"        > /dev/null
ufw allow "$NODE_PORT"/tcp  comment "mgmt"       > /dev/null
ufw allow 443/tcp           comment "HTTPS"      > /dev/null
ufw allow 8443/tcp          comment "HTTPS-alt"  > /dev/null
ufw allow "$NODE_EXPORTER_PORT"/tcp comment "metrics" > /dev/null

if [[ "$WITH_BRIDGES" == "true" ]]; then
  ufw allow 7443:7447/tcp comment "relay" > /dev/null
  ok "relay ports 7443-7447 открыты"
fi

ufw --force enable > /dev/null
ok "UFW: SSH($SSH_PORT), mgmt($NODE_PORT), 443, 8443, metrics($NODE_EXPORTER_PORT)"

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

# ── Глобальный лимит JSON-логов для всех контейнеров ─────────────────────────
# Страхует от разрастания /var/lib/docker/containers/*/*-json.log
# (logrotate их не ротирует — Docker daemon держит fd).
# Идемпотентно: создаём только если daemon.json отсутствует.
if [[ ! -f /etc/docker/daemon.json ]]; then
  info "Настраиваем лимит Docker JSON-логов (50m × 5 на контейнер)..."
  cat > /etc/docker/daemon.json << 'DOCKERCFG'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "50m",
    "max-file": "5"
  }
}
DOCKERCFG
  systemctl restart docker > /dev/null 2>&1 || warn "docker restart failed"
  ok "Docker log-opts установлены (max 250MB на контейнер)"
fi

# ── Параллельный pre-pull nginx-related образов (для фазы 5) ─────────────────
info "Качаем docker-образы в фоне..."
PULL_PIDS=()
( docker pull nginx:alpine    > /dev/null 2>&1 || warn "pull nginx failed" )    &
PULL_PIDS+=($!)
( docker pull node:20-alpine  > /dev/null 2>&1 || warn "pull node failed" )     &
PULL_PIDS+=($!)

# ── potato (обфусцированный xray, собранный через custom Dockerfile) ─────────
#
# Вместо docker pull + docker run строим свой образ через docker compose build:
#   Dockerfile: FROM remnawave/node:latest → переименование xray бинаря в webd
#               + патч supervisord.conf, xray.service.js, entrypoint.sh
#   → ps aux покажет "webd" вместо "rw-core"
#   → ls /usr/local/bin/ внутри контейнера не содержит "xray" / "rw-core"
#   → docker images не содержит remnawave/node (после rmi upstream)
#
# Обновление: cd /opt/potato-core && docker compose build --pull && docker compose up -d
mkdir -p /opt/potato-core /var/log/potato
mkdir -p "$INSTALL_DIR/nginx/ssl/vinnypuxtomoon"

cat > /opt/potato-core/Dockerfile << 'POTATO_DOCKERFILE'
FROM remnawave/node:latest
USER root
# Переименовать реальный xray binary + удалить симлинк-псевдоним.
# Пропатчить supervisord, nestjs-код и entrypoint чтобы ссылались на новый путь.
# Используем простые sed-паттерны (без alternation) — совместимость с busybox sed.
RUN mv /usr/local/bin/xray /usr/local/bin/webd && \
    rm -f /usr/local/bin/rw-core && \
    sed -i 's|/usr/local/bin/rw-core|/usr/local/bin/webd|g' /etc/supervisord.conf && \
    sed -i 's|\[program:xray\]|[program:webd]|g' /etc/supervisord.conf && \
    sed -i 's|xray\.err\.log|webd.err.log|g' /etc/supervisord.conf && \
    sed -i 's|xray\.out\.log|webd.out.log|g' /etc/supervisord.conf && \
    sed -i "s|'/usr/local/bin/xray'|'/usr/local/bin/webd'|g" \
        /opt/app/dist/src/modules/xray-core/xray.service.js && \
    sed -i 's|/usr/local/bin/rw-core|/usr/local/bin/webd|g' /usr/local/bin/docker-entrypoint.sh && \
    sed -i 's|/usr/local/bin/xray|/usr/local/bin/webd|g' /usr/local/bin/docker-entrypoint.sh
POTATO_DOCKERFILE

cat > /opt/potato-core/docker-compose.yml << EOF
services:
  potato:
    build:
      context: .
      dockerfile: Dockerfile
    image: local/potato:v1
    container_name: potato
    hostname: potato
    network_mode: host
    restart: always
    cap_add:
      - NET_ADMIN
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
    env_file:
      - .env
    volumes:
      - '/var/log/potato:/var/log/app'
      - '${INSTALL_DIR}/nginx/ssl/vinnypuxtomoon:/etc/ssl/app:ro'
    logging:
      driver: json-file
      options:
        max-size: "50m"
        max-file: "5"
EOF

printf 'NODE_PORT=%s\nSECRET_KEY=%s\n' "$NODE_PORT" "$SECRET_KEY" > /opt/potato-core/.env
chmod 600 /opt/potato-core/.env

if docker ps --format '{{.Names}}' | grep -q "^potato$"; then
  ok "potato уже запущен"
else
  info "Собираем обфусцированный образ potato (~30s)..."
  docker rm -f potato > /dev/null 2>&1 || true
  ( cd /opt/potato-core && docker compose up -d --build > /dev/null 2>&1 )
  # Убираем upstream-тег чтобы docker images не показывал remnawave/node
  docker rmi remnawave/node:latest > /dev/null 2>&1 || true
  if wait_container_running potato 15; then
    ok "potato запущен (obfuscated build)"
  else
    warn "potato не запустился — проверь: docker logs potato"
  fi
fi

# ── beeper (metrics, простой retag без патчей) ───────────────────────────────
mkdir -p /opt/potato-metrics

if ! docker images --format '{{.Repository}}:{{.Tag}}' | grep -q "^local/beeper:v1$"; then
  info "Загружаем beeper..."
  docker pull prom/node-exporter:latest > /dev/null 2>&1 || warn "pull beeper failed"
  docker tag prom/node-exporter:latest local/beeper:v1 > /dev/null 2>&1
  docker rmi prom/node-exporter:latest > /dev/null 2>&1 || true
fi

# Logrotate (раз в сутки штатным cron.daily; size 100M триггерит ротацию раньше)
cat > /etc/logrotate.d/potato << 'LOGROTATE'
/var/log/potato/*.log {
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
rm -f /etc/cron.d/remnanode-logrotate /etc/cron.d/potato-logrotate 2>/dev/null || true

cat > /opt/potato-metrics/docker-compose.yml << EOF
services:
  beeper:
    image: local/beeper:v1
    container_name: beeper
    network_mode: host
    pid: host
    restart: always
    volumes:
      - '/:/host:ro,rslave'
    command:
      - '--path.rootfs=/host'
      - '--web.listen-address=:${NODE_EXPORTER_PORT}'
    logging:
      driver: json-file
      options:
        max-size: "50m"
        max-file: "5"
EOF

if docker ps --format '{{.Names}}' | grep -q "^beeper$"; then
  ok "beeper уже запущен"
else
  docker rm -f beeper > /dev/null 2>&1 || true
  ( cd /opt/potato-metrics && docker compose up -d > /dev/null 2>&1 )
  if docker ps --format '{{.Names}}' | grep -q "^beeper$"; then
    ok "beeper на порту $NODE_EXPORTER_PORT"
  else
    warn "beeper не запустился"
  fi
fi

# ── Helper-скрипт для обновления образов ──────────────────────────────────────
# Использование: /opt/potato-core/update.sh
cat > /opt/potato-core/update.sh << 'UPDATE_SH'
#!/bin/bash
# Обновление potato (xray) и beeper (metrics) до свежих upstream-версий.
# Сохраняет обфускацию (rebuild через наш Dockerfile, retag, rmi upstream).
set -e
GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓${NC} $*"; }
info() { echo -e "${CYAN}→${NC} $*"; }

info "Обновляем potato (xray)..."
cd /opt/potato-core
docker compose build --pull
docker rmi remnawave/node:latest 2>/dev/null || true
docker compose up -d
ok "potato обновлён"

info "Обновляем beeper (metrics)..."
docker pull prom/node-exporter:latest > /dev/null
docker tag prom/node-exporter:latest local/beeper:v1
docker rmi prom/node-exporter:latest 2>/dev/null || true
cd /opt/potato-metrics
docker compose up -d --force-recreate
ok "beeper обновлён"

echo ""
ok "Готово. Логи potato:"
docker logs --tail 30 potato
UPDATE_SH
chmod +x /opt/potato-core/update.sh

# =============================================================================
# 5. Клонирование репы + nginx (docker compose)
# =============================================================================
header "5/5 — Nginx + лендинг"

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

cd "$INSTALL_DIR"

# Гарантируем наличие vinnypuxtomoon cert (реальный wildcard или placeholder)
ensure_vinnypuxtomoon_cert

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
  | grep -E "potato|beeper|wombat" || true
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

# ─── Финальная очистка (обфускация следов установки) ─────────────────────────
# Удаляем всё что намекает на setup-процесс и оригинальные имена проекта.
# Безопасно: systemd продолжит работать с контейнерами через docker restart=always.
{
  # Resume-скрипт (использовался для продолжения после reboot — больше не нужен)
  rm -f "$SCRIPT_PATH"

  # Systemd resume service (отключаем и удаляем unit)
  systemctl disable "${RESUME_SERVICE}.service" > /dev/null 2>&1 || true
  rm -f "/etc/systemd/system/${RESUME_SERVICE}.service"
  systemctl daemon-reload > /dev/null 2>&1 || true

  # Legacy-артефакты от старых установок (если обновлялись со старых версий)
  rm -f /etc/systemd/system/node-setup-resume.service 2>/dev/null
  rm -f /usr/local/sbin/node-setup.sh 2>/dev/null
  rm -rf /var/lib/node-setup 2>/dev/null
  rm -rf /opt/vinnypux-node 2>/dev/null
  rm -rf /opt/remnanode /opt/node-exporter 2>/dev/null
  rm -rf /var/log/remnanode 2>/dev/null

  # Временный setup-скрипт если юзер запускал через "curl -o /tmp/..."
  rm -f /tmp/setup-node.sh /tmp/potato-setup.sh 2>/dev/null

  # State-файл содержит SECRET_KEY — после успешной установки не нужен
  rm -f "$STATE_FILE" 2>/dev/null

  # Обрезаем setup.log до последних 100 строк (достаточно для последующего дебага)
  if [[ -f "$LOG_FILE" ]]; then
    tail -100 "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
  fi

  # Bash history текущей сессии (curl с SECRET_KEY / CF_Token засветился)
  history -c 2>/dev/null || true
  : > "${HOME}/.bash_history" 2>/dev/null || true
  export HISTFILE=/dev/null
} > /dev/null 2>&1 || true
