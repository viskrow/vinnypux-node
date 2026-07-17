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
#   --ssh-port 22        SSH сервер хоста (только для UFW allow), дефолт 22
#   --node-port 3318     Remnawave node-agent listen port (обфускация),
#                          дефолт 3318. В Remnawave panel entry укажи такой же.
#   --f2b-ignoreip "..." admin/dev IP|CIDR для fail2ban ignoreip (space-separated).
#                          НЕ хардкодить в репо — передавать аргументом. Без него
#                          в ignoreip только localhost (риск забанить админа).
#                          Env F2B_IGNOREIP=... тоже работает.
# =============================================================================

set -euo pipefail

# ─── Self-detach в system.slice ───────────────────────────────────────────────
# При запуске через `nohup ... &` / `bash -c ... &` через SSH процесс умирает
# посередине: parent SSH-session закрывается → systemd-logind делает cleanup
# user@.service slice через UserStopDelaySec → kill всех процессов в slice
# (включая nohup'нутые). Setsid отвязывает только tty, не slice. Решение:
# `systemd-run --scope --slice=system.slice` — процесс выходит из user@ slice
# в system.slice, переживает logout/SSH-disconnect/unattended-upgrades cascade.
# VINNYPUX_DETACHED=1 защищает от рекурсии. Fallback на setsid --fork если
# systemd-run недоступен (не-systemd система).
# INVOCATION_ID set by systemd для unit-launched processes → skip detach
# (мы уже в нужной slice, повторный exec systemd-run только сломает parent unit accounting)
if [ "${VINNYPUX_DETACHED:-0}" != "1" ] && [ ! -t 0 ] && [ -z "${INVOCATION_ID:-}" ]; then
  if command -v systemd-run >/dev/null 2>&1; then
    export VINNYPUX_DETACHED=1
    exec systemd-run --scope --slice=system.slice --quiet \
      --setenv=VINNYPUX_DETACHED=1 --setenv=HOME="${HOME:-/root}" \
      --setenv=CF_Token="${CF_Token:-}" \
      "$0" "$@" < /dev/null
  elif command -v setsid >/dev/null 2>&1; then
    export VINNYPUX_DETACHED=1
    # --fork: гарантированный fork перед setsid, даже если parent уже pgrp leader
    exec setsid --fork "$0" "$@" < /dev/null
  fi
fi

# HOME может быть не задан (systemd-context) или задан в /. Acme.sh ставит
# бинарь в $HOME/.acme.sh — если HOME не /root, наш check "-x /root/.acme.sh/acme.sh"
# проваливается даже после успешной установки.
export HOME="${HOME:-/root}"
[[ "$HOME" == "/" ]] && export HOME="/root"

# ─── Константы ────────────────────────────────────────────────────────────────
REPO_URL="https://github.com/viskrow/vinnypux-node.git"
SCRIPT_URL="https://raw.githubusercontent.com/viskrow/vinnypux-node/main/setup-node.sh"
INSTALL_DIR="/opt/potato"
NODE_PORT="3318"  # дефолт обфусцированный; override через --node-port
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
F2B_IGNOREIP=$(printf '%q' "$F2B_IGNOREIP")
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
# Phase 5 (acme.sh DNS-01 + npm build wombat) обычно занимает 2-5 мин.
# Без явного timeout systemd дефолтит на 90с (DefaultTimeoutStartSec) и убивает
# середину сборки образов. infinity корректно парсится для Type=oneshot
# (systemd 255, проверено 2026-07-17: TimeoutStartUSec=infinity). Раньше стояло
# =0 — семантически тоже infinity, но нода 78.159.245.126 всё равно отработала
# по 90с-дефолту → используем явный infinity. TimeoutSec страхует start+stop.
TimeoutStartSec=infinity
TimeoutSec=infinity
Environment=HOME=/root
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
  # Уже есть BBRv3? XanMod-ядро или upstream kernel >= 6.12.
  uname -r | grep -qi xanmod && return 0
  local kv; kv=$(uname -r); kv=${kv%%-*}
  [[ "$(printf '%s\n6.12\n' "$kv" | sort -V | head -1)" == "6.12" ]] && return 0
  # BBRv3 нет → нужен XanMod. Но если deb.xanmod.org недостижим (напр. rfx-1 из AS25490) —
  # принимаем stock BBR1, чтобы установка не падала (curl без -f: 404 на / = достижим).
  if ! curl -sS --max-time 8 -o /dev/null http://deb.xanmod.org/ 2>/dev/null; then
    warn "deb.xanmod.org недостижим — XanMod пропущен, остаёмся на stock BBR1"
    return 0
  fi
  return 1
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

# ─── Pre-flight: блокируем apt-auxiliary сервисы + чистим broken 3rd-party repos
# Auto-services (unattended-upgrades, esm-cache, packagekit, apt-news) хватают
# apt-lock параллельно нашему install → race → exit 100. Maskим их.
# Broken 3rd-party repos (ookla speedtest-cli bintray/packagecloud noble) дают
# `apt-get update` exit 100 даже если main Ubuntu repos OK. Удаляем такие.
apt_preflight() {
  local svc
  for svc in unattended-upgrades.service esm-cache.service apt-news.service \
             packagekit.service apt-daily.service apt-daily-upgrade.service \
             apt-daily.timer apt-daily-upgrade.timer \
             ua-timer.service ua-reboot-cmds.service; do
    systemctl stop "$svc" 2>/dev/null || true
    systemctl mask "$svc" 2>/dev/null || true
  done
  rm -f /etc/apt/sources.list.d/ookla_speedtest-cli.list \
        /etc/apt/sources.list.d/speedtest.list \
        /etc/apt/sources.list.d/*bintray*.list \
        /etc/apt/sources.list.d/*bintray*.sources 2>/dev/null || true
  # стрип битого xanmod flat-suite репо (старые ноды: "deb ... releases main" → apt update 404).
  # xanmod-блок ниже re-создаёт codename-suite если ядро нужно.
  if grep -qsE "deb\.xanmod\.org +releases +main" /etc/apt/sources.list.d/xanmod-release.list 2>/dev/null; then
    rm -f /etc/apt/sources.list.d/xanmod-release.list
  fi
}

# ─── Безопасный apt-вызов: lock-timeout, log в файл, tail на failure ─────────
# Заменяет `apt-get ... > /dev/null 2>&1` который скрывал ВСЕ ошибки и приводил
# к silent-death под `set -e`. Теперь при failure видим last 20 строк apt-output.
apt_safe() {
  local desc="$1"; shift
  local log
  log=$(mktemp /tmp/apt-XXXXXX.log)
  if "$@" -o DPkg::Lock::Timeout=300 > "$log" 2>&1; then
    rm -f "$log"
    return 0
  fi
  warn "apt-get $desc упал, последние строки:"
  tail -20 "$log" >&2
  rm -f "$log"
  die "apt-get $desc failed"
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

  # Установка acme.sh если ещё нет.
  # curl|sh installer может "успешно" вернуть exit 0 даже когда git clone провалился
  # (тихий баг). Поэтому проверяем РЕЗУЛЬТАТ — существование бинаря — и retry.
  if [[ ! -x "$acme" ]]; then
    info "Устанавливаем acme.sh..."
    local attempt
    for attempt in 1 2 3; do
      rm -rf /root/.acme.sh
      curl -fsSL https://get.acme.sh | sh -s email="admin@$domain" >/tmp/acme-install.log 2>&1 || true
      [[ -x "$acme" ]] && break
      warn "acme.sh install попытка $attempt провалилась, retry..."
      sleep 3
    done
    if [[ ! -x "$acme" ]]; then
      warn "Последний лог установки acme.sh:"
      tail -30 /tmp/acme-install.log 2>/dev/null
      rm -f /tmp/acme-install.log
      die "Не удалось установить acme.sh после 3 попыток"
    fi
    rm -f /tmp/acme-install.log
    ok "acme.sh установлен"
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
    warn "acme.sh issue провалился (LE rate-limit 5/неделю? --cf-token?):"
    tail -20 /tmp/acme-issue.log
    rm -f /tmp/acme-issue.log
    # НЕ валим setup: оставляем существующий cert если есть, иначе placeholder.
    # Реальный fix при LE-лимите — скопировать wildcard с живой ноды в $cert_dir до запуска.
    if [[ -s "$cert_dir/cert.pem" ]] && [[ -s "$cert_dir/key.pem" ]]; then
      warn "оставляю существующий cert в $cert_dir"
    else
      warn "генерю placeholder cert (nginx стартует; замени реальным wildcard позже)"
      openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
        -keyout "$cert_dir/key.pem" -out "$cert_dir/cert.pem" \
        -subj "/CN=placeholder" \
        -addext "subjectAltName=DNS:vinnypuxtomoon.today,DNS:*.vinnypuxtomoon.today" > /dev/null 2>&1
      chmod 600 "$cert_dir/key.pem"
    fi
    return 0
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

  # 1. cert уже есть (напр. скопирован с другой ноды) → не трогаем.
  # ПРИОРИТЕТ выше acme: обходит LE rate-limit (5 dup-сертов/неделю) при серии деплоев —
  # копируешь wildcard с живой ноды в $cert_dir и acme скипается.
  if [[ -s "$cert_dir/cert.pem" ]] && [[ -s "$cert_dir/key.pem" ]]; then
    ok "vinnypuxtomoon cert уже на месте — не трогаем (acme скип)"
    return 0
  fi

  # 2. CF_Token задан → реальный wildcard через acme.sh (non-fatal: при fail → placeholder)
  if [[ -n "$CF_Token" ]]; then
    issue_wildcard_acme
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
F2B_IGNOREIP="${F2B_IGNOREIP:-}"  # доп. admin/dev IP|CIDR для fail2ban ignoreip (через --f2b-ignoreip; НЕ хардкодить в репо)
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
    --node-port)      NODE_PORT="$2";     shift 2 ;;
    --no-update)      SKIP_UPDATE="true"; shift ;;
    --with-bridges)   WITH_BRIDGES="true"; shift ;;
    --f2b-ignoreip)   F2B_IGNOREIP="$2";  shift 2 ;;
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

# ── 1.0. Pre-flight: глушим apt-auxiliary services + сносим broken 3rd-party repos
apt_preflight

# ── 1.1. Базовые пакеты одним вызовом ────────────────────────────────────────
wait_apt_lock
info "Устанавливаем базовые пакеты..."
apt_safe "update" apt-get update -qq
apt_safe "install base" env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
  gnupg wget curl ca-certificates \
  ufw logrotate git openssl socat cron ethtool
ok "Базовые пакеты установлены"

# ── 1.2. apt upgrade ─────────────────────────────────────────────────────────
if [[ "$SKIP_UPDATE" == "true" ]]; then
  warn "apt upgrade пропущен (--no-update)"
else
  wait_apt_lock
  info "apt upgrade..."
  apt_safe "upgrade" env DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold"
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
  # XanMod репо: с 2026 мигрировали с flat-suite "releases" (пустой) на codename-style.
  XANMOD_SUITE=$(lsb_release -cs 2>/dev/null || echo noble)
  echo "deb [signed-by=/usr/share/keyrings/xanmod-archive-keyring.gpg] http://deb.xanmod.org $XANMOD_SUITE main" \
    > /etc/apt/sources.list.d/xanmod-release.list
  wait_apt_lock
  apt_safe "update (xanmod)" apt-get update -qq

  # Подбираем пакет под CPU-уровень с фолбэком вниз
  XANMOD_PKG=""
  for lvl in "$CPU_LEVEL" x64v3 x64v2 x64v1; do
    XANMOD_PKG=$(apt-cache search "linux-image.*${lvl}.*xanmod" 2>/dev/null \
      | { grep -v "\-rt\-" || true; } | sort -V | tail -1 | awk '{print $1}' || true)
    [[ -n "$XANMOD_PKG" ]] && { info "Пакет: $XANMOD_PKG ($lvl)"; break; }
  done
  [[ -z "$XANMOD_PKG" ]] && die "Не найден пакет XanMod"

  wait_apt_lock
  apt_safe "install xanmod" apt-get install -y "$XANMOD_PKG"
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
# ── Резерв сервисных портов от эфемерного диапазона ───────────────────────────
# port_range расширен до 1024 → ядро иначе хватает сервисные порты (2053/7443/7444/...)
# как эфемерные source-порты исходящих коннектов; если занят в момент старта xray →
# инбаунд падает с "bind: address already in use" и НЕ ретраит (порт молча не слушается).
net.ipv4.ip_local_reserved_ports = 443,2053,2096,4443,4444,5443,6443,7443-7447,8443-8444,${NODE_PORT},${NODE_EXPORTER_PORT}
# ── Анти-спуф (loose RP-filter, безопасно для multi-IP/policy-routing) ────────
net.ipv4.conf.all.rp_filter = 2
net.ipv4.conf.default.rp_filter = 2
# ── Память / swap (не свопиться под нагрузкой) ───────────────────────────────
vm.swappiness = 10
# ── UDP min-буферы (Hysteria2 / QUIC) ────────────────────────────────────────
net.ipv4.udp_rmem_min = 16384
net.ipv4.udp_wmem_min = 16384
# ── SYN-флуд + TIME-WAIT хардеринг ───────────────────────────────────────────
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_rfc1337 = 1
net.ipv4.tcp_no_metrics_save = 1
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
  echo nf_conntrack > /etc/modules-load.d/nf_conntrack.conf   # preload рано → sysctl не откатывается на ребуте (иначе nf_conntrack_* → kernel-дефолты)
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

# NIC RX ring → max (гасит burst rx_drops на high-pps нодах; virtio/без ethtool-g = no-op)
cat > /usr/local/sbin/nic-ring.sh << 'RINGSH'
#!/bin/sh
IF=$(ip route show default 2>/dev/null | awk '{print $5; exit}')
[ -n "$IF" ] || exit 0
M=$(ethtool -g "$IF" 2>/dev/null | awk '/Pre-set/{f=1} f&&/^RX:/{print $2; exit}')
case "$M" in ''|*[!0-9]*) exit 0 ;; esac
C=$(ethtool -g "$IF" 2>/dev/null | awk 'f&&/^RX:/{print $2;exit} /Current hardware/{f=1}')
[ "$C" = "$M" ] && exit 0
ethtool -G "$IF" rx "$M" 2>/dev/null || true
RINGSH
chmod +x /usr/local/sbin/nic-ring.sh
/usr/local/sbin/nic-ring.sh
cat > /etc/systemd/system/nic-ring.service << 'RINGSVC'
[Unit]
Description=Maximise NIC RX ring buffer
After=network-online.target
Wants=network-online.target
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/nic-ring.sh
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
RINGSVC
systemctl daemon-reload
systemctl enable nic-ring.service > /dev/null 2>&1

# THP off (latency: убирает фоновую memory-compaction под нагрузкой; THP — это /sys, не sysctl)
echo never > /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || true
echo never > /sys/kernel/mm/transparent_hugepage/defrag  2>/dev/null || true
cat > /etc/systemd/system/disable-thp.service << 'THPEOF'
[Unit]
Description=Disable Transparent Huge Pages
After=local-fs.target
[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo never > /sys/kernel/mm/transparent_hugepage/enabled; echo never > /sys/kernel/mm/transparent_hugepage/defrag'
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
THPEOF
systemctl daemon-reload
systemctl enable --now disable-thp.service > /dev/null 2>&1

ok "BBR3 + sysctl + ulimits + fq + THP-off + NIC-ring настроены"

# =============================================================================
# 3. Firewall (UFW)
# =============================================================================
header "3/5 — Firewall"

ufw default deny incoming > /dev/null
ufw default allow outgoing > /dev/null
ufw allow "$SSH_PORT"/tcp   comment "SSH"        > /dev/null
ufw allow "$NODE_PORT"/tcp  comment "mgmt"       > /dev/null
ufw allow 443/tcp           comment "HTTPS"      > /dev/null
ufw allow 2053/tcp          comment "HTTPS-cf"   > /dev/null
ufw allow 8443/tcp          comment "HTTPS-alt"  > /dev/null
ufw allow 6443/tcp          comment "edge"       > /dev/null
ufw allow 7443/tcp          comment "trojan"     > /dev/null
ufw allow 7444/tcp          comment "grpc"       > /dev/null
ufw allow 2096/udp          comment "hysteria2"  > /dev/null
# wombat (docker bridge 172.18.x) → xray :4443 cdn-xhttp inbound
ufw allow from 172.16.0.0/12 to any port 4443 proto tcp comment "cdn-xhttp internal" > /dev/null
ufw allow "$NODE_EXPORTER_PORT"/tcp comment "metrics" > /dev/null

if [[ "$WITH_BRIDGES" == "true" ]]; then
  ufw allow 7443:7447/tcp comment "relay" > /dev/null
  ok "relay ports 7443-7447 открыты"
fi

ufw --force enable > /dev/null
ok "UFW: SSH($SSH_PORT), mgmt($NODE_PORT), 443, 2053, 8443, 6443, 7443, 7444, 2096/udp, metrics($NODE_EXPORTER_PORT)"

# ─── Ingress edge filter ──────────────────────────────────────────────────────
# Drop inbound traffic from a static set of known noisy/abusive source networks.
# Built-in list (no external fetch). Runs AFTER `ufw --force enable` so the chain
# sits above the UFW chains at INPUT 1.
info "Применяю edge-фильтр…"
cat > /etc/edge-deny.list <<'DENYLIST'
176.100.243.247/32
176.208.65.146/32
176.208.67.114/32
176.208.69.226/32
176.208.70.162/32
176.208.79.82/32
176.210.118.218/32
176.211.103.178/32
176.211.103.202/32
176.211.46.130/32
176.211.47.122/32
176.211.48.242/32
176.211.51.218/32
176.211.56.130/32
178.178.207.0/24
178.185.133.251/32
178.185.170.42/32
178.185.202.130/32
178.185.202.162/32
178.185.216.114/32
178.185.228.58/32
178.185.234.162/32
178.185.235.58/32
178.185.235.74/32
178.185.238.154/32
178.185.238.178/32
178.185.239.50/32
178.185.239.58/32
178.185.241.114/32
178.185.241.98/32
185.224.228.0/24
185.224.229.0/24
185.224.230.0/24
185.224.231.0/24
188.246.224.80/32
188.68.217.207
188.68.217.207/32
193.168.46.143/32
194.26.25.137/32
194.67.63.200/30
195.209.120.0/22
195.209.122.0/24
195.209.123.0/24
212.164.59.250/32
212.192.156.0/22
212.192.156.0/24
212.192.157.0/24
212.192.158.0/24
212.41.10.41/32
212.41.12.45
212.41.12.45/32
212.41.12.46
212.41.12.46/32
212.41.12.47
212.41.12.47/32
212.41.12.48
212.41.12.48/32
212.41.13.23
212.41.13.23/32
212.41.13.24
212.41.13.24/32
212.41.13.25
212.41.13.25/32
212.41.26.138/32
212.67.10.218/32
212.67.11.128/32
212.67.11.136/32
212.67.11.167/32
212.67.11.227/32
212.67.11.233/32
212.67.11.234/32
212.67.11.37/32
213.59.217.242/32
217.65.82.18/32
2a0c:a9c7:156::/48
2a0c:a9c7:157::/48
2a0c:a9c7:158::/48
31.131.251.106
31.131.251.106/32
31.131.251.235
31.131.251.235/32
31.131.255.205
31.131.255.205/32
31.131.255.206
31.131.255.206/32
31.131.255.207
31.131.255.207/32
31.131.255.208
31.131.255.208/32
31.131.255.209
31.131.255.209/32
31.131.255.210
31.131.255.210/32
31.131.255.211
31.131.255.211/32
31.131.255.212
31.131.255.212/32
31.131.255.240
31.131.255.240/32
37.9.13.105
37.9.13.105/32
37.9.13.217
37.9.13.217/32
37.9.13.54
37.9.13.54/32
37.9.13.84/32
45.141.86.171/32
45.146.167.105
45.146.167.105/32
45.146.167.237
45.146.167.237/32
45.146.167.56
45.146.167.56/32
45.146.167.68
45.146.167.68/32
45.92.176.129
45.92.176.129/32
45.92.176.143
45.92.176.143/32
45.92.176.144
45.92.176.144/32
45.92.176.145
45.92.176.145/32
45.92.176.205/32
45.92.176.94
45.92.176.94/32
45.92.177.113
45.92.177.113/32
45.92.177.127
45.92.177.127/32
45.92.177.237
45.92.177.237/32
45.93.20.103/32
45.93.20.104/32
45.93.20.109/32
45.93.20.126/32
45.93.20.148/32
45.93.20.229/32
45.93.20.45/32
45.93.20.79/32
5.143.224.100/30
5.143.224.104/30
5.159.97.203/32
5.178.87.167/32
5.188.159.228/32
5.35.16.53
62.113.99.65/32
62.76.98.0/24
62.84.116.11/32
62.84.116.13/32
62.84.116.219/32
62.84.116.237/32
62.84.116.34/32
77.223.102.101/32
77.223.102.191/32
77.223.102.84/32
77.223.103.45/32
77.223.103.53/32
77.223.120.227/32
80.249.131.92/32
80.93.187.17/32
82.148.21.205/32
85.142.100.0/24
85.142.100.2/32
85.175.147.234/32
85.175.69.50/32
89.169.28.191/32
89.169.28.210/32
89.169.28.214/32
91.122.177.241/32
92.124.109.218/32
92.223.103.144/32
92.38.153.0/24
94.25.46.114/32
94.26.228.18/32
94.26.228.205/32
95.143.190.169/32
95.143.190.179/32
95.143.191.147/32
95.143.191.223/32
95.143.191.245/32
95.167.133.10/32
95.167.148.18/32
95.167.186.2/32
95.167.197.242/32
95.167.198.186/32
95.167.199.34/32
95.167.199.90/32
95.167.200.10/32
95.167.62.66/32
95.167.62.82/32
95.167.82.26/32
95.167.87.66/32
95.189.36.106/32
DENYLIST
install -m 755 /dev/stdin /usr/local/sbin/edge-deny-load <<'LOADER'
#!/bin/bash
L=/etc/edge-deny.list
for c in iptables ip6tables; do
  $c -nL EDGE-DENY >/dev/null 2>&1 && $c -F EDGE-DENY || $c -N EDGE-DENY 2>/dev/null
  $c -C INPUT -j EDGE-DENY 2>/dev/null || $c -I INPUT 1 -j EDGE-DENY
done
while IFS= read -r n; do
  n="${n%%#*}"; n="${n// /}"; [ -z "$n" ] && continue
  case "$n" in
    *:*) ip6tables -A EDGE-DENY -s "$n" -j DROP 2>/dev/null ;;
    *)   iptables  -A EDGE-DENY -s "$n" -j DROP 2>/dev/null ;;
  esac
done < "$L"
mkdir -p /etc/iptables
iptables-save  > /etc/iptables/rules.v4 2>/dev/null
ip6tables-save > /etc/iptables/rules.v6 2>/dev/null
LOADER
/usr/local/sbin/edge-deny-load || true
if ! crontab -l 2>/dev/null | grep -q 'edge-deny-load'; then
  # Note: { ... || true; ... } необходим — под `set -euo pipefail` пустой crontab
  # делает `crontab -l` exit 1, subshell умирает до echo, pipefail валит скрипт.
  { crontab -l 2>/dev/null || true; echo '@reboot /usr/local/sbin/edge-deny-load'; } | crontab -
fi
ok "edge-фильтр: $(iptables -nL EDGE-DENY 2>/dev/null | grep -c DROP) сетей (INPUT 1, @reboot)"

# ─── AntiScanner (SCANNERS-BLOCK) ─────────────────────────────────────────────
# Комплементарно edge-фильтру: ГРЧЦ/CyberOK CIDR-диапазоны + gist-автообновление.
# Manual-лист ВСТРОЕН (self-contained); gist — best-effort (github на части RU-нод блочат) с
# fallback на встроенный manual → жёсткой github-зависимости нет. Цепочка SCANNERS-BLOCK @INPUT 1,
# persist через systemd-таймер (OnBootSec re-apply + daily refresh).
info "Ставлю AntiScanner (SCANNERS-BLOCK)…"
mkdir -p /usr/local/etc /usr/local/sbin
cat > /usr/local/etc/antiscanner_manual.txt <<'ASMANUAL'
# vinnypux manual scanner blocklist (curated) — merged into AntiScanner SCANNERS-BLOCK
# Source: user's contact 2026-06-19. Mostly ФГУП ГРЧЦ (RKN scanner) + CyberOK + Selectel-hosted scanners.
# Format: one IPv4/IPv6 or CIDR per line. '#' comments + blank lines ignored.
# ГРЧЦ / Роскомнадзор (FGUP GRCHC) — main IP-ban scan source
195.209.120.0/22
195.209.122.0/24
195.209.123.0/24
212.192.156.0/22
212.192.156.0/24
212.192.157.0/24
212.192.158.0/24
185.224.228.0/24
185.224.229.0/24
185.224.230.0/24
185.224.231.0/24
62.76.98.0/24
194.67.63.200/30
5.143.224.100/30
5.143.224.104/30
# CyberOK (scan-24.skipa.cyberok.ru -> 45.146.167.56) + Beget-hosted
45.146.167.56
45.146.167.68
45.146.167.105
45.146.167.237
# Selectel-hosted scanners
31.131.251.106
31.131.251.235
31.131.255.205
31.131.255.206
31.131.255.207
31.131.255.208
31.131.255.209
31.131.255.210
31.131.255.211
31.131.255.212
31.131.255.240
37.9.13.54
37.9.13.105
37.9.13.217
45.92.176.94
45.92.176.129
45.92.176.143
45.92.176.144
45.92.176.145
45.92.177.113
45.92.177.127
45.92.177.237
212.41.12.45
212.41.12.46
212.41.12.47
212.41.12.48
212.41.13.23
212.41.13.24
212.41.13.25
# misc RU scanner nets
92.38.153.0/24
85.142.100.0/24
5.35.16.53
188.68.217.207
ASMANUAL
cat > /usr/local/sbin/update-antiscanner.sh <<'ASUPD'
#!/bin/bash
# AntiScanner updater: gist (best-effort) -> cache, MERGED with local manual list, dedup.
URL="https://gist.githubusercontent.com/sngvy/07cee7ac810c9d222fbebddff8c1d1b8/raw/blacklist.txt"
CACHE="/usr/local/etc/antiscanner_blacklist.txt"     # last-good gist copy (github blocked on some RU nodes)
MANUAL="/usr/local/etc/antiscanner_manual.txt"       # our curated ГРЧЦ/CyberOK list (extend freely)
TEMP_FILE=$(mktemp); LIST=$(mktemp)
MODE="iptables"

setup_iptables_chains() {
    for cmd in iptables ip6tables; do
        if ! $cmd -L SCANNERS-BLOCK -n &>/dev/null; then
            $cmd -N SCANNERS-BLOCK
        else
            $cmd -F SCANNERS-BLOCK
        fi
        if ! $cmd -C INPUT -j SCANNERS-BLOCK &>/dev/null; then
            $cmd -I INPUT 1 -j SCANNERS-BLOCK
        fi
    done
}

# 1) upstream gist -> refresh cache (best effort; github is blocked from some RU segments)
if curl -sSL --connect-timeout 8 --max-time 15 "$URL" -o "$TEMP_FILE" && [[ -s "$TEMP_FILE" ]]; then
    install -D -m644 "$TEMP_FILE" "$CACHE"
fi

# 2) build working list = cache (gist) + manual, deduped
: > "$LIST"
[[ -s "$CACHE" ]]  && cat "$CACHE"  >> "$LIST"
[[ -s "$MANUAL" ]] && cat "$MANUAL" >> "$LIST"
# strip comments/blank, trim, dedup
sed -e 's/#.*//' -e 's/[[:space:]]//g' "$LIST" | grep -E '.' | sort -u > "${LIST}.clean"
mv "${LIST}.clean" "$LIST"

if [[ -s "$LIST" ]]; then
    setup_iptables_chains
    while IFS= read -r subnet; do
        [[ -z "$subnet" ]] && continue
        if [[ "$subnet" =~ : ]]; then
            ip6tables -A SCANNERS-BLOCK -s "$subnet" -j DROP 2>/dev/null
        else
            iptables  -A SCANNERS-BLOCK -s "$subnet" -j DROP 2>/dev/null
        fi
    done < "$LIST"
    mkdir -p /etc/iptables
    iptables-save  > /etc/iptables/rules.v4
    ip6tables-save > /etc/iptables/rules.v6
    echo "$(date '+%F %T') [SUCCESS] AntiScanner: $(wc -l < "$LIST") entries (gist/cache + manual)"
else
    echo "$(date '+%F %T') [SKIP] AntiScanner: empty list (no cache, no manual)"
fi
rm -f "$TEMP_FILE" "$LIST"
ASUPD
chmod +x /usr/local/sbin/update-antiscanner.sh
cat > /etc/systemd/system/antiscanner.service <<'ASSVC'
[Unit]
Description=AntiScanner blacklist updater (SCANNERS-BLOCK)
After=network-online.target
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/update-antiscanner.sh
ASSVC
cat > /etc/systemd/system/antiscanner.timer <<'ASTIMER'
[Unit]
Description=AntiScanner refresh (boot + daily)
[Timer]
OnBootSec=2min
OnCalendar=daily
Persistent=true
[Install]
WantedBy=timers.target
ASTIMER
/usr/local/sbin/update-antiscanner.sh || true
systemctl daemon-reload 2>/dev/null || true
systemctl enable --now antiscanner.timer 2>/dev/null || true
ok "AntiScanner: $(iptables -S SCANNERS-BLOCK 2>/dev/null | grep -c DROP || echo 0) правил (SCANNERS-BLOCK, boot+daily)"

# ─── SSH anti-flood (без смены порта) ─────────────────────────────────────────
# Сканеры флудят :22, держат unauth-слоты до LoginGraceTime → MaxStartups
# переполняется → sshd рубит RST'ом легит-коннекты (kex_exchange_identification).
cat > /etc/ssh/sshd_config.d/99-antiflood.conf << 'SSHEOF'
LoginGraceTime 20
MaxStartups 60:30:200
MaxSessions 20
PerSourceMaxStartups 10
PerSourceNetBlockSize 24
SSHEOF
if sshd -t 2>/dev/null; then
  systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
  ok "SSH anti-flood применён (LoginGraceTime 20, MaxStartups 60:30:200, PerSource 10)"
else
  rm -f /etc/ssh/sshd_config.d/99-antiflood.conf
  warn "sshd -t fail → anti-flood drop-in откатан"
fi

# ─── fail2ban (банит SSH-сканеры) ─────────────────────────────────────────────
# ignoreip из --f2b-ignoreip (admin/dev IP), НЕ хардкодится в репо. aggressive-mode
# ловит "Connection reset"/"Did not receive identification string".
if DEBIAN_FRONTEND=noninteractive apt-get install -y fail2ban > /dev/null 2>&1; then
  cat > /etc/fail2ban/jail.d/sshd.local << F2BEOF
[sshd]
enabled = true
mode = aggressive
maxretry = 3
findtime = 10m
bantime = 1d
ignoreip = 127.0.0.1/8 ::1 ${F2B_IGNOREIP}
F2BEOF
  systemctl enable --now fail2ban > /dev/null 2>&1 || true
  [[ -z "$F2B_IGNOREIP" ]] && warn "fail2ban: --f2b-ignoreip не задан → в ignoreip только localhost (рискуешь забанить админа на flaky-линке)"
  ok "fail2ban установлен (sshd aggressive, ignoreip: localhost${F2B_IGNOREIP:+ + $F2B_IGNOREIP})"
else
  warn "fail2ban установить не удалось — пропускаем"
fi

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

# ── journald cap + disk-guard ───────────────────────────────────────────────
# Малодисковые ноды (CDNvideo 8.7G) ползут по journald/apt/docker → на full нода
# умирает. Кап journald + пороговый reclaim-скрипт по крону.
mkdir -p /etc/systemd/journald.conf.d
printf '[Journal]\nSystemMaxUse=200M\n' > /etc/systemd/journald.conf.d/99-cap.conf
systemctl restart systemd-journald 2>/dev/null || true
cat > /usr/local/sbin/disk-guard.sh <<'DGUARD'
#!/bin/bash
# disk-guard: reclaim space when / crosses THRESH%. cron-driven, cheap no-op when fine.
set -eu
THRESH="${1:-85}"; L=/var/log/disk-guard.log
use() { df / | awk 'NR==2{gsub(/%/,"",$5); print $5}'; }
U=$(use); [ "$U" -lt "$THRESH" ] && exit 0
echo "$(date '+%F %T') disk ${U}% >= ${THRESH}% -> reclaim" >> "$L"
apt-get clean 2>/dev/null || true
journalctl --vacuum-size=200M >>"$L" 2>&1 || true
docker image prune -f   >>"$L" 2>&1 || true
docker builder prune -f >>"$L" 2>&1 || true
echo "$(date '+%F %T') after reclaim: $(use)%" >> "$L"
DGUARD
chmod +x /usr/local/sbin/disk-guard.sh
if ! crontab -l 2>/dev/null | grep -q 'disk-guard'; then
  { crontab -l 2>/dev/null || true; echo '17 * * * * /usr/local/sbin/disk-guard.sh 85'; } | crontab -
fi
ok "journald cap 200M + disk-guard (hourly, threshold 85%)"

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
#               + патч пути xrayPath в /opt/app/dist/main.js (2.8.0-бандл, Debian 13)
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
# Переименовать реальный xray binary + удалить симлинк-псевдоним rw-core + пропатчить пути.
# Node 2.8.0 (Debian 13): перешёл на s6-overlay (supervisord выпилен). xray запускает s6-сервис,
# и ровно 2 s6-файла зовут /usr/local/bin/rw-core (симлинк→xray): xray/run (exec core) и
# init-env.sh (детект XRAY_CORE_VERSION). Их ОБЯЗАТЕЛЬНО патчить, иначе после `rm rw-core`
# s6 execает несуществующий бинарь → xray не стартует (баг hvds-us 2026-07-08, s6-разбор).
# main.js-патч xrayPath — косметика баннера; реальный спавн+детект версии живут в s6-скриптах.
# program name / log-файлы ВНУТРИ контейнера остаются "xray" (снаружи через ps aux = webd).
RUN mv /usr/local/bin/xray /usr/local/bin/webd && \
    rm -f /usr/local/bin/rw-core && \
    sed -i 's|/usr/local/bin/xray|/usr/local/bin/webd|g' /opt/app/dist/main.js && \
    sed -i 's|/usr/local/bin/rw-core|/usr/local/bin/webd|g' \
        /etc/s6-overlay/s6-rc.d/xray/run \
        /etc/s6-overlay/scripts/init-env.sh
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

# Идемпотентно: каждый запуск скрипта пересобирает образ (Dockerfile мог
# обновиться между запусками), compose сам решает пересоздавать ли контейнер
# на основе хеша image/config.
info "Собираем/обновляем образ potato (~30s если изменился Dockerfile)..."
# Pre-pull базы с retry: Docker Hub ужесточил anonymous pull-лимит (2026) → --pull под set -e
# падал на транзиентном flake (особенно cloud с shared NAT-egress). 3 попытки решают.
for _try in 1 2 3; do
  docker pull remnawave/node:latest > /dev/null 2>&1 && break
  warn "pull remnawave/node:latest попытка $_try не удалась, retry через 10s..."; sleep 10
done
# --pull (база уже в кэше → быстро) ИЛИ fallback на чистый build из кэша если --pull rate-limited
( cd /opt/potato-core && { docker compose build --pull || docker compose build; } > /dev/null 2>&1 )
# Сносим pre-obfuscation остаток если есть (старый remnanode из docker run --network host)
# держит host-порты 443/8443/7443-7447 → новый potato в EADDRINUSE → Restarting loop.
docker rm -f remnanode > /dev/null 2>&1 || true
( cd /opt/potato-core && docker compose up -d > /dev/null 2>&1 )
# Убираем upstream-тег чтобы docker images не показывал remnawave/node
docker rmi remnawave/node:latest > /dev/null 2>&1 || true
if wait_container_running potato 15; then
  ok "potato запущен (obfuscated build)"
else
  warn "potato не запустился — проверь: docker logs potato"
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
rm -f /etc/cron.d/remnanode-logrotate /etc/cron.d/potato-logrotate /etc/logrotate.d/remnanode 2>/dev/null || true

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
  # Сносим pre-obfuscation сирот которые держат host-порты (network_mode: host).
  # Без этого новый beeper попадёт в EADDRINUSE → Restarting loop.
  docker rm -f beeper node-exporter > /dev/null 2>&1 || true
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

info "Собираем и запускаем wombat (nginx)..."
# Очистка конкурентов на портах: старые compose-проекты до обфускации,
# system nginx/apache, orphan-контейнеры — всё что захватило 80/443/9443.
docker compose down 2>/dev/null || true
for legacy in /opt/vinnypux-node /opt/vinnypux-selfsteal /opt/remnanode; do
  [[ -f "$legacy/docker-compose.yml" ]] && (cd "$legacy" && docker compose down 2>/dev/null) || true
done
for p in 80 443 9443; do
  containers=$(docker ps -aq --filter "publish=$p" 2>/dev/null)
  [[ -n "$containers" ]] && docker rm -f $containers > /dev/null 2>&1 || true
done
# System nginx/apache могут блокировать :80 — останавливаем (не удаляем, юзер сам решит)
for svc in nginx apache2 httpd lighttpd; do
  systemctl is-active --quiet "$svc" 2>/dev/null && {
    warn "Останавливаем system $svc — он держит :80 и блокирует wombat"
    systemctl stop "$svc" > /dev/null 2>&1 || true
    systemctl disable "$svc" > /dev/null 2>&1 || true
  }
done
docker compose up -d --build

# Ждём до 15 сек пока wombat реально поднимется
if wait_container_running wombat 15; then
  ok "wombat запущен"
else
  warn "wombat не запустился — проверь: cd $INSTALL_DIR && docker compose logs"
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
