FROM ubuntu:22.04@sha256:5c8b2c0a6c745bc177669abfaa716b4bc57d58e2ea3882fb5da67f4d59e3dda5

ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TOOLCHAIN=1.94.1
ARG RUFF_VERSION=0.15.9
ARG BLACK_VERSION=26.3.1

COPY requirements.txt /tmp/requirements.txt

RUN apt-get update \
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
    "black==${BLACK_VERSION}" \
    -r /tmp/requirements.txt

WORKDIR /work
