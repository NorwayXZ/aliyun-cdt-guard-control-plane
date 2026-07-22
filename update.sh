#!/usr/bin/env bash
set -euo pipefail

APP_NAME="aliyun-cdt-guard-control-plane"
INSTALL_DIR="${INSTALL_DIR:-/opt/aliyun-cdt-guard-control-plane}"
REPO_SLUG="${REPO_SLUG:-NorwayXZ/aliyun-cdt-guard-control-plane}"
BRANCH="${BRANCH:-main}"
SOURCE_ARCHIVE_URL="${SOURCE_ARCHIVE_URL:-https://github.com/${REPO_SLUG}/archive/refs/heads/${BRANCH}.tar.gz}"

if [ "$(id -u)" -ne 0 ]; then
  echo "Please run as root: sudo bash update.sh"
  exit 1
fi

need_cmd() {
  command -v "$1" >/dev/null 2>&1
}

if ! need_cmd curl; then
  echo "curl is required. Please install curl first, then rerun update."
  exit 1
fi

if ! need_cmd tar; then
  echo "tar is required. Please install tar first, then rerun update."
  exit 1
fi

if ! need_cmd python3; then
  echo "python3 is required. Please install python3 first, then rerun update."
  exit 1
fi

if [ ! -d "$INSTALL_DIR" ]; then
  echo "Install directory not found: $INSTALL_DIR"
  echo "Run install.sh first."
  exit 1
fi

TMP_DIR="$(mktemp -d)"
echo "Downloading latest $APP_NAME from $REPO_SLUG ($BRANCH)..."
curl -fsSL "$SOURCE_ARCHIVE_URL" -o "$TMP_DIR/source.tar.gz"
mkdir -p "$TMP_DIR/source"
tar -xzf "$TMP_DIR/source.tar.gz" -C "$TMP_DIR/source" --strip-components=1

echo "Stopping services..."
systemctl stop cdt-guard-control-plane.timer >/dev/null 2>&1 || true
systemctl stop cdt-guard-control-plane-web.service >/dev/null 2>&1 || true

echo "Updating program files..."
install -d -m 700 "$INSTALL_DIR"
install -m 755 "$TMP_DIR/source/guard.py" "$INSTALL_DIR/guard.py"
install -m 755 "$TMP_DIR/source/web.py" "$INSTALL_DIR/web.py"
install -m 644 "$TMP_DIR/source/notifications.py" "$INSTALL_DIR/notifications.py"
install -m 644 "$TMP_DIR/source/requirements.txt" "$INSTALL_DIR/requirements.txt"
install -m 644 "$TMP_DIR/source/VERSION" "$INSTALL_DIR/VERSION"
install -m 755 "$TMP_DIR/source/update.sh" "$INSTALL_DIR/update.sh"

rm -rf "$INSTALL_DIR/ui-prototype"

install -m 644 "$TMP_DIR/source/cdt-guard-control-plane.service" /etc/systemd/system/cdt-guard-control-plane.service
install -m 644 "$TMP_DIR/source/cdt-guard-control-plane.timer" /etc/systemd/system/cdt-guard-control-plane.timer
install -m 644 "$TMP_DIR/source/cdt-guard-control-plane-web.service" /etc/systemd/system/cdt-guard-control-plane-web.service
sed -i "s#/opt/aliyun-cdt-guard-control-plane#$INSTALL_DIR#g" /etc/systemd/system/cdt-guard-control-plane.service /etc/systemd/system/cdt-guard-control-plane-web.service

if [ ! -d "$INSTALL_DIR/venv" ]; then
  echo "Creating Python virtual environment..."
  python3 -m venv "$INSTALL_DIR/venv"
fi

echo "Updating Python dependencies..."
"$INSTALL_DIR/venv/bin/pip" install --no-cache-dir --upgrade pip
"$INSTALL_DIR/venv/bin/pip" install --no-cache-dir -r "$INSTALL_DIR/requirements.txt"

chmod 700 "$INSTALL_DIR"
chmod 600 "$INSTALL_DIR/guard.env" "$INSTALL_DIR/instances.json" "$INSTALL_DIR/web.env" 2>/dev/null || true

cat > /usr/local/bin/cdt-guard-control-plane <<EOF
#!/bin/sh
export CDT_GUARD_HOME="$INSTALL_DIR"
exec "$INSTALL_DIR/venv/bin/python" "$INSTALL_DIR/guard.py" "\$@"
EOF
chmod 755 /usr/local/bin/cdt-guard-control-plane

cat > /usr/local/bin/cdt-guard-control-plane-update <<EOF
#!/bin/sh
export INSTALL_DIR="$INSTALL_DIR"
exec /usr/bin/env bash "$INSTALL_DIR/update.sh" "\$@"
EOF
chmod 755 /usr/local/bin/cdt-guard-control-plane-update

systemctl daemon-reload
systemctl enable --now cdt-guard-control-plane.timer
systemctl restart cdt-guard-control-plane-web.service

VERSION="$(cat "$INSTALL_DIR/VERSION" 2>/dev/null || echo latest)"
echo
echo "$APP_NAME updated to $VERSION."
echo "Configs, secrets, status and history were kept in: $INSTALL_DIR"
