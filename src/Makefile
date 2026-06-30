BPF_C_FILES := $(wildcard *.bpf.c)
BPF_O_FILES := $(patsubst %.bpf.c,%.bpf.o,$(BPF_C_FILES))

BUILD_SCRIPT     := $(abspath ../scripts/build-bpf.sh)
BPF_BUILDER_DIR  := $(abspath ../bpf-builder)
BPF_BUILDER_IMG  := bpf-builder:latest
SRCDIR           ?= $(shell pwd)

.PHONY: all clean shell

all: $(BPF_O_FILES)

%.bpf.o: %.bpf.c
	bash $(BUILD_SCRIPT) $<

# Drop into an interactive bash inside the bpf-builder container.
# Same mounts as scripts/build-bpf.sh: src/ as /work (rw) and the host
# kernel BTF read-only. /work is the WORKDIR of the image.
#
# The trailing "|| true" swallows the non-zero exit status that bash
# leaves behind when the user exits the shell after a Ctrl-C or a
# failed command — without it, make would noisily report "Error 130"
# even for a normal interactive session.
shell:
	@if ! docker images $(BPF_BUILDER_IMG) --format '{{.Repository}}:{{.Tag}}' | grep -q '^$(BPF_BUILDER_IMG)$$'; then \
	    echo "[INFO] Building $(BPF_BUILDER_IMG)..."; \
	    docker build -t $(BPF_BUILDER_IMG) $(BPF_BUILDER_DIR); \
	fi
	docker run --rm -it \
	    -v "$(SRCDIR):/work:rw" \
	    -v "/sys/kernel/btf:/sys/kernel/btf:ro" \
	    $(BPF_BUILDER_IMG) bash || true

clean:
	rm -f $(BPF_O_FILES) vmlinux.h
