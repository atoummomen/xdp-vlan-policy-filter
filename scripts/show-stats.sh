#!/bin/bash
set -euo pipefail

# Read per-VLAN packet counters from the pinned BPF maps created by
# scripts/attach-xdp.sh.
#
# The BPF maps are BPF_MAP_TYPE_PERCPU_ARRAY maps, so each key contains one
# value per CPU. This script sums those per-CPU values to print one readable
# total for each VLAN key.

FILTER_SWITCH="${FILTER_SWITCH:-clab-xdp-vlan-policy-filter-filter-switch}"

echo "=== XDP VLAN filter counters on ${FILTER_SWITCH} ==="

# docker exec -i keeps stdin open so the heredoc script below is executed inside
# the filter-switch container.
docker exec -i "${FILTER_SWITCH}" bash -s <<'EOF'
set -euo pipefail

lookup_total() {
    local map="$1"
    local key_hex="$2"

    if [[ ! -e "/sys/fs/bpf/${map}" ]]; then
        echo "missing"
        return
    fi

    # bpftool expects ARRAY map keys in little-endian byte order.
    #
    # Examples:
    # - VLAN 100  -> decimal 100  -> hex 0x00000064 -> key "64 00 00 00"
    # - VLAN 200  -> decimal 200  -> hex 0x000000c8 -> key "c8 00 00 00"
    # - untagged  -> decimal 4096 -> hex 0x00001000 -> key "00 10 00 00"
    #
    # For per-CPU maps, bpftool JSON exposes the values under:
    #
    #   .formatted.values[].value
    #
    # jq sums those values to produce one total counter.
    bpftool -j map lookup pinned "/sys/fs/bpf/${map}" key hex ${key_hex} 2>/dev/null \
        | jq '[.formatted.values[].value] | add // 0'
}

print_row() {
    local label="$1"
    local key_hex="$2"
    local seen pass drop

    seen="$(lookup_total seen_counter "${key_hex}")"
    pass="$(lookup_total pass_counter "${key_hex}")"
    drop="$(lookup_total drop_counter "${key_hex}")"

    printf '%-12s seen=%-8s pass=%-8s drop=%-8s\n' "${label}" "${seen}" "${pass}" "${drop}"
}

echo "Counters: seen/pass/drop"
echo "Expected after VLAN tests: VLAN 100 pass increases, VLAN 200 drop increases, untagged stays 0 for VLAN traffic."
echo ""

# Keys must match the constants used by src/vlan_filter.bpf.c.
print_row "VLAN 100" "64 00 00 00"
print_row "VLAN 200" "c8 00 00 00"
print_row "untagged" "00 10 00 00"
EOF
