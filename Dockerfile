FROM ubuntu:22.04@sha256:5c8b2c0a6c745bc177669abfaa716b4bc57d58e2ea3882fb5da67f4d59e3dda5

ARG DEBIAN_FRONTEND=noninteractive
ARG UBUNTU_SNAPSHOT=20260405T120000Z
ARG UBUNTU_CA_CERTIFICATES_VERSION=20240203~22.04.1
ARG UBUNTU_CA_CERTIFICATES_SHA256=7b6d6a66bc70a0c0e87893cbe3d0db28e909710ea2f7c6be4d2b74806b1eef75
ARG RUST_TOOLCHAIN=1.94.1
ARG RUFF_VERSION=0.15.9
ARG BLACK_VERSION=26.3.1

ADD https://snapshot.ubuntu.com/ubuntu/${UBUNTU_SNAPSHOT}/pool/main/c/ca-certificates/ca-certificates_${UBUNTU_CA_CERTIFICATES_VERSION}_all.deb /tmp/ubuntu-ca-certificates.deb

RUN echo "${UBUNTU_CA_CERTIFICATES_SHA256}  /tmp/ubuntu-ca-certificates.deb" | sha256sum -c - \
  && mkdir -p /tmp/ca-root /etc/ssl/certs \
  && dpkg-deb -x /tmp/ubuntu-ca-certificates.deb /tmp/ca-root \
  && cat /tmp/ca-root/usr/share/ca-certificates/mozilla/*.crt >/etc/ssl/certs/ca-certificates.crt \
  && perl -0pi -e "s{http://(?:archive|security)\\.ubuntu\\.com/ubuntu/?}{https://snapshot.ubuntu.com/ubuntu/${UBUNTU_SNAPSHOT}/}g" /etc/apt/sources.list \
  && apt-get update \
  && apt-get install -y --no-install-recommends \
    bash \
    binutils \
    ca-certificates \
    gcc \
    coreutils \
    curl \
    file \
    findutils \
    git \
    make \
    libc6-dev \
    python3-pip \
    mtools \
    nasm \
    shellcheck \
    shfmt \
    python3 \
    qemu-system-x86 \
    qemu-system-gui \
    ripgrep \
    socat \
    tigervnc-viewer \
    xdotool \
    xvfb \
    grub-common \
    grub-pc-bin \
    xorriso \
  && rm -rf /tmp/ca-root /tmp/ubuntu-ca-certificates.deb \
  && rm -rf /var/lib/apt/lists/*

ENV RUSTUP_HOME=/opt/rustup
ENV CARGO_HOME=/opt/cargo
ENV PATH=/opt/cargo/bin:$PATH

RUN mkdir -p "${RUSTUP_HOME}" "${CARGO_HOME}" \
  && curl -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal --default-toolchain "${RUST_TOOLCHAIN}" \
  && rustup target add i586-unknown-linux-gnu \
  && rustup component add rustfmt

RUN python3 -m pip install --no-cache-dir \
    "ruff==${RUFF_VERSION}" \
    "black==${BLACK_VERSION}"

WORKDIR /work
