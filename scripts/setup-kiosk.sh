#!/bin/bash
# Proxmox HDMI kiosk setup for pve2 (rack display -> Grafana playlist)
# Run as root on the Proxmox node connected to the rack display.
# Usage:  bash setup-kiosk.sh   then   reboot

set -e

# ===================== EDIT THESE =====================
MODE="kiosk"                                     # rack display: Grafana playlist
BROWSER_URL="https://example.com/"
GRAFANA_IP="10.0.0.31"                        # Grafana (monitoring container)
PLAYLIST_ID="rack"                               # Grafana playlist uid
ROTATE=""                                        # set to "-r" if the image is sideways
# ======================================================

KIOSK_URL="http://${GRAFANA_IP}:3000/playlists/play/${PLAYLIST_ID}?kiosk&autofitpanels"
GRAFANA_HEALTH="http://${GRAFANA_IP}:3000/api/health"

if [ "$(id -u)" -ne 0 ]; then
  echo "Please run as root."
  exit 1
fi

echo ">>> Installing packages..."
apt-get update
apt-get install -y --no-install-recommends \
  cage pipewire pipewire-pulse wireplumber \
  curl wget ca-certificates fonts-dejavu-core fonts-noto-core

echo ">>> Installing Google Chrome (includes Widevine for streaming)..."
if ! command -v google-chrome-stable >/dev/null 2>&1; then
  wget -q -O /tmp/google-chrome.deb \
    https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
  apt-get install -y /tmp/google-chrome.deb
  rm -f /tmp/google-chrome.deb
fi

echo ">>> Creating kiosk user..."
if ! id kiosk >/dev/null 2>&1; then
  useradd -m -s /bin/bash kiosk
fi
usermod -aG video,render,input,audio kiosk

echo ">>> Setting up auto-login on the HDMI console (tty1)..."
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf <<'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin kiosk --noclear %I $TERM
EOF

echo ">>> Writing launcher script..."
cat > /home/kiosk/start.sh <<'EOF'
#!/bin/bash
# Switch MODE between "browser" and "kiosk", then reboot.

MODE="__MODE__"
BROWSER_URL="__BROWSER_URL__"
KIOSK_URL="__KIOSK_URL__"
GRAFANA_HEALTH="__GRAFANA_HEALTH__"
ROTATE="__ROTATE__"

# What to wait for before opening the browser
if [ "$MODE" = "kiosk" ]; then
  CHECK="$GRAFANA_HEALTH"
else
  CHECK="https://www.google.com"
fi

# Wait up to ~2 minutes for network / Grafana
OK=0
for i in $(seq 1 40); do
  if curl -s -m 3 -o /dev/null "$CHECK"; then OK=1; break; fi
  sleep 3
done

if [ "$OK" -eq 0 ]; then
  clear
  echo "Cannot reach: $CHECK"
  echo "Check network. Current addresses:"
  echo
  ip -br a
  echo
  echo "Retrying in 60 seconds. Press Ctrl+Alt+F2 to log in as root."
  sleep 60
  exit 0   # auto-login restarts this script
fi

# Stop Chrome showing "Restore pages?" after a power cut
PREFS="$HOME/.config/google-chrome/Default/Preferences"
if [ -f "$PREFS" ]; then
  sed -i 's/"exited_cleanly":false/"exited_cleanly":true/; s/"exit_type":"[^"]*"/"exit_type":"Normal"/' "$PREFS"
fi

FLAGS=(
  --ozone-platform=wayland
  --noerrdialogs
  --no-first-run
  --disable-session-crashed-bubble
  --password-store=basic
  --autoplay-policy=no-user-gesture-required
)

if [ "$MODE" = "kiosk" ]; then
  exec cage $ROTATE -- google-chrome-stable --kiosk --incognito "${FLAGS[@]}" "$KIOSK_URL"
else
  exec cage $ROTATE -- google-chrome-stable --start-maximized "${FLAGS[@]}" "$BROWSER_URL"
fi
EOF

sed -i \
  -e "s|__MODE__|${MODE}|" \
  -e "s|__BROWSER_URL__|${BROWSER_URL}|" \
  -e "s|__KIOSK_URL__|${KIOSK_URL//&/\\&}|" \
  -e "s|__GRAFANA_HEALTH__|${GRAFANA_HEALTH}|" \
  -e "s|__ROTATE__|${ROTATE}|" \
  /home/kiosk/start.sh

chmod +x /home/kiosk/start.sh

echo ">>> Writing .bash_profile..."
cat > /home/kiosk/.bash_profile <<'EOF'
if [ "$(tty)" = "/dev/tty1" ]; then
  exec /home/kiosk/start.sh
fi
EOF

chown kiosk:kiosk /home/kiosk/start.sh /home/kiosk/.bash_profile

echo
echo "=================================================="
echo " Done. Mode: ${MODE}"
echo " Reboot to start:   reboot"
echo
echo " Switch mode later: nano /home/kiosk/start.sh  (edit MODE=)"
echo " Root console:      Ctrl+Alt+F2  (back: Ctrl+Alt+F1)"
echo " Undo autologin:    rm /etc/systemd/system/getty@tty1.service.d/autologin.conf"
echo "=================================================="
