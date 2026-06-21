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

.PHONY: build clean check-iso validate-ks help

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

download: ## Download the latest Fedora Workstation ISO
	@echo "Downloading Fedora Workstation 44..."
	curl -L -C - -o Fedora-Workstation-Live-44-1.7.x86_64.iso \
		https://download.fedoraproject.org/pub/fedora/linux/releases/44/Workstation/x86_64/iso/Fedora-Workstation-Live-44-1.7.x86_64.iso
	curl -L -o Fedora-Workstation-44-1.7-x86_64-CHECKSUM \
		https://download.fedoraproject.org/pub/fedora/linux/releases/44/Workstation/x86_64/iso/Fedora-Workstation-44-1.7-x86_64-CHECKSUM
	@echo "Download complete. Run 'make check-iso' to verify."
