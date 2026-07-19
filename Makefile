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
#   make vm-create                     # create test VM with SATA disks
#   make vm-start                      # boot the VM
#   make vm-stop                       # graceful shutdown
#   make vm-destroy                    # remove VM + disk images
#
# Requirements: xorriso, isomd5sum, aria2, qemu-kvm, libvirt, virt-install

SHELL := /bin/bash

FEDORA_VER := 44
FEDORA_REL := 1.7
ISO_LABEL := Fedora-E-dvd-x86_64-44
ARCH := x86_64
ISO_NAME := Fedora-Everything-netinst-$(ARCH)-$(FEDORA_VER)-$(FEDORA_REL).iso
CHECKSUM_NAME := Fedora-Everything-$(FEDORA_VER)-$(FEDORA_REL)-$(ARCH)-CHECKSUM
ISO_SHA256 := bd285201494dd0ba09b54d05ac707de1401668b8512a573edb5922dcf9d7067e
BASE_URL := https://download.fedoraproject.org/pub/fedora/linux/releases/$(FEDORA_VER)/Everything/$(ARCH)/iso
OUTPUT_ISO := tanoki.iso

ISO_DIR := iso
KS_DIR := kickstart
SSH_DIR := $(HOME)/.ssh
VAULT_PASS := ../nas-ansible/.vault_pass
BUILD_DIR := build
WORK_DIR := $(BUILD_DIR)/iso-root
VM_DIR := $(CURDIR)/vm
VM_NAME := tanoki
VM_XML := $(VM_DIR)/tanoki.xml

ISO_SRC := $(ISO_DIR)/source.iso
ISO_OUT := $(BUILD_DIR)/$(OUTPUT_ISO)
KS_FILE := $(KS_DIR)/kickstart.ks

.DEFAULT_GOAL := help
.PHONY: help setup build clean clean-all check-iso validate-ks download flash iso eject \
       vm-create vm-start vm-stop vm-destroy vm-console

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

setup: ## Install required tools (xorriso, isomd5sum, aria2, pykickstart, syslinux)
	@echo "Installing build dependencies..."
	@if command -v dnf >/dev/null 2>&1; then \
		sudo dnf install -y xorriso isomd5sum aria2 pykickstart syslinux; \
	elif command -v apt-get >/dev/null 2>&1; then \
		sudo apt-get install -y xorriso aria2 syslinux-utils; \
	elif command -v pacman >/dev/null 2>&1; then \
		sudo pacman -S --noconfirm xorriso aria2 syslinux; \
	else \
		echo "ERROR: Unsupported package manager."; exit 1; \
	fi
	@echo "All dependencies installed."

validate-ks: ## Validate the kickstart file syntax
	@echo "Validating kickstart..."
	ksvalidator $(KS_FILE)
	@echo "Kickstart is valid."

check-iso: ## Verify ISO integrity with sha256sum
	@if [ ! -f "$(ISO_SRC)" ]; then echo "ERROR: $(ISO_SRC) not found. Run 'make download' first."; exit 1; fi
	@echo "Checking ISO: $(ISO_SRC)"
	@echo "$(ISO_SHA256)  $(ISO_SRC)" | sha256sum -c -

download: ## Download the Fedora Workstation ISO (parallel multi-mirror)
	@echo "Downloading Fedora Workstation $(FEDORA_VER)-$(FEDORA_REL)..."
	@mkdir -p $(ISO_DIR)
	@echo "Using aria2c (parallel download from 10 mirrors across Western Europe)..."
	cd $(ISO_DIR) && aria2c -x 10 -s 10 -j 10 -k 1M --file-allocation=none --auto-file-renaming=false \
		-o source.iso \
		"https://mirror.23m.com/fedora/linux/releases/$(FEDORA_VER)/Everything/$(ARCH)/iso/$(ISO_NAME)" \
		"https://mirror.i3d.net/pub/fedora/linux/releases/$(FEDORA_VER)/Everything/$(ARCH)/iso/$(ISO_NAME)" \
		"https://fedora.mirrorservice.org/fedora/linux/releases/$(FEDORA_VER)/Everything/$(ARCH)/iso/$(ISO_NAME)" \
		"https://mirror.in2p3.fr/pub/fedora/linux/releases/$(FEDORA_VER)/Everything/$(ARCH)/iso/$(ISO_NAME)" \
		"https://www.nic.funet.fi/pub/mirrors/fedora.redhat.com/pub/fedora/linux/releases/$(FEDORA_VER)/Everything/$(ARCH)/iso/$(ISO_NAME)" \
		"https://mirror.netsite.dk/fedora/linux/releases/$(FEDORA_VER)/Everything/$(ARCH)/iso/$(ISO_NAME)" \
		"https://ftp-stud.hs-esslingen.de/pub/fedora/linux/releases/$(FEDORA_VER)/Everything/$(ARCH)/iso/$(ISO_NAME)" \
		"https://mirror.init7.net/fedora/fedora/linux/releases/$(FEDORA_VER)/Everything/$(ARCH)/iso/$(ISO_NAME)" \
		"https://mirror.imt-systems.com/fedora/linux/releases/$(FEDORA_VER)/Everything/$(ARCH)/iso/$(ISO_NAME)" \
		"https://mirror.bahnhof.net/pub/fedora/linux/releases/$(FEDORA_VER)/Everything/$(ARCH)/iso/$(ISO_NAME)"
	curl -L -o $(ISO_DIR)/$(CHECKSUM_NAME) "$(BASE_URL)/$(CHECKSUM_NAME)"
	@echo "Download complete. Run 'make check-iso' to verify."

build: ## Extract ISO, inject kickstart + SSH keys, rebuild
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
	@# Step 3: Copy all SSH keys + build authorized_keys
	@echo "[3/6] Embedding SSH keys from $(SSH_DIR)/..."
	mkdir -p $(WORK_DIR)/ssh-keys
	@for f in $(SSH_DIR)/*; do \
		[ -f "$$f" ] || continue; \
		case "$$(basename $$f)" in \
			*.old|config|*.swp) continue ;; \
		esac; \
		cp "$$f" $(WORK_DIR)/ssh-keys/; \
		echo "  Copied: $$(basename $$f)"; \
	done
	@grep -rl '^ssh-\|^ecdsa-\|^sk-ssh-' $(WORK_DIR)/ssh-keys/ 2>/dev/null \
		| xargs cat > $(WORK_DIR)/ssh-keys/authorized_keys 2>/dev/null || true
	@if [ -s $(WORK_DIR)/ssh-keys/authorized_keys ]; then \
		echo "  Built authorized_keys ($$(wc -l < $(WORK_DIR)/ssh-keys/authorized_keys) keys)"; \
	else \
		echo "  WARNING: no public keys found for authorized_keys"; \
	fi
	@# Select SSH key for github.com — auto-detect if only one, otherwise prompt
	@PRIVKEYS=$$(grep -rl 'PRIVATE KEY' $(WORK_DIR)/ssh-keys/ 2>/dev/null | sort); \
	KEYCOUNT=$$(echo "$$PRIVKEYS" | wc -w); \
	if [ "$$KEYCOUNT" -eq 0 ]; then \
		echo "  WARNING: no private keys found, skipping SSH config"; \
	elif [ "$$KEYCOUNT" -eq 1 ]; then \
		CHOSEN=$$(basename $$PRIVKEYS); \
		echo "  Auto-selected SSH key for github.com: $$CHOSEN (only key)"; \
	else \
		echo ""; \
		echo "  Multiple SSH private keys found:"; \
		i=1; for k in $$PRIVKEYS; do \
			echo "    $$i) $$(basename $$k)"; \
			i=$$((i+1)); \
		done; \
		echo ""; \
		printf "  Select key for github.com [1-$$KEYCOUNT]: "; \
		read choice; \
		CHOSEN=$$(echo "$$PRIVKEYS" | tr ' ' '\n' | sed -n "$${choice}p" | xargs basename); \
		if [ -z "$$CHOSEN" ]; then echo "  Invalid selection, skipping SSH config"; CHOSEN=""; fi; \
	fi; \
	if [ -n "$$CHOSEN" ]; then \
		printf "Host github.com\n  IdentityFile ~/.ssh/%s\n  IdentitiesOnly yes\n  StrictHostKeyChecking accept-new\n" "$$CHOSEN" \
			> $(WORK_DIR)/ssh-keys/config; \
		echo "  Wrote ssh config: github.com -> $$CHOSEN"; \
	fi
	@# Copy vault_pass if configured and available
	@if [ -n "$(VAULT_PASS)" ] && [ -f "$(VAULT_PASS)" ]; then \
		cp "$(VAULT_PASS)" $(WORK_DIR)/ssh-keys/vault_pass; \
		echo "  Copied vault_pass"; \
	elif [ -n "$(VAULT_PASS)" ]; then \
		echo "  WARNING: $(VAULT_PASS) not found, skipping"; \
	fi
	@# Step 3b: Inject Anaconda cyberpunk theme
	@echo "  Injecting cyberpunk theme..."
	@if [ -f theme/tanoki-cyberpunk.css ]; then \
		THEME_DIR=$(WORK_DIR)/usr/share/anaconda/pixmaps; \
		mkdir -p "$$THEME_DIR"; \
		cp theme/tanoki-cyberpunk.css "$$THEME_DIR/custom.css"; \
	fi
	@# Step 4: Patch boot configs to auto-load kickstart
	@echo "[4/6] Patching boot configuration..."
	@# Patch isolinux (BIOS boot) — netinstall ISOs
	@if [ -f $(WORK_DIR)/isolinux/isolinux.cfg ]; then \
		sed -i '/inst\.ks/!s|append |append inst.ks=hd:LABEL=$(ISO_LABEL):/ks.cfg |' $(WORK_DIR)/isolinux/isolinux.cfg; \
		echo "  Patched: isolinux/isolinux.cfg"; \
	fi
	@if [ -f $(WORK_DIR)/isolinux/grub.conf ]; then \
		sed -i '/inst\.ks/!s|append |append inst.ks=hd:LABEL=$(ISO_LABEL):/ks.cfg |' $(WORK_DIR)/isolinux/grub.conf; \
		echo "  Patched: isolinux/grub.conf"; \
	fi
	@# Patch GRUB — add inst.ks, set timeout=0, default=0 for instant boot
	@for grubcfg in $(WORK_DIR)/EFI/BOOT/grub.cfg $(WORK_DIR)/boot/grub2/grub.cfg; do \
		if [ -f "$$grubcfg" ]; then \
			sed -i '/inst\.ks/!{/linux.*vmlinuz/s|quiet|inst.ks=hd:LABEL=$(ISO_LABEL):/ks.cfg quiet|}' "$$grubcfg"; \
			sed -i 's/^set timeout=.*/set timeout=0/' "$$grubcfg"; \
			sed -i 's/^set default=.*/set default="0"/' "$$grubcfg"; \
			echo "  Patched: $$(echo $$grubcfg | sed 's|.*/iso-root/||')"; \
		fi; \
	done
	@# Step 5: Rebuild ISO with xorriso (BIOS + UEFI hybrid)
	@echo "[5/6] Rebuilding ISO..."
	xorriso -as mkisofs \
		-V "$(ISO_LABEL)" \
		-o $(ISO_OUT) \
		-b images/eltorito.img \
		-no-emul-boot \
		-boot-load-size 4 \
		-boot-info-table \
		--grub2-boot-info \
		--grub2-mbr $(WORK_DIR)/boot/grub2/i386-pc/boot_hybrid.img \
		-eltorito-alt-boot \
		-e --interval:appended_partition_2:all:: \
		-no-emul-boot \
		-isohybrid-gpt-basdat \
		-append_partition 2 C12A7328-F81F-11D2-BA4B-00A0C93EC93B $(WORK_DIR)/images/eltorito.img \
		$(WORK_DIR)
	@# Step 6: Implant MD5 checksum
	@echo "[6/6] Implanting ISO checksum..."
	implantisomd5 $(ISO_OUT)
	@# Clean up extracted ISO tree
	rm -rf $(WORK_DIR)
	@echo ""
	@echo "=== Build complete ==="
	@echo "Output: $(ISO_OUT) ($$(du -h $(ISO_OUT) | cut -f1))"
	@echo ""
	@echo "To write to USB:  make flash DEV=/dev/sdX"
	@echo "To copy ISO out:  make iso [DEST=/path/to/output.iso]"
	@echo "  (identify your USB device with: lsblk -d -o NAME,SIZE,MODEL,TRAN)"

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
	@echo "  Connected USB devices:"
	@lsusb 2>/dev/null | sed 's/^/  /' || true
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
	@echo "=== Done. USB drive ejected. Safe to remove. ==="

iso: build ## Copy built ISO to current directory (or DEST=/path/to/file.iso)
	@cp $(ISO_OUT) $(or $(DEST),./$(OUTPUT_ISO))
	@echo ""
	@echo "=== ISO copied ==="
	@echo "Output: $(or $(DEST),./$(OUTPUT_ISO)) ($$(du -h $(or $(DEST),./$(OUTPUT_ISO)) | cut -f1))"

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

# ── VM targets (QEMU/KVM with SATA disks for kickstart compatibility) ────

vm-create: ## Create test VM: qcow2 disks + define from XML
	@if [ ! -f "$(OUTPUT_ISO)" ]; then echo "ERROR: ./$(OUTPUT_ISO) not found. Run 'make iso' first."; exit 1; fi
	@echo "=== Creating $(VM_NAME) VM ==="
	@if sudo virsh dominfo $(VM_NAME) >/dev/null 2>&1; then \
		echo "ERROR: VM '$(VM_NAME)' already exists. Run 'make vm-destroy' first."; exit 1; \
	fi
	@echo "[1/4] Creating disk images..."
	qemu-img create -f qcow2 $(VM_DIR)/tanoki-sda.qcow2 200G
	qemu-img create -f qcow2 $(VM_DIR)/tanoki-sdb.qcow2 50G
	@for d in sdc sdd sde sdf sdg; do \
		qemu-img create -f qcow2 $(VM_DIR)/tanoki-$$d.qcow2 20G; \
	done
	@echo "[2/4] Copying ISO into vm/..."
	cp $(OUTPUT_ISO) $(VM_DIR)/tanoki.iso
	@echo "[3/4] Generating VM definition..."
	sed -e 's|@@VM_DIR@@|$(VM_DIR)|g' \
	    $(VM_XML) > $(BUILD_DIR)/tanoki-vm.xml
	@echo "[4/4] Defining VM..."
	sudo virsh define $(BUILD_DIR)/tanoki-vm.xml
	@echo ""
	@echo "=== VM '$(VM_NAME)' created ==="
	@echo "  Disks: sda(200G) sdb(50G) sdc-sdg(20G each)"
	@echo "  ISO:   vm/tanoki.iso"
	@echo ""
	@echo "Run 'make vm-start' to boot."

vm-start: ## Start the VM and open SPICE console
	@if ! sudo virsh dominfo $(VM_NAME) >/dev/null 2>&1; then \
		echo "ERROR: VM '$(VM_NAME)' not defined. Run 'make vm-create' first."; exit 1; \
	fi
	sudo virsh start $(VM_NAME)
	@echo "VM '$(VM_NAME)' started."
	@echo "Opening console... (close the viewer window to detach)"
	@sleep 1
	virt-viewer --connect qemu:///system $(VM_NAME) &

vm-stop: ## Graceful shutdown of the VM
	sudo virsh shutdown $(VM_NAME)
	@echo "Shutdown signal sent to '$(VM_NAME)'."

vm-destroy: ## Force stop + undefine VM + delete disk images — DESTRUCTIVE
	@echo "This will permanently delete VM '$(VM_NAME)' and all its disk images."
	@read -p "Type 'yes' to confirm: " confirm; \
	if [ "$$confirm" != "yes" ]; then echo "Aborted."; exit 1; fi
	-sudo virsh destroy $(VM_NAME) 2>/dev/null
	-sudo virsh undefine $(VM_NAME) --snapshots-metadata 2>/dev/null
	rm -f $(VM_DIR)/tanoki-sd*.qcow2 $(VM_DIR)/tanoki.iso
	rm -f $(BUILD_DIR)/tanoki-vm.xml
	@echo "VM '$(VM_NAME)' removed."

vm-console: ## Open SPICE console to running VM
	virt-viewer --connect qemu:///system $(VM_NAME)
