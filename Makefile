# Makefile for building a custom Fedora ISO via kickstart
#
# Usage:
#   1. Download a Fedora Workstation Live ISO into this directory
#   2. make build
#   3. make check-iso
#
# Requirements: livecd-tools, pykickstart, genisoimage/xorriso

SHELL := /bin/bash

# Auto-detect the source ISO (first .iso file that isn't our output)
ISO_SRC := $(shell ls -1 Fedora-*.iso 2>/dev/null | head -1)
ISO_OUT := nas-workstation.iso
KS_FILE := kickstart.ks
SCRATCH := scratch

FEDORA_VER := 44
FEDORA_REL := 1.7
ISO_NAME := Fedora-Workstation-Live-$(FEDORA_VER)-$(FEDORA_REL).x86_64.iso
CHECKSUM_NAME := Fedora-Workstation-$(FEDORA_VER)-$(FEDORA_REL)-x86_64-CHECKSUM
BASE_URL := https://download.fedoraproject.org/pub/fedora/linux/releases/$(FEDORA_VER)/Workstation/x86_64/iso

.PHONY: build clean check-iso validate-ks help download

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

validate-ks: ## Validate the kickstart file syntax
	@echo "Validating kickstart..."
	ksvalidator $(KS_FILE)
	@echo "Kickstart is valid."

check-iso: ## Verify ISO integrity with sha256sum
	@if [ -z "$(ISO_SRC)" ]; then echo "ERROR: No Fedora ISO found. Download one first."; exit 1; fi
	@echo "Checking ISO: $(ISO_SRC)"
	@CHECKSUM_FILE=$$(ls -1 *-CHECKSUM 2>/dev/null | head -1); \
	if [ -n "$$CHECKSUM_FILE" ]; then \
		sha256sum -c --ignore-missing "$$CHECKSUM_FILE"; \
	else \
		echo "No CHECKSUM file found. Computing checksum:"; \
		sha256sum "$(ISO_SRC)"; \
	fi

build: validate-ks ## Build the custom ISO from kickstart + source ISO
	@if [ -z "$(ISO_SRC)" ]; then echo "ERROR: No Fedora ISO found. Download one first."; exit 1; fi
	@echo "Building custom ISO from $(ISO_SRC) with $(KS_FILE)..."
	@mkdir -p $(SCRATCH)
	sudo livemedia-creator \
		--make-iso \
		--iso=$(ISO_SRC) \
		--ks=$(KS_FILE) \
		--resultdir=$(SCRATCH)/result \
		--tmp=$(SCRATCH)/tmp \
		--logfile=$(SCRATCH)/build.log \
		--project="NAS Workstation" \
		--releasever=44 \
		--volid="NAS-WS"
	@if [ -f $(SCRATCH)/result/images/boot.iso ]; then \
		mv $(SCRATCH)/result/images/boot.iso $(ISO_OUT); \
		echo "Built: $(ISO_OUT) ($$(du -h $(ISO_OUT) | cut -f1))"; \
	else \
		echo "ERROR: Build failed. Check $(SCRATCH)/build.log"; \
		exit 1; \
	fi

clean: ## Remove build artifacts and scratch directory
	rm -rf $(SCRATCH)
	rm -f $(ISO_OUT)
	@echo "Cleaned."

download: ## Download the Fedora Workstation ISO (uses aria2 if available for speed)
	@echo "Downloading Fedora Workstation $(FEDORA_VER)-$(FEDORA_REL)..."
	@if ! command -v aria2c >/dev/null 2>&1; then \
		echo "Installing aria2..."; \
		if command -v dnf >/dev/null 2>&1; then sudo dnf install -y aria2; \
		elif command -v apt-get >/dev/null 2>&1; then sudo apt-get install -y aria2; \
		elif command -v pacman >/dev/null 2>&1; then sudo pacman -S --noconfirm aria2; \
		else echo "ERROR: Could not install aria2. Install it manually."; exit 1; fi; \
	fi
	@echo "Using aria2c (parallel download from 10 mirrors across Western Europe)..."
	aria2c -x 10 -s 10 -j 10 -k 1M --file-allocation=none --auto-file-renaming=false \
		-o $(ISO_NAME) \
		"https://mirror.23m.com/fedora/linux/releases/$(FEDORA_VER)/Workstation/x86_64/iso/$(ISO_NAME)" \
		"https://mirror.i3d.net/pub/fedora/linux/releases/$(FEDORA_VER)/Workstation/x86_64/iso/$(ISO_NAME)" \
		"https://fedora.mirrorservice.org/fedora/linux/releases/$(FEDORA_VER)/Workstation/x86_64/iso/$(ISO_NAME)" \
		"https://mirror.in2p3.fr/pub/fedora/linux/releases/$(FEDORA_VER)/Workstation/x86_64/iso/$(ISO_NAME)" \
		"https://www.nic.funet.fi/pub/mirrors/fedora.redhat.com/pub/fedora/linux/releases/$(FEDORA_VER)/Workstation/x86_64/iso/$(ISO_NAME)" \
		"https://mirror.netsite.dk/fedora/linux/releases/$(FEDORA_VER)/Workstation/x86_64/iso/$(ISO_NAME)" \
		"https://ftp-stud.hs-esslingen.de/pub/fedora/linux/releases/$(FEDORA_VER)/Workstation/x86_64/iso/$(ISO_NAME)" \
		"https://mirror.init7.net/fedora/fedora/linux/releases/$(FEDORA_VER)/Workstation/x86_64/iso/$(ISO_NAME)" \
		"https://mirror.imt-systems.com/fedora/linux/releases/$(FEDORA_VER)/Workstation/x86_64/iso/$(ISO_NAME)" \
		"https://mirror.bahnhof.net/pub/fedora/linux/releases/$(FEDORA_VER)/Workstation/x86_64/iso/$(ISO_NAME)"
	curl -L -o $(CHECKSUM_NAME) "$(BASE_URL)/$(CHECKSUM_NAME)"
	@echo "Download complete. Run 'make check-iso' to verify."
