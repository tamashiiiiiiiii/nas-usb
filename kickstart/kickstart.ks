# Fedora NAS Workstation Kickstart
# Automated install to /dev/sda with custom partitioning

text
lang en_IE.UTF-8
keyboard --xlayouts='ie'
timezone Europe/Dublin --utc

# Network
network --bootproto=dhcp --activate --onboot=yes
network --hostname=tanoki

# Root password
rootpw --plaintext 123456

# Authentication
auth authselect --enableshadow --passalgo=sha512

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
part /tmp/bcache-cache --size=92262 --ondisk=sda

# Services
services --enabled=sshd,NetworkManager,cockpit.socket,postfix,samba,nfs-server,fail2ban,clamav-freshclam,tuned,pcp

# Reboot after install
reboot --eject

# Package selection
%packages
@^workstation-product-environment
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
nodejs
npm

# Container runtime
podman
podman-compose
podman-docker
containernetworking-plugins

# Storage & RAID
mdadm
lvm2
xfsprogs
bcache-tools

# Network services (from nas-ansible roles)
samba
samba-client
samba-common
netatalk
postfix
cyrus-sasl-plain
unbound
avahi
avahi-tools
bind-utils

# Security (from nas-ansible roles)
fail2ban-server
fail2ban-sendmail
clamav
clamav-update
clamd
policycoreutils-python-utils
checkpolicy
authselect

# Monitoring (from nas-ansible roles)
pcp
pcp-system-tools
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

# Virtualisation (from nas-ansible roles)
libvirt
qemu-kvm
virt-install

# Misc
mailx
ledmon
plymouth
plymouth-plugin-two-step
plymouth-scripts
livecd-tools
pykickstart
%end

# Post-install script
%post --log=/root/ks-post.log
set -ex

# Enable root login via SSH
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config

# Set up bcache cache device
if [ -b /dev/sda5 ]; then
    make-bcache -C /dev/sda5 || true
fi

# Install AI coding tools
curl -fsSL https://claude.ai/install.sh | bash || true
npm install -g @openai/codex || true
curl -fsSL https://opencode.ai/install | bash || true
curl https://cursor.com/install -fsSL | bash || true
curl -fsSL https://x.ai/cli/install.sh | bash || true

%end
