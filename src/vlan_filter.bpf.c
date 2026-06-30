#include "vmlinux.h"
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_endian.h>

#define ETH_P_8021Q 0x8100
#define ETH_P_8021AD 0x88A8

#define VLAN_VID_MASK 0x0fff
#define ALLOWED_VLAN 100

#define UNTAGGED_KEY 4096
#define STATS_MAX_ENTRIES 4097

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
int xdp_vlan_filter(struct xdp_md *ctx)
{
    void *data = (void *)(long)ctx->data;
    void *data_end = (void *)(long)ctx->data_end;

    struct ethhdr *eth = data;
    struct vlan_hdr *vh;
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

    if (vlan_id == ALLOWED_VLAN) {
        bump(&pass_counter, key);
        return XDP_PASS;
    }

    bump(&drop_counter, key);
    return XDP_DROP;
}

char _license[] SEC("license") = "GPL";
