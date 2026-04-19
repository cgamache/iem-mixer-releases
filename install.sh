#!/usr/bin/env bash
set -euo pipefail

# ─── Configuration ───────────────────────────────────────────────────────────
GH_REPO="cgamache/iem-mixer-releases"

# ─── Defaults ────────────────────────────────────────────────────────────────
X32_IP=""
INSTALL_SERVICE=true
DRY_RUN=false

# ─── Parse args ──────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case $1 in
    --x32-ip)      X32_IP="$2";           shift 2 ;;
    --no-service)  INSTALL_SERVICE=false; shift ;;
    --dry-run)     DRY_RUN=true;          shift ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

# ─── Platform detection ──────────────────────────────────────────────────────
OS="$(uname -s)"
ARCH="$(uname -m)"

case "$OS-$ARCH" in
  Linux-x86_64)   RID="linux-x64"  ; INSTALL_DIR="/opt/iem-mixer" ;;
  Linux-aarch64)  RID="linux-arm64"; INSTALL_DIR="/opt/iem-mixer" ;;
  Darwin-x86_64)  RID="osx-x64"   ; INSTALL_DIR="/usr/local/iem-mixer" ;;
  Darwin-arm64)   RID="osx-arm64" ; INSTALL_DIR="/usr/local/iem-mixer" ;;
  *)
    echo "Unsupported platform: $OS $ARCH"
    exit 1
    ;;
esac

echo "Platform: $OS $ARCH → $RID"

# ─── Dry-run mode: print plan and exit ───────────────────────────────────────
if $DRY_RUN; then
  echo ""
  echo "[dry-run] Would fetch latest version from: https://api.github.com/repos/$GH_REPO/releases/latest"
  echo "[dry-run] Would download: https://github.com/$GH_REPO/releases/download/v<version>/iem-mixer-<version>-${RID}.tar.gz"
  echo "[dry-run] Would install to: $INSTALL_DIR"
  echo "[dry-run] Would write appsettings.json with X32 IP: ${X32_IP:-<prompt>}"
  echo "[dry-run] Install service: $INSTALL_SERVICE"
  exit 0
fi

# ─── Resolve latest version from GitHub API ──────────────────────────────────
VERSION="$(curl -fsSL "https://api.github.com/repos/$GH_REPO/releases/latest" \
  | grep '"tag_name"' | head -1 | sed 's/.*"tag_name": *"v\([^"]*\)".*/\1/')"
if [[ -z "$VERSION" ]]; then
  echo "Error: could not determine latest version from GitHub."
  exit 1
fi
echo "Version:  $VERSION"

ARCHIVE="iem-mixer-${VERSION}-${RID}.tar.gz"
DOWNLOAD_URL="https://github.com/$GH_REPO/releases/download/v${VERSION}/$ARCHIVE"

# ─── Prompt for X32 IP if not supplied ───────────────────────────────────────
if [[ -z "$X32_IP" ]]; then
  read -rp "Enter X32 IP address: " X32_IP
fi

if [[ -z "$X32_IP" ]]; then
  echo "X32 IP address is required."
  exit 1
fi

# ─── Download + extract ──────────────────────────────────────────────────────
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Downloading $ARCHIVE..."
curl -fsSL --progress-bar "$DOWNLOAD_URL" -o "$TMP/$ARCHIVE"

echo "Installing to $INSTALL_DIR..."
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
tar -xzf "$TMP/$ARCHIVE" -C "$INSTALL_DIR" --strip-components=1

if [[ ! -f "$INSTALL_DIR/iem-mixer-dotnet" ]]; then
  echo "Error: binary not found in archive. Expected: $INSTALL_DIR/iem-mixer-dotnet"
  exit 1
fi

# ─── Write appsettings.json ──────────────────────────────────────────────────
cat > "$INSTALL_DIR/appsettings.json" <<APPSETTINGS
{
  "X32": {
    "IpAddress": "$X32_IP",
    "Port": 10023
  },
  "Kestrel": {
    "Endpoints": {
      "Http": { "Url": "http://0.0.0.0:5000" }
    }
  }
}
APPSETTINGS

echo "Config written: X32 at $X32_IP:10023, listening on :5000"

# ─── Make executable ─────────────────────────────────────────────────────────
chmod +x "$INSTALL_DIR/iem-mixer-dotnet"

# ─── Service install ─────────────────────────────────────────────────────────
if $INSTALL_SERVICE; then
  if [[ "$OS" == "Linux" ]]; then
    cat > /etc/systemd/system/iem-mixer.service <<UNIT
[Unit]
Description=IEM Mixer — X32 monitor mix controller
After=network.target

[Service]
Type=simple
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/iem-mixer-dotnet
Restart=always
RestartSec=5
Environment=ASPNETCORE_ENVIRONMENT=Production
StandardOutput=journal
StandardError=journal
SyslogIdentifier=iem-mixer

[Install]
WantedBy=multi-user.target
UNIT
    systemctl daemon-reload
    systemctl enable --now iem-mixer
    echo "systemd service enabled and started."

  elif [[ "$OS" == "Darwin" ]]; then
    mkdir -p /var/log/iem-mixer
    cat > /Library/LaunchDaemons/com.iem-mixer.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.iem-mixer</string>
  <key>ProgramArguments</key>
  <array><string>$INSTALL_DIR/iem-mixer-dotnet</string></array>
  <key>WorkingDirectory</key><string>$INSTALL_DIR</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>ASPNETCORE_ENVIRONMENT</key><string>Production</string>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>/var/log/iem-mixer/out.log</string>
  <key>StandardErrorPath</key><string>/var/log/iem-mixer/err.log</string>
</dict>
</plist>
PLIST
    launchctl bootout system /Library/LaunchDaemons/com.iem-mixer.plist 2>/dev/null || true
    launchctl bootstrap system /Library/LaunchDaemons/com.iem-mixer.plist
    echo "launchd daemon loaded."
  fi
fi

# ─── Detect LAN IP for final message ─────────────────────────────────────────
if [[ "$OS" == "Linux" ]]; then
  LAN_IP="$(ip route get 1 2>/dev/null | awk '{print $7; exit}' || hostname -I | awk '{print $1}')"
else
  # Try the default route interface first, then fall back to en0/en1
  _iface="$(route get default 2>/dev/null | awk '/interface:/{print $2}')"
  LAN_IP="$(ipconfig getifaddr "$_iface" 2>/dev/null \
    || ipconfig getifaddr en0 2>/dev/null \
    || ipconfig getifaddr en1 2>/dev/null \
    || echo "<this-machine-ip>")"
fi

echo ""
echo "IEM Mixer installed successfully."
echo "Connect phones to: http://$LAN_IP:5000/monitor/1"
