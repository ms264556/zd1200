/*
 * meshpatch-arm.c - ARM 3.14.43 wlan.ko patcher for the ap-arm-* APs.
 *
 * Scans the loaded wlan text for the VLAN inner-EtherType check and turns the
 * conditional branch into an unconditional one, skipping the destructive
 * memmove(data+2, data, 16) / skb_pull(skb, 2).  The stock branch word is
 * verified before the write and exactly one signature match is required.
 *
 * The wlan base and size are module parameters:
 *
 *   insmod meshpatch-arm.ko wlan_base=0x... wlan_size=...
 *
 * The 3.14.43 struct kernel_param and param_ops_ulong are used; the module
 * has no headers so it can be built with a bare ARM cross compiler.
 */
typedef unsigned int u32;
typedef unsigned long ulong;

struct kernel_param;
struct kernel_param_ops {
    int (*set)(const char *val, const struct kernel_param *kp);
    int (*get)(char *buffer, const struct kernel_param *kp);
    void (*free)(void *arg);
};
struct kernel_param {
    const char *name;
    const struct kernel_param_ops *ops;
    unsigned short perm;
    signed char level;
    unsigned char flags;
    union {
        void *arg;
        const void *str;
        const void *arr;
    };
};

extern const struct kernel_param_ops param_ops_ulong;
extern unsigned long kallsyms_lookup_name(const char *name);

typedef void (*clean_area_fn)(void *addr, int size);
typedef void (*flush_icache_fn)(void);

static void flush_text(void *addr, unsigned int len)
{
    static clean_area_fn clean;
    static flush_icache_fn icache;

    if (!clean)
        clean = (clean_area_fn)kallsyms_lookup_name("cpu_v7_dcache_clean_area");
    if (!icache)
        icache = (flush_icache_fn)kallsyms_lookup_name("v7_flush_icache_all");
    if (clean)
        clean(addr, (int)len);
    if (icache)
        icache();
}

static ulong wlan_base;
static ulong wlan_size;

static const struct kernel_param __param_wlan_base
    __attribute__((section("__param"), used)) = {
        .name = "wlan_base", .ops = &param_ops_ulong, .arg = &wlan_base
    };
static const struct kernel_param __param_wlan_size
    __attribute__((section("__param"), used)) = {
        .name = "wlan_size", .ops = &param_ops_ulong, .arg = &wlan_size
    };

static const u32 mesh_sig[6] = {
    0xe5943118, 0xe1d330bc, 0xe6bf3fb3, 0xe6ff3073, 0xe3530c81, 0x1a000002
};
#define MESH_STOCK   0x1a000002u
#define MESH_PATCHED 0xea000002u

static u32 *find_site(void)
{
    u32 *p, *end, *found = 0;
    int matches = 0;

    if (!wlan_base || wlan_size < sizeof(mesh_sig) + 4)
        return 0;
    end = (u32 *)(wlan_base + wlan_size - sizeof(mesh_sig));
    for (p = (u32 *)wlan_base; p <= end; p++) {
        if (p[0] != mesh_sig[0] || p[1] != mesh_sig[1] ||
            p[2] != mesh_sig[2] || p[3] != mesh_sig[3] ||
            p[4] != mesh_sig[4] || p[5] != mesh_sig[5])
            continue;
        if (++matches > 1)
            return 0;
        found = p;
    }
    return matches == 1 ? found : 0;
}

int meshpatch_init(void)
{
    u32 *p = find_site();

    if (!p)
        return -2;
    if (p[5] == MESH_PATCHED)
        return 0;
    if (p[5] != MESH_STOCK)
        return -22;
    p[5] = MESH_PATCHED;
    flush_text(&p[5], 4);
    if (p[5] != MESH_PATCHED)
        return -5;
    return 0;
}

void meshpatch_cleanup(void)
{
    u32 *p = find_site();

    if (p && p[5] == MESH_PATCHED) {
        p[5] = MESH_STOCK;
        flush_text(&p[5], 4);
    }
}
