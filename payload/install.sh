#!/bin/bash
set -euo pipefail

timestamp() { date "+%Y-%m-%d %H:%M:%S"; }
log() { echo "[$(timestamp)] $*"; }

section() {
  echo
  echo "=================================================="
  echo "== $*"
  echo "=================================================="
  echo
}

LOG_DIR="/var/log/frostearch"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/install-$(date +%F_%H-%M-%S).log"

if [[ -w /dev/tty1 ]]; then
  exec > >(tee -a "$LOG_FILE" /dev/tty1) 2>&1
else
  exec > >(tee -a "$LOG_FILE") 2>&1
fi

log "Running installer"
log "Logging to $LOG_FILE"

TEMP_SUDOERS=""
SUDO_KEEPALIVE_PID=""

on_error() {
  local rc=$?
  echo
  echo "[$(timestamp)] ❌ Installer failed (exit $rc)."
  echo "Check log: $LOG_FILE"
  exit "$rc"
}

cleanup() {
  if [[ -n "$SUDO_KEEPALIVE_PID" ]]; then
    kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    wait "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
  fi

  if [[ -n "$TEMP_SUDOERS" ]]; then
    if [[ "$(id -u)" -eq 0 ]]; then
      rm -f "$TEMP_SUDOERS" 2>/dev/null || true
    else
      sudo rm -f "$TEMP_SUDOERS" 2>/dev/null || true
    fi
  fi
}

trap on_error ERR
trap cleanup EXIT INT TERM

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=/dev/null
source "$REPO_ROOT/lib/common.sh"

MODE="${MODE:-desktop}"
ARCH_USER="${ARCH_USER:-}"

detect_user() {
  awk -F: '$3 >= 1000 && $3 < 65534 {print $1; exit}' /etc/passwd
}

if [[ -z "$ARCH_USER" ]]; then
  ARCH_USER="$(detect_user || true)"
fi

if [[ -z "$ARCH_USER" ]]; then
  log "ERROR: Could not auto-detect a non-root user (UID >= 1000)."
  log "Create a user during archinstall, or run with ARCH_USER=username."
  exit 1
fi

require_user "$ARCH_USER"

case "$MODE" in
  desktop) MODE_FILE="$REPO_ROOT/modes/desktop.sh" ;;
  server)  MODE_FILE="$REPO_ROOT/modes/server.sh" ;;
  *)
    log "ERROR: MODE must be 'desktop' or 'server' (got: $MODE)"
    exit 1
    ;;
esac

if [[ ! -f "$MODE_FILE" ]]; then
  log "Missing mode file: $MODE_FILE"
  exit 1
fi

log "Starting installer"
log "Mode: $MODE"
log "User: $ARCH_USER"

TEMP_SUDOERS="/etc/sudoers.d/99-installer-nopasswd-$ARCH_USER"

if [[ "$(id -u)" -ne 0 ]]; then
  sudo -v

  (
    while true; do
      sleep 60
      sudo -n true >/dev/null 2>&1 || exit 0
    done
  ) &
  SUDO_KEEPALIVE_PID="$!"
fi

write_sudoers_rule() {
  local content
  content="$ARCH_USER ALL=(ALL) NOPASSWD: /usr/bin/pacman"

  if [[ "$(id -u)" -eq 0 ]]; then
    printf '%s\n' "$content" >"$TEMP_SUDOERS"
    chmod 440 "$TEMP_SUDOERS"
    visudo -cf "$TEMP_SUDOERS"
  else
    printf '%s\n' "$content" | sudo tee "$TEMP_SUDOERS" >/dev/null
    sudo chmod 440 "$TEMP_SUDOERS"
    sudo visudo -cf "$TEMP_SUDOERS"
  fi
}

write_sudoers_rule

# shellcheck source=/dev/null
source "$MODE_FILE"

if ! declare -p FLATPAK_PACKAGES >/dev/null 2>&1; then
  FLATPAK_PACKAGES=()
fi

init_paths "$REPO_ROOT" "$ARCH_USER"

FIRST_BOOT_DIALOG_TITLE="${FIRST_BOOT_DIALOG_TITLE:-FrosteArch}"
FIRST_BOOT_DIALOG_MARKDOWN_REL="${FIRST_BOOT_DIALOG_MARKDOWN_REL:-shared/first-boot-message.md}"
FIRST_BOOT_DIALOG_MARKDOWN_FILE="$REPO_ROOT/$FIRST_BOOT_DIALOG_MARKDOWN_REL"
FIRST_BOOT_DIALOG_RENDERER_FILE="${FIRST_BOOT_DIALOG_RENDERER_FILE:-$REPO_ROOT/shared/render-first-boot-dialog.py}"
THEME_PROFILES_DIR="${THEME_PROFILES_DIR:-$REPO_ROOT/themes}"
THEME_METADATA_FILE="${THEME_METADATA_FILE:-$REPO_ROOT/shared/theme-profiles.json}"
THEME_SWITCHER_FILE="${THEME_SWITCHER_FILE:-$REPO_ROOT/shared/frostearch-theme-switcher.sh}"
THEME_METADATA_HELPER_FILE="${THEME_METADATA_HELPER_FILE:-$REPO_ROOT/shared/theme-metadata-tool.py}"
THEME_WALLPAPERS_DIR="${THEME_WALLPAPERS_DIR:-$REPO_ROOT/themes}"
THEME_DEFAULT_ID="${THEME_DEFAULT_ID:-$MODE_NAME}"
KARA_GIT_URL="${KARA_GIT_URL:-https://github.com/dhruv8sh/kara.git}"
KARA_GIT_REF="${KARA_GIT_REF:-v1.0.0}"
SETUP_AUDIO_PRODUCTION="${SETUP_AUDIO_PRODUCTION:-false}"

log "Theme profiles source: $THEME_PROFILES_DIR"
log "Theme wallpapers source: $THEME_WALLPAPERS_DIR"

section "System setup"
system_update
enable_multilib
ensure_git

section "Installing official packages"
install_official_packages OFFICIAL_PACKAGES
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo || true

section "Installing yay"
install_yay "$ARCH_USER"

section "Installing AUR packages"
install_aur_packages "$ARCH_USER" AUR_PACKAGES

section "Installing Flatpak packages"
install_flatpak_packages FLATPAK_PACKAGES

section "Configuring services and firewall"
enable_services SERVICES_ENABLE
mask_services SERVICES_MASK
configure_firewall FIREWALL_RULES

section "Configuring greetd and PAM"
configure_greetd
configure_pam_kwallet

section "Applying dotfiles"
apply_dotfiles "$ARCH_USER" "$DOTFILES_DIR"

if [[ "${SETUP_AUDIO_PRODUCTION:-false}" == "true" ]]; then
  section "Setting up audio production environment"
  install_audio_base "$ARCH_USER" "$REPO_ROOT"
fi

section "Installing Kara pager"
install_kara_pager_from_source "$ARCH_USER" "$KARA_GIT_URL" "$KARA_GIT_REF"

section "Installing theme switcher"
install_theme_switcher_required "$ARCH_USER" "$THEME_PROFILES_DIR" "$THEME_METADATA_FILE" "$THEME_SWITCHER_FILE" "$THEME_WALLPAPERS_DIR" "$THEME_METADATA_HELPER_FILE"

section "Applying default theme"
apply_theme_via_switcher_required "$ARCH_USER" "$THEME_DEFAULT_ID"

# KWallet must be enabled after konsave has restored kdeglobals so it is
# not clobbered when the profile overwrites that file.
set_wallet_enabled "$ARCH_USER"

section "Configuring first-login experience"
disable_kde_welcome_popup "$ARCH_USER"
install_first_boot_dialog_autostart_required \
  "$ARCH_USER" "$FIRST_BOOT_DIALOG_MARKDOWN_FILE" "$FIRST_BOOT_DIALOG_TITLE" "$FIRST_BOOT_DIALOG_RENDERER_FILE"

log "Installation complete."
log "Rebooting in 3 seconds..."
sleep 3
reboot || true