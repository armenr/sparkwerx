/* A private streaming/input test screen, not a desktop shell or key logger.
 * No typed text is saved. Counters and pointer position live only in memory. */
#define main color_client_main
#include "color-client.c"
#undef main

struct frame_buffer {
    struct wl_buffer *buffer;
    uint32_t *pixels;
    int busy, bar, px, py;
};
static struct frame_buffer frames[3];
static struct wl_keyboard *keyboard;
static struct wl_pointer *pointer;
static unsigned key_count, click_count, scroll_count, frame_count;
static int pointer_x = 320, pointer_y = 320, configured, pending;
static const uint32_t background = 0xff101a29, accent = 0xff5ce6c2;
static const unsigned char letters[][7] = {
    {14,17,17,31,17,17,17}, {30,17,17,30,17,17,30}, {14,17,16,16,16,17,14},
    {30,17,17,17,17,17,30}, {31,16,16,30,16,16,31}, {31,16,16,30,16,16,16},
    {14,17,16,23,17,17,15}, {17,17,17,31,17,17,17}, {31,4,4,4,4,4,31},
    {7,2,2,2,2,18,12}, {17,18,20,24,20,18,17}, {16,16,16,16,16,16,31},
    {17,27,21,21,17,17,17}, {17,25,21,19,17,17,17}, {14,17,17,17,17,17,14},
    {30,17,17,30,16,16,16}, {14,17,17,17,21,18,13}, {30,17,17,30,20,18,17},
    {15,16,16,14,1,1,30}, {31,4,4,4,4,4,4}, {17,17,17,17,17,17,14},
    {17,17,17,17,17,10,4}, {17,17,17,21,21,21,10}, {17,17,10,4,10,17,17},
    {17,17,10,4,4,4,4}, {31,1,2,4,8,16,31},
    {14,17,19,21,25,17,14}, {4,12,4,4,4,4,14}, {14,17,1,2,4,8,31},
    {30,1,1,14,1,1,30}, {2,6,10,18,31,2,2}, {31,16,16,30,1,1,30},
    {14,16,16,30,17,17,14}, {31,1,2,4,8,8,8}, {14,17,17,14,17,17,14},
    {14,17,17,15,1,1,14}
};

static void rect(struct frame_buffer *b, int x, int y, int w, int h, uint32_t fill) {
    for (int row = y < 0 ? 0 : y; row < y + h && row < height; ++row)
        for (int col = x < 0 ? 0 : x; col < x + w && col < width; ++col)
            b->pixels[(size_t)row * width + col] = fill;
}
static void label(struct frame_buffer *b, int x, int y, const char *text) {
    for (; *text; ++text, x += 36) {
        int index = *text >= 'A' && *text <= 'Z' ? *text - 'A'
            : (*text >= '0' && *text <= '9' ? *text - '0' + 26 : -1);
        if (index < 0) continue;
        for (int row = 0; row < 7; ++row)
            for (int col = 0; col < 5; ++col)
                if (letters[index][row] & (16 >> col))
                    rect(b, x + col * 6, y + row * 6, 5, 5, accent);
    }
}
static void paint(void);
static void release_buffer(void *data, struct wl_buffer *buffer) {
    (void)buffer;
    ((struct frame_buffer *)data)->busy = 0;
    if (!pending) paint();
}
static const struct wl_buffer_listener buffer_listener = {.release = release_buffer};
static void next_frame(void *data, struct wl_callback *callback, uint32_t time) {
    (void)data; (void)time;
    wl_callback_destroy(callback);
    pending = 0;
    paint();
}
static const struct wl_callback_listener frame_listener = {.done = next_frame};
static void paint(void) {
    if (!configured || pending) return;
    struct frame_buffer *b = NULL;
    for (unsigned i = 0; i < 3; ++i)
        if (!frames[i].busy) { b = &frames[i]; break; }
    if (!b) return;
    rect(b, 48, 180, width - 96, 60, background);
    char counts[96];
    snprintf(counts, sizeof(counts), "KEYS %u   CLICKS %u   SCROLL %u", key_count, click_count, scroll_count);
    label(b, 48, 180, counts);
    rect(b, b->bar, height - 140, 100, 80, background);
    b->bar = 48 + (int)((frame_count++ * 12U) % (unsigned)(width - 196));
    rect(b, b->bar, height - 140, 100, 80, 0xffffbb55);
    rect(b, b->px - 15, b->py - 15, 31, 31, background);
    b->px = pointer_x; b->py = pointer_y;
    /* The colored cross is part of the captured video, so motion tests the
     * complete client -> Sunshine -> Wayland -> capture return path. */
    rect(b, b->px - 15, b->py - 2, 31, 5, 0xffff658c);
    rect(b, b->px - 2, b->py - 15, 5, 31, 0xffff658c);
    b->busy = pending = 1;
    struct wl_callback *callback = wl_surface_frame(surface);
    wl_callback_add_listener(callback, &frame_listener, NULL);
    wl_surface_attach(surface, b->buffer, 0, 0);
    wl_surface_damage_buffer(surface, 0, 0, width, height);
    wl_surface_commit(surface);
}
static void canvas_configure(void *d, struct xdg_surface *s, uint32_t serial) {
    (void)d;
    xdg_surface_ack_configure(s, serial);
    if (configured) return;
    if (width < 1920 || width > 3840 || height < 1080 || height > 2160)
        die("unexpected trial canvas dimensions");
    size_t size = (size_t)width * height * 4;
    for (unsigned i = 0; i < 3; ++i) {
        struct frame_buffer *b = &frames[i];
        int fd = memfd_create("sparkwerx-trial-canvas", MFD_CLOEXEC);
        if (fd < 0 || ftruncate(fd, (off_t)size) < 0) die("cannot allocate canvas");
        b->pixels = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
        if (b->pixels == MAP_FAILED) die("cannot map canvas");
        struct wl_shm_pool *pool = wl_shm_create_pool(shm, fd, (int)size);
        b->buffer = wl_shm_pool_create_buffer(pool, 0, width, height, width * 4, WL_SHM_FORMAT_ARGB8888);
        wl_shm_pool_destroy(pool); close(fd);
        wl_buffer_add_listener(b->buffer, &buffer_listener, b);
        rect(b, 0, 0, width, height, background);
        label(b, 48, 48, "SPARKWERX PRIVATE TRIAL");
        label(b, 48, 110, "MOVE CLICK TYPE SCROLL");
        label(b, 48, height - 220, "ANIMATION IS NOT AN FPS MEASUREMENT");
    }
    configured = 1;
    paint();
}
static const struct xdg_surface_listener canvas_listener = {.configure = canvas_configure};

static void keymap(void *d, struct wl_keyboard *k, uint32_t format, int fd, uint32_t size) {
    (void)d; (void)k; (void)format; (void)size;
    close(fd); /* No typed text is interpreted or logged. */
}
static void key_enter(void *d, struct wl_keyboard *k, uint32_t serial, struct wl_surface *s, struct wl_array *keys) {
    (void)d; (void)k; (void)serial; (void)s; (void)keys;
}
static void key_leave(void *d, struct wl_keyboard *k, uint32_t serial, struct wl_surface *s) {
    (void)d; (void)k; (void)serial; (void)s;
}
static void key_event(void *d, struct wl_keyboard *k, uint32_t serial, uint32_t time, uint32_t key, uint32_t state) {
    (void)d; (void)k; (void)serial; (void)time; (void)key;
    key_count += state == WL_KEYBOARD_KEY_STATE_PRESSED;
}
static void modifiers(void *d, struct wl_keyboard *k, uint32_t serial, uint32_t down, uint32_t latched, uint32_t locked, uint32_t group) {
    (void)d; (void)k; (void)serial; (void)down; (void)latched; (void)locked; (void)group;
}
static const struct wl_keyboard_listener key_listener = {
    .keymap = keymap, .enter = key_enter, .leave = key_leave, .key = key_event, .modifiers = modifiers};
static void point_motion(void *d, struct wl_pointer *p, uint32_t time, wl_fixed_t x, wl_fixed_t y) {
    (void)d; (void)p; (void)time;
    pointer_x = wl_fixed_to_int(x); pointer_y = wl_fixed_to_int(y);
}
static void point_enter(void *d, struct wl_pointer *p, uint32_t serial, struct wl_surface *s, wl_fixed_t x, wl_fixed_t y) {
    (void)s;
    point_motion(d, p, serial, x, y);
    wl_pointer_set_cursor(p, serial, NULL, 0, 0);
}
static void point_leave(void *d, struct wl_pointer *p, uint32_t serial, struct wl_surface *s) {
    (void)d; (void)p; (void)serial; (void)s;
}
static void point_button(void *d, struct wl_pointer *p, uint32_t serial, uint32_t time, uint32_t button, uint32_t state) {
    (void)d; (void)p; (void)serial; (void)time; (void)button;
    click_count += state == WL_POINTER_BUTTON_STATE_PRESSED;
}
static void point_axis(void *d, struct wl_pointer *p, uint32_t time, uint32_t axis, wl_fixed_t value) {
    (void)d; (void)p; (void)time; (void)axis; (void)value;
    ++scroll_count;
}
static const struct wl_pointer_listener point_listener = {
    .enter = point_enter, .leave = point_leave, .motion = point_motion,
    .button = point_button, .axis = point_axis};
static void capabilities(void *d, struct wl_seat *seat, uint32_t caps) {
    (void)d;
    if ((caps & WL_SEAT_CAPABILITY_KEYBOARD) && !keyboard) {
        keyboard = wl_seat_get_keyboard(seat);
        wl_keyboard_add_listener(keyboard, &key_listener, NULL);
    }
    if ((caps & WL_SEAT_CAPABILITY_POINTER) && !pointer) {
        pointer = wl_seat_get_pointer(seat);
        wl_pointer_add_listener(pointer, &point_listener, NULL);
    }
}
static const struct wl_seat_listener seat_listener = {.capabilities = capabilities};
static void canvas_global(void *d, struct wl_registry *r, uint32_t id, const char *interface, uint32_t version) {
    global(d, r, id, interface, version);
    if (!strcmp(interface, "wl_seat")) {
        struct wl_seat *seat = wl_registry_bind(r, id, &wl_seat_interface, 1);
        wl_seat_add_listener(seat, &seat_listener, NULL);
    }
}
static const struct wl_registry_listener canvas_registry = {canvas_global, global_remove};

int main(int argc, char **argv) {
    if (argc == 2 && !strcmp(argv[1], "--describe")) {
        puts("private-canvas: animation and input counters; no shell, typed-text log, or network");
        return 0;
    }
    if (argc != 1 || geteuid() == 0) die("private canvas requires a normal user");
    struct wl_display *display = wl_display_connect(NULL);
    if (!display) die("cannot connect private canvas");
    struct wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &canvas_registry, NULL);
    if (wl_display_roundtrip(display) < 0 || !compositor || !shm || !shell)
        die("canvas globals missing");
    surface = wl_compositor_create_surface(compositor);
    struct xdg_surface *xdg_surface = xdg_wm_base_get_xdg_surface(shell, surface);
    xdg_surface_add_listener(xdg_surface, &canvas_listener, NULL);
    struct xdg_toplevel *toplevel = xdg_surface_get_toplevel(xdg_surface);
    xdg_toplevel_add_listener(toplevel, &toplevel_listener, NULL);
    xdg_toplevel_set_app_id(toplevel, "sparkwerx-private-trial");
    xdg_toplevel_set_title(toplevel, "Sparkwerx private trial");
    xdg_toplevel_set_fullscreen(toplevel, NULL);
    wl_surface_commit(surface);
    while (wl_display_dispatch(display) >= 0) {}
    return 1;
}
