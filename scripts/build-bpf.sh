#!/bin/bash
set -euo pipefail

# Build helper for the eBPF program.
#
# This script does two jobs:
#
# 1. Generate vmlinux.h from the running kernel BTF information.
# 2. Compile a .bpf.c source file into a .bpf.o object file.
#
# The compilation is done inside the dedicated bpf-builder Docker image so the
# host system does not need to have the full BPF toolchain installed directly.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

# By default, generated files are written to the current working directory.
# When the script is called by src/Makefile, the current directory is src/.
SRCDIR="$(pwd)"

GENERATE_VMLINUX=false
SRCFILE=""

# Optional mode:
#
#   ./scripts/build-bpf.sh --gen-vmlinux
#
# generates vmlinux.h only.
#
# Normal mode:
#
#   ./scripts/build-bpf.sh vlan_filter.bpf.c
#
# compiles the selected BPF source file.
if [[ "${1:-}" == "--gen-vmlinux" ]]; then
    GENERATE_VMLINUX=true
    SRCFILE="${2:-}"
else
    SRCFILE="${1:-}"
fi

# If the user runs the script from the repository root without arguments,
# build the main project BPF program from src/.
if [[ -z "${SRCFILE}" && "${GENERATE_VMLINUX}" == false ]]; then
    SRCDIR="${PROJECT_ROOT}/src"
    SRCFILE="vlan_filter.bpf.c"
fi

# vmlinux.h is generated from kernel BTF information.
# Without /sys/kernel/btf/vmlinux, the CO-RE-style BPF build cannot proceed.
if [[ "${GENERATE_VMLINUX}" == true || -n "${SRCFILE}" ]]; then
    if [[ ! -r /sys/kernel/btf/vmlinux ]]; then
        echo "[ERROR] Kernel BTF not available: /sys/kernel/btf/vmlinux"
        echo "  Cannot generate vmlinux.h or compile BPF programs."
        exit 1
    fi
fi

# Build the local BPF builder image if it does not already exist.
# This image contains clang, llvm-strip, bpftool, and libbpf headers.
if ! docker images bpf-builder:latest --format '{{.Repository}}:{{.Tag}}' | grep -q '^bpf-builder:latest$'; then
    echo "[INFO] Building bpf-builder:latest..."
    docker build -t bpf-builder:latest "${PROJECT_ROOT}/bpf-builder"
fi

# Generate vmlinux.h in the selected source directory.
# The host kernel BTF directory is mounted read-only, while the source directory
# is mounted read/write so the generated header can be saved there.
if [[ "${GENERATE_VMLINUX}" == true ]]; then
    echo "[INFO] Generating vmlinux.h in ${SRCDIR}..."
    docker run --rm \
        -v "${SRCDIR}:/work:rw" \
        -v "/sys/kernel/btf:/sys/kernel/btf:ro" \
        bpf-builder:latest \
        sh -c "bpftool btf dump file /sys/kernel/btf/vmlinux format c > /work/vmlinux.h"
    echo "[OK] vmlinux.h generated"
fi

if [[ -n "${SRCFILE}" ]]; then
    # Stop early if the requested BPF source file does not exist in SRCDIR.
    if [[ ! -f "${SRCDIR}/${SRCFILE}" ]]; then
        echo "[ERROR] Source file not found: ${SRCDIR}/${SRCFILE}"
        exit 1
    fi

    OUTFILE="${SRCFILE%.c}.o"

    # The BPF source includes "vmlinux.h".
    # If the header is missing, generate it automatically before compiling.
    if [[ ! -f "${SRCDIR}/vmlinux.h" ]]; then
        echo "[INFO] vmlinux.h missing, generating automatically..."
        docker run --rm \
            -v "${SRCDIR}:/work:rw" \
            -v "/sys/kernel/btf:/sys/kernel/btf:ro" \
            bpf-builder:latest \
            sh -c "bpftool btf dump file /sys/kernel/btf/vmlinux format c > /work/vmlinux.h"
    fi

    # Compile the BPF program for the eBPF target.
    #
    # - -target bpf tells clang to generate eBPF bytecode.
    # - -D__TARGET_ARCH_x86 matches the lab machine architecture.
    # - -I/work allows the source file to include /work/vmlinux.h.
    # - llvm-strip -g removes debug information from the final object.
    echo "[INFO] Compiling ${SRCFILE}..."
    docker run --rm \
        -v "${SRCDIR}:/work:rw" \
        bpf-builder:latest \
        sh -c "clang -g -O2 -target bpf -D__TARGET_ARCH_x86 -I/work -c \"/work/${SRCFILE}\" -o \"/work/${OUTFILE}\" && llvm-strip -g \"/work/${OUTFILE}\""
    echo "[OK] Compiled: ${SRCFILE} -> ${OUTFILE}"
fi
