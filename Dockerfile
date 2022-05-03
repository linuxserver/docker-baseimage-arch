FROM alpine:3.15 as rootfs-stage

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
COPY patch/ /tmp/patch

RUN \
  mkdir -m 0755 -p \
    /root-out/var/{cache/pacman/pkg,lib/pacman,log} \
    /root-out/{dev,run,etc} && \
  mkdir -m 1777 -p \
    /root-out/tmp && \
  mkdir -m 0555 -p \
    /root-out/{sys,proc} && \
  pacman -r /root-out -Sy --noconfirm \
    bash \
    coreutils \
    findutils \
    gawk \
    grep \
    gzip \
    less \
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
  cp -a /tmp/patch/init-stage2.patch /root-out/ && \
  rm /root-out/var/lib/pacman/sync/*

# runtime stage
FROM scratch
COPY --from=pacstrap-stage /root-out/ /
ARG BUILD_DATE
ARG VERSION
LABEL build_version="Linuxserver.io version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="TheLamer"

# set version for s6 overlay
ARG OVERLAY_VERSION="v2.2.0.3"
ARG OVERLAY_ARCH="amd64"

# environment variables
ENV PS1="$(whoami)@$(hostname):$(pwd)\\$ " \
HOME="/root" \
TERM="xterm"

# add s6 overlay
ADD https://github.com/just-containers/s6-overlay/releases/download/${OVERLAY_VERSION}/s6-overlay-${OVERLAY_ARCH}-installer /tmp/
RUN \
  echo "**** create abc user and make our folders ****" && \
  groupadd -g 1000 users && \
  useradd -u 911 -U -d /config -s /bin/false abc && \
  usermod -G users abc && \
  mkdir -p \
    /app \
    /config \
    /defaults && \
  echo "**** install s6 ****" && \
  chmod +x /tmp/s6-overlay-${OVERLAY_ARCH}-installer && \
  /tmp/s6-overlay-${OVERLAY_ARCH}-installer / && \
  rm /tmp/s6-overlay-${OVERLAY_ARCH}-installer && \
  mv /usr/bin/with-contenv /usr/bin/with-contenvb && \
  echo "**** configure pacman ****" && \
  locale-gen && \
  pacman-key --init && \
  pacman-key --populate archlinux && \
  echo "**** patch files ****" && \
  pacman -Sy --noconfirm \
    patch && \
  patch -u /etc/s6/init/init-stage2 -i /init-stage2.patch && \
  echo "**** configure locale ****" && \
  echo "en_US.UTF-8 UTF-8" > /etc/locale.gen && \
  locale-gen && \
  echo "**** cleanup ****" && \
  pacman -Rsn --noconfirm \
    patch && \
  rm -rf \
    /init-stage2.patch \
    /tmp/* \
    /var/cache/pacman/pkg/* \
    /var/lib/pacman/sync/*

# add local files
COPY root/ /

ENTRYPOINT ["/init"]
