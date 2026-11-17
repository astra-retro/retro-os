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

# Build all four native PS3 ISO tools from one immutable upstream revision.
# Keep gcc, make and git in a throwaway build stage, not the installed OS.
FROM registry.fedoraproject.org/fedora:${FEDORA_VERSION} AS ps3iso-utils-builder
ARG PS3ISO_UTILS_COMMIT=878090980a9042c61901920fed1b034af215e8c7
RUN dnf5 -y install --setopt=install_weak_deps=False git gcc make \
    && git clone --quiet https://github.com/bucanero/ps3iso-utils.git /tmp/ps3iso-utils \
    && git -C /tmp/ps3iso-utils checkout --quiet --detach "${PS3ISO_UTILS_COMMIT}" \
    && test "$(git -C /tmp/ps3iso-utils rev-parse HEAD)" = "${PS3ISO_UTILS_COMMIT}" \
    && for tool in extractps3iso makeps3iso patchps3iso splitps3iso; do \
         make -C "/tmp/ps3iso-utils/${tool}"; \
         install -D -m 0755 "/tmp/ps3iso-utils/${tool}/${tool}" "/out/bin/${tool}"; \
       done \
    && install -D -m 0644 /tmp/ps3iso-utils/LICENSE /out/share/licenses/ps3iso-utils/LICENSE

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
      && dnf5 -y install plymouth-plugin-script dconf grub2-efi-x64-modules gnome-shell-extension-dash-to-dock blueprint-compiler openssh-server firewalld glib2-devel librsvg2-tools \
      && bash /astra-branding/install-common.sh /astra-branding/assets installed \
      && /ctx/build-initramfs.sh \
      && /ctx/finalize.sh \
      && /ctx/cleanup.sh

# Ship only the binaries and GPL license; no compiler or build-time git.
COPY --from=ps3iso-utils-builder /out/bin/ /usr/bin/
COPY --from=ps3iso-utils-builder /out/share/licenses/ps3iso-utils/ /usr/share/licenses/ps3iso-utils/
RUN for tool in extractps3iso makeps3iso patchps3iso splitps3iso; do \
      test -x "/usr/bin/${tool}" || exit 1; \
    done

RUN --mount=type=tmpfs,target=/run \
      --network=none \
      bootc container lint