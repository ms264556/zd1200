/*
 * wlan_fils.c - minimal 3.14.43 ARM module stub, no vendor wlan_fils.ko needed.
 *
 * The AP kernel has no public build tree, so the module's struct module,
 * .modinfo and vermagic are provided here in the same layout as the vendor
 * wlan_fils.ko: state/list at 0x00, name at 0x0c, init at 0xc0, exit at
 * 0x134, total 0x13c bytes.  Only name/init/exit are set; the loader fills
 * the rest at load time.
 */
typedef unsigned int u32;

struct module_stub {
    u32 state;
    u32 list_next;
    u32 list_prev;
    char name[64];
    unsigned char pad0[0xc0 - 0x0c - 64];
    int (*init)(void);
    unsigned char pad1[0x134 - 0xc0 - 4];
    void (*exit)(void);
    unsigned char pad2[0x13c - 0x134 - 4];
} __attribute__((packed));

extern int meshpatch_init(void);
extern void meshpatch_cleanup(void);

struct module_stub __this_module
    __attribute__((section(".gnu.linkonce.this_module"), used)) = {
    .name = "meshpatch",
    .init = meshpatch_init,
    .exit = meshpatch_cleanup,
};

static const char mod_license[] __attribute__((section(".modinfo"), used)) =
    "license=GPL";
static const char mod_depends[] __attribute__((section(".modinfo"), used)) =
    "depends=wlan";
static const char mod_vermagic[] __attribute__((section(".modinfo"), used)) =
    "vermagic=3.14.43 SMP mod_unload ARMv7 p2v8 ";
