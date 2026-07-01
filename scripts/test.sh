#!/bin/bash
set -euo pipefail

# Functional validation for the static VLAN policy.
#
# Expected behavior:
# - VLAN 100 traffic must pass through the filter-switch.
# - VLAN 200 traffic must be dropped by the XDP program.
#
# The test is sent from node1 toward node2 using the VLAN subinterfaces created
# by containerlab/bin/entrypoint.sh.

NODE1="${NODE1:-clab-xdp-vlan-policy-filter-node1}"
VLAN100_DST="${VLAN100_DST:-10.100.0.2}"
VLAN200_DST="${VLAN200_DST:-10.200.0.2}"

echo "=== XDP VLAN policy test ==="

echo "VLAN 100 should pass"
# Ping through eth1.100. This packet carries VLAN ID 100 and should be allowed
# by the XDP program, then forwarded by the Linux bridge to node2.
if docker exec "${NODE1}" ping -I eth1.100 -c 3 -W 1 "${VLAN100_DST}"; then
    echo "[OK] VLAN 100 passed as expected"
else
    echo "[FAIL] VLAN 100 did not pass" >&2
    exit 1
fi

echo ""
echo "VLAN 200 should drop"
# Ping through eth1.200. This packet carries VLAN ID 200 and should be dropped
# at the filter-switch before it reaches node2.
#
# In this case, ping failure is the expected successful test result.
if docker exec "${NODE1}" ping -I eth1.200 -c 3 -W 1 "${VLAN200_DST}"; then
    echo "[FAIL] VLAN 200 passed, but it should drop" >&2
    exit 1
else
    echo "[OK] VLAN 200 dropped as expected"
fi
