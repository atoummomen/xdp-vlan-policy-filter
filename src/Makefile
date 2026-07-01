# Build every eBPF C source file in this directory.
#
# Example:
#   vlan_filter.bpf.c -> vlan_filter.bpf.o
#
# The real compilation is delegated to ../scripts/build-bpf.sh so the same
# build logic is used whether the user runs:
#
#   ./scripts/build-bpf.sh
#
# from the repository root, or:
#
#   make
#
# from inside src/.
BPF_C_FILES := $(wildcard *.bpf.c)
BPF_O_FILES := $(patsubst %.bpf.c,%.bpf.o,$(BPF_C_FILES))

# Absolute paths are used so the Makefile works even when called from another
# directory, for example with: make -C src
BUILD_SCRIPT     := $(abspath ../scripts/build-bpf.sh)
BPF_BUILDER_DIR  := $(abspath ../bpf-builder)
BPF_BUILDER_IMG  := bpf-builder:latest

# Source directory mounted into the builder container.
# Defaults to the current src/ directory.
SRCDIR           ?= $(shell pwd)

.PHONY: all clean shell

all: $(BPF_O_FILES)

# Build one BPF object from one BPF C source file.
# The script handles vmlinux.h generation and clang compilation inside the
# dedicated bpf-builder container.
%.bpf.o: %.bpf.c
	bash $(BUILD_SCRIPT) $<

# Open an interactive shell inside the BPF builder container.
#
# This is a debugging helper, not part of the normal validated workflow.
# It uses the same important mounts as scripts/build-bpf.sh:
#
# - src/ is mounted as /work with read/write access.
# - /sys/kernel/btf is mounted read-only so vmlinux.h can be generated from
#   the running kernel BTF information.
#
# The trailing "|| true" prevents make from reporting an error when the user
# exits the interactive shell after Ctrl-C or another non-zero shell exit.
shell:
	@if ! docker images $(BPF_BUILDER_IMG) --format '{{.Repository}}:{{.Tag}}' | grep -q '^$(BPF_BUILDER_IMG)$$'; then \
	    echo "[INFO] Building $(BPF_BUILDER_IMG)..."; \
	    docker build -t $(BPF_BUILDER_IMG) $(BPF_BUILDER_DIR); \
	fi
	docker run --rm -it \
	    -v "$(SRCDIR):/work:rw" \
	    -v "/sys/kernel/btf:/sys/kernel/btf:ro" \
	    $(BPF_BUILDER_IMG) bash || true

# Remove generated BPF build artifacts from src/.
# These files are ignored by Git and can be regenerated.
clean:
	rm -f $(BPF_O_FILES) vmlinux.h
