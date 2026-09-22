#define _GNU_SOURCE
/* A disposable SHM client. Hyprland must composite these pixels; no GPU driver,
 * desktop toolkit, input handling, or network code lives in this client. */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
#include <wayland-client.h>
#include "xdg-shell-client-protocol.h"

static struct wl_compositor *compositor;
static struct wl_shm *shm;
static struct xdg_wm_base *shell;
static struct wl_surface *surface;
static uint32_t color;
static int width, height, painted;

static void die(const char *message) {
    fprintf(stderr, "color-client: %s\n", message);
    exit(1);
}

static void ping(void *data, struct xdg_wm_base *base, uint32_t serial) {
    (void)data;
    xdg_wm_base_pong(base, serial);
}
static const struct xdg_wm_base_listener shell_listener = {.ping = ping};

static void global(void *data, struct wl_registry *registry, uint32_t name,
                   const char *interface, uint32_t version) {
    (void)data;
    (void)version;
    if (!strcmp(interface, "wl_compositor"))
        compositor = wl_registry_bind(registry, name, &wl_compositor_interface, 4);
    else if (!strcmp(interface, "wl_shm"))
        shm = wl_registry_bind(registry, name, &wl_shm_interface, 1);
    else if (!strcmp(interface, "xdg_wm_base")) {
        shell = wl_registry_bind(registry, name, &xdg_wm_base_interface, 1);
        xdg_wm_base_add_listener(shell, &shell_listener, NULL);
    }
}
static void global_remove(void *data, struct wl_registry *registry, uint32_t name) {
    (void)data;
    (void)registry;
    (void)name;
}
static const struct wl_registry_listener registry_listener = {global, global_remove};

static void configure(void *data, struct xdg_surface *xdg_surface, uint32_t serial) {
    (void)data;
    xdg_surface_ack_configure(xdg_surface, serial);
    if (painted)
        return;
    if (width < 1 || width > 3840 || height < 1 || height > 2160)
        die("invalid fullscreen size");
    size_t size = (size_t)width * (size_t)height * 4;
    int fd = memfd_create("sparkwerx-test-color", MFD_CLOEXEC);
    if (fd < 0 || ftruncate(fd, (off_t)size) < 0)
        die("cannot allocate SHM buffer");
    uint32_t *pixels = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (pixels == MAP_FAILED)
        die("cannot map SHM buffer");
    for (size_t i = 0; i < size / 4; ++i)
        pixels[i] = color;
    struct wl_shm_pool *pool = wl_shm_create_pool(shm, fd, (int)size);
    struct wl_buffer *buffer = wl_shm_pool_create_buffer(
        pool, 0, width, height, width * 4, WL_SHM_FORMAT_ARGB8888);
    wl_shm_pool_destroy(pool);
    close(fd);
    wl_surface_attach(surface, buffer, 0, 0);
    wl_surface_damage_buffer(surface, 0, 0, width, height);
    wl_surface_commit(surface);
    painted = 1;
    /* Buffer and mapping deliberately live until this short-lived client exits. */
}
static const struct xdg_surface_listener surface_listener = {.configure = configure};

static void toplevel_configure(void *data, struct xdg_toplevel *toplevel,
                               int32_t w, int32_t h, struct wl_array *states) {
    (void)data;
    (void)toplevel;
    (void)states;
    if (w > 0)
        width = w;
    if (h > 0)
        height = h;
}
static void toplevel_close(void *data, struct xdg_toplevel *toplevel) {
    (void)data;
    (void)toplevel;
    exit(0);
}
static const struct xdg_toplevel_listener toplevel_listener = {
    .configure = toplevel_configure, .close = toplevel_close};

int main(int argc, char **argv) {
    if (argc != 2 || (strcmp(argv[1], "red") && strcmp(argv[1], "green")))
        die("expected red or green");
    color = !strcmp(argv[1], "red") ? 0xffff0000 : 0xff00ff00;
    struct wl_display *display = wl_display_connect(NULL);
    if (!display)
        die("cannot connect to private Wayland display");
    struct wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registry_listener, NULL);
    if (wl_display_roundtrip(display) < 0 || !compositor || !shm || !shell)
        die("required Wayland globals missing");
    surface = wl_compositor_create_surface(compositor);
    struct xdg_surface *xdg_surface = xdg_wm_base_get_xdg_surface(shell, surface);
    xdg_surface_add_listener(xdg_surface, &surface_listener, NULL);
    struct xdg_toplevel *toplevel = xdg_surface_get_toplevel(xdg_surface);
    xdg_toplevel_add_listener(toplevel, &toplevel_listener, NULL);
    xdg_toplevel_set_app_id(toplevel, "sparkwerx-capture-test");
    xdg_toplevel_set_title(toplevel, "Sparkwerx private capture test");
    xdg_toplevel_set_fullscreen(toplevel, NULL);
    wl_surface_commit(surface);
    while (wl_display_dispatch(display) >= 0) {}
    return 1;
}
