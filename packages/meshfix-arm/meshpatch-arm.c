/*
 * meshpatch-arm.c - ARM 3.14.43 wlan.ko patcher for the ap-arm-* APs.
 *
 * Scans the loaded wlan text for the VLAN inner-EtherType check and turns the
 * conditional branch into an unconditional one, skipping the destructive
 * memmove(data+2, data, 16) / skb_pull(skb, 2).  Both the ZoneDirector
 * 10.5.1.x and the SmartZone 5.2.2 sequences are recognised.  The stock branch
 * word is verified before the write and exactly one signature match is
 * required.
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

/*
 * The VLAN check sequence is the same in the ZoneDirector 10.5.1.x and the
 * SmartZone 5.2.2 AP wlan.ko; only the first instruction differs because
 * struct sk_buff moved by 12 bytes between the two builds:
 *
 *   ZD 10.5.1.x:  e5943118  ldr r3, [r4, #0x118]
 *   SZ 5.2.2:     e5963124  ldr r3, [r6, #0x124]
 *
 * The ldrh/rev16/uxth/cmp/bne tail is identical, and the stock branch word is
 * 0x1a000002 in both.  Match either, but still require exactly one match in
 * total so an unknown build is left alone.
 */
#define MESH_SIG_WORDS 6
static const u32 mesh_sigs[][MESH_SIG_WORDS] = {
    { 0xe5943118, 0xe1d330bc, 0xe6bf3fb3, 0xe6ff3073, 0xe3530c81, 0x1a000002 },
    { 0xe5963124, 0xe1d330bc, 0xe6bf3fb3, 0xe6ff3073, 0xe3530c81, 0x1a000002 },
};
#define MESH_SIG_COUNT (sizeof(mesh_sigs) / sizeof(mesh_sigs[0]))

#define MESH_STOCK   0x1a000002u
#define MESH_PATCHED 0xea000002u

static int sig_matches(const u32 *p, const u32 *sig)
{
    int i;

    for (i = 0; i < MESH_SIG_WORDS; i++)
        if (p[i] != sig[i])
            return 0;
    return 1;
}

static u32 *find_site(void)
{
    u32 *p, *end, *found = 0;
    unsigned int s;
    int matches = 0;

    if (!wlan_base || wlan_size < sizeof(mesh_sigs[0]) + 4)
        return 0;
    end = (u32 *)(wlan_base + wlan_size - sizeof(mesh_sigs[0]));
    for (p = (u32 *)wlan_base; p <= end; p++) {
        for (s = 0; s < MESH_SIG_COUNT; s++) {
            if (!sig_matches(p, mesh_sigs[s]))
                continue;
            if (++matches > 1)
                return 0;
            found = p;
        }
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
