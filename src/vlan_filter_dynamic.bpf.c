#include "vmlinux.h"
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_endian.h>

/* VLAN EtherTypes handled by the parser. */
#define ETH_P_8021Q 0x8100
#define ETH_P_8021AD 0x88A8

/* The VLAN identifier is stored in the lower 12 bits of the VLAN TCI field. */
#define VLAN_VID_MASK 0x0fff

/* Dynamic policy values stored in vlan_policy. */
#define VLAN_POLICY_DROP 0
#define VLAN_POLICY_PASS 1
#define VLAN_POLICY_MAX_ENTRIES 4096

/* Key 4096 is reserved for untagged frames because valid VLAN IDs are 0..4095. */
#define UNTAGGED_KEY 4096
#define STATS_MAX_ENTRIES 4097

/*
 * Runtime VLAN policy map.
 *
 * Key:   VLAN ID in the range 0..4095.
 * Value: 0 = drop, 1 = pass. Missing keys pass by default.
 */
struct {
    __uint(type, BPF_MAP_TYPE_HASH);
    __uint(max_entries, VLAN_POLICY_MAX_ENTRIES);
    __type(key, __u32);
    __type(value, __u32);
} vlan_policy SEC(".maps");

/* Per-CPU packet counters for classified traffic. */
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

static __always_inline void bump(void *map, __u32 key)
{
    __u64 *value;

    value = bpf_map_lookup_elem(map, &key);
    if (value)
        *value += 1;
}

SEC("xdp")
int xdp_vlan_filter_dynamic(struct xdp_md *ctx)
{
    void *data = (void *)(long)ctx->data;
    void *data_end = (void *)(long)ctx->data_end;

    struct ethhdr *eth = data;
    struct vlan_hdr *vh;
    __u32 *policy;
    __u16 h_proto;
    __u16 vlan_id;
    __u32 key;

    if ((void *)(eth + 1) > data_end)
        return XDP_PASS;

    h_proto = bpf_ntohs(eth->h_proto);

    if (h_proto != ETH_P_8021Q && h_proto != ETH_P_8021AD) {
        key = UNTAGGED_KEY;
        bump(&seen_counter, key);
        bump(&pass_counter, key);
        return XDP_PASS;
    }

    vh = (void *)(eth + 1);
    if ((void *)(vh + 1) > data_end)
        return XDP_PASS;

    vlan_id = bpf_ntohs(vh->h_vlan_TCI) & VLAN_VID_MASK;
    key = vlan_id;

    bump(&seen_counter, key);

    policy = bpf_map_lookup_elem(&vlan_policy, &key);
    if (!policy || *policy == VLAN_POLICY_PASS) {
        bump(&pass_counter, key);
        return XDP_PASS;
    }

    /* Explicit drop, or fail closed for any invalid explicit policy value. */
    bump(&drop_counter, key);
    return XDP_DROP;
}

char _license[] SEC("license") = "GPL";
