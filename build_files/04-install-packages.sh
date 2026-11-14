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
    bpfrag \
    bpftune \
    framework-system \
    game-devices-udev \
    ScopeBuddy \
    amdsmi \
    bluez \
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
    fuse \
    fuse-libs \
    fw-fanctrl \
    gamescope \
    git \
    glow \
    google-noto-sans-cjk-fonts \
    greenboot \
    greenboot-default-health-checks \
    gum \
    i2c-tools \
    input-remapper \
    jq \
    kernel-tools \
    ladspa-caps-plugins \
    lato-fonts \
    libcec \
    libddcutil \
    libinput-utils \
    libxcrypt-compat \
    linuxconsoletools \
    openssl3-libs \
    lm_sensors \
    lsb_release \
    lshw \
    lzip \
    mesa-vulkan-drivers \
    mono-core \
    mono-winforms \
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
    twitter-twemoji-fonts \
    udica \
    unzip \
    usbip \
    v4l-utils \
    vim \
    vulkan-tools \
    xorriso \
    wireplumber \
    yad \
    ydotool \
    zenity

# Fedora 45 ships OpenSSL 4 as openssl-libs; native emulators such as
# Ryujinx/Ryubing may still need the OpenSSL 3 ABI (libssl.so.3).
# Install the official Fedora compatibility RPM, not unsupported OpenSSL 1.1
# and never a symlink from libssl.so.3 to the incompatible libssl.so.4.
rpm -q openssl3-libs
test -s /usr/lib64/libssl.so.3
test -s /usr/lib64/libcrypto.so.3

# -- Disable unnecessary services --
# Mask services that are not needed.
echo "==> Disabling unnecessary services..."
ln -s /dev/null /etc/NetworkManager/dispatcher.d/04-iscsi
systemctl mask iscsi
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
    rom-properties-gtk4 \
    ibus-mozc \
    openssh-askpass \
    firewall-config
