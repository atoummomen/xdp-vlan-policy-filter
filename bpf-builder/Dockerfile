FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# Toolchain used by scripts/build-bpf.sh to generate vmlinux.h and compile .bpf.c files.
RUN apt-get update && apt-get install -y \
    clang \
    llvm \
    llvm-dev \
    less \
    libelf-dev \
    libbpf-dev \
    linux-tools-generic \
    make \
    && rm -rf /var/lib/apt/lists/* \
    && cp /usr/lib/linux-tools/$(ls /usr/lib/linux-tools/ | head -1)/bpftool /usr/local/bin/bpftool

# The project src/ directory is mounted here by the build script.
WORKDIR /work
