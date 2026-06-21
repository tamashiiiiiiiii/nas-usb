# Fedora NAS Workstation Kickstart
# Automated install to /dev/sda with custom partitioning

text
url --mirrorlist=https://mirrors.fedoraproject.org/mirrorlist?repo=fedora-44&arch=x86_64
lang en_US.UTF-8
keyboard --xlayouts='pt'
timezone Europe/Lisbon --utc

# Network
network --bootproto=dhcp --activate --onboot=yes --hostname=tanoki.online

# Root password
rootpw --plaintext 123456

# Users
user --name=nas --password=nas --plaintext --groups=wheel


# SELinux and firewall
selinux --enforcing
firewall --enabled --service=ssh --service=samba --service=nfs --service=cockpit

# Bootloader
bootloader --location=mbr

# Disk partitioning — wipe first disk completely
# Works on sda (SATA/SAS), vda (virtio VM), nvme0n1 (NVMe)
zerombr
clearpart --all --initlabel

part /boot/efi  --fstype=efi  --size=512
part /boot      --fstype=xfs  --size=1946
part /          --fstype=xfs  --size=57242
part /downloads --fstype=xfs  --size=92262

# Default boot target — multi-user (no GUI on boot)
skipx
firstboot --disabled

# Services
services --enabled=sshd,NetworkManager,cockpit.socket,postfix,samba,nfs-server,fail2ban,clamav-freshclam,tuned,pcp

# Reboot after install
reboot --eject

# Package selection — skip unavailable packages, don't block install
%packages --ignoremissing

# Base environment
@^workstation-product-environment

# Desktop environments and apps
@office
@kde-media
@kde-software-development
@libreoffice
@mate-applications
@network-server
@sound-and-video
@system-tools
@window-managers
@design-suite
@audio
@budgie-desktop
@budgie-desktop-apps
@c-development
@cloud-management
@container-management
@cosmic-desktop
@cosmic-desktop-apps
@admin-tools
@desktop-accessibility
@development-tools
@editors
@games
@kde-apps
@kde-desktop

# Media
vlc

# Core tools
vim
git
htop
tmux
curl
wget
gcc
make
python3-pip
python3-passlib
nodejs
npm
openssl
dbus
rsync

# Ansible (from Makefile bootstrap)
ansible-core
sshpass

# Container runtime (from roles/podman)
podman
podman-compose
podman-docker
containernetworking-plugins

# Storage & RAID (from roles/mdadm, roles/fstrim, roles/mounts, Makefile disk-prep)
mdadm
lvm2
xfsprogs
bcache-tools
ledmon
hdparm
lsscsi
nvme-cli
parted
gdisk

# Network services (from roles/samba, roles/netatalk, roles/email-smarthost, roles/unbound, roles/dnsmasq, roles/dns)
samba
samba-client
samba-common
netatalk
postfix
cyrus-sasl-plain
unbound
dnsmasq
avahi
avahi-tools
bind-utils

# File sharing (from roles/ftp, roles/nfs)
vsftpd
nfs-utils

# Security (from roles/fail2ban, roles/clamav, roles/selinux, roles/audit, roles/lynis)
fail2ban-server
fail2ban-sendmail
clamav
clamav-update
clamd
policycoreutils-python-utils
checkpolicy
python3-libselinux
authselect
audit
lynis

# Certificates (from roles/certs)
certbot

# Monitoring (from roles/pcp, roles/sysstat, roles/smartmontools, roles/cockpit)
pcp
pcp-system-tools
sysstat
smartmontools
cockpit-ws
cockpit-system
cockpit-storaged
cockpit-networkmanager
cockpit-podman
cockpit-selinux
cockpit-packagekit
cockpit-machines
cockpit-session-recording
cockpit-sosreport
cockpit-bridge
cockpit-files
cockpit-kdump

# System services (from roles/ntp, roles/cron, roles/kdump, roles/tuned, roles/logrotate, roles/rsyslog, roles/auto-updates)
chrony
cronie
kexec-tools
tuned
logrotate
rsyslog
dnf5-plugin-automatic
firewalld

# Hardware (from roles/fancontrol, roles/ipmi)
lm_sensors
ipmitool
freeipmi

# Virtualisation (from roles/libvirt)
libvirt
qemu-kvm
virt-install

# Boot (from roles/plymouth)
plymouth
plymouth-plugin-two-step
plymouth-scripts

# Misc
mailx
livecd-tools
pykickstart
%end

# Post-install script
%post --log=/root/ks-post.log
set -ex

# Set default target to multi-user (no GUI on boot)
systemctl set-default multi-user.target

# Enable root login and password authentication via SSH
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config

# Copy SSH keys from installer media (placed by Makefile)
if [ -d /run/install/repo/ssh-keys ]; then
    mkdir -p /root/.ssh
    cp /run/install/repo/ssh-keys/* /root/.ssh/
    chmod 700 /root/.ssh
    chmod 600 /root/.ssh/*
    for f in /root/.ssh/*.pub; do [ -f "$f" ] && chmod 644 "$f"; done
fi

# Install all ansible packages (wildcard)
dnf install -y ansible-* || true

# Clone nas-ansible repo
git clone git@github.com:tamashiiiiiiiii/nas-ansible.git /opt/nas-ansible || \
    git clone https://github.com/tamashiiiiiiiii/nas-ansible.git /opt/nas-ansible || true

# Create raw bcache cache partition — no filesystem, no mount
# Detect install disk (sda, vda, or nvme0n1)
INSTALL_DISK=$(lsblk -dno NAME,TYPE | awk '$2=="disk"{print "/dev/"$1; exit}')
if [ -n "$INSTALL_DISK" ]; then
    LAST_PART_END=$(parted -s "$INSTALL_DISK" unit MiB print | awk '/^ [0-9]/{end=$3} END{print end}' | tr -d 'MiB')
    if [ -n "$LAST_PART_END" ]; then
        parted -s "$INSTALL_DISK" mkpart primary "${LAST_PART_END}MiB" 100% || true
    fi
fi

# Install AI coding tools (skip failures)
curl -fsSL https://claude.ai/install.sh | bash || true
npm install -g @openai/codex || true
curl -fsSL https://opencode.ai/install | bash || true
curl https://cursor.com/install -fsSL | bash || true
curl -fsSL https://x.ai/cli/install.sh | bash || true

%end
