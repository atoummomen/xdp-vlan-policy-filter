#!/bin/bash
set -euo pipefail

# Load the validated static VLAN XDP program on the filter switch and attach it
# to both bridge-facing ports. The loaded maps are pinned under /sys/fs/bpf so
# show-stats.sh can read packet counters after traffic tests.

FILTER_SWITCH="${FILTER_SWITCH:-clab-xdp-vlan-policy-filter-filter-switch}"

echo "=== Attach XDP VLAN filter on ${FILTER_SWITCH} ==="

# docker exec -i is required so the heredoc below is passed to bash inside the
# container. Without -i, the script body may not be executed reliably.
docker exec -i "${FILTER_SWITCH}" bash -s <<'EOF'
set -euo pipefail

BPF_OBJECT="/work/bpf/vlan_filter.bpf.o"
BPF_PROG_PIN="/sys/fs/bpf/vlan_filter"

echo "[INFO] Detaching existing XDP programs from eth1 and eth2"
bpftool net detach xdp dev eth1 2>/dev/null || true
bpftool net detach xdp dev eth2 2>/dev/null || true

echo "[INFO] Removing old pinned program and maps"
rm -f "${BPF_PROG_PIN}" \
      /sys/fs/bpf/seen_counter \
      /sys/fs/bpf/pass_counter \
      /sys/fs/bpf/drop_counter || true

echo "[INFO] Ensuring MTU 1500 before XDP attach"
# Keep the veth/bridge MTU aligned so XDP attach and test traffic use the same
# packet-size assumptions across the lab.
ip link set dev eth1 mtu 1500 || true
ip link set dev eth2 mtu 1500 || true
ip link set dev br0 mtu 1500 || true

echo "[INFO] Loading ${BPF_OBJECT} and pinning maps under /sys/fs/bpf"
bpftool prog load "${BPF_OBJECT}" "${BPF_PROG_PIN}" type xdp pinmaps /sys/fs/bpf

echo "[INFO] Attaching XDP program to eth1 and eth2"
bpftool net attach xdp pinned "${BPF_PROG_PIN}" dev eth1
bpftool net attach xdp pinned "${BPF_PROG_PIN}" dev eth2

echo "[INFO] Current bpftool net state"
bpftool net
EOF

echo "=== XDP attach complete ==="
