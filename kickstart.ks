# Fedora NAS Workstation Kickstart
# Automated install to /dev/sda with custom partitioning

# System language and keyboard
lang en_IE.UTF-8
keyboard --xlayouts='ie'
timezone Europe/Dublin --utc

# Network
network --bootproto=dhcp --activate --onboot=yes
network --hostname=tanoki

# Root password and SSH
rootpw --plaintext 123456
sshkey --username=root "ssh-rsa PLACEHOLDER_ADD_YOUR_KEY"
auth authselect --enableshadow --passalgo=sha512

# SELinux and firewall
selinux --enforcing
firewall --enabled --service=ssh

# Bootloader
bootloader --location=mbr --boot-drive=sda

# Disk partitioning — wipe sda completely
zerombr
clearpart --all --drives=sda --initlabel
ignoredisk --only-use=sda

part /boot/efi --fstype=efi   --size=512   --ondisk=sda --asprimary
part /boot     --fstype=xfs   --size=1946  --ondisk=sda
part /          --fstype=xfs   --size=57242 --ondisk=sda
part /downloads --fstype=xfs   --size=92262 --ondisk=sda
part /dev/bcache0 --fstype=ext4 --size=92262 --ondisk=sda --label=bcache-cache

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

# Additional packages
vim
git
htop
tmux
curl
wget
podman
podman-compose
nodejs
npm
python3-pip
gcc
make
livecd-tools
pykickstart
bcache-tools
%end

# Post-install script
%post --log=/root/ks-post.log
set -ex

# Enable root login via SSH
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config

# Install AI coding tools
curl -fsSL https://claude.ai/install.sh | bash || true
npm install -g @openai/codex || true
curl -fsSL https://opencode.ai/install | bash || true
curl https://cursor.com/install -fsSL | bash || true
curl -fsSL https://x.ai/cli/install.sh | bash || true

%end
