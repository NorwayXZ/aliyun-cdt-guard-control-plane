#!/usr/bin/env bash
set -euo pipefail

APP_NAME="aliyun-cdt-guard-control-plane"
INSTALL_DIR="${INSTALL_DIR:-/opt/aliyun-cdt-guard-control-plane}"
REPO_SLUG="${REPO_SLUG:-NorwayXZ/aliyun-cdt-guard-control-plane}"
BRANCH="${BRANCH:-main}"
SOURCE_ARCHIVE_URL="${SOURCE_ARCHIVE_URL:-https://github.com/${REPO_SLUG}/archive/refs/heads/${BRANCH}.tar.gz}"
GET_PIP_URL="${GET_PIP_URL:-https://bootstrap.pypa.io/get-pip.py}"
WEB_PORT="${WEB_PORT:-8788}"
WEB_USER="${WEB_USER:-admin}"

if [ "$(id -u)" -ne 0 ]; then
  echo "Please run as root: sudo bash install.sh"
  exit 1
fi

need_cmd() {
  command -v "$1" >/dev/null 2>&1
}

apt_lock_holder() {
  local lock_path="$1"
  if need_cmd fuser; then
    fuser "$lock_path" 2>/dev/null | tr ' ' '\n' | sed '/^$/d' | head -n 1
    return
  fi
  ps -eo pid=,comm= | awk '$2 ~ /^(apt|apt-get|dpkg|unattended-upgrades|unattended-upgrade)$/ {print $1; exit}'
}

wait_for_apt_locks() {
  local waited=0
  local max_wait="${APT_LOCK_WAIT_SECONDS:-300}"
  local locks=(
    /var/lib/dpkg/lock-frontend
    /var/lib/dpkg/lock
    /var/lib/apt/lists/lock
    /var/cache/apt/archives/lock
  )

  while true; do
    local holder=""
    local lock=""
    for lock in "${locks[@]}"; do
      if [ -e "$lock" ]; then
        holder="$(apt_lock_holder "$lock" || true)"
        if [ -n "$holder" ]; then
          break
        fi
      fi
    done

    if [ -z "$holder" ]; then
      return 0
    fi

    if [ "$waited" -ge "$max_wait" ]; then
      echo "APT/dpkg is still locked by process $holder after ${max_wait}s."
      ps -fp "$holder" || true
      echo "Please wait for the other apt process to finish, then rerun the installer."
      exit 1
    fi

    echo "APT/dpkg is locked by process $holder. Waiting... (${waited}s/${max_wait}s)"
    ps -fp "$holder" || true
    sleep 5
    waited=$((waited + 5))
  done
}

backup_bad_dpkg_update_file() {
  local output="$1"
  local bad_file=""
  local backup_dir=""

  bad_file="$(printf '%s\n' "$output" | sed -n "s#.*parsing file '\\(/var/lib/dpkg/updates/[0-9][0-9]*\\)'.*#\\1#p" | head -n 1)"
  if [ -z "$bad_file" ] || [ ! -f "$bad_file" ]; then
    return 1
  fi

  backup_dir="/root/dpkg-updates-backup-$(date +%Y%m%d%H%M%S)"
  install -d -m 700 "$backup_dir"
  echo "dpkg update file looks corrupted: $bad_file"
  echo "Moving it to backup directory: $backup_dir"
  mv "$bad_file" "$backup_dir/"
  return 0
}

repair_dpkg_state() {
  if ! need_cmd dpkg; then
    return 0
  fi

  wait_for_apt_locks
  if dpkg --audit 2>/dev/null | grep -q .; then
    echo "dpkg has unfinished package configuration. Running: dpkg --configure -a"
    local output=""
    local status=0
    set +e
    output="$(DEBIAN_FRONTEND=noninteractive dpkg --configure -a 2>&1)"
    status=$?
    set -e
    printf '%s\n' "$output"
    if [ "$status" -ne 0 ] && backup_bad_dpkg_update_file "$output"; then
      echo "Retrying: dpkg --configure -a"
      DEBIAN_FRONTEND=noninteractive dpkg --configure -a
      return 0
    fi
    return "$status"
  fi
}

apt_run() {
  local waited=0
  local max_wait="${APT_LOCK_WAIT_SECONDS:-300}"
  local output=""
  local status=0
  local holder=""

  while true; do
    wait_for_apt_locks
    repair_dpkg_state
    set +e
    output="$(apt-get -o DPkg::Lock::Timeout="$max_wait" "$@" 2>&1)"
    status=$?
    set -e
    printf '%s\n' "$output"

    if [ "$status" -eq 0 ]; then
      return 0
    fi

    if printf '%s\n' "$output" | grep -q 'dpkg was interrupted'; then
      echo "dpkg was interrupted. Repairing package state and retrying..."
      wait_for_apt_locks
      set +e
      repair_output="$(DEBIAN_FRONTEND=noninteractive dpkg --configure -a 2>&1)"
      repair_status=$?
      set -e
      printf '%s\n' "$repair_output"
      if [ "$repair_status" -ne 0 ]; then
        backup_bad_dpkg_update_file "$repair_output" || return "$repair_status"
        DEBIAN_FRONTEND=noninteractive dpkg --configure -a
      fi
      sleep 2
      continue
    fi

    if ! printf '%s\n' "$output" | grep -Eq 'Could not get lock|Unable to acquire the dpkg frontend lock|Unable to lock directory|is another process using it'; then
      return "$status"
    fi

    if [ "$waited" -ge "$max_wait" ]; then
      echo "APT/dpkg lock did not clear after ${max_wait}s."
      return "$status"
    fi

    holder="$(printf '%s\n' "$output" | sed -n 's/.*process \([0-9][0-9]*\).*/\1/p' | head -n 1)"
    if [ -n "$holder" ]; then
      echo "APT/dpkg is locked by process $holder. Waiting... (${waited}s/${max_wait}s)"
      ps -fp "$holder" || true
    else
      echo "APT/dpkg is locked. Waiting... (${waited}s/${max_wait}s)"
    fi
    sleep 5
    waited=$((waited + 5))
  done
}

install_packages() {
  if need_cmd apt-get; then
    export DEBIAN_FRONTEND=noninteractive
    repair_dpkg_state
    apt_run update -y
    apt_run install -y python3 python3-venv curl openssl ca-certificates tar
  elif need_cmd dnf; then
    dnf install -y python3 python3-pip curl openssl tar
  elif need_cmd yum; then
    yum install -y python3 python3-pip curl openssl tar
  else
    echo "Unsupported Linux distribution. Please install python3, python3-venv, curl, tar and openssl first."
    exit 1
  fi
}

ensure_runtime_available() {
  local missing=""
  for cmd in python3 curl tar openssl; do
    if ! need_cmd "$cmd"; then
      missing="$missing $cmd"
    fi
  done

  if [ -n "$missing" ]; then
    echo "Missing required command(s):$missing"
    echo "Fix the system package manager first, or install these commands manually, then rerun install.sh."
    exit 1
  fi

  if ! python3 - <<'PY' >/dev/null 2>&1
import venv
PY
  then
    echo "Python venv module is not available."
    echo "Install python3-venv first, or fix dpkg/apt and rerun install.sh without SKIP_SYSTEM_PACKAGES=1."
    exit 1
  fi
}

is_valid_port() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
  esac
  [ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}

port_is_free() {
  local port="$1"
  python3 - "$port" <<'PY' >/dev/null 2>&1
import socket
import sys

port = int(sys.argv[1])
for family, host in ((socket.AF_INET, "0.0.0.0"), (socket.AF_INET6, "::")):
    sock = socket.socket(family, socket.SOCK_STREAM)
    try:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        sock.bind((host, port))
    except OSError:
        sys.exit(1)
    finally:
        sock.close()
sys.exit(0)
PY
}

find_available_port() {
  local start_port="$1"
  local port="$start_port"
  local max_port="${PORT_SCAN_MAX:-65535}"

  if ! is_valid_port "$start_port"; then
    echo "Invalid WEB_PORT: $start_port. WEB_PORT must be between 1 and 65535." >&2
    exit 1
  fi

  while [ "$port" -le "$max_port" ]; do
    if port_is_free "$port"; then
      echo "$port"
      return 0
    fi
    port=$((port + 1))
  done

  echo "No free web port found from $start_port to $max_port." >&2
  exit 1
}

python_has_ensurepip() {
  python3 - <<'PY' >/dev/null 2>&1
import ensurepip
PY
}

create_python_venv() {
  local venv_dir="$1"
  local tmp_dir=""

  if [ -x "$venv_dir/bin/python" ] && [ -x "$venv_dir/bin/pip" ]; then
    return 0
  fi

  rm -rf "$venv_dir"
  if python_has_ensurepip; then
    python3 -m venv "$venv_dir"
    return 0
  fi

  echo "Python ensurepip is not available. Creating venv without pip, then bootstrapping pip..."
  python3 -m venv --without-pip "$venv_dir"
  tmp_dir="$(mktemp -d)"
  curl -fsSL "$GET_PIP_URL" -o "$tmp_dir/get-pip.py"
  "$venv_dir/bin/python" "$tmp_dir/get-pip.py" --no-cache-dir
  rm -rf "$tmp_dir"
}

prepare_source() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [ -f "$script_dir/guard.py" ] && [ -f "$script_dir/web.py" ]; then
    echo "$script_dir"
    return
  fi

  local tmp_dir
  tmp_dir="$(mktemp -d)"
  echo "Downloading $APP_NAME source archive..." >&2
  curl -fsSL "$SOURCE_ARCHIVE_URL" -o "$tmp_dir/source.tar.gz"
  mkdir -p "$tmp_dir/source"
  tar -xzf "$tmp_dir/source.tar.gz" -C "$tmp_dir/source" --strip-components=1
  echo "$tmp_dir/source"
}

if [ "${SKIP_SYSTEM_PACKAGES:-0}" = "1" ]; then
  echo "Skipping system package installation because SKIP_SYSTEM_PACKAGES=1."
  ensure_runtime_available
else
  install_packages
  ensure_runtime_available
fi
SRC_DIR="$(prepare_source)"

install -d -m 700 "$INSTALL_DIR"
install -m 755 "$SRC_DIR/guard.py" "$INSTALL_DIR/guard.py"
install -m 755 "$SRC_DIR/web.py" "$INSTALL_DIR/web.py"
install -m 755 "$SRC_DIR/notifications.py" "$INSTALL_DIR/notifications.py"
install -m 755 "$SRC_DIR/update.sh" "$INSTALL_DIR/update.sh"
install -m 644 "$SRC_DIR/requirements.txt" "$INSTALL_DIR/requirements.txt"
install -m 644 "$SRC_DIR/VERSION" "$INSTALL_DIR/VERSION"
install -m 644 "$SRC_DIR/cdt-guard-control-plane.service" /etc/systemd/system/cdt-guard-control-plane.service
install -m 644 "$SRC_DIR/cdt-guard-control-plane.timer" /etc/systemd/system/cdt-guard-control-plane.timer
install -m 644 "$SRC_DIR/cdt-guard-control-plane-web.service" /etc/systemd/system/cdt-guard-control-plane-web.service
sed -i "s#/opt/aliyun-cdt-guard-control-plane#$INSTALL_DIR#g" /etc/systemd/system/cdt-guard-control-plane.service /etc/systemd/system/cdt-guard-control-plane-web.service

rm -rf "$INSTALL_DIR/ui-prototype"

create_python_venv "$INSTALL_DIR/venv"
"$INSTALL_DIR/venv/bin/pip" install --no-cache-dir --upgrade pip
"$INSTALL_DIR/venv/bin/pip" install --no-cache-dir -r "$INSTALL_DIR/requirements.txt"

if [ ! -f "$INSTALL_DIR/guard.env" ]; then
  umask 077
  cat > "$INSTALL_DIR/guard.env" <<'EOF'
# Optional global fallback credentials.
# New servers can be added completely from the web panel, so these may stay empty.
ALIYUN_ACCESS_KEY_ID=
ALIYUN_ACCESS_KEY_SECRET=
ALIYUN_REGION_ID=cn-hongkong
EOF
fi

if [ ! -f "$INSTALL_DIR/instances.json" ]; then
  umask 077
  cat > "$INSTALL_DIR/instances.json" <<'EOF'
{
  "defaults": {
    "enabled": true,
    "start_threshold_gb": 175,
    "stop_threshold_gb": 180,
    "traffic_region_id": "cn-hongkong",
    "traffic_scope": "account_non_china",
    "warning_threshold_gb": 160
  },
  "instances": [],
  "version": 1
}
EOF
fi

if [ ! -f "$INSTALL_DIR/web.env" ]; then
  SELECTED_WEB_PORT="$(find_available_port "$WEB_PORT")"
  if [ "$SELECTED_WEB_PORT" != "$WEB_PORT" ]; then
    echo "Port $WEB_PORT is already in use. Using available port $SELECTED_WEB_PORT instead."
  fi
  WEB_PASS="$(openssl rand -base64 24 | tr -d '\n')"
  WEB_SESSION_SECRET="$(openssl rand -hex 32)"
  umask 077
  cat > "$INSTALL_DIR/web.env" <<EOF
WEB_USERNAME=$WEB_USER
WEB_PASSWORD=$WEB_PASS
WEB_SESSION_SECRET=$WEB_SESSION_SECRET
CDT_GUARD_HOST=0.0.0.0
CDT_GUARD_PORT=$SELECTED_WEB_PORT
EOF
else
  WEB_PASS="$(sed -n 's/^WEB_PASSWORD=//p' "$INSTALL_DIR/web.env" | head -n 1)"
  SELECTED_WEB_PORT="$(sed -n 's/^CDT_GUARD_PORT=//p' "$INSTALL_DIR/web.env" | head -n 1)"
  if [ -z "$SELECTED_WEB_PORT" ]; then
    SELECTED_WEB_PORT="$(find_available_port "$WEB_PORT")"
    umask 077
    printf '\nCDT_GUARD_PORT=%s\n' "$SELECTED_WEB_PORT" >> "$INSTALL_DIR/web.env"
  fi
  if ! grep -q '^WEB_SESSION_SECRET=' "$INSTALL_DIR/web.env"; then
    WEB_SESSION_SECRET="$(openssl rand -hex 32)"
    umask 077
    printf '\nWEB_SESSION_SECRET=%s\n' "$WEB_SESSION_SECRET" >> "$INSTALL_DIR/web.env"
  fi
fi

chmod 700 "$INSTALL_DIR"
chmod 600 "$INSTALL_DIR/guard.env" "$INSTALL_DIR/instances.json" "$INSTALL_DIR/web.env"

rm -f /usr/local/bin/cdt-guard-control-plane
cat > /usr/local/bin/cdt-guard-control-plane <<EOF
#!/bin/sh
export CDT_GUARD_HOME="$INSTALL_DIR"
exec "$INSTALL_DIR/venv/bin/python" "$INSTALL_DIR/guard.py" "\$@"
EOF
chmod 755 /usr/local/bin/cdt-guard-control-plane

rm -f /usr/local/bin/cdt-guard-control-plane-update
cat > /usr/local/bin/cdt-guard-control-plane-update <<EOF
#!/bin/sh
export INSTALL_DIR="$INSTALL_DIR"
exec /usr/bin/env bash "$INSTALL_DIR/update.sh" "\$@"
EOF
chmod 755 /usr/local/bin/cdt-guard-control-plane-update

systemctl daemon-reload
systemctl enable --now cdt-guard-control-plane.timer
systemctl enable --now cdt-guard-control-plane-web.service

IP_ADDR="$(curl -fsS --max-time 3 https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')"

cat <<EOF

$APP_NAME installed.

Web panel:
  URL:      http://$IP_ADDR:$SELECTED_WEB_PORT
  Username: $WEB_USER
  Password: $WEB_PASS

Commands:
  cdt-guard-control-plane status
  cdt-guard-control-plane run
  cdt-guard-control-plane-update
  systemctl status cdt-guard-control-plane.timer
  systemctl status cdt-guard-control-plane-web.service

Update:
  curl -fsSL https://raw.githubusercontent.com/NorwayXZ/aliyun-cdt-guard-control-plane/main/update.sh | sudo bash

Uninstall:
  curl -fsSL https://raw.githubusercontent.com/NorwayXZ/aliyun-cdt-guard-control-plane/main/uninstall.sh | sudo bash

EOF
