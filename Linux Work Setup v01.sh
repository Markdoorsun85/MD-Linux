sudo bash -c '
set -u
export DEBIAN_FRONTEND=noninteractive

echo "[1/8] Fix Chrome/Edge repos (wipe dups, add clean ones)"
mkdir -p /usr/share/keyrings
rm -f /etc/apt/sources.list.d/google-chrome*.list || true
rm -f /etc/apt/sources.list.d/microsoft-edge*.list || true
wget -qO- https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor >/usr/share/keyrings/google-linux-signing-keyring.gpg
cat >/etc/apt/sources.list.d/google-chrome.list <<EOF1
deb [arch=amd64 signed-by=/usr/share/keyrings/google-linux-signing-keyring.gpg] http://dl.google.com/linux/chrome/deb/ stable main
EOF1
wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor >/usr/share/keyrings/microsoft-edge.gpg
cat >/etc/apt/sources.list.d/microsoft-edge-stable.list <<EOF2
deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft-edge.gpg] https://packages.microsoft.com/repos/edge stable main
EOF2

echo "[2/8] Update & full upgrade"
apt-get update -y
apt-get upgrade -y
apt-get dist-upgrade -y || true
apt-get -f install -y || true
apt-get autoremove -y
apt-get clean -y

echo "[3/8] Ensure Flatpak + Flathub"
apt-get install -y --no-install-recommends flatpak
flatpak remotes | awk "{print \$1}" | grep -qx flathub || \
  flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

echo "[4/8] Install browsers (Chrome & Edge)"
apt-get update -y
apt-get install -y --no-install-recommends google-chrome-stable microsoft-edge-stable || { apt-get -f install -y; apt-get install -y google-chrome-stable microsoft-edge-stable; }

echo "[5/8] Install ClamAV (engine+daemon+GUI) and VLC"
apt-get install -y --no-install-recommends clamav clamav-daemon clamtk vlc || { apt-get -f install -y; apt-get install -y clamav clamav-daemon clamtk vlc; }

echo "[6/8] Seed ClamAV definitions & enable services"
systemctl stop clamav-freshclam 2>/dev/null || true
freshclam || true
systemctl enable --now clamav-freshclam 2>/dev/null || true
systemctl enable --now clamav-daemon 2>/dev/null || true

echo "[7/8] Install TeamViewer (amd64)"
tmp=/tmp/teamviewer_amd64.deb
wget -qO "$tmp" https://download.teamviewer.com/download/linux/teamviewer_amd64.deb
dpkg -i "$tmp" || apt-get -f install -y
rm -f "$tmp"

echo "[8/8] Install Speech Note (Flatpak)"
flatpak list --app | awk "{print \$1}" | grep -qx net.mkiol.SpeechNote || \
  flatpak install -y flathub net.mkiol.SpeechNote || true

echo
echo "=== Done ==="
echo "Chrome:           $(command -v google-chrome >/dev/null && echo OK || echo MISSING)"
echo "Edge:             $(command -v microsoft-edge >/dev/null || command -v microsoft-edge-stable >/dev/null && echo OK || echo MISSING)"
echo "VLC:              $(command -v vlc >/dev/null && echo OK || echo MISSING)"
echo "ClamTk GUI:       $(command -v clamtk >/dev/null && echo OK || echo MISSING)"
echo "TeamViewer:       $(command -v teamviewer >/dev/null && echo OK || echo MISSING)"
systemctl is-active clamav-freshclam >/dev/null 2>&1 && echo "Freshclam:        running" || echo "Freshclam:        not running"
systemctl is-active clamav-daemon   >/dev/null 2>&1 && echo "ClamAV daemon:    running"  || echo "ClamAV daemon:    not running"
flatpak list --app 2>/dev/null | awk "{print \$1}" | grep -qx net.mkiol.SpeechNote && echo "Speech Note:      OK" || echo "Speech Note:      MISSING"
echo "Reboot recommended if a kernel or core libs were updated."
'
