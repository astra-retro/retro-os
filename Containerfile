ARG BASE_IMAGE_NAME="${BASE_IMAGE_NAME:-silverblue}"
ARG FEDORA_VERSION="${FEDORA_VERSION:-45}"
ARG ARCH="${ARCH:-x86_64}"

ARG BASE_IMAGE="${BASE_IMAGE:-ghcr.io/ublue-os/${BASE_IMAGE_NAME}-main:${FEDORA_VERSION}}"
ARG KERNEL_FLAVOR="${KERNEL_FLAVOR:-ogc}"
ARG KERNEL_VERSION="${KERNEL_VERSION:-${ARCH}}"
ARG NVIDIA_FLAVOR="${NVIDIA_FLAVOR:-nvidia-open}"

FROM ${BASE_IMAGE} AS base-image
FROM ghcr.io/ublue-os/akmods:${KERNEL_FLAVOR}-${FEDORA_VERSION}-${KERNEL_VERSION} AS akmods
FROM ghcr.io/ublue-os/akmods-extra:${KERNEL_FLAVOR}-${FEDORA_VERSION}-${KERNEL_VERSION} AS akmods-extra
FROM ghcr.io/ublue-os/akmods-${NVIDIA_FLAVOR}:${KERNEL_FLAVOR}-${FEDORA_VERSION}-${KERNEL_VERSION} AS akmods-nvidia

FROM scratch AS branding_assets
COPY branding /

FROM scratch AS ctx
COPY build_files /

FROM scratch AS system_files
COPY system_files /


FROM base-image AS retro-os

ARG IMAGE_NAME="${IMAGE_NAME:-retro-os}"
ARG IMAGE_VENDOR="${IMAGE_VENDOR:-astra-retro}"
ARG IMAGE_BRANCH="${IMAGE_BRANCH:-stable}"
ARG BASE_IMAGE_NAME
ARG FEDORA_VERSION
ARG SHA_HEAD_SHORT="${SHA_HEAD_SHORT}"
ARG VERSION_TAG="${VERSION_TAG}"
ARG VERSION_PRETTY="${VERSION_PRETTY}"
ARG KERNEL_FLAVOR
ARG NVIDIA_FLAVOR

RUN --mount=type=cache,dst=/var/cache \
      --mount=type=cache,dst=/var/cache/libdnf5 \
      --mount=type=cache,dst=/var/log \
      --mount=type=bind,from=akmods,src=/kernel-rpms,dst=/tmp/kernel-rpms \
      --mount=type=bind,from=akmods,src=/rpms/common,dst=/tmp/rpms/common \
      --mount=type=bind,from=akmods,src=/rpms/kmods,dst=/tmp/rpms/kmods \
      --mount=type=bind,from=akmods-extra,src=/rpms/extra,dst=/tmp/rpms/extra \
      --mount=type=bind,from=akmods-extra,src=/rpms/kmods,dst=/tmp/rpms/kmods-extra \
      --mount=type=bind,from=akmods-nvidia,src=/rpms,dst=/tmp/rpms/nvidia \
      --mount=type=bind,from=ctx,source=/,target=/ctx \
      --mount=type=bind,from=system_files,source=/,target=/tmp/system_files \
      --mount=type=tmpfs,dst=/tmp \
      --mount=type=secret,id=GITHUB_TOKEN \
      /ctx/build.sh

RUN --mount=type=cache,dst=/var/cache \
      --mount=type=cache,dst=/var/log \
      --mount=type=bind,from=ctx,source=/,target=/ctx \
      --mount=type=bind,from=branding_assets,source=/,target=/astra-branding \
      --mount=type=tmpfs,dst=/tmp \
      /ctx/image-info.sh \
      && dnf5 -y install plymouth-plugin-script dconf grub2-efi-x64-modules gnome-shell-extension-dash-to-dock blueprint-compiler openssh-server firewalld glib2-devel \
      && bash /astra-branding/install-common.sh /astra-branding/assets installed \
      && /ctx/build-initramfs.sh \
      && /ctx/finalize.sh \
      && /ctx/cleanup.sh

RUN --mount=type=tmpfs,target=/run \
      --network=none \
      bootc container lint