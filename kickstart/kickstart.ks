# Fedora NAS Workstation Kickstart
# Automated install to /dev/sda with custom partitioning

text
lang pt_PT.UTF-8
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
bootloader --location=mbr --boot-drive=sda

# Disk partitioning — wipe sda completely
zerombr
clearpart --all --drives=sda --initlabel
ignoredisk --only-use=sda

part /boot/efi  --fstype=efi  --size=512   --ondisk=sda
part /boot      --fstype=xfs  --size=1946  --ondisk=sda
part /          --fstype=xfs  --size=57242 --ondisk=sda
part /downloads --fstype=xfs  --size=92262 --ondisk=sda

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

# Create raw bcache cache partition (sda5) — no filesystem, no mount
END_OF_SDA4=$(parted -s /dev/sda unit MiB print | awk '/^ 4 /{print $3}' | tr -d 'MiB')
if [ -n "$END_OF_SDA4" ]; then
    parted -s /dev/sda mkpart primary "${END_OF_SDA4}MiB" 100% || true
fi

# Install AI coding tools (skip failures)
curl -fsSL https://claude.ai/install.sh | bash || true
npm install -g @openai/codex || true
curl -fsSL https://opencode.ai/install | bash || true
curl https://cursor.com/install -fsSL | bash || true
curl -fsSL https://x.ai/cli/install.sh | bash || true

%end
