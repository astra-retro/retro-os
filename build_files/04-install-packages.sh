#!/usr/bin/env bash
#
# Install new packages, apply system configuration changes, and set up
# service.
#
set -xeuo pipefail

echo "::group::Install packages"
trap 'echo "::endgroup::"' EXIT

# -- Install Nerd Fonts --
echo "==> Installing Nerd Fonts..."
dnf5 -y install \
    --enable-repo=copr:copr.fedorainfracloud.org:che:nerd-fonts \
    nerd-fonts

# -- Install core packages --
echo "==> Installing core packages..."
dnf5 -y install \
    amdsmi \
    bluez \
    bpfrag \
    bpftune \
    btop \
    cage \
    cockpit-files \
    cockpit-networkmanager \
    cockpit-podman \
    cockpit-storaged \
    cockpit-system \
    compsize \
    ddcutil \
    duf \
    edk2-ovmf \
    f3 \
    fastfetch \
    fira-code-fonts \
    fish \
    flatpak \
    framework-system \
    fuse \
    fuse-libs \
    fw-fanctrl \
    game-devices-udev \
    gamescope \
    git \
    glow \
    google-noto-sans-cjk-fonts \
    greenboot \
    greenboot-default-health-checks \
    gum \
    i2c-tools \
    input-remapper \
    inputattach-cec-units \
    jq \
    kernel-tools \
    ladspa-caps-plugins \
    lato-fonts \
    libcec \
    libddcutil \
    libinput-utils \
    libxcrypt-compat \
    linux-cec \
    linuxconsoletools \
    lm_sensors \
    ls-iommu \
    lsb_release \
    lshw \
    lzip \
    mesa-vulkan-drivers \
    msedit \
    NetworkManager \
    openrgb-udev-rules \
    p7zip \
    p7zip-plugins \
    pipewire \
    pipewire-module-filter-chain-sofa \
    python3-icoextract \
    python3-pip \
    rar \
    rocm-clinfo \
    rocm-opencl \
    rocm-smi \
    rsync \
    ryzenadj \
    ScopeBuddy \
    scx-scheds \
    scx-tools \
    twitter-twemoji-fonts \
    udica \
    unzip \
    usbip \
    v4l-utils \
    vim \
    vulkan-low-latency-layer \
    vulkan-tools \
    wireplumber \
    yad \
    ydotool \
    zenity

# -- Disable unnecessary services --
# Mask services that are not needed.
echo "==> Disabling unnecessary services..."
ln -s /dev/null /etc/NetworkManager/dispatcher.d/04-iscsi
systemctl mask iscsi
systemctl mask systemd-remount-fs.service
systemctl mask fedora-atomic-desktop-appstream-cache-refresh

# -- Create autostart directory --
echo "==> Creating autostart directory..."
mkdir -p /etc/xdg/autostart

# -- Install GNOME packages --
# Install GNOME desktop packages including extensions, themes, and tools.
echo "==> Installing GNOME packages..."
dnf5 -y install \
    nautilus-gsconnect \
    gnome-shell-extension-user-theme \
    gnome-shell-extension-gsconnect \
    gnome-search-yafti \
    rom-properties-gtk4 \
    ibus-mozc \
    openssh-askpass \
    firewall-config

# -- Enable dconf-update service --
# Enable the dconf-update service for configuration persistence.
echo "==> Enabling dconf-update service..."
systemctl enable dconf-update.service
