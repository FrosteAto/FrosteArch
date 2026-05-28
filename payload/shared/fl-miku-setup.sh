#!/bin/bash
# fl-miku-setup: initialise the fl-miku Wine prefix for FL Studio + Piapro + Miku.
#
# Run this once from a live KDE Plasma session after the main FrosteArch install.
# Safe to re-run (idempotent where possible).
#
# What this script does:
#   1. Creates the dedicated Wine prefix at FL_MIKU_PREFIX
#   2. Sets Windows version to Windows 10
#   3. Installs winetricks components required by FL Studio 25 (allfonts, webview2)
#   4. Disables Wine file-type hijacking in this prefix
#   5. Creates VST2/VST3 plugin directories inside the prefix
#   6. Downloads the FL Studio installer from Image-Line and runs it
#   7. Extracts the SonicWire Miku V4X zip (requires p7zip) if present
#   8. Runs the three Miku installers in order:
#        Crypton Software Installer (64bit) — Piapro Studio VST
#        MIKU V4X Installer                — V4X voicebank
#        MIKU V4 English Installer         — English voicebank (optional)
#   9. Writes wrapper launcher scripts to ~/.local/bin
#  10. Writes .desktop entries so FL Studio / winecfg / kill appear in KRunner
#
# Before running:
#   - Place the SonicWire Miku V4X zip in: ~/Installers/Audio/MikuV4X/
#     (zip64 format — must be extracted with 7z, which this script handles)
#
# After this script finishes, you must manually:
#   - Activate FL Studio (sign in to your Image-Line account)
#   - In FL Studio: Options → Manage plugins → add C:\VST2 and C:\VST3
#   - Run a plugin scan to detect Piapro Studio

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration — override via environment variables if needed
# ---------------------------------------------------------------------------
FL_MIKU_PREFIX="${FL_MIKU_PREFIX:-$HOME/.local/share/wineprefixes/fl-miku}"

# The Image-Line download server provides a stable versioned URL.
# If this URL is stale, download the installer manually from:
#   https://www.image-line.com/fl-studio/download
# and save it to FL_INSTALLER_FILE.
FL_INSTALLER_URL="${FL_INSTALLER_URL:-https://install.image-line.com/flstudio/flstudio_win64_25.2.5.5319.exe}"
FL_INSTALLER_DIR="${FL_INSTALLER_DIR:-$HOME/Installers/Audio/FL}"
FL_INSTALLER_FILE="$FL_INSTALLER_DIR/flstudio_installer.exe"

# Directory where the SonicWire Miku V4X zip (or its extracted contents) should be placed.
# The zip is zip64 format — this script will extract it automatically using 7z (p7zip).
MIKU_INSTALLER_DIR="${MIKU_INSTALLER_DIR:-$HOME/Installers/Audio/MikuV4X}"

BIN_DIR="$HOME/.local/bin"
APP_DIR="$HOME/.local/share/applications"
STATE_DIR="$FL_MIKU_PREFIX/.fl-miku-setup-state"
INSTALL_COMPONENTS=()  # empty = full setup; populated by select_install_mode

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log()  { echo "[fl-miku-setup] $*"; }
die()  { log "ERROR: $*" >&2; exit 1; }
hr()   { echo "──────────────────────────────────────────────────────────────"; }
step() { echo; hr; log "$*"; hr; echo; }

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
require_display() {
  if [[ -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" ]]; then
    die "No graphical session detected. Run this script from within KDE Plasma."
  fi
}

require_tools() {
  local missing=()
  command -v wine       >/dev/null 2>&1 || missing+=(wine)
  command -v winetricks >/dev/null 2>&1 || missing+=(winetricks)
  command -v wineserver >/dev/null 2>&1 || missing+=(wineserver)
  if [[ "${#missing[@]}" -gt 0 ]]; then
    die "Missing required tools: ${missing[*]}. Install them with: sudo pacman -S ${missing[*]}"
  fi
}

winetricks_has_verb() {
  local verb="$1"
  WINEPREFIX="$FL_MIKU_PREFIX" winetricks list-all 2>/dev/null | awk '{print $1}' | grep -Fxq "$verb"
}

winetricks_has_installed_verb() {
  local verb="$1"
  WINEPREFIX="$FL_MIKU_PREFIX" winetricks list-installed 2>/dev/null | awk '{print $1}' | grep -Fxq "$verb"
}

run_wine_jp() {
  # No LANG/LC_ALL override here — those are host-shell locale vars that do NOT
  # affect Wine's internal Windows environment and cause '\' → '¥' rendering in
  # the terminal.  Japanese codepage and locale are set in the prefix registry
  # by configure_font_substitutes instead.
  WINEPREFIX="$FL_MIKU_PREFIX" WINEDEBUG=-all "$@"
}

# Returns 0 if the given component should be installed in the current run.
# An empty INSTALL_COMPONENTS array means "full setup" (install everything).
should_install() {
  local component="$1"
  if [[ "${#INSTALL_COMPONENTS[@]}" -eq 0 ]]; then
    return 0
  fi
  local c
  for c in "${INSTALL_COMPONENTS[@]}"; do
    [[ "$c" == "$component" ]] && return 0
  done
  return 1
}

select_install_mode() {
  echo
  log "What would you like to install?"
  echo
  echo "  1) Full setup — all components not yet installed  [default]"
  echo "  2) FL Studio only"
  echo "  3) Piapro Studio  (Mutant VSTi + Piapro Studio VST)"
  echo "  4) Hatsune Miku V4X voicebank"
  echo "  5) Hatsune Miku V4 English voicebank"
  echo "  6) All Miku components  (Piapro + V4X + V4 English)"
  echo "  7) Recreate launcher scripts and desktop entries only"
  echo "  8) Activate voicebank licences  (find and run Crypton/Vocaloid license tools)"
  echo
  local choice
  while true; do
    read -r -p "Select an option [1]: " choice
    choice="${choice:-1}"
    case "$choice" in
      1)
        log "Running full setup."
        INSTALL_COMPONENTS=()
        return 0
        ;;
      2)
        log "Will install: FL Studio"
        INSTALL_COMPONENTS=(fl)
        return 0
        ;;
      3)
        log "Will install: Piapro Studio"
        INSTALL_COMPONENTS=(piapro)
        return 0
        ;;
      4)
        log "Will install: Hatsune Miku V4X voicebank"
        INSTALL_COMPONENTS=(miku_v4x)
        return 0
        ;;
      5)
        log "Will install: Hatsune Miku V4 English voicebank"
        INSTALL_COMPONENTS=(miku_v4_en)
        return 0
        ;;
      6)
        log "Will install: All Miku components"
        INSTALL_COMPONENTS=(piapro miku_v4x miku_v4_en)
        return 0
        ;;
      7)
        log "Will recreate: Launcher scripts and desktop entries"
        INSTALL_COMPONENTS=(launchers)
        return 0
        ;;
      8)
        log "Will run: Voicebank licence activation"
        INSTALL_COMPONENTS=(activate)
        return 0
        ;;
    esac
    echo "Please enter a number from 1 to 8."
  done
}

wait_for_wine_exit() {
  local context="$1"
  local wait_seconds="${2:-2}"

  if command -v timeout >/dev/null 2>&1; then
    if WINEPREFIX="$FL_MIKU_PREFIX" timeout "${wait_seconds}s" wineserver -w >/dev/null 2>&1; then
      return 0
    fi
    log "WARNING: Timed out waiting for Wine to exit after $context. Forcing shutdown."
  else
    log "WARNING: 'timeout' not found; forcing Wine shutdown after $context."
  fi

  WINEPREFIX="$FL_MIKU_PREFIX" wineserver -k >/dev/null 2>&1 || true
}

prefix_has_path() {
  local pattern="$1"
  find "$FL_MIKU_PREFIX/drive_c" -path "$FL_MIKU_PREFIX/drive_c" -prune -o -ipath "$pattern" -print 2>/dev/null | grep -q .
}

piapro_installed() {
  find "$FL_MIKU_PREFIX/drive_c" \( -iname 'VDAWVSTi*.dll' -o -iname 'VDAWVSTi*.vst3' \) 2>/dev/null | grep -q .
}

miku_v4x_installed() {
  prefix_has_path "*Crypton*Hatsune Miku V4X*" || prefix_has_path "*Hatsune Miku V4X*"
}

miku_v4_english_installed() {
  prefix_has_path "*Crypton*Hatsune Miku V4 English*" || prefix_has_path "*Miku V4 English*"
}

step_state_path() {
  local name="$1"
  echo "$STATE_DIR/$name.done"
}

step_done() {
  local name="$1"
  [[ -f "$(step_state_path "$name")" ]]
}

mark_step_done() {
  local name="$1"
  mkdir -p "$STATE_DIR"
  : > "$(step_state_path "$name")"
}

remove_if_exists() {
  local path="$1"
  if [[ -e "$path" ]]; then
    rm -rf "$path"
  fi
}

wipe_everything() {
  step "Wiping Wine prefix and local launchers"
  log "Removing Wine prefix: $FL_MIKU_PREFIX"
  WINEPREFIX="$FL_MIKU_PREFIX" wineserver -k 2>/dev/null || true
  rm -rf "$FL_MIKU_PREFIX"

  log "Removing launcher scripts: $BIN_DIR/fl-studio, $BIN_DIR/fl-miku-winecfg, $BIN_DIR/fl-miku-kill, $BIN_DIR/fl-miku-run-exe"
  remove_if_exists "$BIN_DIR/fl-studio"
  remove_if_exists "$BIN_DIR/fl-miku-winecfg"
  remove_if_exists "$BIN_DIR/fl-miku-kill"
  remove_if_exists "$BIN_DIR/fl-miku-run-exe"

  log "Removing desktop entries: $APP_DIR/fl-studio.desktop, $APP_DIR/fl-miku-winecfg.desktop, $APP_DIR/fl-miku-kill.desktop"
  remove_if_exists "$APP_DIR/fl-studio.desktop"
  remove_if_exists "$APP_DIR/fl-miku-winecfg.desktop"
  remove_if_exists "$APP_DIR/fl-miku-kill.desktop"

  log "Removing setup state directory: $STATE_DIR"
  rm -rf "$STATE_DIR"

  log "Keeping downloaded installers in place so setup can be restarted quickly."
  log "Full cleanup complete."
}

prompt_startup_choice_existing() {
  echo "  1) Continue using the existing prefix"
  echo "  2) Wipe everything and start from scratch"
  echo "  3) Quit"

  local choice
  while true; do
    read -r -p "Select an option: " choice
    case "$choice" in
      1)
        log "Continuing with the existing prefix."
        return 0
        ;;
      2)
        wipe_everything
        return 0
        ;;
      3)
        log "Exiting without making changes."
        exit 0
        ;;
    esac
    echo "Please enter one of the listed numbers."
  done
}

prompt_startup_choice() {
  echo
  log "What do you want to do?"
  if [[ -e "$FL_MIKU_PREFIX" ]]; then
    prompt_startup_choice_existing
  else
    echo "  1) Start setup"
    echo "  2) Quit"
    local choice
    while true; do
      read -r -p "Select an option: " choice
      case "$choice" in
        1)
          log "Starting setup from scratch."
          return 0
          ;;
        2)
          log "Exiting without making changes."
          exit 0
          ;;
      esac
      echo "Please enter one of the listed numbers."
    done
  fi
}

# ---------------------------------------------------------------------------
# Prefix initialisation
# ---------------------------------------------------------------------------
init_prefix() {
  if [[ -f "$FL_MIKU_PREFIX/system.reg" || -f "$FL_MIKU_PREFIX/user.reg" ]]; then
    log "Wine prefix already exists — skipping initialisation."
    mark_step_done prefix_init
    return 0
  fi

  step "Initialising Wine prefix"
  log "Path: $FL_MIKU_PREFIX"
  mkdir -p "$FL_MIKU_PREFIX"
  # wine-mono and wine-gecko are installed as system packages, so Wine will
  # not prompt to download them during initialisation.
  WINEPREFIX="$FL_MIKU_PREFIX" WINEDEBUG=-all wineboot -u
  log "Prefix ready."
  mark_step_done prefix_init
}

set_windows_version() {
  if winetricks_has_installed_verb win10 || step_done win10; then
    log "Windows version already set to Windows 10 — skipping."
    mark_step_done win10
    return 0
  fi

  step "Setting Windows version to Windows 10"
  WINEPREFIX="$FL_MIKU_PREFIX" WINEDEBUG=-all winetricks -q win10
  mark_step_done win10
}

# ---------------------------------------------------------------------------
# Winetricks dependencies (FL Studio 25 requirements)
# ---------------------------------------------------------------------------
install_winetricks_deps() {
  step "Installing winetricks components"
  if winetricks_has_installed_verb allfonts; then
    log "allfonts already installed — skipping."
  else
    log "Component: allfonts (Microsoft font set — may take a few minutes)"
    WINEPREFIX="$FL_MIKU_PREFIX" winetricks -q allfonts
    mark_step_done allfonts
  fi

  if winetricks_has_installed_verb webview2; then
    log "webview2 already installed — skipping."
  elif winetricks_has_verb webview2; then
    log "Component: webview2 (Microsoft Edge WebView2 — required by FL Studio 25)"
    if WINEPREFIX="$FL_MIKU_PREFIX" winetricks -q webview2; then
      log "webview2 installed."
      mark_step_done webview2
    else
      log "WARNING: webview2 installation failed. Continuing setup."
      log "Try again later with: WINEPREFIX=\"$FL_MIKU_PREFIX\" winetricks -q webview2"
    fi
  else
    log "WARNING: Your winetricks build does not provide the 'webview2' verb. Continuing setup."
    log "Update winetricks and then run: WINEPREFIX=\"$FL_MIKU_PREFIX\" winetricks -q webview2"
  fi

  if winetricks_has_installed_verb corefonts; then
    log "corefonts already installed — skipping."
  elif winetricks_has_verb corefonts; then
    log "Component: corefonts (Microsoft core fonts for normal Latin text rendering)"
    if WINEPREFIX="$FL_MIKU_PREFIX" winetricks -q corefonts; then
      log "corefonts installed."
      mark_step_done corefonts
    else
      log "WARNING: corefonts installation failed. Continuing setup."
    fi
  fi

  if winetricks_has_installed_verb cjkfonts; then
    log "cjkfonts already installed — skipping."
  elif winetricks_has_verb cjkfonts; then
    log "Component: cjkfonts (CJK fonts for Japanese text rendering)"
    if WINEPREFIX="$FL_MIKU_PREFIX" winetricks -q cjkfonts; then
      log "cjkfonts installed."
      mark_step_done cjkfonts
    else
      log "WARNING: cjkfonts installation failed. Continuing setup."
    fi
  fi

  if winetricks_has_installed_verb meiryo; then
    log "meiryo already installed — skipping."
  elif winetricks_has_verb meiryo; then
    log "Component: meiryo (Japanese UI font used by many installers)"
    if WINEPREFIX="$FL_MIKU_PREFIX" winetricks -q meiryo; then
      log "meiryo installed."
      mark_step_done meiryo
    else
      log "WARNING: meiryo installation failed. Continuing setup."
    fi
  fi

  if winetricks_has_installed_verb fontfix; then
    log "fontfix already installed — skipping."
  elif winetricks_has_verb fontfix; then
    log "Component: fontfix (improves Wine font fallback and rendering)"
    if WINEPREFIX="$FL_MIKU_PREFIX" winetricks -q fontfix; then
      log "fontfix installed."
      mark_step_done fontfix
    else
      log "WARNING: fontfix installation failed. Continuing setup."
    fi
  fi

  if winetricks_has_installed_verb takao; then
    log "takao already installed — skipping."
  elif winetricks_has_verb takao; then
    log "Component: takao (additional Japanese gothic/mincho fallback fonts)"
    if WINEPREFIX="$FL_MIKU_PREFIX" winetricks -q takao; then
      log "takao installed."
      mark_step_done takao
    else
      log "WARNING: takao installation failed. Continuing setup."
    fi
  fi
}

configure_font_substitutes() {
  # State key v3 — forces re-run on prefixes with earlier versions.
  # v3 changes: targets Noto Sans CJK JP (guaranteed on Arch via noto-fonts-cjk)
  # instead of Meiryo (winetricks meiryo often fails to download), and adds
  # MS UI Gothic / MS PGothic which many Japanese MSI dialog templates request.
  if step_done font_substitutes_v3; then
    log "Wine font substitution rules already configured (v3) — skipping."
    return 0
  fi

  step "Configuring Wine Japanese locale and font substitutions"

  # ── 1. Set ANSI/OEM codepage to 932 (Shift-JIS) ────────────────────────────
  # Without ACP=932, Win32 control text encoded as Shift-JIS bytes is decoded
  # with the default Western (1252) codepage, producing squares regardless of
  # which fonts are installed.  This is the primary cause of tofu on buttons.
  WINEPREFIX="$FL_MIKU_PREFIX" WINEDEBUG=-all \
    wine reg add "HKEY_LOCAL_MACHINE\\SYSTEM\\CurrentControlSet\\Control\\Nls\\CodePage" \
      /v "ACP"   /t REG_SZ /d "932" /f >/dev/null 2>&1 || true
  WINEPREFIX="$FL_MIKU_PREFIX" WINEDEBUG=-all \
    wine reg add "HKEY_LOCAL_MACHINE\\SYSTEM\\CurrentControlSet\\Control\\Nls\\CodePage" \
      /v "OEMCP" /t REG_SZ /d "932" /f >/dev/null 2>&1 || true
  WINEPREFIX="$FL_MIKU_PREFIX" WINEDEBUG=-all \
    wine reg add "HKEY_LOCAL_MACHINE\\SYSTEM\\CurrentControlSet\\Control\\Nls\\CodePage" \
      /v "MACCP" /t REG_SZ /d "10001" /f >/dev/null 2>&1 || true

  # ── 2. Set Windows locale to Japanese (0x0411) ──────────────────────────────
  WINEPREFIX="$FL_MIKU_PREFIX" WINEDEBUG=-all \
    wine reg add "HKEY_LOCAL_MACHINE\\SYSTEM\\CurrentControlSet\\Control\\Nls\\Language" \
      /v "Default"         /t REG_SZ /d "0411" /f >/dev/null 2>&1 || true
  WINEPREFIX="$FL_MIKU_PREFIX" WINEDEBUG=-all \
    wine reg add "HKEY_LOCAL_MACHINE\\SYSTEM\\CurrentControlSet\\Control\\Nls\\Language" \
      /v "InstallLanguage" /t REG_SZ /d "0411" /f >/dev/null 2>&1 || true
  WINEPREFIX="$FL_MIKU_PREFIX" WINEDEBUG=-all \
    wine reg add "HKEY_USERS\\.Default\\Control Panel\\International" \
      /v "Locale"    /t REG_SZ /d "00000411" /f >/dev/null 2>&1 || true
  WINEPREFIX="$FL_MIKU_PREFIX" WINEDEBUG=-all \
    wine reg add "HKEY_USERS\\.Default\\Control Panel\\International" \
      /v "sLanguage" /t REG_SZ /d "JPN"       /f >/dev/null 2>&1 || true
  WINEPREFIX="$FL_MIKU_PREFIX" WINEDEBUG=-all \
    wine reg add "HKEY_USERS\\.Default\\Control Panel\\International" \
      /v "iCountry"  /t REG_SZ /d "81"        /f >/dev/null 2>&1 || true
  WINEPREFIX="$FL_MIKU_PREFIX" WINEDEBUG=-all \
    wine reg add "HKEY_USERS\\.Default\\Control Panel\\International" \
      /v "sCountry"  /t REG_SZ /d "Japan"     /f >/dev/null 2>&1 || true

  # ── 3. Font substitutes ────────────────────────────────────────────────────
  # Target font: Noto Sans CJK JP (from noto-fonts-cjk, symlinked into
  # drive_c/windows/Fonts/ by install_japanese_fonts_from_system above).
  # This is chosen over Meiryo because winetricks meiryo silently fails to
  # download from Microsoft servers on many systems, leaving no Meiryo fonts
  # installed — making any Meiryo-targeted substitute a dead end.
  #
  # Key names include charset 128 (SHIFTJIS_CHARSET) qualified variants because
  # Win32 GDI looks up fonts keyed on "FaceName,CharsetID" — the plain name
  # entry alone does not match Japanese-charset font requests from dialog
  # controls (buttons, checkboxes).
  local subkey="HKEY_LOCAL_MACHINE\\Software\\Microsoft\\Windows NT\\CurrentVersion\\FontSubstitutes"
  local jp_font="Noto Sans CJK JP"
  local key
  for key in \
    "MS Shell Dlg"     "MS Shell Dlg,128" \
    "MS Shell Dlg 2"   "MS Shell Dlg 2,128" \
    "MS UI Gothic"     "MS UI Gothic,128" \
    "MS PGothic"       "MS PGothic,128" \
    "Tahoma"           "Tahoma,128" \
    "Arial"            "Arial,128"
  do
    WINEPREFIX="$FL_MIKU_PREFIX" WINEDEBUG=-all \
      wine reg add "$subkey" /v "$key" /t REG_SZ /d "$jp_font" /f >/dev/null 2>&1 || true
  done

  # ── 4. Flush the Wine server so all the above changes take effect ────────────
  log "Restarting Wine server to apply locale and font changes..."
  WINEPREFIX="$FL_MIKU_PREFIX" wineserver -k 2>/dev/null || true
  sleep 1
  WINEPREFIX="$FL_MIKU_PREFIX" WINEDEBUG=-all wineboot -u >/dev/null 2>&1 || true
  wait_for_wine_exit "wineboot after font/locale setup" 30

  log "Wine Japanese locale and font substitutions configured."
  mark_step_done font_substitutes_v3
}

# ---------------------------------------------------------------------------
# Prefix hardening
# ---------------------------------------------------------------------------
disable_file_associations() {
  if step_done file_associations; then
    log "Wine file-type hijacking already disabled — skipping."
    return 0
  fi

  step "Disabling Wine file-type hijacking"
  # Stop Wine from registering itself as the default handler for file types.
  WINEPREFIX="$FL_MIKU_PREFIX" WINEDEBUG=-all \
    wine reg add \
      "HKEY_CURRENT_USER\\Software\\Wine\\FileOpenAssociations" \
      /v Enable /d N /f >/dev/null 2>&1 || true
  # Prevent winemenubuilder from creating desktop shortcuts automatically.
  WINEPREFIX="$FL_MIKU_PREFIX" WINEDEBUG=-all \
    wine reg add \
      "HKEY_LOCAL_MACHINE\\Software\\Microsoft\\Windows NT\\CurrentVersion\\Image File Execution Options\\winemenubuilder.exe" \
      /v Debugger /t REG_SZ /d /dev/null /f >/dev/null 2>&1 || true
  log "File associations disabled."
  mark_step_done file_associations
}

# ---------------------------------------------------------------------------
# VST plugin directories
# ---------------------------------------------------------------------------
create_vst_dirs() {
  local vst2="$FL_MIKU_PREFIX/drive_c/VST2"
  local vst3="$FL_MIKU_PREFIX/drive_c/VST3"

  if [[ -d "$vst2" && -d "$vst3" && -f "$(step_state_path vst_dirs)" ]]; then
    log "VST plugin directories already exist — skipping."
    return 0
  fi

  step "Creating VST plugin directories"
  mkdir -p "$vst2" "$vst3"
  log "C:\\VST2  →  $vst2"
  log "C:\\VST3  →  $vst3"
  mark_step_done vst_dirs
}

# ---------------------------------------------------------------------------
# Japanese system fonts — symlink into Wine prefix so Wine can find them
# by family name regardless of fontconfig integration.
# ---------------------------------------------------------------------------
install_japanese_fonts_from_system() {
  if step_done japanese_system_fonts; then
    log "Japanese system fonts already linked into Wine prefix — skipping."
    return 0
  fi

  step "Linking Japanese system fonts into Wine prefix"
  local wine_fonts_dir="$FL_MIKU_PREFIX/drive_c/windows/Fonts"
  mkdir -p "$wine_fonts_dir"

  local installed=0
  local found_font

  # noto-fonts-cjk on Arch Linux installs TTC/OTF files under /usr/share/fonts/.
  # Symlinking them into drive_c/windows/Fonts/ guarantees Wine can find
  # 'Noto Sans CJK JP' by family name even without fontconfig integration.
  while IFS= read -r -d '' found_font; do
    local base
    base="$(basename "$found_font")"
    if [[ ! -e "$wine_fonts_dir/$base" ]]; then
      ln -sf "$found_font" "$wine_fonts_dir/$base"
      log "Linked: $base"
      installed=$(( installed + 1 ))
    fi
  done < <(find /usr/share/fonts -maxdepth 4 \
    \( -iname 'NotoSansCJK*.ttc'    \
       -o -iname 'NotoSansCJKjp*.otf' \
       -o -iname 'NotoSansCJKjp*.ttf' \
       -o -iname 'NotoSansCJK-Regular*' \) \
    -print0 2>/dev/null | sort -zu)

  if (( installed > 0 )); then
    log "Linked $installed Noto CJK JP font(s) into the Wine prefix."
    mark_step_done japanese_system_fonts
  else
    log "WARNING: No Noto CJK JP fonts found on the system."
    log "Install noto-fonts-cjk for correct Japanese rendering:"
    log "  sudo pacman -S noto-fonts-cjk"
    log "Japanese installer UI may still show square glyphs."
  fi
}

# ---------------------------------------------------------------------------
# Miku V4X — zip extraction + installers
# ---------------------------------------------------------------------------
extract_miku_zip() {
  if step_done miku_extract && find "$MIKU_INSTALLER_DIR" -iname "setup.exe" 2>/dev/null | grep -q .; then
    log "Miku V4X package already extracted — skipping."
    return 0
  fi

  step "Extracting Miku V4X package"
  mkdir -p "$MIKU_INSTALLER_DIR"

  if ! command -v 7z >/dev/null 2>&1; then
    log "WARNING: 7z not found. Install p7zip then re-run to auto-extract."
    log "Or extract the zip manually to: $MIKU_INSTALLER_DIR"
    return 0
  fi

  local -a zips
  mapfile -t zips < <(find "$MIKU_INSTALLER_DIR" -maxdepth 1 -name "*.zip" 2>/dev/null)

  if [[ "${#zips[@]}" -eq 0 ]]; then
    # Check if the subfolders are already present from a prior extraction.
    if find "$MIKU_INSTALLER_DIR" -iname "setup.exe" 2>/dev/null | grep -q .; then
      log "Installer contents already extracted — skipping."
    else
      log "No .zip found in $MIKU_INSTALLER_DIR"
      log "Place the SonicWire Miku V4X zip in: $MIKU_INSTALLER_DIR"
    fi
    return 0
  fi

  if [[ "${#zips[@]}" -gt 1 ]]; then
    log "WARNING: Multiple zip files found — using the first one. Remove extras to avoid ambiguity."
    log "Zips found: ${zips[*]}"
  fi

  local zipfile="${zips[0]}"
  log "Found: $zipfile"
  log "Extracting with 7z (zip64 format)..."
  7z x -o"$MIKU_INSTALLER_DIR" -y "$zipfile" || die "Failed to extract Miku zip: $zipfile"
  log "Extraction complete."
  mark_step_done miku_extract
}

run_piapro_installer() {
  step "Installing Piapro Studio"

  local crypton_setup crypton_msi mutant_msi
  crypton_setup="$(find "$MIKU_INSTALLER_DIR" -ipath '*Crypton Software Installer*' -iname 'setup.exe'               2>/dev/null | head -1 || true)"
  crypton_msi="$(  find "$MIKU_INSTALLER_DIR" -ipath '*Crypton Software Installer*' -iname 'PiaproStudioInstaller x64.msi' 2>/dev/null | head -1 || true)"
  mutant_msi="$(   find "$MIKU_INSTALLER_DIR" -ipath '*Crypton Software Installer*' -iname 'MutantInstaller x64.msi' 2>/dev/null | head -1 || true)"

  if [[ -z "$crypton_setup" && -z "$crypton_msi" ]]; then
    log "Crypton Software Installer not found — skipping Piapro Studio."
    log "Place the SonicWire Miku V4X zip (or its extracted contents) in: $MIKU_INSTALLER_DIR"
    return 0
  fi

  if step_done crypton_installer || piapro_installed; then
    log "Piapro Studio already installed — skipping."
    mark_step_done crypton_installer
    return 0
  fi

  if [[ -n "$crypton_msi" ]]; then
    if [[ -n "$mutant_msi" ]] && ! step_done crypton_mutant; then
      log "Running Crypton Mutant installer..."
      log "Path: $mutant_msi"
      run_wine_jp wine msiexec /i "$mutant_msi" || \
        log "WARNING: Crypton Mutant installer exited non-zero — check for errors above."
      wait_for_wine_exit "Crypton Mutant installer"
      mark_step_done crypton_mutant
    fi

    log "Running Piapro Studio MSI directly..."
    log "Path: $crypton_msi"
    run_wine_jp wine msiexec /i "$crypton_msi" || \
      log "WARNING: Piapro Studio MSI exited non-zero — check for errors above."
    wait_for_wine_exit "Piapro Studio installer"
  else
    log "Running Crypton Software installer (bootstrapper)..."
    log "Path: $crypton_setup"
    run_wine_jp wine "$crypton_setup" || \
      log "WARNING: Crypton installer exited non-zero — check for errors above."
    wait_for_wine_exit "Crypton installer"
  fi

  if piapro_installed; then
    log "Piapro Studio installed successfully."
    mark_step_done crypton_installer
  else
    log "WARNING: Piapro Studio does not appear to be installed yet."
  fi
}

run_miku_v4x_installer() {
  step "Installing Hatsune Miku V4X voicebank"

  local miku_vx_setup
  miku_vx_setup="$(find "$MIKU_INSTALLER_DIR" -ipath '*MIKU V4X Installer*' -iname 'setup.exe' 2>/dev/null | head -1 || true)"

  if step_done miku_v4x_installer || miku_v4x_installed; then
    log "Hatsune Miku V4X already installed — skipping."
    mark_step_done miku_v4x_installer
    return 0
  fi

  if [[ -z "$miku_vx_setup" ]]; then
    log "WARNING: Miku V4X Installer not found — skipping."
    log "Place the SonicWire Miku V4X zip (or its extracted contents) in: $MIKU_INSTALLER_DIR"
    return 0
  fi

  log "Running Hatsune Miku V4X installer..."
  log "Path: $miku_vx_setup"
  run_wine_jp wine "$miku_vx_setup" || \
    log "WARNING: Miku V4X installer exited non-zero — check for errors above."
  wait_for_wine_exit "Miku V4X installer"

  if miku_v4x_installed; then
    log "Miku V4X installed successfully."
    mark_step_done miku_v4x_installer
  else
    log "WARNING: Miku V4X does not appear to be installed yet."
  fi
}

run_miku_v4_en_installer() {
  step "Installing Hatsune Miku V4 English voicebank"

  local miku_en_setup
  miku_en_setup="$(find "$MIKU_INSTALLER_DIR" -ipath '*MIKU V4 English Installer*' -iname 'setup.exe' 2>/dev/null | head -1 || true)"

  if step_done miku_v4_en_installer || miku_v4_english_installed; then
    log "Hatsune Miku V4 English already installed — skipping."
    mark_step_done miku_v4_en_installer
    return 0
  fi

  if [[ -z "$miku_en_setup" ]]; then
    log "Miku V4 English Installer not found — skipping (optional voicebank)."
    return 0
  fi

  log "Running Hatsune Miku V4 English installer..."
  log "Path: $miku_en_setup"
  run_wine_jp wine "$miku_en_setup" || \
    log "WARNING: Miku V4 English installer exited non-zero — check for errors above."
  wait_for_wine_exit "Miku V4 English installer"

  if miku_v4_english_installed; then
    log "Miku V4 English installed successfully."
    mark_step_done miku_v4_en_installer
  else
    log "WARNING: Miku V4 English does not appear to be installed yet."
  fi
}

# ---------------------------------------------------------------------------
# Voicebank licence activation
# ---------------------------------------------------------------------------
# After installing the Crypton voicebanks the licences default to trial mode.
# Activation is done by running the Crypton/Vocaloid license manager that was
# placed inside the prefix by the voicebank installer.
# ---------------------------------------------------------------------------
run_voicebank_activation() {
  step "Voicebank licence activation"

  # Known activation executable name patterns from Crypton/Yamaha installers.
  local -a candidates
  mapfile -t candidates < <(
    find "$FL_MIKU_PREFIX/drive_c" \
      \( -iname '*license*manager*.exe' \
         -o -iname '*licensemanager*.exe' \
         -o -iname '*activation*.exe' \
         -o -iname 'Activate4.exe' \
         -o -iname 'Activate*.exe' \
         -o -iname '*vocaloid*license*.exe' \
         -o -iname '*crypton*license*.exe' \
         -o -iname 'VocaloidActivation.exe' \
         -o -iname 'VA4License.exe' \
         -o -iname 'piaprolicense*.exe' \) \
      2>/dev/null | sort
  )

  if [[ "${#candidates[@]}" -eq 0 ]]; then
    log "No Crypton/Vocaloid licence manager executables found in the prefix."
    log "The voicebank may activate from within Piapro Studio itself."
    log "Open Piapro Studio, go to Help → License / Activate and enter your serial."
    log "Or use fl-miku-run-exe to run a specific tool:"
    log "  fl-miku-run-exe '/path/inside/drive_c/...'" 
    log "You can browse the prefix at: $FL_MIKU_PREFIX/drive_c"
    return 0
  fi

  if [[ "${#candidates[@]}" -eq 1 ]]; then
    log "Found licence tool: ${candidates[0]}"
    log "Launching it now — enter your serial key in the window that opens."
    WINEPREFIX="$FL_MIKU_PREFIX" WINEDEBUG=-all wine "${candidates[0]}" || true
    wait_for_wine_exit "licence activation tool" 300
    return 0
  fi

  # Multiple candidates — let the user pick.
  echo
  log "Multiple licence-related executables found. Pick one to run:"
  local i
  for i in "${!candidates[@]}"; do
    echo "  $((i+1))) ${candidates[$i]}"
  done
  echo "  q) Cancel"
  echo

  local choice
  while true; do
    read -r -p "Select an option: " choice
    [[ "$choice" == "q" || "$choice" == "Q" ]] && return 0
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#candidates[@]} )); then
      local selected="${candidates[$((choice-1))]}"
      log "Launching: $selected"
      WINEPREFIX="$FL_MIKU_PREFIX" WINEDEBUG=-all wine "$selected" || true
      wait_for_wine_exit "licence activation tool" 300
      return 0
    fi
    echo "Please enter a number between 1 and ${#candidates[@]}, or q to cancel."
  done
}

# ---------------------------------------------------------------------------
# FL Studio installer download + launch
# ---------------------------------------------------------------------------
download_fl_installer() {
  if [[ -f "$FL_INSTALLER_FILE" ]]; then
    log "FL Studio installer already present: $FL_INSTALLER_FILE"
    mark_step_done fl_installer_download
    return 0
  fi

  step "Preparing FL Studio installer"
  mkdir -p "$FL_INSTALLER_DIR"

  log "Downloading from Image-Line..."
  log "URL: $FL_INSTALLER_URL"
  if curl -L --progress-bar -o "$FL_INSTALLER_FILE" "$FL_INSTALLER_URL"; then
    log "Download complete."
    mark_step_done fl_installer_download
  else
    rm -f "$FL_INSTALLER_FILE"
    log "WARNING: Download failed (partial file removed)."
    log "Download the installer manually from: https://www.image-line.com/fl-studio/download"
    log "Save it to: $FL_INSTALLER_FILE"
    return 1
  fi
}

run_fl_installer() {
  local existing_fl_exe
  existing_fl_exe="$(find_fl_exe)"

  if [[ -n "$existing_fl_exe" ]]; then
    log "FL Studio already installed at: $existing_fl_exe"
    log "Skipping FL Studio installer step."
    return 0
  fi

  if [[ ! -f "$FL_INSTALLER_FILE" ]]; then
    log "No FL Studio installer found — skipping automatic install."
    log "To install manually later:"
    log "  WINEPREFIX=\"$FL_MIKU_PREFIX\" wine /path/to/flstudio_installer.exe"
    return 0
  fi

  step "Running FL Studio installer"
  log "A Wine installer window will open. Follow the steps normally."
  log "Accept the default install location (C:\\Program Files\\Image-Line\\...)."
  WINEPREFIX="$FL_MIKU_PREFIX" WINEDEBUG=-all wine "$FL_INSTALLER_FILE" || \
    log "WARNING: FL Studio installer exited non-zero (this may be harmless, e.g. restart-required)."
  wait_for_wine_exit "FL Studio installer"
  log "FL Studio installer finished."
  mark_step_done fl_installer_run
}

# ---------------------------------------------------------------------------
# Discover FL Studio executable (version-agnostic)
# ---------------------------------------------------------------------------
find_fl_exe() {
  local prefix_programs="$FL_MIKU_PREFIX/drive_c/Program Files/Image-Line"
  local found
  found="$(find "$prefix_programs" -name "FL64.exe" 2>/dev/null | sort -V | tail -1 || true)"
  echo "$found"
}

# ---------------------------------------------------------------------------
# Launcher scripts
# ---------------------------------------------------------------------------
create_launcher_scripts() {
  if [[ -x "$BIN_DIR/fl-studio" && -x "$BIN_DIR/fl-miku-winecfg" && -x "$BIN_DIR/fl-miku-kill" && -x "$BIN_DIR/fl-miku-run-exe" && -f "$(step_state_path launchers)" ]]; then
    log "Launcher scripts already exist — skipping."
    return 0
  fi

  step "Writing launcher scripts"
  mkdir -p "$BIN_DIR"

  # --- fl-studio -------------------------------------------------------
  # Discovers the FL64.exe path at launch time so it survives version updates.
  cat > "$BIN_DIR/fl-studio" <<SCRIPT
#!/bin/bash
export WINEPREFIX="$FL_MIKU_PREFIX"
export WINEDEBUG="-all"

FL_EXE="\$(find "\$WINEPREFIX/drive_c/Program Files/Image-Line" -name "FL64.exe" 2>/dev/null | sort -V | tail -1 || true)"

if [[ -z "\$FL_EXE" ]]; then
  echo "FL Studio (FL64.exe) not found in \$WINEPREFIX."
  echo "Run fl-miku-setup again after installing FL Studio."
  exit 1
fi

exec wine "\$FL_EXE" "\$@"
SCRIPT

  # --- fl-miku-winecfg -------------------------------------------------
  cat > "$BIN_DIR/fl-miku-winecfg" <<SCRIPT
#!/bin/bash
export WINEPREFIX="$FL_MIKU_PREFIX"
exec winecfg
SCRIPT

  # --- fl-miku-kill ----------------------------------------------------
  cat > "$BIN_DIR/fl-miku-kill" <<SCRIPT
#!/bin/bash
export WINEPREFIX="$FL_MIKU_PREFIX"
echo "Stopping Wine processes in fl-miku prefix..."
wineserver -k 2>/dev/null || true
echo "Done."
SCRIPT

  # --- fl-miku-run-exe -------------------------------------------------
  # Convenience wrapper for running arbitrary Windows installers/tools in the prefix.
  cat > "$BIN_DIR/fl-miku-run-exe" <<SCRIPT
#!/bin/bash
# Run an arbitrary Windows executable inside the fl-miku prefix.
# Usage: fl-miku-run-exe /path/to/installer.exe [args...]
export WINEPREFIX="$FL_MIKU_PREFIX"
export WINEDEBUG="-all"
if [[ -z "\${1:-}" ]]; then
  echo "Usage: fl-miku-run-exe /path/to/installer.exe [args...]"
  exit 1
fi
exec wine "\$@"
SCRIPT

  chmod +x \
    "$BIN_DIR/fl-studio" \
    "$BIN_DIR/fl-miku-winecfg" \
    "$BIN_DIR/fl-miku-kill" \
    "$BIN_DIR/fl-miku-run-exe"

  log "Launchers written to $BIN_DIR"
  mark_step_done launchers
}

# ---------------------------------------------------------------------------
# Desktop entries (.desktop files for KRunner / app menu)
# ---------------------------------------------------------------------------
create_desktop_entries() {
  if [[ -f "$APP_DIR/fl-studio.desktop" && -f "$APP_DIR/fl-miku-winecfg.desktop" && -f "$APP_DIR/fl-miku-kill.desktop" && -f "$(step_state_path desktop_entries)" ]]; then
    log "Desktop entries already exist — skipping."
    return 0
  fi

  step "Writing desktop entries"
  mkdir -p "$APP_DIR"

  cat > "$APP_DIR/fl-studio.desktop" <<DESKTOP
[Desktop Entry]
Name=FL Studio
GenericName=Digital Audio Workstation
Comment=FL Studio music production (fl-miku Wine prefix)
Exec=$BIN_DIR/fl-studio
Icon=audio-x-generic
Terminal=false
Type=Application
Categories=Audio;AudioVideo;Music;
Keywords=fl;studio;daw;music;production;image-line;
DESKTOP

  cat > "$APP_DIR/fl-miku-winecfg.desktop" <<DESKTOP
[Desktop Entry]
Name=FL Miku Wine Config
Comment=Configure the fl-miku Wine prefix (winecfg)
Exec=$BIN_DIR/fl-miku-winecfg
Icon=preferences-system
Terminal=false
Type=Application
Categories=Audio;Settings;
Keywords=wine;config;fl;miku;winecfg;
DESKTOP

  cat > "$APP_DIR/fl-miku-kill.desktop" <<DESKTOP
[Desktop Entry]
Name=Kill FL Miku Wine
Comment=Stop all Wine processes in the fl-miku prefix
Exec=$BIN_DIR/fl-miku-kill
Icon=process-stop
Terminal=true
Type=Application
Categories=Audio;
Keywords=wine;kill;fl;miku;stop;
DESKTOP

  update-desktop-database "$APP_DIR" 2>/dev/null || true
  log "Desktop entries written to $APP_DIR"
  mark_step_done desktop_entries
}

# ---------------------------------------------------------------------------
# Post-setup instructions
# ---------------------------------------------------------------------------
print_next_steps() {
  local fl_exe
  fl_exe="$(find_fl_exe)"

  hr
  echo
  log "Setup complete."
  echo
  if [[ -n "$fl_exe" ]]; then
    log "FL Studio found at: $fl_exe"
  else
    log "FL Studio was not installed yet (or is at an unexpected path)."
    log "Install it, then update the fl-studio launcher if needed."
  fi
  echo
  log "Next steps:"
  echo
  log "  1. Launch 'FL Studio' from KRunner and sign in to your Image-Line"
  log "     account to activate your licence."
  echo
  log "  2. In FL Studio → Options → Manage plugins, add VST paths:"
  log "     C:\\VST2    (for VST2 plugins)"
  log "     C:\\VST3    (for VST3 plugins)"
  echo
  log "  3. Run a plugin scan in FL Studio to detect Piapro Studio."
  echo
  log "  4. Activate your Crypton voicebank licences (Hatsune Miku V4X / V4 English)"
  log "     if they show a trial expiry date in Piapro Studio:"
  log "     Re-run this script and select option 8 — Activate voicebank licences."
  log "     This searches the prefix for the Crypton/Vocaloid license manager and"
  log "     launches it so you can enter your serial key."
  echo
  log "  If Piapro Studio or Miku installers were not found, place the SonicWire"
  log "  Miku V4X zip in: $MIKU_INSTALLER_DIR"
  log "  then re-run this script — it will extract and install automatically."
  echo
  log "Available in KRunner:"
  log "  'FL Studio'           — launch the DAW"
  log "  'FL Miku Wine Config' — open winecfg for this prefix"
  log "  'Kill FL Miku Wine'   — stop Wine server for this prefix"
  echo
  hr
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  hr
  log "FL Miku Setup"
  log "Prefix : $FL_MIKU_PREFIX"
  log "Wine   : $(wine --version 2>/dev/null || echo 'not found')"
  hr
  echo

  require_display
  require_tools

  prompt_startup_choice
  select_install_mode

  # ── Prefix setup ─ always runs; all steps are idempotent ─────────────────
  init_prefix
  set_windows_version
  install_winetricks_deps
  install_japanese_fonts_from_system
  configure_font_substitutes
  disable_file_associations
  create_vst_dirs

  # ── Selective installer steps ─────────────────────────────────────────────
  if should_install "fl"; then
    if [[ -n "$(find_fl_exe)" ]]; then
      log "FL Studio already installed — skipping download and installer step."
    else
      download_fl_installer
      run_fl_installer
    fi
  fi

  # Extract the Miku zip before any Miku installer that needs it.
  if should_install "piapro" || should_install "miku_v4x" || should_install "miku_v4_en"; then
    extract_miku_zip
  fi

  if should_install "piapro";    then run_piapro_installer;     fi
  if should_install "miku_v4x";  then run_miku_v4x_installer;   fi
  if should_install "miku_v4_en"; then run_miku_v4_en_installer; fi
  if should_install "activate";  then run_voicebank_activation;  fi

  # ── Launchers always recreated / updated at the end ───────────────────────
  create_launcher_scripts
  create_desktop_entries

  print_next_steps
}

main "$@"
