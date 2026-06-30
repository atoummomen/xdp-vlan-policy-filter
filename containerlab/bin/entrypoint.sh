#!/bin/bash
set -euo pipefail

# Shared node bootstrap for the lab. Host nodes receive VLAN subinterfaces;
# the filter-switch receives a Linux bridge and bpffs for pinned XDP objects.

HOSTNAME=$(hostname)
CFG_FILE="/etc/nodes/${HOSTNAME}.cfg"

echo "=== Node entrypoint: ${HOSTNAME} ==="

if [[ ! -f "${CFG_FILE}" ]]; then
    echo "[FATAL] Missing config: ${CFG_FILE}"
    exit 1
fi

source "${CFG_FILE}"

ip link set lo up

configure_host() {
    ip link set "${BASE_IFACE}" up

    # Create both test VLANs on the host-facing interface. Existing interfaces
    # are tolerated so re-running the entrypoint remains safe.
    ip link add link "${BASE_IFACE}" name "${BASE_IFACE}.${VLAN100_ID}" type vlan id "${VLAN100_ID}" 2>/dev/null || true
    ip link add link "${BASE_IFACE}" name "${BASE_IFACE}.${VLAN200_ID}" type vlan id "${VLAN200_ID}" 2>/dev/null || true

    echo "[INFO] Setting MTU 1500 on host interfaces ${BASE_IFACE}, ${BASE_IFACE}.${VLAN100_ID}, ${BASE_IFACE}.${VLAN200_ID}"
    ip link set dev "${BASE_IFACE}" mtu 1500 || true
    ip link set dev "${BASE_IFACE}.${VLAN100_ID}" mtu 1500 || true
    ip link set dev "${BASE_IFACE}.${VLAN200_ID}" mtu 1500 || true

    echo "[INFO] Attempting to disable VLAN header reordering on host VLAN interfaces"
    # XDP sees the expected VLAN header only when the kernel/NIC does not hide
    # or reorder it before the packet reaches the program.
    ip link set "${BASE_IFACE}.${VLAN100_ID}" type vlan reorder_hdr off || true
    ip link set "${BASE_IFACE}.${VLAN200_ID}" type vlan reorder_hdr off || true

    echo "[INFO] Attempting to disable VLAN offload on host base interface ${BASE_IFACE}"
    ethtool -K "${BASE_IFACE}" rxvlan off txvlan off 2>/dev/null || true
    ethtool -K "${BASE_IFACE}" rx-vlan-offload off tx-vlan-offload off 2>/dev/null || true

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

    echo "[INFO] Attempting to disable VLAN offload on bridge ports ${BRIDGE_PORT1} and ${BRIDGE_PORT2}"
    # Disable VLAN offloads on bridge ports for predictable VLAN visibility in
    # the XDP program across virtualized lab environments.
    ethtool -K "${BRIDGE_PORT1}" rxvlan off txvlan off 2>/dev/null || true
    ethtool -K "${BRIDGE_PORT2}" rxvlan off txvlan off 2>/dev/null || true
    ethtool -K "${BRIDGE_PORT1}" rx-vlan-offload off tx-vlan-offload off 2>/dev/null || true
    ethtool -K "${BRIDGE_PORT2}" rx-vlan-offload off tx-vlan-offload off 2>/dev/null || true

    echo "[INFO] Setting MTU 1500 on bridge ports ${BRIDGE_PORT1} and ${BRIDGE_PORT2}"
    ip link set dev "${BRIDGE_PORT1}" mtu 1500 || true
    ip link set dev "${BRIDGE_PORT2}" mtu 1500 || true

    ip link add name "${BRIDGE_NAME}" type bridge 2>/dev/null || true
    ip link set "${BRIDGE_PORT1}" master "${BRIDGE_NAME}"
    ip link set "${BRIDGE_PORT2}" master "${BRIDGE_NAME}"

    echo "[INFO] Setting MTU 1500 on bridge ${BRIDGE_NAME}"
    ip link set dev "${BRIDGE_NAME}" mtu 1500 || true
    ip link set "${BRIDGE_NAME}" up

    # bpffs is required for bpftool to pin the loaded XDP program and maps.
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

echo ""
ip addr show
echo ""
bridge link show || true
echo ""
echo "[INFO] Node ${HOSTNAME} ready"
