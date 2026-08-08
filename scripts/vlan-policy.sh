#!/bin/bash
set -euo pipefail

# Manage the dynamic VLAN policy map used by vlan_filter_dynamic.bpf.c.

FILTER_SWITCH="${FILTER_SWITCH:-clab-xdp-vlan-policy-filter-filter-switch}"
POLICY_MAP="/sys/fs/bpf/xdp_vlan_dynamic/vlan_policy"

usage() {
    cat <<'EOF'
Usage:
  ./scripts/vlan-policy.sh block VLAN...
  ./scripts/vlan-policy.sh drop VLAN...
  ./scripts/vlan-policy.sh pass VLAN...
  ./scripts/vlan-policy.sh allow VLAN...
  ./scripts/vlan-policy.sh show VLAN
  ./scripts/vlan-policy.sh list blocked
  ./scripts/vlan-policy.sh list all
EOF
}

die() {
    echo "[ERROR] $*" >&2
    exit 1
}

docker_exec() {
    docker exec "${FILTER_SWITCH}" "$@"
}

require_dynamic_map() {
    docker_exec true >/dev/null 2>&1 || die "Cannot reach filter-switch container: ${FILTER_SWITCH}"

    if ! docker_exec test -e "${POLICY_MAP}"; then
        die "Dynamic policy map not found. Run ./scripts/attach-xdp-dynamic.sh first."
    fi
}

validate_vlan() {
    local vlan="$1"

    if [[ ! "${vlan}" =~ ^[0-9]+$ ]]; then
        die "Invalid VLAN ID '${vlan}': must be numeric"
    fi

    if (( vlan < 0 || vlan > 4095 )); then
        die "Invalid VLAN ID '${vlan}': must be in range 0..4095"
    fi
}

u32_to_le_hex() {
    local value="$1"

    printf '%02x %02x %02x %02x' \
        $(( value & 0xff )) \
        $(( (value >> 8) & 0xff )) \
        $(( (value >> 16) & 0xff )) \
        $(( (value >> 24) & 0xff ))
}

lookup_policy() {
    local vlan="$1"
    local key_hex output

    key_hex="$(u32_to_le_hex "${vlan}")"

    if ! output="$(docker_exec bpftool -j map lookup pinned "${POLICY_MAP}" key hex ${key_hex} 2>/dev/null)"; then
        echo "missing"
        return 0
    fi

    printf '%s\n' "${output}" | jq -r '
        def hexbyte(s):
            (s | ascii_downcase | ltrimstr("0x") | explode)
            | reduce .[] as $c (0; . * 16 +
                if $c >= 48 and $c <= 57 then $c - 48
                elif $c >= 97 and $c <= 102 then $c - 87
                else 0 end);
        def byte(x): if (x | type) == "number" then x else hexbyte(x) end;
        def le32(a): (byte(a[0]) + (byte(a[1]) * 256) + (byte(a[2]) * 65536) + (byte(a[3]) * 16777216));
        def scalar(x):
            if (x | type) == "number" then x
            elif (x | type) == "string" then
                if (x | startswith("0x")) then hexbyte(x) else (x | tonumber?) end
            else null
            end;
        if (.value | type) == "array" then le32(.value)
        elif (.value? | type) == "number" or (.value? | type) == "string" then scalar(.value)
        elif (.formatted.value? | type) == "number" or (.formatted.value? | type) == "string" then scalar(.formatted.value)
        else "invalid-json"
        end
    '
}

policy_state() {
    local value="$1"

    case "${value}" in
        missing) echo "allowed by default" ;;
        0) echo "blocked" ;;
        1) echo "explicitly allowed" ;;
        *) echo "invalid policy value ${value}" ;;
    esac
}

update_policy() {
    local vlan="$1"
    local value="$2"
    local key_hex value_hex

    key_hex="$(u32_to_le_hex "${vlan}")"
    value_hex="$(u32_to_le_hex "${value}")"

    docker_exec bpftool map update pinned "${POLICY_MAP}" \
        key hex ${key_hex} \
        value hex ${value_hex} >/dev/null
}

set_policy() {
    local action="$1"
    local desired="$2"
    shift 2

    if (( $# == 0 )); then
        die "${action} requires at least one VLAN ID"
    fi

    local vlan current from_state
    for vlan in "$@"; do
        validate_vlan "${vlan}"
        current="$(lookup_policy "${vlan}")"
        from_state="$(policy_state "${current}")"

        if [[ "${desired}" == "0" ]]; then
            case "${current}" in
                0) echo "VLAN ${vlan} is already blocked" ;;
                *)
                    update_policy "${vlan}" 0
                    echo "VLAN ${vlan} changed from ${from_state} to blocked"
                    ;;
            esac
        else
            case "${current}" in
                1) echo "VLAN ${vlan} is already explicitly allowed" ;;
                *)
                    update_policy "${vlan}" 1
                    echo "VLAN ${vlan} changed from ${from_state} to explicitly allowed"
                    ;;
            esac
        fi
    done
}

show_policy() {
    local vlan="$1"
    local current

    validate_vlan "${vlan}"
    current="$(lookup_policy "${vlan}")"
    echo "VLAN ${vlan}: $(policy_state "${current}")"
}

list_policy() {
    local mode="$1"

    docker_exec bpftool -j map dump pinned "${POLICY_MAP}" | jq -r --arg mode "${mode}" '
        def hexbyte(s):
            (s | ascii_downcase | ltrimstr("0x") | explode)
            | reduce .[] as $c (0; . * 16 +
                if $c >= 48 and $c <= 57 then $c - 48
                elif $c >= 97 and $c <= 102 then $c - 87
                else 0 end);
        def byte(x): if (x | type) == "number" then x else hexbyte(x) end;
        def le32(a): (byte(a[0]) + (byte(a[1]) * 256) + (byte(a[2]) * 65536) + (byte(a[3]) * 16777216));
        def scalar(x):
            if (x | type) == "number" then x
            elif (x | type) == "string" then
                if (x | startswith("0x")) then hexbyte(x) else (x | tonumber?) end
            else null
            end;
        def decode_value(e):
            if (e.value | type) == "array" then le32(e.value)
            elif (e.value? | type) == "number" or (e.value? | type) == "string" then scalar(e.value)
            elif (e.formatted.value? | type) == "number" or (e.formatted.value? | type) == "string" then scalar(e.formatted.value)
            else null
            end;
        def decode_key(e):
            if (e.key | type) == "array" then le32(e.key)
            elif (e.key? | type) == "number" or (e.key? | type) == "string" then scalar(e.key)
            elif (e.formatted.key? | type) == "number" or (e.formatted.key? | type) == "string" then scalar(e.formatted.key)
            else null
            end;
        [ .[] | {key: decode_key(.), value: decode_value(.)} | select(.key != null) ]
        | sort_by(.key)
        | if $mode == "blocked" then map(select(.value == 0)) else . end
        | if length == 0 then
              if $mode == "blocked" then "No explicit blocked VLAN entries." else "No explicit VLAN policy entries. All VLANs are allowed by default." end
          else
              .[] | if .value == 0 then
                    "VLAN \(.key): blocked"
                  elif .value == 1 then
                    "VLAN \(.key): explicitly allowed"
                  else
                    "VLAN \(.key): invalid policy value \(.value)"
                  end
          end
    '
}

main() {
    if (( $# < 1 )); then
        usage
        exit 1
    fi

    local command="$1"
    shift

    case "${command}" in
        -h|--help|help)
            usage
            exit 0
            ;;
    esac

    require_dynamic_map

    case "${command}" in
        block|drop)
            set_policy "${command}" 0 "$@"
            ;;
        pass|allow)
            set_policy "${command}" 1 "$@"
            ;;
        show)
            if (( $# != 1 )); then
                die "show requires exactly one VLAN ID"
            fi
            show_policy "$1"
            ;;
        list)
            if (( $# != 1 )); then
                die "list requires one argument: blocked or all"
            fi
            case "$1" in
                blocked|all) list_policy "$1" ;;
                *) die "Invalid list mode '$1': expected blocked or all" ;;
            esac
            ;;
        *)
            usage
            die "Unknown command: ${command}"
            ;;
    esac
}

main "$@"
