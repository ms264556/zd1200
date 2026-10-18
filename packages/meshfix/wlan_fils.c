/*
 * wlan_fils.c - minimal 2.6.32 module stub, no vendor wlan_fils.ko needed.
 *
 * The AP kernel has no public build tree, so the module's struct module,
 * .modinfo and vermagic are provided here in the same layout as the vendor
 * wlan_fils.ko: state/list at 0x00, name at 0x0c, init at 0xbc, exit at
 * 0x120, total 0x130 bytes.  Only name/init/exit are set; the loader fills
 * the rest at load time.
 */
typedef unsigned int u32;

struct module_stub {
    u32 state;
    u32 list_next;
    u32 list_prev;
    char name[64];
    unsigned char pad0[0xbc - 0x0c - 64];
    int (*init)(void);
    unsigned char pad1[0x120 - 0xbc - 4];
    void (*exit)(void);
    unsigned char pad2[0x130 - 0x120 - 4];
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
    "vermagic=2.6.32.24 mod_unload MIPS32_R2 32BIT ";
