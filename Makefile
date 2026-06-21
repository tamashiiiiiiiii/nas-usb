# Makefile for building a custom Fedora ISO via kickstart
#
# Project structure:
#   kickstart/   - Kickstart configuration files
#   iso/         - Downloaded source ISOs (gitignored)
#   build/       - Build artifacts and scratch (gitignored)
#
# Usage:
#   make download    # fetch Fedora ISO into iso/
#   make check-iso   # verify checksum
#   make build       # build custom ISO into build/
#
# Requirements: livecd-tools, pykickstart

SHELL := /bin/bash

FEDORA_VER := 44
FEDORA_REL := 1.7
ISO_NAME := Fedora-Workstation-Live-$(FEDORA_VER)-$(FEDORA_REL).x86_64.iso
CHECKSUM_NAME := Fedora-Workstation-$(FEDORA_VER)-$(FEDORA_REL)-x86_64-CHECKSUM
BASE_URL := https://download.fedoraproject.org/pub/fedora/linux/releases/$(FEDORA_VER)/Workstation/x86_64/iso

ISO_DIR := iso
KS_DIR := kickstart
BUILD_DIR := build

ISO_SRC := $(ISO_DIR)/$(ISO_NAME)
ISO_OUT := $(BUILD_DIR)/nas-workstation.iso
KS_FILE := $(KS_DIR)/kickstart.ks

.PHONY: build clean check-iso validate-ks help download

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

validate-ks: ## Validate the kickstart file syntax
	@echo "Validating kickstart..."
	ksvalidator $(KS_FILE)
	@echo "Kickstart is valid."

check-iso: ## Verify ISO integrity with sha256sum
	@if [ ! -f "$(ISO_SRC)" ]; then echo "ERROR: $(ISO_SRC) not found. Run 'make download' first."; exit 1; fi
	@echo "Checking ISO: $(ISO_SRC)"
	@CHECKSUM_FILE=$$(ls -1 $(ISO_DIR)/*-CHECKSUM 2>/dev/null | head -1); \
	if [ -n "$$CHECKSUM_FILE" ]; then \
		cd $(ISO_DIR) && sha256sum -c --ignore-missing "$$(basename $$CHECKSUM_FILE)"; \
	else \
		echo "No CHECKSUM file found. Computing checksum:"; \
		sha256sum "$(ISO_SRC)"; \
	fi

build: validate-ks ## Build the custom ISO from kickstart + source ISO
	@if [ ! -f "$(ISO_SRC)" ]; then echo "ERROR: $(ISO_SRC) not found. Run 'make download' first."; exit 1; fi
	@echo "Building custom ISO from $(ISO_SRC) with $(KS_FILE)..."
	@mkdir -p $(BUILD_DIR)/scratch
	sudo livemedia-creator \
		--make-iso \
		--iso=$(ISO_SRC) \
		--ks=$(KS_FILE) \
		--resultdir=$(BUILD_DIR)/scratch/result \
		--tmp=$(BUILD_DIR)/scratch/tmp \
		--logfile=$(BUILD_DIR)/build.log \
		--project="NAS Workstation" \
		--releasever=$(FEDORA_VER) \
		--volid="NAS-WS"
	@if [ -f $(BUILD_DIR)/scratch/result/images/boot.iso ]; then \
		mv $(BUILD_DIR)/scratch/result/images/boot.iso $(ISO_OUT); \
		echo "Built: $(ISO_OUT) ($$(du -h $(ISO_OUT) | cut -f1))"; \
	else \
		echo "ERROR: Build failed. Check $(BUILD_DIR)/build.log"; \
		exit 1; \
	fi

clean: ## Remove build artifacts
	rm -rf $(BUILD_DIR)/scratch $(BUILD_DIR)/build.log
	rm -f $(ISO_OUT)
	@echo "Cleaned."

clean-all: clean ## Remove build artifacts and downloaded ISOs
	rm -f $(ISO_DIR)/*.iso $(ISO_DIR)/*.aria2 $(ISO_DIR)/*-CHECKSUM
	@echo "Cleaned all."

download: ## Download the Fedora Workstation ISO (parallel multi-mirror)
	@echo "Downloading Fedora Workstation $(FEDORA_VER)-$(FEDORA_REL)..."
	@if ! command -v aria2c >/dev/null 2>&1; then \
		echo "Installing aria2..."; \
		if command -v dnf >/dev/null 2>&1; then sudo dnf install -y aria2; \
		elif command -v apt-get >/dev/null 2>&1; then sudo apt-get install -y aria2; \
		elif command -v pacman >/dev/null 2>&1; then sudo pacman -S --noconfirm aria2; \
		else echo "ERROR: Could not install aria2. Install it manually."; exit 1; fi; \
	fi
	@mkdir -p $(ISO_DIR)
	@echo "Using aria2c (parallel download from 10 mirrors across Western Europe)..."
	cd $(ISO_DIR) && aria2c -x 10 -s 10 -j 10 -k 1M --file-allocation=none --auto-file-renaming=false \
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
	curl -L -o $(ISO_DIR)/$(CHECKSUM_NAME) "$(BASE_URL)/$(CHECKSUM_NAME)"
	@echo "Download complete. Run 'make check-iso' to verify."
