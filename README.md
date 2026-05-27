<p align="center">
  <img width="3440" height="1440" alt="Screenshot_20260112_200906" src="./payload/images/FrosteArch Logo 2.png" />
</p>

FrosteArch is a custom Arch Linux distro built around a practical, opinionated setup for both desktop and server use.

There are two editions to choose:

- Desktop Edition
- Server Edition

FrosteArch Desktop is a full daily-driver environment with programming, productivity, gaming, and creative tools already installed.

FrosteArch Server is a lean profile tuned for long-running services, including Plex defaults and enough local tooling to debug directly on the machine.

---

<h2 align="center">FrosteArch Desktop</h2>

<p align="center">
  <img width="3440" height="1440" alt="Screenshot_20260112_200906" src="./payload/images/Desktop1.png" />
</p>

<br>

<p align="center">
  <img width="3440" height="1440" alt="Screenshot_20260112_201312" src="./payload/images/Desktop2.png" />
</p>

---

<h2 align="center">FrosteArch Server</h2>

<p align="center">
  <img width="1920" height="1200" alt="Screenshot_20260212_192443" src="./payload/images/Server1.png" />
</p>

<br>

<p align="center">
  <img width="1920" height="1200" alt="Screenshot_20260212_192431" src="./payload/images/Server2.png" />
</p>

---

<h2 align="center">Roadmap</h2>

- Update desktop images
- Update server konsave / dotfiles
- Nvidia support

---

<h2 align="center">Installation Guide</h2>

The FrosteArch install flow is mostly automated, while keeping the key Archinstall choices in your hands.

## Before you begin

- Use a stable internet connection during install.
- Decide which ISO you want:
  - Desktop Edition: full daily-driver setup.
  - Server Edition: lightweight setup with server defaults.

## Step 1: Download the ISO

Download the Desktop or Server ISO from the Releases page.

Optional but recommended checksum verification:

```bash
sha256sum <your-iso-file>.iso
```

## Step 2: Write the ISO to a USB

Use USBImager, Balena Etcher, or Rufus.

If you are on Linux and want to use `dd`:

```bash
sudo dd if=<your-iso-file>.iso of=/dev/<usb-device> bs=4M status=progress oflag=sync
```

## Step 3: Boot from the USB

- Boot the target machine from the USB.
- Select the FrosteArch install option in the boot menu.
- The installer launcher should auto-start on tty1.

If it does not auto-start, run one of these manually:

```bash
/root/start-install-desktop.sh
# or
/root/start-install-server.sh
```

## Step 4: Complete Archinstall base configuration

In Archinstall, configure the basics:

- Mirror region
- Disk layout and mount points
- User account(s) and passwords
- Timezone and locale

Then let Archinstall complete the base system installation.

## Step 5: Let FrosteArch finish setup

After Archinstall finishes, FrosteArch continues automatically and applies packages, services, and system configuration.

Install output is logged to:

```bash
/var/log/frostearch/install-<timestamp>.log
```

## Step 6: Reboot into FrosteArch

Once setup fully completes:

- Reboot
- Remove the USB when prompted
- Log into your new system

## Step 7: Quick post-install checks

- Confirm networking is up
- Run updates

```bash
yay
```

For troubleshooting logs:

```bash
cat /var/log/archinstall/install.log
ls -1 /var/log/frostearch/
```

## Step 8: Success!

FrosteArch is now installed and ready to use, tweak, and build on.

---

<h2 align="center">FAQ</h2>


## Why not use a headless server?

- No modern hardware has a meaningful loss from having something like plasma running in the background
  - Miku :)
- Sometimes it's easier to debug on-device and this is running on a spare laptop
  - Miku :D
- I can still SSH in
  - Miku :3
- I wanted an excuse to rice Arch again
  - Miku :0
- I have a staggering skill issue

## How do I use my programs?

Pressing alt + space will open KRunner, which you can use to type in any program name or category and it will appear.

## How do I update my programs?

Just type yay into the terminal, it will find and update everything for you. Very handy.

## How do I get new programs?

Google "*program you need or problem to solve* Arch" and and it will probably appear. If it's part of the main Arch repos you can do 

```
sudo pacman -S *packageName*
```
and if it's part of the AUR you can do
```
yay -S *packageName*
```
to install it.

---

<h2 align="center">Credit where credit is due</h2>

## Arch Linux

Obviously, this is built on top of Arch Linux. Thank you for every maintainer for their hard work!

`https://archlinux.org/`

## Archinstall

My scripts and changes are stapled onto & around Archinstall. Without their incredible work this wouldn't be possible. Thanks!

`https://archinstall.archlinux.page/`

## Wallpapers

- Ina: https://www.pixiv.net/en/artworks/103938068
- Miku: https://www.pixiv.net/en/artworks/73597952
