# Quickstart

```bash
cp ~/.ssh/id_* ssh-keys/      # copy your SSH keys (needed for git clone in post-install)
make download                  # fetch Fedora 44 ISO into iso/ (parallel multi-mirror)
make check-iso                 # verify checksum
make build                     # build custom ISO into build/
```

The output ISO (`build/nas-workstation.iso`) is a bootable Fedora installer that auto-partitions `/dev/sda`, installs a full workstation with 25+ desktop/development groups, and runs post-install scripts for AI coding tools.

## Project Structure

```
nas-usb/
├── kickstart/           # Kickstart configuration files
│   └── kickstart.ks     # Main kickstart (partitioning, packages, post-install)
├── ssh-keys/            # SSH keys embedded into ISO (gitignored, you provide these)
├── iso/                 # Downloaded source ISOs (gitignored)
├── build/               # Build output and scratch (gitignored)
├── Makefile             # Build automation
└── README.md
```

## SSH Keys

Place your SSH key pair in `ssh-keys/` before building:

```bash
cp ~/.ssh/id_ed25519 ssh-keys/
cp ~/.ssh/id_ed25519.pub ssh-keys/
```

These are embedded into the ISO and copied to `/root/.ssh/` (mode 600) during install. This allows the `%post` script to `git clone` the nas-ansible repo via SSH. The keys are gitignored and never committed.

## Make Targets

| Target | Description |
|---|---|
| `make help` | Show available targets |
| `make download` | Download Fedora 44 ISO via aria2 from 10 EU mirrors in parallel |
| `make check-iso` | Verify downloaded ISO against Fedora CHECKSUM file |
| `make validate-ks` | Validate kickstart syntax with `ksvalidator` |
| `make build` | Build the custom ISO using `livemedia-creator` (requires root) |
| `make clean` | Remove build artifacts from `build/` |
| `make clean-all` | Remove build artifacts and downloaded ISOs |

## Kickstart Configuration

The `kickstart/kickstart.ks` file defines a fully automated Fedora installation.

### Disk Layout

The installer wipes `/dev/sda` completely and creates the following partition scheme:

| Partition | Size | Filesystem | Mount Point | Purpose |
|---|---|---|---|---|
| sda1 | 512 MB | vfat | /boot/efi | EFI System Partition |
| sda2 | 1.9 GB | xfs | /boot | Boot partition |
| sda3 | 55.9 GB | xfs | / | Root filesystem |
| sda4 | 90.1 GB | xfs | /downloads | Downloads / media storage |
| sda5 | 90.1 GB | bcache | (cache) | SSD cache for RAID arrays |

### System Configuration

| Setting | Value |
|---|---|
| Language | en_IE.UTF-8 |
| Keyboard | Irish (ie) |
| Timezone | Europe/Dublin (UTC) |
| Root password | 123456 (plaintext, change after install) |
| SELinux | Enforcing |
| Firewall | Enabled, SSH allowed |
| Root SSH login | Enabled |

### Package Groups (25+)

The kickstart installs a comprehensive workstation environment:

**Desktop Environments:**
- KDE (kde-apps, kde-desktop)
- COSMIC (cosmic-desktop, cosmic-desktop-apps)
- Budgie (budgie-desktop, budgie-desktop-apps)
- MATE (mate-applications)

**Development:**
- development-tools, c-development, kde-software-development
- editors, container-management, cloud-management

**Productivity:**
- office, libreoffice, design-suite

**Media:**
- kde-media, sound-and-video, audio

**System:**
- admin-tools, system-tools, network-server
- desktop-accessibility, window-managers

**Other:**
- games, vlc

### Additional Packages

Beyond groups, the kickstart installs: `vim`, `git`, `htop`, `tmux`, `curl`, `wget`, `podman`, `podman-compose`, `nodejs`, `npm`, `python3-pip`, `gcc`, `make`, `livecd-tools`, `pykickstart`, `bcache-tools`.

### Post-Install Scripts

The `%post` section runs after installation:

1. **Enable root SSH login** — sets `PermitRootLogin yes` in sshd_config
2. **Install AI coding tools:**
   - [Claude Code](https://claude.ai) — Anthropic's CLI coding assistant
   - [OpenCode](https://opencode.ai) — Open-source coding agent
   - [Codex](https://www.npmjs.com/package/@openai/codex) — OpenAI's CLI tool
   - [Cursor](https://cursor.com) — AI-powered code editor
   - [Grok CLI](https://x.ai) — xAI's command-line interface

## Download Mirrors

The `make download` target uses `aria2c` for parallel multi-source downloading from 10 Western European mirrors:

| Country | Mirror |
|---|---|
| Norway | mirror.23m.com |
| Netherlands | mirror.i3d.net |
| UK | fedora.mirrorservice.org |
| France | mirror.in2p3.fr |
| Finland | nic.funet.fi |
| Denmark | mirror.netsite.dk |
| Germany | ftp-stud.hs-esslingen.de |
| Switzerland | mirror.init7.net |
| Austria | mirror.imt-systems.com |
| Sweden | mirror.bahnhof.net |

`aria2` is auto-installed if missing (supports dnf, apt-get, pacman).

## Requirements

| Requirement | Purpose |
|---|---|
| `aria2` | Parallel ISO download (auto-installed) |
| `livecd-tools` | ISO build tool |
| `pykickstart` | Kickstart validation (`ksvalidator`) |
| Root access | Required for `livemedia-creator` |
| ~10 GB free space | For build scratch and output ISO |

## Build Process

1. `make download` fetches the Fedora 44 Workstation Live ISO (~2.3 GB) into `iso/`
2. `make check-iso` verifies the download against the Fedora CHECKSUM file
3. `make validate-ks` checks the kickstart syntax
4. `make build` runs `livemedia-creator` which:
   - Mounts the source ISO
   - Applies the kickstart configuration
   - Installs all packages into a temporary root
   - Generates the custom bootable ISO at `build/nas-workstation.iso`

## Writing to USB

**WARNING: This will erase the target device. Triple-check you have the right one.**

1. **Insert your USB drive** and identify it:
   ```bash
   lsblk -d -o NAME,SIZE,MODEL,TRAN | grep usb
   ```
   Look for your USB drive by size and model name. It will be something like `sdb` or `sdc` — **never `sda`** (that's your system disk).

2. **Verify it's the right device** by checking its partitions:
   ```bash
   lsblk /dev/sdX       # replace X with your USB drive letter
   ```
   Confirm the size matches your USB stick.

3. **Unmount** any mounted partitions from the USB:
   ```bash
   umount /dev/sdX*      # replace X with your USB drive letter
   ```

4. **Write the ISO** to the USB drive using `dd`:
   ```
   sudo dd if=build/nas-workstation.iso of=/dev/sd?? bs=4M status=progress
   ```
   Replace `??` with the correct drive letter you identified in step 1.

5. **Flush and eject:**
   ```bash
   sync
   sudo eject /dev/sdX   # replace X with your USB drive letter
   ```

6. **Boot from the USB.** The installer will automatically:
   - Wipe `/dev/sda`
   - Create the partition layout
   - Install all packages and groups
   - Copy SSH keys, clone nas-ansible repo
   - Install AI coding tools
   - Reboot into multi-user.target

## Updating Fedora Version

Edit the version variables at the top of the `Makefile`:

```makefile
FEDORA_VER := 44
FEDORA_REL := 1.7
```

Then run `make clean-all && make download && make build`.
