#!/bin/bash
set -euo pipefail

# Shared node bootstrap script for the Containerlab topology.
#
# The same script is mounted into all nodes, but each node loads its own
# configuration file from /etc/nodes/<hostname>.cfg.
#
# Roles:
# - node1 and node2 use NODE_ROLE=host and receive VLAN subinterfaces.
# - filter-switch uses NODE_ROLE=filter-switch and receives a Linux bridge,
#   bridge ports, and bpffs for pinned XDP programs/maps.

HOSTNAME=$(hostname)
CFG_FILE="/etc/nodes/${HOSTNAME}.cfg"

echo "=== Node entrypoint: ${HOSTNAME} ==="

if [[ ! -f "${CFG_FILE}" ]]; then
    echo "[FATAL] Missing config: ${CFG_FILE}"
    exit 1
fi

# Load per-node variables such as NODE_ROLE, interface names, VLAN IDs,
# addresses, bridge name, and bridge ports.
source "${CFG_FILE}"

ip link set lo up

configure_host() {
    ip link set "${BASE_IFACE}" up

    # Create the two VLAN subinterfaces used by the validation tests.
    #
    # The command is allowed to fail if the interface already exists, which
    # keeps the entrypoint safe to re-run during debugging.
    ip link add link "${BASE_IFACE}" name "${BASE_IFACE}.${VLAN100_ID}" type vlan id "${VLAN100_ID}" 2>/dev/null || true
    ip link add link "${BASE_IFACE}" name "${BASE_IFACE}.${VLAN200_ID}" type vlan id "${VLAN200_ID}" 2>/dev/null || true

    # Keep MTU explicit and consistent across the lab.
    # This avoids XDP attach/runtime issues caused by unexpected interface MTUs.
    echo "[INFO] Setting MTU 1500 on host interfaces ${BASE_IFACE}, ${BASE_IFACE}.${VLAN100_ID}, ${BASE_IFACE}.${VLAN200_ID}"
    ip link set dev "${BASE_IFACE}" mtu 1500 || true
    ip link set dev "${BASE_IFACE}.${VLAN100_ID}" mtu 1500 || true
    ip link set dev "${BASE_IFACE}.${VLAN200_ID}" mtu 1500 || true

    # Disable VLAN header reordering on VLAN interfaces.
    # This helps keep VLAN headers visible in the packet representation expected
    # by the XDP program during lab validation.
    echo "[INFO] Attempting to disable VLAN header reordering on host VLAN interfaces"
    ip link set "${BASE_IFACE}.${VLAN100_ID}" type vlan reorder_hdr off || true
    ip link set "${BASE_IFACE}.${VLAN200_ID}" type vlan reorder_hdr off || true

    # Disable VLAN offloads when supported by the virtual interface.
    # Some drivers may not support every option, so failures are ignored.
    echo "[INFO] Attempting to disable VLAN offload on host base interface ${BASE_IFACE}"
    ethtool -K "${BASE_IFACE}" rxvlan off txvlan off 2>/dev/null || true
    ethtool -K "${BASE_IFACE}" rx-vlan-offload off tx-vlan-offload off 2>/dev/null || true

    # Remove stale addresses before assigning the expected test addresses.
    ip addr flush dev "${BASE_IFACE}.${VLAN100_ID}" 2>/dev/null || true
    ip addr flush dev "${BASE_IFACE}.${VLAN200_ID}" 2>/dev/null || true

    ip addr add "${VLAN100_IP}/${VLAN100_PREFIX}" dev "${BASE_IFACE}.${VLAN100_ID}"
    ip addr add "${VLAN200_IP}/${VLAN200_PREFIX}" dev "${BASE_IFACE}.${VLAN200_ID}"

    ip link set "${BASE_IFACE}.${VLAN100_ID}" up
    ip link set "${BASE_IFACE}.${VLAN200_ID}" up

    echo "[OK] Host VLAN interfaces configured"
}

configure_filter_switch() {
    ip link set "${BRIDGE_PORT1}" up
    ip link set "${BRIDGE_PORT2}" up

    # Disable VLAN offloads on bridge ports for predictable VLAN visibility in
    # the XDP program across virtualized lab environments.
    echo "[INFO] Attempting to disable VLAN offload on bridge ports ${BRIDGE_PORT1} and ${BRIDGE_PORT2}"
    ethtool -K "${BRIDGE_PORT1}" rxvlan off txvlan off 2>/dev/null || true
    ethtool -K "${BRIDGE_PORT2}" rxvlan off txvlan off 2>/dev/null || true
    ethtool -K "${BRIDGE_PORT1}" rx-vlan-offload off tx-vlan-offload off 2>/dev/null || true
    ethtool -K "${BRIDGE_PORT2}" rx-vlan-offload off tx-vlan-offload off 2>/dev/null || true

    # Keep bridge ports at MTU 1500 for consistency with the host interfaces.
    echo "[INFO] Setting MTU 1500 on bridge ports ${BRIDGE_PORT1} and ${BRIDGE_PORT2}"
    ip link set dev "${BRIDGE_PORT1}" mtu 1500 || true
    ip link set dev "${BRIDGE_PORT2}" mtu 1500 || true

    # Create the Linux bridge used to forward packets that are allowed by XDP.
    # Existing bridge creation is tolerated so the script can be re-run.
    ip link add name "${BRIDGE_NAME}" type bridge 2>/dev/null || true
    ip link set "${BRIDGE_PORT1}" master "${BRIDGE_NAME}"
    ip link set "${BRIDGE_PORT2}" master "${BRIDGE_NAME}"

    echo "[INFO] Setting MTU 1500 on bridge ${BRIDGE_NAME}"
    ip link set dev "${BRIDGE_NAME}" mtu 1500 || true
    ip link set "${BRIDGE_NAME}" up

    # bpffs is required because attach-xdp.sh pins the loaded XDP program and
    # BPF maps under /sys/fs/bpf. Mount it only if it is not already mounted.
    if ! findmnt -t bpf /sys/fs/bpf >/dev/null 2>&1; then
        mkdir -p /sys/fs/bpf
        mount -t bpf bpf /sys/fs/bpf
        echo "[OK] bpffs mounted at /sys/fs/bpf"
    fi

    echo "[OK] Filter switch bridge configured"
}

case "${NODE_ROLE}" in
    host)
        configure_host
        ;;
    filter-switch)
        configure_filter_switch
        ;;
    *)
        echo "[FATAL] Unknown NODE_ROLE=${NODE_ROLE}"
        exit 1
        ;;
esac

# Print the final node state. These commands are useful when debugging
# Containerlab startup and also document the interfaces created by the script.
echo ""
ip addr show
echo ""
bridge link show || true
echo ""
echo "[INFO] Node ${HOSTNAME} ready"
