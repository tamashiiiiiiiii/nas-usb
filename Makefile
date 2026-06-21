# Makefile for Tanoki Fedora Custom ISO Builder
#
# Extracts the original Fedora ISO, injects kickstart + SSH keys,
# patches boot config to auto-load kickstart, and rebuilds the ISO.
#
# Usage:
#   cp ~/.ssh/id_* ssh-keys/          # provide SSH keys
#   make download                      # fetch Fedora ISO
#   make check-iso                     # verify checksum
#   make build                         # build custom ISO
#   make flash DEV=/dev/sdX            # write to USB + sync + eject
#
# Requirements: xorriso, isomd5sum, aria2

SHELL := /bin/bash

FEDORA_VER := 44
FEDORA_REL := 1.7
ARCH := x86_64
ISO_NAME := Fedora-Workstation-Live-$(FEDORA_VER)-$(FEDORA_REL).$(ARCH).iso
CHECKSUM_NAME := Fedora-Workstation-$(FEDORA_VER)-$(FEDORA_REL)-$(ARCH)-CHECKSUM
ISO_SHA256 := 1620295f6a00c27c3208f0c00b8ece4eab1ec69b9002152d97488bf26a426ddf
BASE_URL := https://download.fedoraproject.org/pub/fedora/linux/releases/$(FEDORA_VER)/Workstation/$(ARCH)/iso
OUTPUT_ISO := Fedora-$(FEDORA_VER)-Tanoki-$(ARCH).iso

ISO_DIR := iso
KS_DIR := kickstart
SSH_DIR := ssh-keys
BUILD_DIR := build
WORK_DIR := $(BUILD_DIR)/iso-root

ISO_SRC := $(ISO_DIR)/$(ISO_NAME)
ISO_OUT := $(BUILD_DIR)/$(OUTPUT_ISO)
KS_FILE := $(KS_DIR)/kickstart.ks

.PHONY: help build clean clean-all check-iso check-deps validate-ks download flash

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

check-deps: ## Install build dependencies (xorriso, isomd5sum, aria2)
	@echo "Checking dependencies..."
	@command -v xorriso >/dev/null 2>&1 || { echo "Installing xorriso..."; sudo dnf -y install xorriso; }
	@command -v implantisomd5 >/dev/null 2>&1 || { echo "Installing isomd5sum..."; sudo dnf -y install isomd5sum; }
	@if ! command -v aria2c >/dev/null 2>&1; then \
		echo "Installing aria2..."; \
		if command -v dnf >/dev/null 2>&1; then sudo dnf install -y aria2; \
		elif command -v apt-get >/dev/null 2>&1; then sudo apt-get install -y aria2; \
		elif command -v pacman >/dev/null 2>&1; then sudo pacman -S --noconfirm aria2; \
		fi; \
	fi
	@echo "All dependencies satisfied."

validate-ks: ## Validate the kickstart file syntax
	@echo "Validating kickstart..."
	ksvalidator $(KS_FILE)
	@echo "Kickstart is valid."

check-iso: ## Verify ISO integrity with sha256sum
	@if [ ! -f "$(ISO_SRC)" ]; then echo "ERROR: $(ISO_SRC) not found. Run 'make download' first."; exit 1; fi
	@echo "Checking ISO: $(ISO_SRC)"
	@echo "$(ISO_SHA256)  $(ISO_SRC)" | sha256sum -c -

download: check-deps ## Download the Fedora Workstation ISO (parallel multi-mirror)
	@echo "Downloading Fedora Workstation $(FEDORA_VER)-$(FEDORA_REL)..."
	@mkdir -p $(ISO_DIR)
	@echo "Using aria2c (parallel download from 10 mirrors across Western Europe)..."
	cd $(ISO_DIR) && aria2c -x 10 -s 10 -j 10 -k 1M --file-allocation=none --auto-file-renaming=false \
		-o $(ISO_NAME) \
		"https://mirror.23m.com/fedora/linux/releases/$(FEDORA_VER)/Workstation/$(ARCH)/iso/$(ISO_NAME)" \
		"https://mirror.i3d.net/pub/fedora/linux/releases/$(FEDORA_VER)/Workstation/$(ARCH)/iso/$(ISO_NAME)" \
		"https://fedora.mirrorservice.org/fedora/linux/releases/$(FEDORA_VER)/Workstation/$(ARCH)/iso/$(ISO_NAME)" \
		"https://mirror.in2p3.fr/pub/fedora/linux/releases/$(FEDORA_VER)/Workstation/$(ARCH)/iso/$(ISO_NAME)" \
		"https://www.nic.funet.fi/pub/mirrors/fedora.redhat.com/pub/fedora/linux/releases/$(FEDORA_VER)/Workstation/$(ARCH)/iso/$(ISO_NAME)" \
		"https://mirror.netsite.dk/fedora/linux/releases/$(FEDORA_VER)/Workstation/$(ARCH)/iso/$(ISO_NAME)" \
		"https://ftp-stud.hs-esslingen.de/pub/fedora/linux/releases/$(FEDORA_VER)/Workstation/$(ARCH)/iso/$(ISO_NAME)" \
		"https://mirror.init7.net/fedora/fedora/linux/releases/$(FEDORA_VER)/Workstation/$(ARCH)/iso/$(ISO_NAME)" \
		"https://mirror.imt-systems.com/fedora/linux/releases/$(FEDORA_VER)/Workstation/$(ARCH)/iso/$(ISO_NAME)" \
		"https://mirror.bahnhof.net/pub/fedora/linux/releases/$(FEDORA_VER)/Workstation/$(ARCH)/iso/$(ISO_NAME)"
	curl -L -o $(ISO_DIR)/$(CHECKSUM_NAME) "$(BASE_URL)/$(CHECKSUM_NAME)"
	@echo "Download complete. Run 'make check-iso' to verify."

build: check-deps ## Extract ISO, inject kickstart + SSH keys, rebuild
	@if [ ! -f "$(ISO_SRC)" ]; then echo "ERROR: $(ISO_SRC) not found. Run 'make download' first."; exit 1; fi
	@if [ ! -f "$(KS_FILE)" ]; then echo "ERROR: $(KS_FILE) not found."; exit 1; fi
	@echo "=== Building custom Tanoki ISO ==="
	@echo ""
	@# Clean previous build
	rm -rf $(WORK_DIR)
	mkdir -p $(BUILD_DIR)
	@# Step 1: Extract ISO contents
	@echo "[1/6] Extracting $(ISO_SRC)..."
	xorriso -osirrox on -indev $(ISO_SRC) -extract / $(WORK_DIR)
	chmod -R u+w $(WORK_DIR)
	@# Step 2: Inject kickstart file
	@echo "[2/6] Injecting kickstart..."
	cp $(KS_FILE) $(WORK_DIR)/ks.cfg
	@# Step 3: Copy SSH keys into ISO
	@echo "[3/6] Embedding SSH keys..."
	mkdir -p $(WORK_DIR)/ssh-keys
	@if [ -d "$(SSH_DIR)" ] && [ "$$(ls -A $(SSH_DIR) 2>/dev/null | grep -v .gitkeep)" ]; then \
		cp -a $(SSH_DIR)/* $(WORK_DIR)/ssh-keys/ 2>/dev/null; \
		rm -f $(WORK_DIR)/ssh-keys/.gitkeep; \
		echo "  Copied: $$(ls $(WORK_DIR)/ssh-keys/)"; \
	else \
		echo "  WARNING: No SSH keys found in $(SSH_DIR)/. Git clone in %%post will use HTTPS fallback."; \
	fi
	@# Step 4: Patch boot configs to auto-load kickstart
	@echo "[4/6] Patching boot configuration..."
	@# Patch isolinux (BIOS boot)
	@if [ -f $(WORK_DIR)/isolinux/isolinux.cfg ]; then \
		sed -i 's|append |append inst.ks=cdrom:/ks.cfg |g' $(WORK_DIR)/isolinux/isolinux.cfg; \
		echo "  Patched: isolinux/isolinux.cfg"; \
	fi
	@if [ -f $(WORK_DIR)/isolinux/grub.conf ]; then \
		sed -i 's|append |append inst.ks=cdrom:/ks.cfg |g' $(WORK_DIR)/isolinux/grub.conf; \
		echo "  Patched: isolinux/grub.conf"; \
	fi
	@# Patch GRUB (UEFI boot)
	@if [ -f $(WORK_DIR)/EFI/BOOT/grub.cfg ]; then \
		sed -i '/^menuentry/,/^}/{s|linux\(.*\)|linux\1 inst.ks=cdrom:/ks.cfg|}' $(WORK_DIR)/EFI/BOOT/grub.cfg; \
		echo "  Patched: EFI/BOOT/grub.cfg"; \
	fi
	@if [ -f $(WORK_DIR)/boot/grub2/grub.cfg ]; then \
		sed -i '/^menuentry/,/^}/{s|linux\(.*\)|linux\1 inst.ks=cdrom:/ks.cfg|}' $(WORK_DIR)/boot/grub2/grub.cfg; \
		echo "  Patched: boot/grub2/grub.cfg"; \
	fi
	@# Step 5: Rebuild ISO with xorriso
	@echo "[5/6] Rebuilding ISO..."
	xorriso -as mkisofs \
		-V "Fedora-Tanoki" \
		-o $(ISO_OUT) \
		-b isolinux/isolinux.bin \
		-c isolinux/boot.cat \
		-no-emul-boot \
		-boot-load-size 4 \
		-boot-info-table \
		-eltorito-alt-boot \
		-e images/efiboot.img \
		-no-emul-boot \
		-isohybrid-mbr /usr/share/syslinux/isohdpfx.bin \
		-isohybrid-gpt-basdat \
		$(WORK_DIR)
	@# Step 6: Implant MD5 checksum
	@echo "[6/6] Implanting ISO checksum..."
	implantisomd5 $(ISO_OUT)
	@echo ""
	@echo "=== Build complete ==="
	@echo "Output: $(ISO_OUT) ($$(du -h $(ISO_OUT) | cut -f1))"
	@echo ""
	@echo "To write to USB, run:  make flash DEV=/dev/sdX"
	@echo "  (identify your USB device first with: lsblk -d -o NAME,SIZE,MODEL,TRAN)"

flash: ## Write ISO to USB drive (requires DEV=/dev/sdX) — DESTRUCTIVE
ifndef DEV
	@echo "ERROR: Specify the USB device."
	@echo ""
	@echo "1. Identify your USB drive:"
	@echo "   lsblk -d -o NAME,SIZE,MODEL,TRAN"
	@echo ""
	@echo "2. Then run:"
	@echo "   make flash DEV=/dev/sdX"
	@exit 1
endif
	@if [ ! -f "$(ISO_OUT)" ]; then echo "ERROR: $(ISO_OUT) not found. Run 'make build' first."; exit 1; fi
	@if [ ! -b "$(DEV)" ]; then echo "ERROR: $(DEV) is not a block device."; exit 1; fi
	@echo ""
	@echo "============================================================"
	@echo "  THIS WILL PERMANENTLY ERASE ALL DATA ON $(DEV)"
	@echo "============================================================"
	@echo ""
	@echo "  Device:  $(DEV)"
	@lsblk -d -o NAME,SIZE,MODEL,TRAN $(DEV) | sed 's/^/  /'
	@echo ""
	@echo "  Existing partitions on $(DEV):"
	@lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT $(DEV) | sed 's/^/  /'
	@echo ""
	@echo "  ISO:     $(ISO_OUT) ($$(du -h $(ISO_OUT) | cut -f1))"
	@echo ""
	@echo "  To confirm, type the FULL device path (e.g. /dev/sdb):"
	@read -p "  > " confirm; \
	if [ "$$confirm" != "$(DEV)" ]; then echo "Aborted. You typed '$$confirm' but the target is '$(DEV)'."; exit 1; fi
	@echo ""
	sudo dd if=$(ISO_OUT) of=$(DEV) bs=4M status=progress oflag=sync
	sync
	sudo eject $(DEV) || true
	@echo ""
	@echo "=== Done. USB drive ejected. Safe to remove. ===

eject: ## Safely eject a USB device (requires DEV=/dev/sdX)
ifndef DEV
	@echo "Usage: make eject DEV=/dev/sdX"
	@exit 1
endif
	sync
	sudo eject $(DEV) || sudo udisksctl power-off -b $(DEV) || true
	@echo "$(DEV) ejected. Safe to remove."

clean: ## Remove build artifacts
	rm -rf $(BUILD_DIR)
	@echo "Cleaned."

clean-all: clean ## Remove build artifacts and downloaded ISOs
	rm -f $(ISO_DIR)/*.iso $(ISO_DIR)/*.aria2 $(ISO_DIR)/*-CHECKSUM
	@echo "Cleaned all."
