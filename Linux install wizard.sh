#!/usr/bin/env bash
# Mark's Terminal Post-Install — Flatpak-first with APT fallback — SAFE v10
# - Task #1 is forced: sudo apt update && sudo apt upgrade -y
# - Other tasks default=N and prompt
# - Fancy spinner + elapsed time; logs to ~/.local/share/postinstall/logs/...

set -euo pipefail
set +m
export DEBIAN_FRONTEND=noninteractive

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
  if ! command -v flatpak >/dev/null 2>&1; then sudo apt-get update -y && sudo apt-get install -y flatpak; fi
  if ! flatpak remote-list | grep -qi flathub; then sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo; fi
}
fp_user_install(){ ensure_flatpak; sudo -u "$REAL_USER" flatpak install -y flathub "$1"; }

normalize_anydesk_repo() {
  sudo rm -f /etc/apt/sources.list.d/anydesk*.list
  sudo sed -i '/deb .*anydesk\.com/d' /etc/apt/sources.list
  sudo install -d -m 0755 /usr/share/keyrings /etc/apt/sources.list.d
  if [[ ! -f /usr/share/keyrings/anydesk-archive-keyring.gpg ]]; then
    wget -qO- https://keys.anydesk.com/repos/DEB-GPG-KEY | sudo gpg --dearmor -o /usr/share/keyrings/anydesk-archive-keyring.gpg
  fi
  echo "deb [signed-by=/usr/share/keyrings/anydesk-archive-keyring.gpg] http://deb.anydesk.com/ all main" | sudo tee /etc/apt/sources.list.d/anydesk-stable.list >/dev/null
  sudo rm -f /usr/share/keyrings/anydesk.gpg
}
purge_teamviewer_repo() {
  sudo rm -f /etc/apt/sources.list.d/teamviewer*.list
  sudo rm -f /usr/share/keyrings/teamviewer-archive-keyring.gpg
  sudo rm -f /etc/apt/trusted.gpg.d/teamviewer*.gpg /etc/apt/trusted.gpg.d/teamviewer*.asc 2>/dev/null || true
  sudo apt-key del EF9DBDC73B7D1A07 2>/dev/null || true
}

# ---------- TASKS ----------
TASK_IDS=(
  UPDATE_UPGRADE           # FORCED Y
  ADD_ALL_REPOS
  UPDATE FLATPAK_ENABLE REMOVE_TRANSMISSION
  GPARTED SYNAPTIC CURL_WGET
  GRUB_CUSTOMIZER BASIC_GRUB_TWEAKS
  TEAMVIEWER ANYDESK PIA BRAVE CHROME EDGE
  FLAMESHOT QBITTORRENT VLC OBS GIMP HANDBRAKE STEAM
  CLAMAV
)
TASK_LABELS=(
  "System Update & Upgrade — runs: sudo apt update && sudo apt upgrade -y (FORCED)"
  "Add All Repositories (one-shot) — Universe/Multiverse, Flathub, Brave/Chrome/Edge, AnyDesk repo."
  "Update System — APT preflight & base tools."
  "Enable Flatpak — Adds Flathub and enables Flatpak."
  "Remove Transmission — Uninstalls Transmission."
  "Install GParted — Flatpak preferred, APT fallback."
  "Install Synaptic — Advanced APT GUI."
  "Install Curl/Wget (Extra) — Ensures latest versions."
  "Install GRUB Customizer — (Not in Ubuntu 24.04; will SKIP if unavailable)."
  "Basic GRUB Tweaks — Safe timeout tweak with backup + update-grub."
  "Install TeamViewer — Use system package only (no external repo)."
  "Install AnyDesk — Remote desktop (official repo)."
  "Install PIA VPN — Uses local .run if found in ~/Downloads."
  "Install Brave Browser — Privacy browser (official repo)."
  "Install Google Chrome — Official Google repo."
  "Install Microsoft Edge — Official Microsoft repo."
  "Install Flameshot — Flatpak preferred, APT fallback."
  "Install qBittorrent — Flatpak preferred, APT fallback."
  "Install VLC Media Player — Flatpak preferred, APT fallback."
  "Install OBS Studio — Flatpak preferred, APT fallback."
  "Install GIMP — Flatpak preferred, APT fallback."
  "Install HandBrake — Flatpak preferred, APT fallback."
  "Install Steam — Flatpak preferred, APT fallback."
  "Install ClamAV + GUI — clamav + daemon + clamtk."
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
do_UPDATE_UPGRADE(){ run_with_spinner "Running: sudo apt update && sudo apt upgrade -y" bash -lc 'sudo apt update && sudo apt upgrade -y'; }

do_ADD_ALL_REPOS() {
  run_with_spinner "Preparing repo tools (software-properties-common, curl, gpg)" bash -lc 'sudo apt-get update -y && sudo apt-get install -y software-properties-common curl gpg ca-certificates'
  run_with_spinner "Enabling Universe & Multiverse" bash -lc 'sudo add-apt-repository -y universe || true; sudo add-apt-repository -y multiverse || true'
  run_with_spinner "Removing TeamViewer vendor repo (system package only)" purge_teamviewer_repo
  run_with_spinner "Enabling Flatpak & Flathub" ensure_flatpak
  run_with_spinner "Adding Brave repo" bash -lc '
    sudo install -d -m 0755 /usr/share/keyrings /etc/apt/sources.list.d
    if [[ ! -f /usr/share/keyrings/brave-browser-archive-keyring.gpg ]]; then curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg; fi
    echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg arch=$(dpkg --print-architecture)] https://brave-browser-apt-release.s3.brave.com/ stable main" | sudo tee /etc/apt/sources.list.d/brave-browser-release.list >/dev/null
  '
  run_with_spinner "Adding Google Chrome repo" bash -lc '
    sudo install -d -m 0755 /usr/share/keyrings /etc/apt/sources.list.d
    if [[ ! -f /usr/share/keyrings/google-chrome-archive-keyring.gpg ]]; then curl -fsSL https://dl.google.com/linux/linux_signing_key.pub | sudo gpg --dearmor -o /usr/share/keyrings/google-chrome-archive-keyring.gpg; fi
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/google-chrome-archive-keyring.gpg] http://dl.google.com/linux/chrome/deb/ stable main" | sudo tee /etc/apt/sources.list.d/google-chrome.list >/dev/null
  '
  run_with_spinner "Adding Microsoft Edge repo" bash -lc '
    sudo install -d -m 0755 /usr/share/keyrings /etc/apt/sources.list.d
    if [[ ! -f /usr/share/keyrings/microsoft-archive-keyring.gpg ]]; then curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | sudo gpg --dearmor -o /usr/share/keyrings/microsoft-archive-keyring.gpg; fi
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/microsoft-archive-keyring.gpg] https://packages.microsoft.com/repos/edge stable main" | sudo tee /etc/apt/sources.list.d/microsoft-edge.list >/dev/null
  '
  run_with_spinner "Adding AnyDesk repo (normalized)" normalize_anydesk_repo
  run_with_spinner "Refreshing package lists (apt-get update)" bash -lc 'sudo apt-get update -y'
}

do_UPDATE() {
  run_with_spinner "APT preflight (configure/fix)" bash -lc 'sudo dpkg --configure -a || true; sudo apt-get -y -f install || true'
  run_with_spinner "Updating package lists"        bash -lc 'sudo apt-get update -y'
  run_with_spinner "Installing base tools"         bash -lc 'sudo apt-get install -y curl wget gnupg ca-certificates software-properties-common apt-transport-https'
}
do_FLATPAK_ENABLE(){ run_with_spinner "Enabling Flatpak & Flathub" ensure_flatpak; }
do_REMOVE_TRANSMISSION(){ run_with_spinner "Removing Transmission & cleaning up" bash -lc 'sudo apt-get remove --purge -y transmission transmission-gtk transmission-common transmission-qt || true; sudo apt-get autoremove -y || true'; }

do_GPARTED() {
  run_with_spinner "Installing GParted (Flatpak or APT fallback)" bash -lc '
    if ! command -v flatpak >/dev/null 2>&1; then sudo apt-get update -y && sudo apt-get install -y flatpak; fi
    if ! flatpak remote-list | grep -qi flathub; then sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo; fi
    if sudo -u "'"$REAL_USER"'" flatpak install -y flathub org.gnome.GParted; then exit 0; fi
    if sudo -u "'"$REAL_USER"'" flatpak install -y flathub org.gparted.GParted; then exit 0; fi
    sudo apt-get update -y; CAND=$(apt-cache policy gparted | awk "/Candidate:/ {print \$2}")
    [[ -z "$CAND" || "$CAND" == "(none)" ]] && { echo "gparted not in APT repos"; exit 2; }
    sudo apt-get install -y gparted
  '
}

do_SYNAPTIC(){ run_with_spinner "Installing Synaptic (APT)" bash -lc 'sudo apt-get install -y synaptic'; }
do_CURL_WGET(){ run_with_spinner "Installing curl & wget (APT)" bash -lc 'sudo apt-get install -y curl wget'; }

do_GRUB_CUSTOMIZER(){
  run_with_spinner "Checking GRUB Customizer availability" bash -lc 'if . /etc/os-release 2>/dev/null && [[ "${VERSION_CODENAME:-}" == "noble" ]]; then echo "grub-customizer not published for 24.04 (Noble)."; exit 2; fi'
  run_with_spinner "Installing GRUB Customizer (APT)" bash -lc 'sudo apt-get update -y && sudo apt-get install -y grub-customizer || { echo "grub-customizer not available in your repo"; exit 2; }'
}
do_BASIC_GRUB_TWEAKS(){
  run_with_spinner "Safely tweaking GRUB (backup + timeout=3)" bash -lc '
    CFG=/etc/default/grub; TS=$(date +%Y%m%d_%H%M%S); sudo cp -a "$CFG" "$CFG.bak.$TS"
    sudo sed -i "s/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=3/" "$CFG" || echo "GRUB_TIMEOUT=3" | sudo tee -a "$CFG" >/dev/null
    if ! grep -q "^GRUB_DEFAULT=" "$CFG"; then echo "GRUB_DEFAULT=0" | sudo tee -a "$CFG" >/dev/null; fi
  '
  run_with_spinner "Updating GRUB config" bash -lc 'sudo update-grub || sudo grub-mkconfig -o /boot/grub/grub.cfg'
}

do_TEAMVIEWER(){
  run_with_spinner "Installing TeamViewer from system package" bash -lc '
    if dpkg -s teamviewer >/dev/null 2>&1; then echo "teamviewer already installed"; exit 0; fi
    CAND=$(apt-cache policy teamviewer | awk "/Candidate:/ {print \$2}")
    [[ -z "$CAND" || "$CAND" == "(none)" ]] && { echo "teamviewer not in current system repos; skipping."; exit 2; }
    sudo apt-get update -y && sudo apt-get install -y teamviewer
  '
}
do_ANYDESK(){ run_with_spinner "Ensuring AnyDesk repo" normalize_anydesk_repo; run_with_spinner "Installing AnyDesk" bash -lc 'sudo apt-get update -y && sudo apt-get install -y anydesk'; }
do_PIA(){
  run_with_spinner "Installing PIA (if installer found)" bash -lc '
    PIA=$(ls "'"$HOME"'"/Downloads/pia-linux*.run 2>/dev/null | head -n1 || true)
    [[ -z "$PIA" ]] && { echo "PIA installer not found in ~/Downloads"; exit 2; }
    chmod +x "$PIA"; "$PIA" || true
  '
}

# Flatpak-first with APT fallback (apps)
do_FLAMESHOT(){ run_with_spinner "Installing Flameshot (Flatpak or APT fallback)" bash -lc '
  if ! command -v flatpak >/dev/null 2>&1; then sudo apt-get update -y && sudo apt-get install -y flatpak; fi
  if ! flatpak remote-list | grep -qi flathub; then sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo; fi
  if sudo -u "'"$REAL_USER"'" flatpak install -y flathub org.flameshot.Flameshot; then exit 0; fi
  sudo apt-get update -y; CAND=$(apt-cache policy flameshot | awk "/Candidate:/ {print \$2}")
  [[ -z "$CAND" || "$CAND" == "(none)" ]] && { echo "flameshot not in APT repos"; exit 2; }
  sudo apt-get install -y flameshot
'; }

do_QBITTORRENT(){ run_with_spinner "Installing qBittorrent (Flatpak or APT fallback)" bash -lc '
  if ! command -v flatpak >/dev/null 2>&1; then sudo apt-get update -y && sudo apt-get install -y flatpak; fi
  if ! flatpak remote-list | grep -qi flathub; then sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo; fi
  if sudo -u "'"$REAL_USER"'" flatpak install -y flathub org.qbittorrent.qBittorrent; then exit 0; fi
  sudo apt-get update -y; CAND=$(apt-cache policy qbittorrent | awk "/Candidate:/ {print \$2}")
  [[ -z "$CAND" || "$CAND" == "(none)" ]] && { echo "qbittorrent not in APT repos"; exit 2; }
  sudo apt-get install -y qbittorrent
'; }

do_VLC(){ run_with_spinner "Installing VLC (Flatpak or APT fallback)" bash -lc '
  if ! command -v flatpak >/dev/null 2>&1; then sudo apt-get update -y && sudo apt-get install -y flatpak; fi
  if ! flatpak remote-list | grep -qi flathub; then sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo; fi
  if sudo -u "'"$REAL_USER"'" flatpak install -y flathub org.videolan.VLC; then exit 0; fi
  sudo apt-get update -y; CAND=$(apt-cache policy vlc | awk "/Candidate:/ {print \$2}")
  [[ -z "$CAND" || "$CAND" == "(none)" ]] && { echo "vlc not in APT repos"; exit 2; }
  sudo apt-get install -y vlc
'; }

do_OBS(){ run_with_spinner "Installing OBS Studio (Flatpak or APT fallback)" bash -lc '
  if ! command -v flatpak >/dev/null 2>&1; then sudo apt-get update -y && sudo apt-get install -y flatpak; fi
  if ! flatpak remote-list | grep -qi flathub; then sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo; fi
  if sudo -u "'"$REAL_USER"'" flatpak install -y flathub com.obsproject.Studio; then exit 0; fi
  sudo apt-get update -y; CAND=$(apt-cache policy obs-studio | awk "/Candidate:/ {print \$2}")
  [[ -z "$CAND" || "$CAND" == "(none)" ]] && { echo "obs-studio not in APT repos"; exit 2; }
  sudo apt-get install -y obs-studio
'; }

do_GIMP(){ run_with_spinner "Installing GIMP (Flatpak or APT fallback)" bash -lc '
  if ! command -v flatpak >/dev/null 2>&1; then sudo apt-get update -y && sudo apt-get install -y flatpak; fi
  if ! flatpak remote-list | grep -qi flathub; then sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo; fi
  if sudo -u "'"$REAL_USER"'" flatpak install -y flathub org.gimp.GIMP; then exit 0; fi
  sudo apt-get update -y; CAND=$(apt-cache policy gimp | awk "/Candidate:/ {print \$2}")
  [[ -z "$CAND" || "$CAND" == "(none)" ]] && { echo "gimp not in APT repos"; exit 2; }
  sudo apt-get install -y gimp
'; }

do_HANDBRAKE(){ run_with_spinner "Installing HandBrake (Flatpak or APT fallback)" bash -lc '
  if ! command -v flatpak >/dev/null 2>&1; then sudo apt-get update -y && sudo apt-get install -y flatpak; fi
  if ! flatpak remote-list | grep -qi flathub; then sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo; fi
  if sudo -u "'"$REAL_USER"'" flatpak install -y flathub fr.handbrake.ghb; then exit 0; fi
  sudo apt-get update -y; CAND=$(apt-cache policy handbrake | awk "/Candidate:/ {print \$2}")
  if [[ -z "$CAND" || "$CAND" == "(none)" ]]; then echo "handbrake not in APT repos"; exit 2; fi
  sudo apt-get install -y handbrake handbrake-cli || sudo apt-get install -y handbrake
'; }

do_STEAM(){ run_with_spinner "Installing Steam (Flatpak or APT fallback)" bash -lc '
  if ! command -v flatpak >/dev/null 2>&1; then sudo apt-get update -y && sudo apt-get install -y flatpak; fi
  if ! flatpak remote-list | grep -qi flathub; then sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo; fi
  if sudo -u "'"$REAL_USER"'" flatpak install -y flathub com.valvesoftware.Steam; then exit 0; fi
  sudo apt-get update -y
  for pkg in steam-installer steam; do
    CAND=$(apt-cache policy "$pkg" | awk "/Candidate:/ {print \$2}")
    if [[ -n "$CAND" && "$CAND" != "(none)" ]]; then sudo apt-get install -y "$pkg"; exit 0; fi
  done
  echo "steam package not found in APT repos"; exit 2
'; }

do_CLAMAV(){ run_with_spinner "Installing ClamAV + daemon + GUI" bash -lc 'sudo apt-get update -y && sudo apt-get install -y clamav clamav-daemon clamtk; sudo systemctl enable --now clamav-freshclam.service || true; sudo freshclam || true'; }

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

