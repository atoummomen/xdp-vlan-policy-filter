#!/bin/bash
set -euo pipefail

# Load and attach the VLAN XDP program on the filter-switch container.
#
# XDP is attached to both switch-facing ports:
# - eth1 receives traffic from node1.
# - eth2 receives traffic from node2.
#
# The BPF program and maps are pinned under /sys/fs/bpf so they can be inspected
# later by bpftool and by scripts/show-stats.sh.

FILTER_SWITCH="${FILTER_SWITCH:-clab-xdp-vlan-policy-filter-filter-switch}"

echo "=== Attach XDP VLAN filter on ${FILTER_SWITCH} ==="

# docker exec -i is required because the script body is provided through the
# heredoc below. Without -i, bash inside the container may not receive stdin.
docker exec -i "${FILTER_SWITCH}" bash -s <<'EOF'
set -euo pipefail

BPF_OBJECT="/work/bpf/vlan_filter.bpf.o"
BPF_PROG_PIN="/sys/fs/bpf/vlan_filter"

echo "[INFO] Detaching existing XDP programs from eth1 and eth2"
# Detach any previous XDP program so the script can be safely re-run.
bpftool net detach xdp dev eth1 2>/dev/null || true
bpftool net detach xdp dev eth2 2>/dev/null || true

echo "[INFO] Removing old pinned program and maps"
# Remove old pinned objects to avoid stale programs or stale map pins from a
# previous run. The program will recreate fresh pins when loaded below.
rm -f "${BPF_PROG_PIN}" \
      /sys/fs/bpf/seen_counter \
      /sys/fs/bpf/pass_counter \
      /sys/fs/bpf/drop_counter || true

echo "[INFO] Ensuring MTU 1500 before XDP attach"
# Keep the veth and bridge MTU aligned so XDP attach and test traffic use the
# same packet-size assumptions across the lab.
ip link set dev eth1 mtu 1500 || true
ip link set dev eth2 mtu 1500 || true
ip link set dev br0 mtu 1500 || true

echo "[INFO] Loading ${BPF_OBJECT} and pinning maps under /sys/fs/bpf"
# Load the compiled XDP object and pin its maps under /sys/fs/bpf.
# Pinning makes the maps accessible after loading, so show-stats.sh can read
# seen/pass/drop counters after the traffic tests.
bpftool prog load "${BPF_OBJECT}" "${BPF_PROG_PIN}" type xdp pinmaps /sys/fs/bpf

echo "[INFO] Attaching XDP program to eth1 and eth2"
# Attach to both bridge ports so packets are filtered before normal Linux bridge
# forwarding, regardless of the direction in which they enter the switch.
bpftool net attach xdp pinned "${BPF_PROG_PIN}" dev eth1
bpftool net attach xdp pinned "${BPF_PROG_PIN}" dev eth2

echo "[INFO] Current bpftool net state"
bpftool net
EOF

echo "=== XDP attach complete ==="
