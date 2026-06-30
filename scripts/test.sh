#!/bin/bash
set -euo pipefail

# Functional test for the validated static VLAN policy:
# VLAN 100 must pass and VLAN 200 must be dropped by the XDP program.

NODE1="${NODE1:-clab-xdp-vlan-policy-filter-node1}"
VLAN100_DST="${VLAN100_DST:-10.100.0.2}"
VLAN200_DST="${VLAN200_DST:-10.200.0.2}"

echo "=== XDP VLAN policy test ==="
echo "VLAN 100 should pass"
if docker exec "${NODE1}" ping -I eth1.100 -c 3 -W 1 "${VLAN100_DST}"; then
    echo "[OK] VLAN 100 passed as expected"
else
    echo "[FAIL] VLAN 100 did not pass" >&2
    exit 1
fi

echo ""
echo "VLAN 200 should drop"
if docker exec "${NODE1}" ping -I eth1.200 -c 3 -W 1 "${VLAN200_DST}"; then
    echo "[FAIL] VLAN 200 passed, but it should drop" >&2
    exit 1
else
    echo "[OK] VLAN 200 dropped as expected"
fi
