/* Extend the unchanged disposable color client solely for synthetic input
 * receipt. This is not a key logger: only aggregate counts are emitted. */
#define main color_client_main
#include "color-client.c"
#undef main
#include <xkbcommon/xkbcommon.h>

static struct wl_seat *input_seat;
static struct wl_keyboard *keyboard;
static struct wl_pointer *pointer;
static struct xkb_context *context;
static struct xkb_keymap *keymap;
static struct xkb_state *key_state;
static unsigned keys, lower, upper, buttons, axes, motions;
static unsigned axis_counts[2];

static void received(void) {
    if (keys == 6 && lower == 1 && upper == 1 && buttons == 4 && axes == 2 && motions > 0
        && axis_counts[0] == 1 && axis_counts[1] == 1) {
        puts("PASS|private_input_receipt|keys=6;lower=1;upper=1;buttons=4;axes=2;motion=yes");
        fflush(stdout);
        exit(0);
    }
}
static void keyboard_map(void *d, struct wl_keyboard *kb, uint32_t format, int fd, uint32_t size) {
    (void)d; (void)kb;
    if (format != WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1 || size > 1024 * 1024 || !size)
        die("unexpected input keymap");
    char *map = mmap(NULL, size, PROT_READ, MAP_PRIVATE, fd, 0);
    close(fd);
    if (map == MAP_FAILED || map[size - 1] != 0) die("invalid input keymap data");
    if (key_state) xkb_state_unref(key_state);
    if (keymap) xkb_keymap_unref(keymap);
    keymap = xkb_keymap_new_from_string(context, map, XKB_KEYMAP_FORMAT_TEXT_V1, XKB_KEYMAP_COMPILE_NO_FLAGS);
    munmap(map, size);
    if (!keymap) die("cannot parse input keymap");
    key_state = xkb_state_new(keymap);
    if (!key_state) die("cannot create input state");
}
static void keyboard_enter(void *d, struct wl_keyboard *kb, uint32_t serial, struct wl_surface *s, struct wl_array *pressed) {
    (void)d; (void)kb; (void)serial; (void)s; (void)pressed;
}
static void keyboard_leave(void *d, struct wl_keyboard *kb, uint32_t serial, struct wl_surface *s) {
    (void)d; (void)kb; (void)serial; (void)s;
}
static void keyboard_key(void *d, struct wl_keyboard *kb, uint32_t serial, uint32_t time, uint32_t key, uint32_t state) {
    (void)d; (void)kb; (void)serial; (void)time;
    if (!key_state) die("input event before keymap");
    ++keys;
    if (state == WL_KEYBOARD_KEY_STATE_PRESSED) {
        xkb_keysym_t symbol = xkb_state_key_get_one_sym(key_state, key + 8);
        lower += symbol == XKB_KEY_a;
        upper += symbol == XKB_KEY_A;
    }
    received();
}
static void keyboard_modifiers(void *d, struct wl_keyboard *kb, uint32_t serial, uint32_t down, uint32_t latched, uint32_t locked, uint32_t group) {
    (void)d; (void)kb; (void)serial;
    if (key_state) xkb_state_update_mask(key_state, down, latched, locked, 0, 0, group);
}
static void repeat(void *d, struct wl_keyboard *kb, int32_t rate, int32_t delay) {
    (void)d; (void)kb; (void)rate; (void)delay;
}
static const struct wl_keyboard_listener keyboard_listener = {
    keyboard_map, keyboard_enter, keyboard_leave, keyboard_key, keyboard_modifiers, repeat};
static void pointer_enter(void *d, struct wl_pointer *p, uint32_t serial, struct wl_surface *s, wl_fixed_t x, wl_fixed_t y) {
    (void)d; (void)p; (void)serial; (void)s; (void)x; (void)y;
    ++motions;
}
static void pointer_leave(void *d, struct wl_pointer *p, uint32_t serial, struct wl_surface *s) {
    (void)d; (void)p; (void)serial; (void)s;
}
static void pointer_motion(void *d, struct wl_pointer *p, uint32_t time, wl_fixed_t x, wl_fixed_t y) {
    (void)d; (void)p; (void)time; (void)x; (void)y;
    ++motions;
}
static void pointer_button(void *d, struct wl_pointer *p, uint32_t serial, uint32_t time, uint32_t button, uint32_t state) {
    (void)d; (void)p; (void)serial; (void)time; (void)button; (void)state;
    ++buttons;
    received();
}
static void pointer_axis(void *d, struct wl_pointer *p, uint32_t time, uint32_t axis, wl_fixed_t value) {
    (void)d; (void)p; (void)time; (void)value;
    if (axis > 1) die("unexpected scroll axis");
    ++axes;
    ++axis_counts[axis];
    received();
}
static const struct wl_pointer_listener pointer_listener = {
    .enter = pointer_enter, .leave = pointer_leave, .motion = pointer_motion,
    .button = pointer_button, .axis = pointer_axis};
static void seat_capabilities(void *data, struct wl_seat *seat, uint32_t caps) {
    (void)data;
    if ((caps & WL_SEAT_CAPABILITY_KEYBOARD) && !keyboard) {
        keyboard = wl_seat_get_keyboard(seat);
        wl_keyboard_add_listener(keyboard, &keyboard_listener, NULL);
    }
    if ((caps & WL_SEAT_CAPABILITY_POINTER) && !pointer) {
        pointer = wl_seat_get_pointer(seat);
        wl_pointer_add_listener(pointer, &pointer_listener, NULL);
    }
}
static const struct wl_seat_listener seat_listener = {.capabilities = seat_capabilities};
static void input_global(void *data, struct wl_registry *registry, uint32_t id, const char *interface, uint32_t version) {
    global(data, registry, id, interface, version);
    if (!strcmp(interface, "wl_seat")) {
        if (input_seat) die("multiple input seats");
        input_seat = wl_registry_bind(registry, id, &wl_seat_interface, 1);
        wl_seat_add_listener(input_seat, &seat_listener, NULL);
    }
}
static const struct wl_registry_listener input_registry = {input_global, global_remove};
int main(void) {
    alarm(15);
    if (geteuid() == 0) die("normal user required");
    context = xkb_context_new(XKB_CONTEXT_NO_ENVIRONMENT_NAMES);
    if (!context) die("cannot create XKB context");
    color = 0xff143d59;
    struct wl_display *display = wl_display_connect(NULL);
    if (!display) die("cannot connect private input receiver");
    struct wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &input_registry, NULL);
    if (wl_display_roundtrip(display) < 0 || !compositor || !shm || !shell || !input_seat)
        die("input receiver globals missing");
    surface = wl_compositor_create_surface(compositor);
    struct xdg_surface *xdg_surface = xdg_wm_base_get_xdg_surface(shell, surface);
    xdg_surface_add_listener(xdg_surface, &surface_listener, NULL);
    struct xdg_toplevel *toplevel = xdg_surface_get_toplevel(xdg_surface);
    xdg_toplevel_add_listener(toplevel, &toplevel_listener, NULL);
    xdg_toplevel_set_app_id(toplevel, "sparkwerx-input-test");
    xdg_toplevel_set_title(toplevel, "Sparkwerx private input test");
    xdg_toplevel_set_fullscreen(toplevel, NULL);
    wl_surface_commit(surface);
    int ready = 0;
    while (wl_display_dispatch(display) >= 0) {
        if (painted && !ready) { puts("READY"); fflush(stdout); ready = 1; }
    }
    return 1;
}
