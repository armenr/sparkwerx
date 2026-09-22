// Real Unix-socket Wayland protocol fixture; no GPU, IP socket, evdev or root.
#include "wayland-input.hpp"
#include <atomic>
#include <iostream>
#include <thread>
#include <wayland-server.h>
#include "virtual-keyboard-server.h"
#include "virtual-pointer-server.h"

namespace {
void require(bool value) { if (!value) throw std::runtime_error("Wayland input fixture assertion failed"); }
struct Fixture {
    wl_display *server = wl_display_create();
    wl_resource *seat = nullptr, *output = nullptr;
    std::vector<std::pair<uint32_t, uint32_t>> keys;
    std::vector<uint32_t> depressed;
    std::vector<std::pair<uint32_t, uint32_t>> buttons;
    unsigned absolute = 0, relative = 0, frames = 0, axes = 0, keymaps = 0;
    unsigned axis_counts[2]{};
    bool exact_output = false;
    std::string output_name;
    std::atomic<bool> done{false};
    std::thread thread;
    std::string directory;

    static Fixture &self(wl_resource *r) { return *static_cast<Fixture *>(wl_resource_get_user_data(r)); }
    static void destroy(wl_client *, wl_resource *r) { wl_resource_destroy(r); }
    static void keymap(wl_client *, wl_resource *r, uint32_t format, int32_t fd, uint32_t size) {
        require(format == WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1 && size > 100 && size < 1024 * 1024);
        std::vector<char> data(size);
        require(pread(fd, data.data(), size, 0) == size && data.back() == 0);
        close(fd);
        xkb_context *context = xkb_context_new(XKB_CONTEXT_NO_ENVIRONMENT_NAMES);
        xkb_keymap *map = xkb_keymap_new_from_string(context, data.data(), XKB_KEYMAP_FORMAT_TEXT_V1,
                                                    XKB_KEYMAP_COMPILE_NO_FLAGS);
        require(map != nullptr);
        xkb_keymap_unref(map);
        xkb_context_unref(context);
        ++self(r).keymaps;
    }
    static void key(wl_client *, wl_resource *r, uint32_t, uint32_t code, uint32_t state) {
        self(r).keys.emplace_back(code, state);
    }
    static void modifiers(wl_client *, wl_resource *r, uint32_t down, uint32_t, uint32_t, uint32_t) {
        self(r).depressed.push_back(down);
    }
    static constexpr struct zwp_virtual_keyboard_v1_interface keyboard_impl{keymap, key, modifiers, destroy};
    static void new_keyboard(wl_client *c, wl_resource *r, wl_resource *seat, uint32_t id) {
        require(seat == self(r).seat);
        auto *keyboard = wl_resource_create(c, &zwp_virtual_keyboard_v1_interface, 1, id);
        wl_resource_set_implementation(keyboard, &keyboard_impl, &self(r), nullptr);
    }
    static constexpr struct zwp_virtual_keyboard_manager_v1_interface keyboard_manager_impl{new_keyboard};
    static void motion(wl_client *, wl_resource *r, uint32_t, wl_fixed_t x, wl_fixed_t y) {
        require(wl_fixed_to_int(x) == 20 && wl_fixed_to_int(y) == -10);
        ++self(r).relative;
    }
    static void abs(wl_client *, wl_resource *r, uint32_t, uint32_t x, uint32_t y, uint32_t w, uint32_t h) {
        require(x == 0 && y == 2159 && w == 3840 && h == 2160);
        ++self(r).absolute;
    }
    static void button(wl_client *, wl_resource *r, uint32_t, uint32_t code, uint32_t state) {
        self(r).buttons.emplace_back(code, state);
    }
    static void axis(wl_client *, wl_resource *r, uint32_t, uint32_t direction, wl_fixed_t value) {
        require(direction <= 1 && wl_fixed_to_double(value) == -15.0);
        ++self(r).axes;
        ++self(r).axis_counts[direction];
    }
    static void frame(wl_client *, wl_resource *r) { ++self(r).frames; }
    static void source(wl_client *, wl_resource *, uint32_t v) { require(v == WL_POINTER_AXIS_SOURCE_WHEEL); }
    static void axis_stop(wl_client *, wl_resource *, uint32_t, uint32_t) { require(false); }
    static void discrete(wl_client *, wl_resource *, uint32_t, uint32_t, wl_fixed_t, int32_t) { require(false); }
    static constexpr struct zwlr_virtual_pointer_v1_interface pointer_impl{
        motion, abs, button, axis, frame, source, axis_stop, discrete, destroy};
    static void new_pointer(wl_client *, wl_resource *, wl_resource *, uint32_t) { require(false); }
    static void new_pointer_output(wl_client *c, wl_resource *r, wl_resource *seat, wl_resource *output, uint32_t id) {
        require(seat == self(r).seat && output == self(r).output);
        self(r).exact_output = true;
        auto *pointer = wl_resource_create(c, &zwlr_virtual_pointer_v1_interface, 2, id);
        wl_resource_set_implementation(pointer, &pointer_impl, &self(r), nullptr);
    }
    static constexpr struct zwlr_virtual_pointer_manager_v1_interface pointer_manager_impl{
        new_pointer, destroy, new_pointer_output};
    static void bind_seat(wl_client *c, void *data, uint32_t version, uint32_t id) {
        auto &f = *static_cast<Fixture *>(data);
        f.seat = wl_resource_create(c, &wl_seat_interface, version, id);
        wl_resource_set_implementation(f.seat, nullptr, data, nullptr);
        wl_seat_send_capabilities(f.seat, WL_SEAT_CAPABILITY_KEYBOARD | WL_SEAT_CAPABILITY_POINTER);
    }
    static void bind_output(wl_client *c, void *data, uint32_t version, uint32_t id) {
        auto &f = *static_cast<Fixture *>(data);
        f.output = wl_resource_create(c, &wl_output_interface, version, id);
        wl_resource_set_implementation(f.output, nullptr, data, nullptr);
        wl_output_send_name(f.output, f.output_name.c_str());
        wl_output_send_done(f.output);
    }
    static void bind_keyboard(wl_client *c, void *data, uint32_t version, uint32_t id) {
        auto *resource = wl_resource_create(c, &zwp_virtual_keyboard_manager_v1_interface, version, id);
        wl_resource_set_implementation(resource, &keyboard_manager_impl, data, nullptr);
    }
    static void bind_pointer(wl_client *c, void *data, uint32_t version, uint32_t id) {
        auto *resource = wl_resource_create(c, &zwlr_virtual_pointer_manager_v1_interface, version, id);
        wl_resource_set_implementation(resource, &pointer_manager_impl, data, nullptr);
    }
    Fixture(std::string name = "SPARKWERX-REMOTE", bool pointer_protocol = true, bool second_seat = false)
        : output_name(std::move(name)) {
        char pattern[] = "/tmp/sparkwerx-input.XXXXXX";
        char *path = mkdtemp(pattern);
        require(path != nullptr && server != nullptr);
        directory = path;
        setenv("XDG_RUNTIME_DIR", path, 1);
        setenv("WAYLAND_DISPLAY", "sparkwerx-test", 1);
        require(wl_display_add_socket(server, "sparkwerx-test") == 0);
        wl_global_create(server, &wl_seat_interface, 1, this, bind_seat);
        if (second_seat) wl_global_create(server, &wl_seat_interface, 1, this, bind_seat);
        wl_global_create(server, &wl_output_interface, 4, this, bind_output);
        wl_global_create(server, &zwp_virtual_keyboard_manager_v1_interface, 1, this, bind_keyboard);
        if (pointer_protocol)
            wl_global_create(server, &zwlr_virtual_pointer_manager_v1_interface, 2, this, bind_pointer);
        thread = std::thread([this] {
            while (!done) {
                wl_event_loop_dispatch(wl_display_get_event_loop(server), 10);
                wl_display_flush_clients(server);
            }
        });
    }
    void finish() { done = true; if (thread.joinable()) thread.join(); }
    ~Fixture() {
        finish();
        wl_display_destroy_clients(server);
        wl_display_destroy(server);
        rmdir(directory.c_str());
    }
};

void exercise(sparkwerx::WaylandInput &input) {
    input.key(0x41, false); input.key(0x41, true);
    input.key(0xA0, false);
    input.key(0x41, false); input.key(0x41, false); input.key(0x41, true);
    input.key(0xA0, true); input.key(0xA0, true);
    input.key(0xFFFF, false);
    input.absolute(-100, 99999, 3840, 2160);
    input.move(20, -10);
    input.button(1, false); input.button(1, true);
    input.button(3, false); input.button(3, true);
    input.scroll(120, false); input.scroll(120, true);
    input.sync();
}
}
int main(int argc, char **argv) {
    alarm(15);
    try {
        require(argc == 2);
        if (std::strcmp(argv[1], "--exercise") == 0) {
            const char *runtime = std::getenv("XDG_RUNTIME_DIR");
            require(runtime && std::strcmp(runtime, "/run/sw/user/r") == 0);
            sparkwerx::WaylandInput input;
            // Let the receiving client bind the newly announced seat devices.
            std::this_thread::sleep_for(std::chrono::milliseconds(500));
            exercise(input);
            // Keep devices alive until the recipient has consumed the events.
            std::this_thread::sleep_for(std::chrono::milliseconds(500));
            std::cout << "PASS|wayland_input_exercise|private protocol events submitted\n";
            return 0;
        }
        require(std::strcmp(argv[1], "--self-test") == 0);
        require(sparkwerx::keycode(0x41) == KEY_A && sparkwerx::keycode(0xA0) == KEY_LEFTSHIFT);
        require(sparkwerx::keycode(0xFFFF) == -1);
        for (double value : {NAN, INFINITY}) {
            bool rejected = false;
            try { sparkwerx::coordinate(value, 100); } catch (const std::invalid_argument &) { rejected = true; }
            require(rejected);
        }
        for (int variant = 0; variant < 3; ++variant) {
            Fixture invalid(variant == 0 ? "WRONG-OUTPUT" : "SPARKWERX-REMOTE", variant != 1, variant == 2);
            bool rejected = false;
            try { sparkwerx::WaylandInput input; } catch (const std::runtime_error &) { rejected = true; }
            require(rejected);
        }
        Fixture fixture;
        { sparkwerx::WaylandInput input; exercise(input); }
        fixture.finish();
        const std::vector<std::pair<uint32_t, uint32_t>> expected_keys{
            {KEY_A, 1}, {KEY_A, 0}, {KEY_LEFTSHIFT, 1}, {KEY_A, 1}, {KEY_A, 0}, {KEY_LEFTSHIFT, 0}};
        const std::vector<std::pair<uint32_t, uint32_t>> expected_buttons{
            {BTN_LEFT, 1}, {BTN_LEFT, 0}, {BTN_RIGHT, 1}, {BTN_RIGHT, 0}};
        require(fixture.keys == expected_keys && fixture.buttons == expected_buttons);
        require(fixture.depressed == std::vector<uint32_t>({0, 0, 0, 1, 1, 1, 0}));
        require(fixture.keymaps == 1 && fixture.exact_output && fixture.absolute == 1 &&
                fixture.relative == 1 && fixture.axes == 2 && fixture.frames == 8);
        require(fixture.axis_counts[0] == 1 && fixture.axis_counts[1] == 1);
        std::cout << "PASS|wayland_input|wrong-output/missing-protocol/multiple-seat refusal, keymap, keys, modifiers, pointer, buttons, scroll and teardown\n";
    } catch (const std::exception &e) {
        std::cerr << e.what() << '\n';
        return 1;
    }
}
