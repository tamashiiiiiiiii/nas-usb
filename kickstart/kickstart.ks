# Fedora NAS Server Kickstart
# Automated install to /dev/sda with custom partitioning

text
%include /tmp/url.ks
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
part /          --fstype=xfs  --size=25000 --ondisk=sda
part /var       --fstype=xfs  --size=50000 --ondisk=sda
part /home      --fstype=xfs  --size=2000 --ondisk=sda
part /mtn/downloads --fstype=xfs  --size=92262 --grow --ondisk=sda

# Default boot target — multi-user (no GUI on boot)
skipx
firstboot --disabled

# Services
services --enabled=sshd,NetworkManager

# Pre-install: parallel downloads + auto-detect proxy on gateway
%pre
echo "max_parallel_downloads=10" >> /etc/dnf/dnf.conf
echo "fastestmirror=True" >> /etc/dnf/dnf.conf

# Hardcoded HTTP mirror for Squid cache hits across repeated installs
PINNED_HTTP_MIRROR="http://mirror.init7.net/fedora/fedora/linux/releases/44/Everything/x86_64/os/"
PINNED_MIRROR_BASE="http://mirror.init7.net/fedora/fedora/linux"

# Default: use mirrorlist
MIRRORLIST="https://mirrors.fedoraproject.org/mirrorlist?repo=fedora-44&arch=x86_64&protocol=http"
echo "url --mirrorlist=${MIRRORLIST}" > /tmp/url.ks

GATEWAY=$(ip route show default 2>/dev/null | awk '/default/{print $3; exit}')
if [ -n "$GATEWAY" ]; then
    if curl -s --connect-timeout 3 -o /dev/null -w '%{http_code}' "http://${GATEWAY}:3128/" 2>/dev/null | grep -qE '200|400|403|407'; then
        PROXY="http://${GATEWAY}:3128"
        echo "proxy=${PROXY}" >> /etc/dnf/dnf.conf
        echo "url --url=${PINNED_HTTP_MIRROR}" > /tmp/url.ks
        echo "${PINNED_MIRROR_BASE}" > /tmp/pinned-mirror-base
        echo "${PROXY}" > /tmp/pinned-proxy
        echo "" > /dev/tty1
        echo ">>> Squid proxy at ${GATEWAY}:3128 — pinned to ${PINNED_HTTP_MIRROR}" > /dev/tty1
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
@^server-product-environment
@development-tools
@container-management

# Core tools
vim
git
htop
tmux
curl
wget
gcc
gcc-c++
make
cmake
python3-pip
python3-passlib
nodejs
npm
openssl
dbus
rsync
jq
bash-completion
man-db
tree
screen
acl
attr
findutils
which
file
bc
time

# Compression
xz
zstd
unzip
zip

# SELinux utilities
setools-console
setroubleshoot-server

# Firmware & hardware
lshw
dmidecode

# Ansible (from Makefile bootstrap)
ansible-core
ansible-*
sshpass

# Container runtime (from roles/podman)
podman
podman-compose
podman-docker
podman-remote
containernetworking-plugins
buildah
skopeo

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
e2fsprogs
cifs-utils
udisks2
fuse
fuse3
sshfs

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
net-tools
traceroute
nmap-ncat
tcpdump
iperf3
mtr
whois
ethtool
bridge-utils
iputils
socat

# File sharing (from roles/ftp, roles/nfs)
vsftpd
nfs-utils
ftp

# Security (from roles/fail2ban, roles/clamav, roles/selinux, roles/audit, roles/lynis)
fail2ban-server
fail2ban-sendmail
clamav
clamav-update
clamav-data
clamd
policycoreutils-python-utils
checkpolicy
python3-libselinux
authselect
audit
lynis
nftables
iptables-nft

# Certificates (from roles/certs)
certbot

# Monitoring (from roles/pcp, roles/sysstat, roles/smartmontools, roles/cockpit)
pcp
pcp-system-tools
sysstat
smartmontools
iotop
atop
strace
lsof
perf
procps-ng
psmisc
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
fancontrol

# Virtualisation (from roles/libvirt)
libvirt
qemu-kvm
virt-install


# Misc
mailx
livecd-tools
pykickstart
rclone
systemd-journal-remote
%end

# Pin installed system repos to single mirror if proxy was used during install
%post --nochroot
if [ -f /tmp/pinned-proxy ] && [ -f /tmp/pinned-mirror-base ]; then
    PROXY=$(cat /tmp/pinned-proxy)
    MIRROR_BASE=$(cat /tmp/pinned-mirror-base)
    echo "proxy=${PROXY}" >> /mnt/sysimage/etc/dnf/dnf.conf

    for repo in /mnt/sysimage/etc/yum.repos.d/fedora*.repo; do
        [ -f "$repo" ] || continue
        sed -i 's|^metalink=|#metalink=|' "$repo"
    done

    sed -i "/^\[fedora\]$/a baseurl=${MIRROR_BASE}/releases/\$releasever/Everything/\$basearch/os/" \
        /mnt/sysimage/etc/yum.repos.d/fedora.repo
    sed -i "/^\[fedora-updates\]$/a baseurl=${MIRROR_BASE}/updates/\$releasever/Everything/\$basearch/" \
        /mnt/sysimage/etc/yum.repos.d/fedora-updates.repo
fi

# Copy SSH keys from install media to target system (media is still mounted here)
TARGET=/mnt/sysimage
mkdir -p "$TARGET/root/.ssh"
chmod 700 "$TARGET/root/.ssh"

# Try Anaconda source paths
for d in /run/install/repo /run/install/isodir /mnt/install/source; do
    if [ -d "$d/ssh-keys" ]; then
        cp "$d/ssh-keys"/* "$TARGET/root/.ssh/" 2>/dev/null
        break
    fi
done

# Fallback: mount iso9660 devices directly
if [ ! -f "$TARGET/root/.ssh/id_rsa" ]; then
    for dev in $(blkid -t TYPE=iso9660 -o device 2>/dev/null); do
        TMPMNT=$(mktemp -d)
        mount -o ro "$dev" "$TMPMNT" 2>/dev/null
        if [ -d "$TMPMNT/ssh-keys" ]; then
            cp "$TMPMNT/ssh-keys"/* "$TARGET/root/.ssh/" 2>/dev/null
            umount "$TMPMNT" 2>/dev/null
            rmdir "$TMPMNT"
            break
        fi
        umount "$TMPMNT" 2>/dev/null
        rmdir "$TMPMNT"
    done
fi

# Also copy to nas user
mkdir -p "$TARGET/home/nas/.ssh"
cp "$TARGET/root/.ssh"/* "$TARGET/home/nas/.ssh/" 2>/dev/null
chown -R 1000:1000 "$TARGET/home/nas/.ssh" 2>/dev/null

chmod 600 "$TARGET/root/.ssh/id_rsa" 2>/dev/null
chmod 644 "$TARGET/root/.ssh"/*.pub 2>/dev/null

# Copy vault_pass from install media
VAULT_SRC=""
if [ -f "$TARGET/root/.ssh/vault_pass" ]; then
    VAULT_SRC="$TARGET/root/.ssh/vault_pass"
fi
if [ -z "$VAULT_SRC" ]; then
    for dev in $(blkid -t TYPE=iso9660 -o device 2>/dev/null); do
        [ -n "$VAULT_SRC" ] && break
        TMPMNT=$(mktemp -d)
        mount -o ro "$dev" "$TMPMNT" 2>/dev/null
        if [ -f "$TMPMNT/ssh-keys/vault_pass" ]; then
            VAULT_SRC="$TMPMNT/ssh-keys/vault_pass"
        fi
        umount "$TMPMNT" 2>/dev/null
        rmdir "$TMPMNT"
    done
fi
if [ -n "$VAULT_SRC" ]; then
    mkdir -p "$TARGET/opt/nas-ansible"
    cp "$VAULT_SRC" "$TARGET/opt/nas-ansible/.vault_pass" 2>/dev/null
    chmod 600 "$TARGET/opt/nas-ansible/.vault_pass" 2>/dev/null
    cp "$VAULT_SRC" "$TARGET/root/.vault_pass" 2>/dev/null
    chmod 600 "$TARGET/root/.vault_pass" 2>/dev/null
    echo ">>> vault_pass installed" > /dev/tty5
else
    echo ">>> WARNING: vault_pass not found on media" > /dev/tty5
fi
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

# Clone nas-ansible repo (SSH keys already installed by --nochroot)
ssh-keyscan github.com >> /root/.ssh/known_hosts 2>/dev/null
rm -rf /opt/nas-ansible
GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes" \
    git clone git@github.com:tamashiiiiiiiii/nas-ansible.git /opt/nas-ansible || true
# Ensure vault_pass is in the repo dir even if clone partially succeeded
if [ -f /root/.vault_pass ] && [ -d /opt/nas-ansible ]; then
    cp /root/.vault_pass /opt/nas-ansible/.vault_pass 2>/dev/null
    chmod 600 /opt/nas-ansible/.vault_pass 2>/dev/null
fi

# Format /dev/sdb as bcache cache device (only if it's an SSD)
if [ -b /dev/sdb ]; then
    ROTATIONAL=$(cat /sys/block/sdb/queue/rotational 2>/dev/null || echo "1")
    if [ "$ROTATIONAL" = "0" ]; then
        echo ">>> Formatting /dev/sdb as bcache cache device..."
        wipefs -a /dev/sdb 2>/dev/null || true
        make-bcache -C /dev/sdb 2>/dev/null || true
    else
        echo "WARNING: /dev/sdb is an HDD (rotational), skipping bcache cache setup"
    fi
else
    echo "WARNING: /dev/sdb not found — skipping bcache cache setup"
fi

# Install AI coding tools (non-interactive, skip failures)
export NONINTERACTIVE=1
npm install -g @anthropic-ai/claude-code 2>/dev/null || true
npm install -g @openai/codex 2>/dev/null || true
curl -fsSL https://opencode.ai/install | bash 2>/dev/null || true

%end

# Prompt user to remove USB before reboot
%post --nochroot
echo "" > /dev/tty1
echo "============================================" > /dev/tty1
echo "  Installation complete!" > /dev/tty1
echo "  Please remove the USB key," > /dev/tty1
echo "  then press ENTER to reboot..." > /dev/tty1
echo "============================================" > /dev/tty1
read < /dev/tty1
%end
