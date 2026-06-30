#!/bin/bash
set -euo pipefail

# Read per-VLAN packet counters from the pinned BPF maps created by
# attach-xdp.sh. Per-CPU map values are summed with jq for readable totals.

FILTER_SWITCH="${FILTER_SWITCH:-clab-xdp-vlan-policy-filter-filter-switch}"

echo "=== XDP VLAN filter counters on ${FILTER_SWITCH} ==="

# Keep stdin open for the heredoc executed inside the filter-switch container.
docker exec -i "${FILTER_SWITCH}" bash -s <<'EOF'
set -euo pipefail

lookup_total() {
    local map="$1"
    local key_hex="$2"

    if [[ ! -e "/sys/fs/bpf/${map}" ]]; then
        echo "missing"
        return
    fi

    # bpftool JSON exposes per-CPU counters under .formatted.values[].value.
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
print_row "VLAN 100" "64 00 00 00"
print_row "VLAN 200" "c8 00 00 00"
print_row "untagged" "00 10 00 00"
EOF
