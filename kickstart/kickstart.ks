# Fedora NAS Workstation Kickstart
# Automated install to /dev/sda with custom partitioning

graphical
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
firewall --enabled --service=ssh

# Bootloader
bootloader --location=mbr --boot-drive=sda

# Disk partitioning — wipe sda completely
zerombr
clearpart --all --drives=sda --initlabel
ignoredisk --only-use=sda

part biosboot   --fstype=biosboot --size=1 --ondisk=sda
part /boot/efi  --fstype=efi  --size=512   --ondisk=sda
part /boot      --fstype=xfs  --size=1946  --ondisk=sda
part /          --fstype=xfs  --size=57242 --ondisk=sda
part /downloads --fstype=xfs  --size=92262 --ondisk=sda

# Default boot target — multi-user (no GUI on boot)
skipx
firstboot --disabled

# Services
services --enabled=sshd,NetworkManager

# Pre-install: parallel downloads + auto-detect proxy on gateway
%pre
echo "max_parallel_downloads=10" >> /etc/dnf/dnf.conf
echo "fastestmirror=True" >> /etc/dnf/dnf.conf

GATEWAY=$(ip route show default 2>/dev/null | awk '/default/{print $3; exit}')
if [ -n "$GATEWAY" ]; then
    if curl -s --connect-timeout 3 -o /dev/null -w '%{http_code}' "http://${GATEWAY}:3128/" 2>/dev/null | grep -qE '200|400|403|407'; then
        echo "proxy=http://${GATEWAY}:3128" >> /etc/dnf/dnf.conf
        echo "" > /dev/tty1
        echo ">>> Squid proxy detected at ${GATEWAY}:3128 — using it for package downloads" > /dev/tty1
        echo "" > /dev/tty1
    else
        echo "" > /dev/tty1
        echo ">>> No proxy detected on gateway — downloading directly from mirrors" > /dev/tty1
        echo "" > /dev/tty1
    fi
fi

# Inject cyberpunk theme CSS into Anaconda Web UI
CDROM_DEV=$(blkid -t TYPE=iso9660 -o device 2>/dev/null | head -1)
if [ -n "$CDROM_DEV" ]; then
    TMPMNT=$(mktemp -d)
    mount -o ro "$CDROM_DEV" "$TMPMNT" 2>/dev/null
    if [ -f "$TMPMNT/usr/share/anaconda/pixmaps/custom.css" ]; then
        for cssdir in /usr/share/cockpit/anaconda-webui /usr/share/anaconda/pixmaps; do
            if [ -d "$cssdir" ]; then
                cp "$TMPMNT/usr/share/anaconda/pixmaps/custom.css" "$cssdir/tanoki-cyberpunk.css"
            fi
        done
        # Append CSS import to any existing index.html
        for idx in /usr/share/cockpit/anaconda-webui/index.html; do
            if [ -f "$idx" ]; then
                sed -i 's|</head>|<link rel="stylesheet" href="tanoki-cyberpunk.css"></head>|' "$idx"
            fi
        done
    fi
    umount "$TMPMNT" 2>/dev/null
    rmdir "$TMPMNT"
fi
%end

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


# Misc
mailx
livecd-tools
pykickstart
%end

# Post-install script
%post --log=/root/ks-post.log
set -ex

# Parallel DNF downloads on installed system
echo "max_parallel_downloads=10" >> /etc/dnf/dnf.conf
echo "fastestmirror=True" >> /etc/dnf/dnf.conf

# Set default target to multi-user (no GUI on boot)
systemctl set-default multi-user.target

# Enable root login and password authentication via SSH
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config

# Copy SSH keys from installer media (placed by Makefile)
mkdir -p /root/.ssh
CDROM=$(blkid -t TYPE=iso9660 -o device 2>/dev/null | head -1)
if [ -n "$CDROM" ]; then
    MNTDIR=$(mktemp -d)
    mount -o ro "$CDROM" "$MNTDIR" 2>/dev/null
    if [ -d "$MNTDIR/ssh-keys" ]; then
        cp "$MNTDIR/ssh-keys"/* /root/.ssh/
    fi
    umount "$MNTDIR" 2>/dev/null
    rmdir "$MNTDIR"
fi
for d in /run/install/repo /run/install/isodir /mnt/install/source; do
    if [ -d "$d/ssh-keys" ]; then
        cp "$d/ssh-keys"/* /root/.ssh/ 2>/dev/null
        break
    fi
done
chmod 700 /root/.ssh
chmod 600 /root/.ssh/* 2>/dev/null
for f in /root/.ssh/*.pub; do [ -f "$f" ] && chmod 644 "$f"; done

# Install all ansible packages (wildcard)
dnf install -y ansible-* || true

# Clone nas-ansible repo (SSH only, non-interactive)
ssh-keyscan github.com >> /root/.ssh/known_hosts 2>/dev/null
GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes" \
    git clone git@github.com:tamashiiiiiiiii/nas-ansible.git /opt/nas-ansible || true

# Create raw bcache cache partition (sda5) — no filesystem, no mount
LAST_PART_END=$(parted -s /dev/sda unit MiB print | awk '/^ [0-9]/{end=$3} END{print end}' | tr -d 'MiB')
if [ -n "$LAST_PART_END" ]; then
    parted -s /dev/sda mkpart primary "${LAST_PART_END}MiB" 100% || true
fi

# Install AI coding tools (non-interactive, skip failures)
export NONINTERACTIVE=1
curl -fsSL https://claude.ai/install.sh | bash -s -- --yes 2>/dev/null || true
npm install -g @openai/codex 2>/dev/null || true
curl -fsSL https://opencode.ai/install | bash 2>/dev/null || true
curl -fsSL https://cursor.com/install | bash 2>/dev/null || true
curl -fsSL https://x.ai/cli/install.sh | bash 2>/dev/null || true

%end
