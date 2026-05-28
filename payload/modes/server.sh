#!/bin/bash
set -euo pipefail

MODE_NAME="server"

OFFICIAL_PACKAGES=(
  linux-lts linux-lts-headers linux-firmware
  xorg plasma plasma-workspace greetd greetd-tuigreet kwallet kwallet-pam libsecret
  kdialog
  ufw nano btop flatpak kitty dolphin ark fastfetch firefox sof-firmware git partitionmanager
  python python-markdown python-pip python-pipx
  avahi nss-mdns
  noto-fonts noto-fonts-cjk noto-fonts-emoji ttf-dejavu ttf-jetbrains-mono
)

AUR_PACKAGES=( plex-media-server )

SERVICES_ENABLE=(
  NetworkManager.service
  greetd.service
  plexmediaserver.service
  avahi-daemon.service
  ufw.service
)

SERVICES_MASK=( sleep.target suspend.target hibernate.target hybrid-sleep.target )

FIREWALL_RULES=( 22/tcp 32400/tcp 1900/udp 5353/udp )

DOTFILES_SUBDIR="themes/server/dotfiles"

FIRST_BOOT_DIALOG_TITLE="Welcome to FrosteArch Server"
FIRST_BOOT_DIALOG_MARKDOWN_REL="shared/first-boot-server.md"
