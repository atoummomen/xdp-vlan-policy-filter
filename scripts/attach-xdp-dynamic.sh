#!/bin/bash
set -euo pipefail

# Load and attach the dynamic VLAN XDP policy program on the filter-switch.
#
# This switches the lab into dynamic mode. After this script has attached XDP,
# VLAN policy changes are made through /sys/fs/bpf/xdp_vlan_dynamic/vlan_policy
# without rebuilding the BPF object or reattaching XDP.

FILTER_SWITCH="${FILTER_SWITCH:-clab-xdp-vlan-policy-filter-filter-switch}"

echo "=== Attach dynamic XDP VLAN policy on ${FILTER_SWITCH} ==="

docker exec -i "${FILTER_SWITCH}" bash -s <<'EOF'
set -euo pipefail

BPF_OBJECT="/work/bpf/vlan_filter_dynamic.bpf.o"
PIN_DIR="/sys/fs/bpf/xdp_vlan_dynamic"
BPF_PROG_PIN="${PIN_DIR}/vlan_filter_dynamic"
POLICY_MAP_PIN="${PIN_DIR}/vlan_policy"

echo "[INFO] Detaching existing XDP programs from eth1 and eth2"
bpftool net detach xdp dev eth1 2>/dev/null || true
bpftool net detach xdp dev eth2 2>/dev/null || true

echo "[INFO] Removing old dynamic pinned program and maps"
rm -rf "${PIN_DIR}"
mkdir -p "${PIN_DIR}"

echo "[INFO] Ensuring MTU 1500 before XDP attach"
ip link set dev eth1 mtu 1500 || true
ip link set dev eth2 mtu 1500 || true
ip link set dev br0 mtu 1500 || true

echo "[INFO] Loading ${BPF_OBJECT} and pinning dynamic maps under ${PIN_DIR}"
bpftool prog load "${BPF_OBJECT}" "${BPF_PROG_PIN}" type xdp pinmaps "${PIN_DIR}"

echo "[INFO] Initializing default dynamic policy: VLAN 200 blocked"
# VLAN 200 decimal is 0x000000c8, encoded as little-endian u32 bytes.
bpftool map update pinned "${POLICY_MAP_PIN}" \
    key hex c8 00 00 00 \
    value hex 00 00 00 00

echo "[INFO] VLAN 100 is not inserted into vlan_policy; it passes by default"

echo "[INFO] Attaching dynamic XDP program to eth1 and eth2"
bpftool net attach xdp pinned "${BPF_PROG_PIN}" dev eth1
bpftool net attach xdp pinned "${BPF_PROG_PIN}" dev eth2

echo "[INFO] Current bpftool net state"
bpftool net
EOF

echo "=== Dynamic XDP attach complete ==="
