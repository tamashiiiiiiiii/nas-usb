# Quickstart

```bash
make download        # fetch Fedora 44 Workstation ISO
make check-iso       # verify checksum
make build           # build custom ISO with kickstart
```

The output ISO (`nas-workstation.iso`) is a bootable installer that auto-partitions `/dev/sda` and installs a full workstation environment.

## Make Targets

| Target | Description |
|---|---|
| `make help` | Show available targets |
| `make download` | Download Fedora Workstation 44 ISO |
| `make check-iso` | Verify ISO checksum |
| `make validate-ks` | Validate kickstart syntax |
| `make build` | Build the custom ISO |
| `make clean` | Remove build artifacts |

## Kickstart Configuration

The `kickstart.ks` file defines the automated install:

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
- Root access for `livemedia-creator`
- ~10GB free space for build

## Files

| File | Purpose |
|---|---|
| `kickstart.ks` | Fedora kickstart configuration |
| `Makefile` | Build automation |
| `.gitignore` | Excludes ISOs and scratch from git |
