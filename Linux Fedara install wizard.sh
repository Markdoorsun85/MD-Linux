#!/usr/bin/env bash
# Mark's Terminal Post-Install — Fedora (Flatpak-first with DNF fallback) — SAFE v10-fedora
# - Task #1 is forced: sudo dnf upgrade --refresh -y
# - Other tasks default=N and prompt
# - Fancy spinner + elapsed time; logs to ~/.local/share/postinstall/logs/...
#
# Notes:
# - This targets Fedora (uses dnf/rpm). I included RPMFusion enabling for Steam.
# - Repos (Brave/Chrome/Edge/AnyDesk) are added via rpm import/.repo files as per vendor rpm instructions.
# - GRUB updates attempt the usual Fedora paths.
# - Flatpak logic is unchanged; Fedora normally ships with Flatpak installed but we ensure it.
# - Some package names differ on Fedora; script attempts flatpak then dnf fallback.

set -euo pipefail
set +m
export DNF_ASSUME_YES="yes"   # for some tools that auto-ask (not used by dnf directly)
export FW_POLICY=noninteractive

# ---------- sudo preflight ----------
if ! sudo -v; then echo "This script needs sudo privileges."; exit 1; fi

# ---------- logging ----------
LOG_DIR="$HOME/.local/share/postinstall/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/run_$(date +%Y%m%d_%H%M%S).log"
log(){ printf "[%(%F %T)T] %s\n" -1 "$*" | tee -a "$LOG_FILE"; }
sep(){ printf '%s\n' "------------------------------------------------------------"; }

# real user for Flatpak installs
if [[ $EUID -eq 0 ]]; then REAL_USER="${SUDO_USER:-root}"; else REAL_USER="$USER"; fi

# ---------- spinner ----------
run_with_spinner() {
  local msg="$1"; shift
  local pid rc start now elapsed mm ss
  local bar_w=26
  local unicode=${UNICODE_SPINNER:-1}
  local frames_ascii=( '-' '\' '|' '/' )
  local frames_uni=( '⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏' )
  local i=0 fill pct bar spinner sym_ok sym_fail
  if [[ $unicode -eq 1 ]]; then sym_ok="✓"; sym_fail="✗"; else sym_ok="OK"; sym_fail="FAIL"; fi
  ( "$@" ) >>"$LOG_FILE" 2>&1 & pid=$!
  start=$(date +%s); tput civis 2>/dev/null || true; trap 'tput cnorm 2>/dev/null || true' EXIT
  while kill -0 "$pid" 2>/dev/null; do
    now=$(date +%s); elapsed=$((now - start)); mm=$((elapsed/60)); ss=$((elapsed%60))
    pct=$(( (elapsed % (bar_w+1)) * 100 / bar_w )); fill=$(( pct * bar_w / 100 ))
    if [[ $unicode -eq 1 ]]; then spinner="${frames_uni[$(( i % ${#frames_uni[@]} ))]}"; bar="$(printf '█%.0s' $(seq 1 $fill))"; else spinner="${frames_ascii[$(( i % ${#frames_ascii[@]} ))]}"; bar="$(printf '#%.0s' $(seq 1 $fill))"; fi
    printf "\r  %s  [%-*s] %3s%%  %02d:%02d  %s" "$spinner" "$bar_w" "$(printf '%-*s' $bar_w "$bar")" "$pct" "$mm" "$ss" "$msg"
    i=$((i+1)); sleep 0.15
  done
  wait "$pid"; rc=$?
  now=$(date +%s); elapsed=$((now - start)); mm=$((elapsed/60)); ss=$((elapsed%60))
  if [[ $rc -eq 0 ]]; then printf "\r  %s  [%-*s] 100%%  %02d:%02d  %s\n" "$sym_ok" "$bar_w" "$(printf '█%.0s' $(seq 1 $bar_w))" "$mm" "$ss" "$msg"; else printf "\r  %s  [%-*s]  --%%  %02d:%02d  %s\n" "$sym_fail" "$bar_w" "$(printf '%*s' $bar_w '')" "$mm" "$ss" "$msg"; fi
  tput cnorm 2>/dev/null || true; trap - EXIT; return "$rc"
}

# ---------- helpers ----------
ask_yn() {
  local prompt="$1" default="${2:-N}" ans
  while true; do
    read -rp "$prompt [Y/N] (default: $default): " ans || true
    ans="${ans:-$default}"
    case "${ans^^}" in Y|YES) echo Y; return;; N|NO) echo N; return;; *) echo "Please enter Y or N.";; esac
  done
}

ensure_flatpak() {
  if ! command -v flatpak >/dev/null 2>&1; then
    run_with_spinner "Installing Flatpak" bash -lc 'sudo dnf install -y flatpak'
  fi
  if ! flatpak remote-list | grep -qi flathub; then
    run_with_spinner "Adding Flathub remote" bash -lc 'sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo'
  fi
}
fp_user_install(){ ensure_flatpak; sudo -u "$REAL_USER" flatpak install -y flathub "$1"; }

# ---------- repo helpers ----------
# write a simple .repo file (id, name, baseurl, gpgkey-url)
add_repo_file() {
  local id="$1" name="$2" baseurl="$3" gpgkey="$4"
  local repo="/etc/yum.repos.d/${id}.repo"
  sudo bash -c "cat > '$repo' <<'EOF'
[$id]
name=$name
baseurl=$baseurl
enabled=1
gpgcheck=1
gpgkey=$gpgkey
EOF"
  if [[ -n "$gpgkey" ]]; then
    sudo rpm --import "$gpgkey" 2>/dev/null || true
  fi
}

normalize_anydesk_repo() {
  # AnyDesk provides an rpm repo; create /etc/yum.repos.d/anydesk.repo
  if ! rpm -q anydesk >/dev/null 2>&1; then
    sudo bash -c 'cat > /etc/yum.repos.d/anydesk.repo <<EOF
[anydesk]
name=AnyDesk Fedora Repo
baseurl=http://rpm.anydesk.com/fedora/\$basearch/
gpgcheck=1
gpgkey=https://keys.anydesk.com/repos/RPM-GPG-KEY
enabled=1
EOF'
    sudo rpm --import https://keys.anydesk.com/repos/RPM-GPG-KEY 2>/dev/null || true
  fi
}
purge_teamviewer_repo() {
  sudo rm -f /etc/yum.repos.d/teamviewer*.repo 2>/dev/null || true
  sudo rm -f /etc/pki/rpm-gpg/*teamviewer* 2>/dev/null || true
  # Remove package if it exists? We'll leave removal to selected tasks.
}

# ---------- TASKS ----------
TASK_IDS=(
  UPDATE_UPGRADE
  ADD_ALL_REPOS
  UPDATE FLATPAK_ENABLE REMOVE_TRANSMISSION
  GPARTED SYNAPTIC CURL_WGET
  GRUB_CUSTOMIZER BASIC_GRUB_TWEAKS
  TEAMVIEWER ANYDESK PIA BRAVE CHROME EDGE
  FLAMESHOT QBITTORRENT VLC OBS GIMP HANDBRAKE STEAM
  CLAMAV
)
TASK_LABELS=(
  "System Upgrade — runs: sudo dnf upgrade --refresh -y (FORCED)"
  "Add All Repositories (one-shot) — Fedora repos, Flathub, Brave/Chrome/Edge, AnyDesk repo."
  "Update System — DNF preflight & base tools."
  "Enable Flatpak — Adds Flathub and enables Flatpak."
  "Remove Transmission — Uninstalls Transmission."
  "Install GParted — Flatpak preferred, DNF fallback."
  "Install Synaptic-equivalent (dnfdragora) — GUI package manager."
  "Install Curl/Wget (Extra) — Ensures latest versions."
  "Install GRUB Customizer — (likely unavailable on Fedora; will SKIP if unsupported)."
  "Basic GRUB Tweaks — Safe timeout tweak with backup + grub2-mkconfig."
  "Install TeamViewer — Use system package only (no external repo)."
  "Install AnyDesk — Remote desktop (official repo)."
  "Install PIA VPN — Uses local .run if found in ~/Downloads."
  "Install Brave Browser — RPM repo."
  "Install Google Chrome — Official Google repo (RPM)."
  "Install Microsoft Edge — Official Microsoft repo (RPM)."
  "Install Flameshot — Flatpak preferred, DNF fallback."
  "Install qBittorrent — Flatpak preferred, DNF fallback."
  "Install VLC Media Player — Flatpak preferred, DNF fallback."
  "Install OBS Studio — Flatpak preferred, DNF fallback."
  "Install GIMP — Flatpak preferred, DNF fallback."
  "Install HandBrake — Flatpak preferred, DNF fallback."
  "Install Steam — Flatpak preferred, DNF fallback (via RPMFusion)."
  "Install ClamAV + GUI — clamav + freshclam + clamtk."
)

# defaults: N for everything except the first task which is forced Y
DEFAULTS=()
for idx in "${!TASK_IDS[@]}"; do
  if [[ $idx -eq 0 ]]; then DEFAULTS+=(Y); else DEFAULTS+=(N); fi
done

echo
sep
echo "Please select which tasks you want to run:"
echo
declare -A WANT

# Force the first task ON and show it without asking
echo " - ${TASK_LABELS[0]}  [FORCED = Y]"
WANT["${TASK_IDS[0]}"]="Y"

# Ask for the rest
for i in $(seq 1 $((${#TASK_IDS[@]}-1))); do
  id="${TASK_IDS[$i]}"; label="${TASK_LABELS[$i]}"; def="${DEFAULTS[$i]}"
  ans=$(ask_yn " - $label" "$def"); WANT["$id"]="$ans"
done

echo
sep
echo "Summary of selections:"
for i in "${!TASK_IDS[@]}"; do id="${TASK_IDS[$i]}"; printf " [%s] %s\n" "${WANT[$id]}" "${TASK_LABELS[$i]}"; done
echo
if [[ "$(ask_yn 'Proceed with these selections?' Y)" != "Y" ]]; then echo "Aborted. Nothing changed."; exit 0; fi

# ---------- results ----------
RESULT_DESC=(); RESULT_STAT=()
mark_result(){ RESULT_DESC+=("$1"); RESULT_STAT+=("$2"); }

# ---------- runners ----------
do_UPDATE_UPGRADE(){ run_with_spinner "Running: sudo dnf upgrade --refresh -y" bash -lc 'sudo dnf upgrade --refresh -y'; }

do_ADD_ALL_REPOS() {
  run_with_spinner "Preparing repo tools (dnf-plugins-core, curl, rpm, gpg)" bash -lc 'sudo dnf makecache --refresh -y || true; sudo dnf install -y dnf-plugins-core curl rpm gpg ca-certificates'
  run_with_spinner "Enabling RPM Fusion (free & nonfree)" bash -lc '
    sudo dnf install -y https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm || true
  '
  run_with_spinner "Removing TeamViewer vendor repo (system package only)" purge_teamviewer_repo
  run_with_spinner "Ensuring Flatpak & Flathub" ensure_flatpak

  run_with_spinner "Adding Brave repo" bash -lc '
    sudo curl -fsSLo /etc/pki/rpm-gpg/brave-core.asc https://brave-browser-rpm-release.s3.brave.com/brave-core.asc || true
    sudo bash -c "cat > /etc/yum.repos.d/brave-browser.repo <<EOF
[brave-browser]
name=Brave Browser
baseurl=https://brave-browser-rpm-release.s3.brave.com/x86_64/
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/brave-core.asc
EOF"
  '

  run_with_spinner "Adding Google Chrome repo" bash -lc '
    sudo curl -fsSL https://dl.google.com/linux/linux_signing_key.pub -o /etc/pki/rpm-gpg/google-linux-signing-key.pub || true
    sudo bash -c "cat > /etc/yum.repos.d/google-chrome.repo <<EOF
[google-chrome]
name=google-chrome
baseurl=https://dl.google.com/linux/chrome/rpm/stable/\$basearch
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/google-linux-signing-key.pub
EOF"
  '

  run_with_spinner "Adding Microsoft Edge repo" bash -lc '
    sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc 2>/dev/null || true
    sudo bash -c "cat > /etc/yum.repos.d/microsoft-edge.repo <<EOF
[microsoft-edge]
name=Microsoft Edge
baseurl=https://packages.microsoft.com/yumrepos/edge
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF"
  '

  run_with_spinner "Adding AnyDesk repo (normalized)" normalize_anydesk_repo

  run_with_spinner "Refreshing package metadata (dnf makecache)" bash -lc 'sudo dnf makecache --refresh -y || true'
}

do_UPDATE() {
  run_with_spinner "DNF preflight (autorepair)" bash -lc 'sudo rpm --rebuilddb || true'
  run_with_spinner "Refreshing package metadata"        bash -lc 'sudo dnf makecache --refresh -y || true'
  run_with_spinner "Installing base tools"         bash -lc 'sudo dnf install -y curl wget gnupg ca-certificates dnf-plugins-core'
}
do_FLATPAK_ENABLE(){ run_with_spinner "Enabling Flatpak & Flathub" ensure_flatpak; }
do_REMOVE_TRANSMISSION(){ run_with_spinner "Removing Transmission & cleaning up" bash -lc 'sudo dnf remove -y transmission-cli transmission-gtk transmission-common || true; sudo dnf autoremove -y || true'; }

do_GPARTED() {
  run_with_spinner "Installing GParted (Flatpak or DNF fallback)" bash -lc '
    if ! command -v flatpak >/dev/null 2>&1; then sudo dnf install -y flatpak; fi
    if ! flatpak remote-list | grep -qi flathub; then sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo; fi
    if sudo -u "'"$REAL_USER"'" flatpak install -y flathub org.gnome.GParted; then exit 0; fi
    sudo dnf makecache --refresh -y
    if dnf list --available gparted >/dev/null 2>&1; then sudo dnf install -y gparted; else echo "gparted not in DNF repos"; exit 2; fi
  '
}

do_SYNAPTIC(){ run_with_spinner "Installing dnfdragora (GUI package manager)" bash -lc 'sudo dnf install -y dnfdragora || true'; }
do_CURL_WGET(){ run_with_spinner "Installing curl & wget (DNF)" bash -lc 'sudo dnf install -y curl wget'; }

do_GRUB_CUSTOMIZER(){
  run_with_spinner "Checking GRUB Customizer availability" bash -lc 'if ! dnf list --available grub-customizer >/dev/null 2>&1; then echo "grub-customizer not published for Fedora."; exit 2; fi'
  run_with_spinner "Installing GRUB Customizer (DNF)" bash -lc 'sudo dnf install -y grub-customizer'
}
do_BASIC_GRUB_TWEAKS(){
  run_with_spinner "Safely tweaking GRUB (backup + timeout=3)" bash -lc '
    CFG=/etc/default/grub; TS=$(date +%Y%m%d_%H%M%S)
    if [[ -f "$CFG" ]]; then sudo cp -a "$CFG" "$CFG.bak.$TS"; sudo sed -i "s/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=3/" "$CFG" || sudo bash -c "echo GRUB_TIMEOUT=3 >> $CFG"; fi
  '
  run_with_spinner "Updating GRUB config" bash -lc 'sudo grub2-mkconfig -o /boot/grub2/grub.cfg 2>/dev/null || sudo grub2-mkconfig -o /boot/efi/EFI/fedora/grub.cfg 2>/dev/null || true'
}

do_TEAMVIEWER(){
  run_with_spinner "Installing TeamViewer from system package" bash -lc '
    if rpm -q teamviewer >/dev/null 2>&1; then echo "teamviewer already installed"; exit 0; fi
    if dnf list --available teamviewer >/dev/null 2>&1; then sudo dnf install -y teamviewer; else echo "teamviewer not in current repos; skipping."; exit 2; fi
  '
}
do_ANYDESK(){ run_with_spinner "Ensuring AnyDesk repo" normalize_anydesk_repo; run_with_spinner "Installing AnyDesk" bash -lc 'sudo dnf makecache --refresh -y && sudo dnf install -y anydesk || true'; }
do_PIA(){
  run_with_spinner "Installing PIA (if installer found)" bash -lc '
    PIA=$(ls "'"$HOME"'"/Downloads/pia-linux*.run 2>/dev/null | head -n1 || true)
    [[ -z "$PIA" ]] && { echo "PIA installer not found in ~/Downloads"; exit 2; }
    chmod +x "$PIA"; "$PIA" || true
  '
}

# Flatpak-first with DNF fallback (apps)
do_FLAMESHOT(){ run_with_spinner "Installing Flameshot (Flatpak or DNF fallback)" bash -lc '
  if ! command -v flatpak >/dev/null 2>&1; then sudo dnf install -y flatpak; fi
  if ! flatpak remote-list | grep -qi flathub; then sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo; fi
  if sudo -u "'"$REAL_USER"'" flatpak install -y flathub org.flameshot.Flameshot; then exit 0; fi
  sudo dnf makecache --refresh -y
  if dnf list --available flameshot >/dev/null 2>&1; then sudo dnf install -y flameshot; else echo "flameshot not in DNF repos"; exit 2; fi
'; }

do_QBITTORRENT(){ run_with_spinner "Installing qBittorrent (Flatpak or DNF fallback)" bash -lc '
  if ! command -v flatpak >/dev/null 2>&1; then sudo dnf install -y flatpak; fi
  if ! flatpak remote-list | grep -qi flathub; then sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo; fi
  if sudo -u "'"$REAL_USER"'" flatpak install -y flathub org.qbittorrent.qBittorrent; then exit 0; fi
  sudo dnf makecache --refresh -y
  if dnf list --available qbittorrent >/dev/null 2>&1; then sudo dnf install -y qbittorrent; else echo "qbittorrent not in DNF repos"; exit 2; fi
'; }

do_VLC(){ run_with_spinner "Installing VLC (Flatpak or DNF fallback)" bash -lc '
  if ! command -v flatpak >/dev/null 2>&1; then sudo dnf install -y flatpak; fi
  if ! flatpak remote-list | grep -qi flathub; then sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo; fi
  if sudo -u "'"$REAL_USER"'" flatpak install -y flathub org.videolan.VLC; then exit 0; fi
  sudo dnf makecache --refresh -y
  if dnf list --available vlc >/dev/null 2>&1; then sudo dnf install -y vlc; else echo "vlc not in DNF repos"; exit 2; fi
'; }

do_OBS(){ run_with_spinner "Installing OBS Studio (Flatpak or DNF fallback)" bash -lc '
  if ! command -v flatpak >/dev/null 2>&1; then sudo dnf install -y flatpak; fi
  if ! flatpak remote-list | grep -qi flathub; then sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo; fi
  if sudo -u "'"$REAL_USER"'" flatpak install -y flathub com.obsproject.Studio; then exit 0; fi
  sudo dnf makecache --refresh -y
  if dnf list --available obs >/dev/null 2>&1 || dnf list --available obs-studio >/dev/null 2>&1; then sudo dnf install -y obs; else echo "obs-studio not in DNF repos"; exit 2; fi
'; }

do_GIMP(){ run_with_spinner "Installing GIMP (Flatpak or DNF fallback)" bash -lc '
  if ! command -v flatpak >/dev/null 2>&1; then sudo dnf install -y flatpak; fi
  if ! flatpak remote-list | grep -qi flathub; then sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo; fi
  if sudo -u "'"$REAL_USER"'" flatpak install -y flathub org.gimp.GIMP; then exit 0; fi
  sudo dnf makecache --refresh -y
  if dnf list --available gimp >/dev/null 2>&1; then sudo dnf install -y gimp; else echo "gimp not in DNF repos"; exit 2; fi
'; }

do_HANDBRAKE(){ run_with_spinner "Installing HandBrake (Flatpak or DNF fallback)" bash -lc '
  if ! command -v flatpak >/dev/null 2>&1; then sudo dnf install -y flatpak; fi
  if ! flatpak remote-list | grep -qi flathub; then sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo; fi
  if sudo -u "'"$REAL_USER"'" flatpak install -y flathub fr.handbrake.ghb; then exit 0; fi
  sudo dnf makecache --refresh -y
  if dnf list --available HandBrake-cli >/dev/null 2>&1 || dnf list --available HandBrake >/dev/null 2>&1 || dnf list --available handbrake >/dev/null 2>&1; then
    sudo dnf install -y HandBrake-cli HandBrake handbrake || sudo dnf install -y handbrake || true
  else
    echo "handbrake not in DNF repos"
    exit 2
  fi
'; }

do_STEAM(){ run_with_spinner "Installing Steam (Flatpak or DNF + RPMFusion fallback)" bash -lc '
  if ! command -v flatpak >/dev/null 2>&1; then sudo dnf install -y flatpak; fi
  if ! flatpak remote-list | grep -qi flathub; then sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo; fi
  if sudo -u "'"$REAL_USER"'" flatpak install -y flathub com.valvesoftware.Steam; then exit 0; fi
  sudo dnf makecache --refresh -y
  if dnf list --available steam >/dev/null 2>&1 || dnf list --available steam-installer >/dev/null 2>&1; then
    sudo dnf install -y steam || true
    exit 0
  fi
  # If not present, ensure RPM Fusion is enabled and try again
  sudo dnf install -y https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm || true
  sudo dnf makecache --refresh -y
  if dnf list --available steam >/dev/null 2>&1; then sudo dnf install -y steam || true; else echo "steam package not found in DNF repos"; exit 2; fi
'; }

do_CLAMAV(){ run_with_spinner "Installing ClamAV + daemon + GUI" bash -lc 'sudo dnf install -y clamav clamav-update clamtk || true; sudo systemctl enable --now clamav-freshclam.service || true; sudo freshclam || true'; }

# ---------- run selected ----------
echo
sep
echo "Starting selected tasks..."
sep
echo "Full log: $LOG_FILE"
sep
echo

total=${#TASK_IDS[@]}
for i in "${!TASK_IDS[@]}"; do
  id="${TASK_IDS[$i]}"; label="${TASK_LABELS[$i]}"
  idx=$((i+1)); printf "\n[%02d/%02d] %s\n" "$idx" "$total" "$label"

  if [[ "${WANT[$id]}" == "Y" ]]; then
    log "BEGIN: $label"
    set +e; "do_${id}"; rc=$?; set -e
    if   [[ $rc -eq 0 ]]; then RESULT_DESC+=("$label"); RESULT_STAT+=("OK"); log "OK: $label"
    elif [[ $rc -eq 2 ]]; then RESULT_DESC+=("$label"); RESULT_STAT+=("SKIPPED (not found/unsupported)"); log "SKIPPED: $label (missing/unsupported)"
    else RESULT_DESC+=("$label"); RESULT_STAT+=("FAIL"); log "FAIL: $label"; fi
    sep
  else
    RESULT_DESC+=("$label"); RESULT_STAT+=("SKIPPED"); log "SKIPPED: $label"
  fi
done

# ---------- summary ----------
echo
sep
echo "Summary:"
for i in "${!RESULT_DESC[@]}"; do printf " - %-42s : %s\n" "${RESULT_DESC[$i]}" "${RESULT_STAT[$i]}"; done
sep
echo "Done. Log saved to: $LOG_FILE"

