#!/bin/bash
set -euo pipefail

# Compile eBPF C sources using the dedicated bpf-builder image. The script is
# normally called by src/Makefile from inside src/ so generated files stay next
# to the BPF source.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
SRCDIR="$(pwd)"

GENERATE_VMLINUX=false
SRCFILE=""

if [[ "${1:-}" == "--gen-vmlinux" ]]; then
    GENERATE_VMLINUX=true
    SRCFILE="${2:-}"
else
    SRCFILE="${1:-}"
fi

if [[ -z "${SRCFILE}" && "${GENERATE_VMLINUX}" == false ]]; then
    SRCDIR="${PROJECT_ROOT}/src"
    SRCFILE="vlan_filter.bpf.c"
fi

if [[ "${GENERATE_VMLINUX}" == true || -n "${SRCFILE}" ]]; then
    if [[ ! -r /sys/kernel/btf/vmlinux ]]; then
        echo "[ERROR] Kernel BTF not available: /sys/kernel/btf/vmlinux"
        echo "  Cannot generate vmlinux.h or compile BPF programs."
        exit 1
    fi
fi

if ! docker images bpf-builder:latest --format '{{.Repository}}:{{.Tag}}' | grep -q '^bpf-builder:latest$'; then
    echo "[INFO] Building bpf-builder:latest..."
    docker build -t bpf-builder:latest "${PROJECT_ROOT}/bpf-builder"
fi

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
    if [[ ! -f "${SRCDIR}/${SRCFILE}" ]]; then
        echo "[ERROR] Source file not found: ${SRCDIR}/${SRCFILE}"
        exit 1
    fi

    OUTFILE="${SRCFILE%.c}.o"

    if [[ ! -f "${SRCDIR}/vmlinux.h" ]]; then
        echo "[INFO] vmlinux.h missing, generating automatically..."
        docker run --rm \
            -v "${SRCDIR}:/work:rw" \
            -v "/sys/kernel/btf:/sys/kernel/btf:ro" \
            bpf-builder:latest \
            sh -c "bpftool btf dump file /sys/kernel/btf/vmlinux format c > /work/vmlinux.h"
    fi

    echo "[INFO] Compiling ${SRCFILE}..."
    docker run --rm \
        -v "${SRCDIR}:/work:rw" \
        bpf-builder:latest \
        sh -c "clang -g -O2 -target bpf -D__TARGET_ARCH_x86 -I/work -c \"/work/${SRCFILE}\" -o \"/work/${OUTFILE}\" && llvm-strip -g \"/work/${OUTFILE}\""
    echo "[OK] Compiled: ${SRCFILE} -> ${OUTFILE}"
fi
