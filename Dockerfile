FROM ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    binutils \
    ca-certificates \
    coreutils \
    curl \
    file \
    findutils \
    make \
    mtools \
    nasm \
    qemu-system-x86 \
    grub-common \
    grub-pc-bin \
    xorriso \
  && rm -rf /var/lib/apt/lists/*

ENV RUSTUP_HOME=/opt/rustup
ENV CARGO_HOME=/opt/cargo
ENV PATH=/opt/cargo/bin:$PATH

RUN mkdir -p "${RUSTUP_HOME}" "${CARGO_HOME}" \
  && curl -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal --default-toolchain stable \
  && rustup target add i686-unknown-linux-gnu

WORKDIR /work
