# Quickstart

```bash
make download        # fetch Fedora 44 Workstation ISO into iso/
make check-iso       # verify checksum
make build           # build custom ISO into build/
```

The output ISO (`build/nas-workstation.iso`) is a bootable installer that auto-partitions `/dev/sda` and installs a full workstation environment.

## Project Structure

```
nas-usb/
├── kickstart/           # Kickstart configuration files
│   └── kickstart.ks     # Main kickstart (partitioning, packages, post-install)
├── iso/                 # Downloaded source ISOs (gitignored)
├── build/               # Build output and scratch (gitignored)
├── Makefile             # Build automation
└── README.md
```

## Make Targets

| Target | Description |
|---|---|
| `make help` | Show available targets |
| `make download` | Download Fedora 44 ISO (parallel multi-mirror via aria2) |
| `make check-iso` | Verify ISO checksum |
| `make validate-ks` | Validate kickstart syntax |
| `make build` | Build the custom ISO |
| `make clean` | Remove build artifacts |
| `make clean-all` | Remove build artifacts and downloaded ISOs |

## Kickstart Configuration

The `kickstart/kickstart.ks` file defines the automated install:

### Disk Layout (`/dev/sda`)

| Partition | Size | Filesystem | Mount Point |
|---|---|---|---|
| sda1 | 512M | vfat | /boot/efi |
| sda2 | 1.9G | xfs | /boot |
| sda3 | 55.9G | xfs | / |
| sda4 | 90.1G | xfs | /downloads |
| sda5 | 90.1G | bcache | (cache only) |

### Package Groups

Installs 25+ desktop and development groups including KDE, COSMIC, Budgie, MATE, LibreOffice, development tools, container management, and media applications.

### Post-Install

- Enables root SSH login
- Installs AI coding tools: Claude Code, OpenCode, Codex, Cursor, Grok CLI

### Requirements

- `livecd-tools` and `pykickstart` (included in kickstart package list)
- `aria2` (auto-installed by Makefile if missing)
- Root access for `livemedia-creator`
- ~10GB free space for build
