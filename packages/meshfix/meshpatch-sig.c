/*
 * meshpatch-sig.c - signature-scanning wlan.ko patcher for ap-11n-scorpion.
 *
 * Scans the loaded wlan.ko text for the catalog signature, requires exactly
 * one match, verifies the stock branch word and writes the bnel -> b change.
 * The wlan base and size are module parameters:
 *
 *   insmod meshpatch-sig.ko wlan_base=0xc0ae0000 wlan_size=1306774
 *
 * The parameters use two __param entries matching the 2.6.32 struct
 * kernel_param layout; the module loader parses them before init_module().
 * No <linux/module.h> is used, so the stub's __this_module and .modinfo stay
 * authoritative.
 */
typedef unsigned int u32;
typedef unsigned char u8;

struct kernel_param {
    const char *name;
    unsigned short perm;
    unsigned short flags;
    int (*set)(const char *val, struct kernel_param *kp);
    int (*get)(char *buffer, struct kernel_param *kp);
    union {
        void *arg;
    } u;
};

extern int param_set_ulong(const char *val, struct kernel_param *kp);
extern int param_get_ulong(char *buffer, struct kernel_param *kp);

unsigned long wlan_base;
unsigned long wlan_size;

static const char param_name_base[] = "wlan_base";
static const char param_name_size[] = "wlan_size";

static struct kernel_param __param_wlan_base
    __attribute__((used, section("__param"), aligned(sizeof(void *)))) = {
    param_name_base, 0, 0, param_set_ulong, param_get_ulong,
    { (void *)&wlan_base }
};

static struct kernel_param __param_wlan_size
    __attribute__((used, section("__param"), aligned(sizeof(void *)))) = {
    param_name_size, 0, 0, param_set_ulong, param_get_ulong,
    { (void *)&wlan_size }
};

/* catalog rule ap_11n_scorpion_mesh_vlan_rx; ?? positions are masked out */
#define SIG_LEN 64
#define PATCH_OFF 20

static const u8 sig[SIG_LEN] = {
    0x90, 0x42, 0x00, 0x0c, 0x90, 0x63, 0x00, 0x0d,
    0x00, 0x02, 0x12, 0x00, 0x00, 0x62, 0x18, 0x25,
    0x34, 0x02, 0x81, 0x00, 0x54, 0x62, 0x00, 0x00,
    0x8e, 0xa2, 0x01, 0x08, 0x8e, 0xa5, 0x01, 0x08,
    0x3c, 0x02, 0x00, 0x00, 0x24, 0x06, 0x00, 0x10,
    0x24, 0x42, 0x00, 0x00, 0x00, 0x40, 0xf8, 0x09,
    0x24, 0xa4, 0x00, 0x02, 0x24, 0x05, 0x00, 0x02,
    0x02, 0x00, 0xf8, 0x09, 0x02, 0xa0, 0x20, 0x21,
};

static const u8 mask[SIG_LEN] = {
    1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 0, 0,
    1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 0, 0, 1, 1, 1, 1,
    1, 1, 0, 0, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1,
};

#define STOCK_WORD   0x5462000bU
#define PATCHED_WORD 0x1000000bU

static u32 *find_site(void)
{
    const u8 *b;
    u32 n, i, j;
    u32 hits = 0;
    u32 *hit = 0;

    if (!wlan_base || !wlan_size)
        return 0;

    b = (const u8 *)(unsigned long)wlan_base;
    n = (u32)wlan_size;

    for (i = 0; i + SIG_LEN <= n; i++) {
        for (j = 0; j < SIG_LEN; j++) {
            if (mask[j] && b[i + j] != sig[j])
                break;
        }
        if (j == SIG_LEN) {
            hits++;
            hit = (u32 *)(const void *)(b + i + PATCH_OFF);
        }
    }
    return hits == 1 ? hit : 0;
}

static void flush_one(u32 *p)
{
    __asm__ __volatile__("synci 0(%0)" :: "r"(p) : "memory");
}

int init_module(void)
{
    u32 *p = find_site();

    if (!p)
        return -22;
    if (*p == PATCHED_WORD)
        return 0;
    if (*p != STOCK_WORD)
        return -22;

    *p = PATCHED_WORD;
    flush_one(p);
    if (*p != PATCHED_WORD)
        return -5;
    return 0;
}

void cleanup_module(void)
{
    u32 *p = find_site();

    if (!p)
        return;
    if (*p == PATCHED_WORD) {
        *p = STOCK_WORD;
        flush_one(p);
    }
}
