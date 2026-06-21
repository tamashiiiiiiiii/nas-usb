# Fedora NAS Workstation — Custom Kickstart ISO Builder

```bash
make setup                     # install build tools (first time only)
make download                  # fetch Fedora 44 Everything netinstall ISO
make check-iso                 # verify checksum
make build                     # build custom ISO (embeds ~/.ssh/ keys)
make flash DEV=/dev/sdX        # write to USB (requires confirmation)
```

Output: `build/tanoki.iso` — bootable Fedora netinstall that auto-partitions `/dev/sda`, installs 25+ desktop/development groups, and runs post-install scripts.

<details>
<summary>Project Structure</summary>

```
nas-usb/
├── kickstart/           # Kickstart configuration files
│   └── kickstart.ks     # Main kickstart (partitioning, packages, post-install)
├── iso/                 # Downloaded source ISO (gitignored)
├── build/               # Build output (gitignored)
├── Makefile             # Build automation
└── README.md
```

</details>

<details>
<summary>SSH Keys</summary>

The build automatically copies `~/.ssh/id_*` and `known_hosts` into the ISO. During install, the kickstart `%post` copies them to `/root/.ssh/` (mode 600), enabling `git clone` of the nas-ansible repo via SSH. No manual key copying needed.

</details>

<details>
<summary>Make Targets</summary>

| Target | Description |
|---|---|
| `make` | Show help (default) |
| `make setup` | Install required tools (xorriso, isomd5sum, aria2, pykickstart, syslinux) |
| `make download` | Download Fedora 44 Everything netinstall ISO via aria2 (10 EU mirrors) |
| `make check-iso` | Verify downloaded ISO checksum |
| `make validate-ks` | Validate kickstart syntax with `ksvalidator` |
| `make build` | Extract ISO, inject kickstart + SSH keys, patch boot config, rebuild |
| `make flash DEV=/dev/sdX` | Write ISO to USB with confirmation, sync, and eject |
| `make eject DEV=/dev/sdX` | Safely eject a USB device |
| `make clean` | Remove build artifacts |
| `make clean-all` | Remove build artifacts and downloaded ISOs |

</details>

<details>
<summary>Disk Layout</summary>

The installer wipes `/dev/sda` completely and creates:

| Partition | Size | Filesystem | Mount Point | Purpose |
|---|---|---|---|---|
| sda1 | 1 MB | biosboot | — | BIOS boot (GPT compatibility) |
| sda2 | 512 MB | vfat | /boot/efi | EFI System Partition |
| sda3 | 1.9 GB | xfs | /boot | Boot partition |
| sda4 | 55.9 GB | xfs | / | Root filesystem |
| sda5 | 90.1 GB | xfs | /downloads | Downloads / media storage |
| sda6 | remaining | raw | — | bcache cache (created in %post) |

</details>

<details>
<summary>System Configuration</summary>

| Setting | Value |
|---|---|
| Language | en_US.UTF-8 |
| Keyboard | Portuguese (pt) |
| Timezone | Europe/Lisbon (UTC) |
| Hostname | tanoki.online |
| Root password | 123456 (plaintext, change after install) |
| User | nas / nas (wheel group, sudo access) |
| SELinux | Enforcing |
| Firewall | Enabled (SSH, Samba, NFS, Cockpit) |
| Root SSH login | Enabled (PermitRootLogin yes) |
| SSH password auth | Enabled (PasswordAuthentication yes) |
| Default boot target | multi-user.target (console, no GUI) |
| Install source | Fedora 44 mirrorlist (network) |

</details>

<details>
<summary>Package Groups (25+)</summary>

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

</details>

<details>
<summary>Individual Packages (from nas-ansible roles)</summary>

| Category | Packages |
|---|---|
| Core tools | vim, git, htop, tmux, curl, wget, gcc, make, python3-pip, nodejs, npm, openssl, dbus, rsync |
| Ansible | ansible-core, sshpass, ansible-* (via dnf in %post) |
| Containers | podman, podman-compose, podman-docker, containernetworking-plugins |
| Storage | mdadm, lvm2, xfsprogs, bcache-tools, ledmon, hdparm, lsscsi, nvme-cli, parted, gdisk |
| Network | samba, samba-client, netatalk, postfix, unbound, dnsmasq, avahi, bind-utils, vsftpd, nfs-utils |
| Security | fail2ban-server, clamav, clamd, policycoreutils-python-utils, authselect, audit, lynis, certbot |
| Monitoring | pcp, sysstat, smartmontools, cockpit-ws + 12 cockpit plugins |
| System | chrony, cronie, kexec-tools, tuned, logrotate, rsyslog, dnf5-plugin-automatic, firewalld |
| Hardware | lm_sensors, ipmitool, freeipmi |
| Virtualisation | libvirt, qemu-kvm, virt-install |
| Boot | plymouth, plymouth-plugin-two-step, plymouth-scripts |

</details>

<details>
<summary>Post-Install Scripts</summary>

The `%post` section runs after installation:

1. **Set default target** to multi-user.target (console boot)
2. **Enable root SSH** — PermitRootLogin yes + PasswordAuthentication yes
3. **Copy SSH keys** from installer media to `/root/.ssh/` (mode 600)
4. **Install ansible-*** — `dnf install -y ansible-*`
5. **Clone nas-ansible** — `git clone git@github.com:tamashiiiiiiiii/nas-ansible.git /opt/nas-ansible` (falls back to HTTPS)
6. **Create bcache partition** — raw partition filling remaining disk space via parted
7. **Install AI coding tools:**
   - [Claude Code](https://claude.ai) — Anthropic's CLI coding assistant
   - [OpenCode](https://opencode.ai) — Open-source coding agent
   - [Codex](https://www.npmjs.com/package/@openai/codex) — OpenAI's CLI tool
   - [Cursor](https://cursor.com) — AI-powered code editor
   - [Grok CLI](https://x.ai) — xAI's command-line interface

**Enabled services:** sshd, NetworkManager, cockpit.socket, postfix, samba, nfs-server, fail2ban, clamav-freshclam, tuned, pcp

</details>

<details>
<summary>Build Process</summary>

1. `make download` fetches the Fedora 44 Everything netinstall ISO (~1.2 GB) into `iso/source.iso`
2. `make check-iso` verifies against the known SHA256 checksum
3. `make build`:
   - Extracts the ISO with xorriso
   - Injects `kickstart.ks` as `/ks.cfg` at the ISO root
   - Embeds `~/.ssh/id_*` keys into `/ssh-keys/`
   - Patches `grub.cfg` to add `inst.ks=cdrom:/ks.cfg` to all boot entries
   - Rebuilds hybrid ISO (BIOS + UEFI) preserving the original volume ID
   - Implants MD5 checksum with isomd5sum
   - Cleans up the extracted ISO tree
   - Outputs `build/tanoki.iso`

</details>

<details>
<summary>Download Mirrors</summary>

The `make download` target uses `aria2c` for parallel downloading from 10 Western European mirrors:

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

</details>

<details>
<summary>Writing to USB</summary>

Use `make flash DEV=/dev/sdX` which will:

1. Show device info, lsusb output, and existing partitions
2. Require you to type the full device path to confirm
3. Write the ISO with `dd`, run `sync`, and eject

To identify your USB device first:
```bash
lsblk -d -o NAME,SIZE,MODEL,TRAN
```

After booting from the USB, the installer will automatically wipe `/dev/sda`, partition, install all packages from the network, run post-install scripts, and reboot into multi-user.target.

</details>

<details>
<summary>Requirements</summary>

| Requirement | Purpose |
|---|---|
| `xorriso` | ISO extraction and rebuild |
| `isomd5sum` | ISO checksum implanting |
| `aria2` | Parallel multi-mirror ISO download |
| `pykickstart` | Kickstart validation (`ksvalidator`) |
| `syslinux` | MBR boot image for hybrid ISO |
| Network access | Installer fetches packages from Fedora mirrors |

All tools are auto-installed by `make setup`.

</details>

<details>
<summary>Updating Fedora Version</summary>

Edit the version variables at the top of the `Makefile`:

```makefile
FEDORA_VER := 44
FEDORA_REL := 1.7
```

You will also need to update `ISO_SHA256` and the `url --mirrorlist` in `kickstart/kickstart.ks`.

Then run `make clean-all && make download && make build`.

</details>
