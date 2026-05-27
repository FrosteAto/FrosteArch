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

# ---------------------------------------------------------------------------
# Prefix initialisation
# ---------------------------------------------------------------------------
init_prefix() {
  step "Initialising Wine prefix"
  log "Path: $FL_MIKU_PREFIX"
  mkdir -p "$FL_MIKU_PREFIX"
  # wine-mono and wine-gecko are installed as system packages, so Wine will
  # not prompt to download them during initialisation.
  WINEPREFIX="$FL_MIKU_PREFIX" WINEDEBUG=-all wineboot -u
  log "Prefix ready."
}

set_windows_version() {
  step "Setting Windows version to Windows 10"
  WINEPREFIX="$FL_MIKU_PREFIX" WINEDEBUG=-all winetricks -q win10
}

# ---------------------------------------------------------------------------
# Winetricks dependencies (FL Studio 25 requirements)
# ---------------------------------------------------------------------------
install_winetricks_deps() {
  step "Installing winetricks components"
  log "Component: allfonts (Microsoft font set — may take a few minutes)"
  WINEPREFIX="$FL_MIKU_PREFIX" winetricks -q allfonts
  log "Component: webview2 (Microsoft Edge WebView2 — required by FL Studio 25)"
  WINEPREFIX="$FL_MIKU_PREFIX" winetricks -q webview2
}

# ---------------------------------------------------------------------------
# Prefix hardening
# ---------------------------------------------------------------------------
disable_file_associations() {
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
}

# ---------------------------------------------------------------------------
# VST plugin directories
# ---------------------------------------------------------------------------
create_vst_dirs() {
  step "Creating VST plugin directories"
  local vst2="$FL_MIKU_PREFIX/drive_c/VST2"
  local vst3="$FL_MIKU_PREFIX/drive_c/VST3"
  mkdir -p "$vst2" "$vst3"
  log "C:\\VST2  →  $vst2"
  log "C:\\VST3  →  $vst3"
}

# ---------------------------------------------------------------------------
# Miku V4X — zip extraction + installers
# ---------------------------------------------------------------------------
extract_miku_zip() {
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
}

run_miku_installers() {
  step "Installing Piapro Studio + Hatsune Miku V4X voicebanks"

  # Locate each setup.exe by matching the folder names from the SonicWire zip.
  # -ipath is case-insensitive so minor naming variations still match.
  local crypton_setup miku_vx_setup miku_en_setup
  crypton_setup="$(find "$MIKU_INSTALLER_DIR" -ipath '*Crypton Software Installer*' -iname 'setup.exe' 2>/dev/null | head -1 || true)"
  miku_vx_setup="$(find "$MIKU_INSTALLER_DIR" -ipath '*MIKU V4X Installer*' -iname 'setup.exe' 2>/dev/null | head -1 || true)"
  miku_en_setup="$(find "$MIKU_INSTALLER_DIR" -ipath '*MIKU V4 English Installer*' -iname 'setup.exe' 2>/dev/null | head -1 || true)"

  if [[ -z "$crypton_setup" && -z "$miku_vx_setup" ]]; then
    log "No Miku installers found — skipping."
    log "Place the SonicWire Miku V4X zip (or its extracted contents) in: $MIKU_INSTALLER_DIR"
    return 0
  fi

  # 1. Crypton Software Installer — installs Piapro Studio (VST host/plugin)
  if [[ -n "$crypton_setup" ]]; then
    log "Running Crypton Software installer (Piapro Studio)..."
    log "Path: $crypton_setup"
    WINEPREFIX="$FL_MIKU_PREFIX" WINEDEBUG=-all wine "$crypton_setup" || \
      log "WARNING: Crypton installer exited non-zero — check for errors above."
    log "Crypton installer done."
    WINEPREFIX="$FL_MIKU_PREFIX" wineserver -w 2>/dev/null || true
  else
    log "WARNING: Crypton Software Installer not found — skipping Piapro Studio."
  fi

  # 2. Miku V4X voicebank
  if [[ -n "$miku_vx_setup" ]]; then
    log "Running Hatsune Miku V4X installer..."
    log "Path: $miku_vx_setup"
    WINEPREFIX="$FL_MIKU_PREFIX" WINEDEBUG=-all wine "$miku_vx_setup" || \
      log "WARNING: Miku V4X installer exited non-zero — check for errors above."
    log "Miku V4X installer done."
    WINEPREFIX="$FL_MIKU_PREFIX" wineserver -w 2>/dev/null || true
  else
    log "WARNING: Miku V4X Installer not found — skipping."
  fi

  # 3. Miku V4 English voicebank (optional — present in the SonicWire package)
  if [[ -n "$miku_en_setup" ]]; then
    log "Running Hatsune Miku V4 English installer..."
    log "Path: $miku_en_setup"
    WINEPREFIX="$FL_MIKU_PREFIX" WINEDEBUG=-all wine "$miku_en_setup" || \
      log "WARNING: Miku V4 English installer exited non-zero — check for errors above."
    log "Miku V4 English installer done."
  else
    log "Miku V4 English Installer not found — skipping (optional voicebank)."
  fi
}

# ---------------------------------------------------------------------------
# FL Studio installer download + launch
# ---------------------------------------------------------------------------
download_fl_installer() {
  step "Preparing FL Studio installer"
  mkdir -p "$FL_INSTALLER_DIR"

  if [[ -f "$FL_INSTALLER_FILE" ]]; then
    log "Installer already present: $FL_INSTALLER_FILE"
    return 0
  fi

  log "Downloading from Image-Line..."
  log "URL: $FL_INSTALLER_URL"
  if curl -L --progress-bar -o "$FL_INSTALLER_FILE" "$FL_INSTALLER_URL"; then
    log "Download complete."
  else
    rm -f "$FL_INSTALLER_FILE"
    log "WARNING: Download failed (partial file removed)."
    log "Download the installer manually from: https://www.image-line.com/fl-studio/download"
    log "Save it to: $FL_INSTALLER_FILE"
    return 1
  fi
}

run_fl_installer() {
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
  WINEPREFIX="$FL_MIKU_PREFIX" wineserver -w 2>/dev/null || true
  log "FL Studio installer finished."
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
}

# ---------------------------------------------------------------------------
# Desktop entries (.desktop files for KRunner / app menu)
# ---------------------------------------------------------------------------
create_desktop_entries() {
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

  init_prefix
  set_windows_version
  install_winetricks_deps
  disable_file_associations
  create_vst_dirs
  download_fl_installer && run_fl_installer || true
  extract_miku_zip
  run_miku_installers
  create_launcher_scripts
  create_desktop_entries

  print_next_steps
}

main "$@"
