#include "vmlinux.h"
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_endian.h>

/*
 * VLAN EtherTypes handled by the parser.
 *
 * ETH_P_8021Q  = standard IEEE 802.1Q VLAN tag.
 * ETH_P_8021AD = IEEE 802.1ad provider/service VLAN tag.
 *
 * The project validation uses 802.1Q VLAN subinterfaces, but accepting both
 * EtherTypes makes the parser more complete for tagged Ethernet frames.
 */
#define ETH_P_8021Q 0x8100
#define ETH_P_8021AD 0x88A8

/*
 * The VLAN identifier is stored in the lower 12 bits of the VLAN TCI field.
 * The remaining bits are used for PCP and DEI, so they must be masked out.
 */
#define VLAN_VID_MASK 0x0fff

/* Static allowlist policy used in this submission. */
#define ALLOWED_VLAN 100

/*
 * Valid VLAN IDs are in the range 0..4095.
 * Key 4096 is therefore reserved as a separate counter key for untagged frames.
 */
#define UNTAGGED_KEY 4096
#define STATS_MAX_ENTRIES 4097

/*
 * Packet counters are stored in per-CPU arrays.
 *
 * Per-CPU maps avoid contention in the XDP fast path because each CPU updates
 * its own local counter. The user-space stats script later sums the per-CPU
 * values to print one readable total per key.
 */
struct {
    __uint(type, BPF_MAP_TYPE_PERCPU_ARRAY);
    __uint(max_entries, STATS_MAX_ENTRIES);
    __type(key, __u32);
    __type(value, __u64);
} seen_counter SEC(".maps");

struct {
    __uint(type, BPF_MAP_TYPE_PERCPU_ARRAY);
    __uint(max_entries, STATS_MAX_ENTRIES);
    __type(key, __u32);
    __type(value, __u64);
} pass_counter SEC(".maps");

struct {
    __uint(type, BPF_MAP_TYPE_PERCPU_ARRAY);
    __uint(max_entries, STATS_MAX_ENTRIES);
    __type(key, __u32);
    __type(value, __u64);
} drop_counter SEC(".maps");

/*
 * Increment one counter entry.
 *
 * The lookup can theoretically fail if the key is outside the map range.
 * In this project, VLAN IDs 0..4095 and UNTAGGED_KEY 4096 are valid keys.
 */
static __always_inline void bump(void *map, __u32 key)
{
    __u64 *value;

    value = bpf_map_lookup_elem(map, &key);
    if (value)
        *value += 1;
}

/*
 * XDP entry point.
 *
 * The program runs on filter-switch eth1 and eth2 before normal Linux bridge
 * forwarding. It parses the Ethernet header, checks for an optional VLAN tag,
 * updates counters, and returns either XDP_PASS or XDP_DROP.
 */
SEC("xdp")
int xdp_vlan_filter(struct xdp_md *ctx)
{
    void *data = (void *)(long)ctx->data;
    void *data_end = (void *)(long)ctx->data_end;

    struct ethhdr *eth = data;
    struct vlan_hdr *vh;
    __u16 h_proto;
    __u16 vlan_id;
    __u32 key;

    /*
     * Every packet read must be protected by a bounds check.
     * This check proves to the BPF verifier that the Ethernet header is fully
     * inside the packet buffer before eth->h_proto is accessed.
     */
    if ((void *)(eth + 1) > data_end)
        return XDP_PASS;

    h_proto = bpf_ntohs(eth->h_proto);

    /*
     * Untagged frames are outside the VLAN deny policy.
     * They are counted separately under UNTAGGED_KEY and allowed to pass.
     */
    if (h_proto != ETH_P_8021Q && h_proto != ETH_P_8021AD) {
        key = UNTAGGED_KEY;
        bump(&seen_counter, key);
        bump(&pass_counter, key);
        return XDP_PASS;
    }

    /*
     * For VLAN-tagged frames, the VLAN header starts immediately after the
     * Ethernet header. Another bounds check is required before reading it.
     */
    vh = (void *)(eth + 1);
    if ((void *)(vh + 1) > data_end)
        return XDP_PASS;

    /*
     * Extract the VLAN ID from the VLAN TCI field.
     * The TCI contains PCP, DEI, and VID; only the lower 12 VID bits are used
     * for the filtering decision.
     */
    vlan_id = bpf_ntohs(vh->h_vlan_TCI) & VLAN_VID_MASK;
    key = vlan_id;

    bump(&seen_counter, key);

    /*
     * Allowlist policy:
     * - VLAN 100 is allowed.
     * - Any other tagged VLAN, including VLAN 200, is dropped.
     */
    if (vlan_id == ALLOWED_VLAN) {
        bump(&pass_counter, key);
        return XDP_PASS;
    }

    bump(&drop_counter, key);
    return XDP_DROP;
}

/* Required license declaration for loading GPL-compatible eBPF programs. */
char _license[] SEC("license") = "GPL";
