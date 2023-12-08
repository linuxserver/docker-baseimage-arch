# syntax=docker/dockerfile:1

FROM alpine:3.19 as rootfs-stage

ARG ARCH_VERSION

# install packages
RUN \
  apk add --no-cache \
    bash \
    curl \
    jq \
    tar \
    tzdata \
    xz \
    zstd

# grab latest rootfs
RUN \
  echo "**** grab download URL ****" && \
  if [ -z ${ARCH_VERSION+x} ]; then \
    ARCH_VERSION=$(curl -sL https://gitlab.archlinux.org/api/v4/projects/10185/releases \
    | jq -r '.[0].tag_name' | sed 's/^v//g'); \
  fi && \
  PACK_ID=$(curl -sL https://gitlab.archlinux.org/api/v4/projects/10185/packages?sort=desc | jq -r '.[] | select(.version == "'${ARCH_VERSION}'") | .id') && \
  TAR_ID=$(curl -sL https://gitlab.archlinux.org/api/v4/projects/10185/packages/${PACK_ID}/package_files | jq '.[] | select(.file_name == "base-'${ARCH_VERSION}'.tar.zst") | .id') && \
  echo "**** download/extract rootfs ****" && \
  curl -o \
    /rootfs.tar.zst -L \
    https://gitlab.archlinux.org/archlinux/archlinux-docker/-/package_files/${TAR_ID}/download && \
  mkdir /root-out && \
  tar xf \
    /rootfs.tar.zst -C \
    /root-out

# pacstrap stage
FROM scratch as pacstrap-stage
COPY --from=rootfs-stage /root-out/ /

RUN \
  mkdir -m 0755 -p \
    /root-out/var/{cache/pacman/pkg,lib/pacman,log} \
    /root-out/{dev,run,etc} && \
  mkdir -m 1777 -p \
    /root-out/tmp && \
  mkdir -m 0555 -p \
    /root-out/{sys,proc} && \
  pacman -r /root-out -Sy --noconfirm \
    archlinux-keyring \
    bash \
    busybox \
    coreutils \
    curl \
    findutils \
    gawk \
    grep \
    gzip \
    jq \
    less \
    netcat \
    pacman \
    procps-ng \
    sed \
    shadow \
    tar \
    tzdata \
    util-linux \
    which && \
  cp -a /etc/pacman.conf /root-out/etc/pacman.conf && \
  cp -a /etc/pacman.d/mirrorlist /root-out/etc/pacman.d/mirrorlist && \
  rm /root-out/var/lib/pacman/sync/*

# set version for s6 overlay
ARG S6_OVERLAY_VERSION="3.1.5.0"
ARG S6_OVERLAY_ARCH="x86_64"

# add s6 overlay
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz /tmp
RUN tar -C /root-out -Jxpf /tmp/s6-overlay-noarch.tar.xz
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-${S6_OVERLAY_ARCH}.tar.xz /tmp
RUN tar -C /root-out -Jxpf /tmp/s6-overlay-${S6_OVERLAY_ARCH}.tar.xz

# add s6 optional symlinks
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-symlinks-noarch.tar.xz /tmp
RUN tar -C /root-out -Jxpf /tmp/s6-overlay-symlinks-noarch.tar.xz
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-symlinks-arch.tar.xz /tmp
RUN tar -C /root-out -Jxpf /tmp/s6-overlay-symlinks-arch.tar.xz

# runtime stage
FROM scratch
COPY --from=pacstrap-stage /root-out/ /
ARG BUILD_DATE
ARG VERSION
ARG MODS_VERSION="v3"
ARG PKG_INST_VERSION="v1"
LABEL build_version="Linuxserver.io version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="TheLamer"

ADD --chmod=744 "https://raw.githubusercontent.com/linuxserver/docker-mods/mod-scripts/docker-mods.${MODS_VERSION}" "/docker-mods"
ADD --chmod=744 "https://raw.githubusercontent.com/linuxserver/docker-mods/mod-scripts/package-install.${PKG_INST_VERSION}" "/etc/s6-overlay/s6-rc.d/init-mods-package-install/run"

# environment variables
ENV PS1="$(whoami)@$(hostname):$(pwd)\\$ " \
  HOME="/root" \
  TERM="xterm" \
  S6_CMD_WAIT_FOR_SERVICES_MAXTIME="0" \
  S6_VERBOSITY=1 \
  S6_STAGE2_HOOK=/docker-mods \
  VIRTUAL_ENV=/lsiopy \
  PATH="/lsiopy/bin:$PATH"

RUN \
  echo "**** create abc user and make our folders ****" && \
  groupadd -g 1000 users && \
  useradd -u 911 -U -d /config -s /bin/false abc && \
  usermod -G users abc && \
  mkdir -p \
    /app \
    /config \
    /defaults \
    /lsiopy && \
  echo "**** configure pacman ****" && \
  locale-gen && \
  pacman-key --init && \
  pacman-key --populate archlinux && \
  echo "**** configure locale ****" && \
  echo "en_US.UTF-8 UTF-8" > /etc/locale.gen && \
  locale-gen && \
  echo "**** cleanup ****" && \
  rm -rf \
    /tmp/* \
    /var/cache/pacman/pkg/* \
    /var/lib/pacman/sync/*

# add local files
COPY root/ /

ENTRYPOINT ["/init"]
