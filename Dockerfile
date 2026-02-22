FROM ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    binutils \
    ca-certificates \
    coreutils \
    findutils \
    make \
    mtools \
    nasm \
    qemu-system-x86 \
    grub-common \
    grub-pc-bin \
    xorriso \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /work
