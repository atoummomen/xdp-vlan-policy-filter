#!/bin/bash
set -euo pipefail

# Validate dynamic VLAN policy changes without rebuilding, deploying, or
# reattaching XDP. The lab must already be deployed and dynamic XDP must already
# be attached with scripts/attach-xdp-dynamic.sh.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILTER_SWITCH="${FILTER_SWITCH:-clab-xdp-vlan-policy-filter-filter-switch}"
NODE1="${NODE1:-clab-xdp-vlan-policy-filter-node1}"
VLAN200_DST="${VLAN200_DST:-10.200.0.2}"
DYNAMIC_PROG_PIN="/sys/fs/bpf/xdp_vlan_dynamic/vlan_filter_dynamic"

show_dynamic_program() {
    docker exec "${FILTER_SWITCH}" bpftool prog show pinned "${DYNAMIC_PROG_PIN}"
}

expect_vlan200_drop() {
    echo "[TEST] VLAN 200 should drop"
    if docker exec "${NODE1}" ping -I eth1.200 -c 3 -W 1 "${VLAN200_DST}"; then
        echo "[FAIL] VLAN 200 passed, but it should drop" >&2
        exit 1
    fi
    echo "[OK] VLAN 200 dropped as expected"
}

expect_vlan200_pass() {
    echo "[TEST] VLAN 200 should pass"
    if docker exec "${NODE1}" ping -I eth1.200 -c 3 -W 1 "${VLAN200_DST}"; then
        echo "[OK] VLAN 200 passed as expected"
    else
        echo "[FAIL] VLAN 200 did not pass" >&2
        exit 1
    fi
}

echo "=== Dynamic VLAN policy validation ==="
echo "This script does not build, deploy, attach XDP, reattach XDP, or destroy the lab."
echo "It only updates the pinned dynamic policy map and sends existing VLAN 200 traffic."
echo ""

expect_vlan200_drop

echo ""
"${SCRIPT_DIR}/vlan-policy.sh" show 200

echo ""
echo "[INFO] Dynamic program before policy changes"
show_dynamic_program

echo ""
"${SCRIPT_DIR}/vlan-policy.sh" pass 200
expect_vlan200_pass

echo ""
echo "[INFO] Dynamic program after allowing VLAN 200"
show_dynamic_program

echo ""
"${SCRIPT_DIR}/vlan-policy.sh" block 200
expect_vlan200_drop

echo ""
echo "[INFO] Dynamic program after blocking VLAN 200 again"
show_dynamic_program

echo ""
"${SCRIPT_DIR}/vlan-policy.sh" show 200
"${SCRIPT_DIR}/vlan-policy.sh" list blocked
"${SCRIPT_DIR}/vlan-policy.sh" list all

echo ""
BPF_MAP_DIR=/sys/fs/bpf/xdp_vlan_dynamic "${SCRIPT_DIR}/show-stats.sh"

echo "=== Dynamic VLAN policy validation complete ==="
