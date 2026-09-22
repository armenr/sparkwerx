// Session-local input for the separate Sparkwerx trial package. No evdev,
// uinput, X11 fallback, subprocesses, or host permission changes.
#pragma once
#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <mutex>
#include <set>
#include <stdexcept>
#include <string>
#include <vector>
#include <sys/mman.h>
#include <unistd.h>
#include <wayland-client.h>
#include <xkbcommon/xkbcommon.h>
#include "sparkwerx-keyboard-map.hpp"
#include "virtual-keyboard-client.h"
#include "virtual-pointer-client.h"

namespace sparkwerx {
inline uint32_t clock_ms() {
    return static_cast<uint32_t>(std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now().time_since_epoch()).count());
}
inline uint32_t coordinate(double value, int extent) {
    if (!std::isfinite(value) || extent < 1 || extent > 16384)
        throw std::invalid_argument("invalid virtual pointer coordinates");
    return static_cast<uint32_t>(std::clamp(value, 0.0, static_cast<double>(extent - 1)));
}
inline int keycode(uint16_t code) {
    const auto found = inputtino::keyboard::key_mappings.find(static_cast<short>(code));
    return found == inputtino::keyboard::key_mappings.end() ? -1 : found->second.linux_code;
}

class WaylandInput {
    struct Output { wl_output *object; std::string name; };
    wl_display *display = nullptr;
    wl_registry *registry = nullptr;
    wl_seat *seat = nullptr;
    unsigned seats = 0;
    zwp_virtual_keyboard_manager_v1 *keyboard_manager = nullptr;
    zwlr_virtual_pointer_manager_v1 *pointer_manager = nullptr;
    zwp_virtual_keyboard_v1 *keyboard = nullptr;
    zwlr_virtual_pointer_v1 *pointer = nullptr;
    xkb_context *context = nullptr;
    xkb_keymap *keymap = nullptr;
    xkb_state *state = nullptr;
    std::vector<std::unique_ptr<Output>> outputs;
    std::set<uint32_t> pressed;
    std::mutex mutex;

    static void geometry(void *, wl_output *, int32_t, int32_t, int32_t, int32_t,
                         int32_t, const char *, const char *, int32_t) {}
    static void mode(void *, wl_output *, uint32_t, int32_t, int32_t, int32_t) {}
    static void done(void *, wl_output *) {}
    static void scale(void *, wl_output *, int32_t) {}
    static void name(void *data, wl_output *, const char *value) {
        static_cast<Output *>(data)->name = value;
    }
    static void description(void *, wl_output *, const char *) {}
    static constexpr wl_output_listener output_listener{geometry, mode, done, scale, name, description};
    static void capabilities(void *, wl_seat *, uint32_t) {}
    static void seat_name(void *, wl_seat *, const char *) {}
    static constexpr wl_seat_listener seat_listener{capabilities, seat_name};
    static void global(void *data, wl_registry *reg, uint32_t id, const char *iface, uint32_t version) {
        auto &self = *static_cast<WaylandInput *>(data);
        if (!std::strcmp(iface, "wl_seat")) {
            ++self.seats;
            if (!self.seat) {
                self.seat = static_cast<wl_seat *>(wl_registry_bind(reg, id, &wl_seat_interface, 1));
                wl_seat_add_listener(self.seat, &seat_listener, nullptr);
            }
        } else if (!std::strcmp(iface, "wl_output") && version >= 4) {
            auto out = std::make_unique<Output>();
            out->object = static_cast<wl_output *>(wl_registry_bind(reg, id, &wl_output_interface, 4));
            wl_output_add_listener(out->object, &output_listener, out.get());
            self.outputs.push_back(std::move(out));
        } else if (!std::strcmp(iface, "zwp_virtual_keyboard_manager_v1")) {
            self.keyboard_manager = static_cast<zwp_virtual_keyboard_manager_v1 *>(
                wl_registry_bind(reg, id, &zwp_virtual_keyboard_manager_v1_interface, 1));
        } else if (!std::strcmp(iface, "zwlr_virtual_pointer_manager_v1") && version >= 2) {
            self.pointer_manager = static_cast<zwlr_virtual_pointer_manager_v1 *>(
                wl_registry_bind(reg, id, &zwlr_virtual_pointer_manager_v1_interface, 2));
        }
    }
    static void removed(void *, wl_registry *, uint32_t) {}
    static constexpr wl_registry_listener registry_listener{global, removed};
    void flush() {
        if (wl_display_flush(display) < 0)
            throw std::runtime_error("private Wayland input connection failed or stalled");
    }
    void modifiers() {
        zwp_virtual_keyboard_v1_modifiers(keyboard,
            xkb_state_serialize_mods(state, XKB_STATE_MODS_DEPRESSED),
            xkb_state_serialize_mods(state, XKB_STATE_MODS_LATCHED),
            xkb_state_serialize_mods(state, XKB_STATE_MODS_LOCKED),
            xkb_state_serialize_layout(state, XKB_STATE_LAYOUT_EFFECTIVE));
    }
    void destroy() noexcept {
        if (pointer) zwlr_virtual_pointer_v1_destroy(pointer);
        if (keyboard) zwp_virtual_keyboard_v1_destroy(keyboard);
        if (pointer_manager) zwlr_virtual_pointer_manager_v1_destroy(pointer_manager);
        if (keyboard_manager) zwp_virtual_keyboard_manager_v1_destroy(keyboard_manager);
        for (auto &out : outputs) wl_output_destroy(out->object);
        if (seat) wl_seat_destroy(seat);
        if (registry) wl_registry_destroy(registry);
        if (display) { wl_display_flush(display); wl_display_disconnect(display); }
        if (state) xkb_state_unref(state);
        if (keymap) xkb_keymap_unref(keymap);
        if (context) xkb_context_unref(context);
    }
public:
    WaylandInput() {
        try {
            // No implicit fallback to a physical/X11 desktop or root input.
            const char *socket = std::getenv("WAYLAND_DISPLAY");
            if (geteuid() == 0 || !socket || !*socket || !std::getenv("XDG_RUNTIME_DIR"))
                throw std::runtime_error("private normal-user Wayland session required");
            display = wl_display_connect(socket);
            if (!display) throw std::runtime_error("cannot connect private Wayland input");
            registry = wl_display_get_registry(display);
            wl_registry_add_listener(registry, &registry_listener, this);
            if (wl_display_roundtrip(display) < 0 || wl_display_roundtrip(display) < 0)
                throw std::runtime_error("private Wayland registry failed");
            // The display helper disables every other output before this runs.
            if (seats != 1 || !keyboard_manager || !pointer_manager ||
                outputs.size() != 1 || outputs[0]->name != "SPARKWERX-REMOTE")
                throw std::runtime_error("input requires one seat and only SPARKWERX-REMOTE");
            context = xkb_context_new(XKB_CONTEXT_NO_ENVIRONMENT_NAMES);
            const xkb_rule_names names{"evdev", "pc105", "us", "", ""};
            if (context) keymap = xkb_keymap_new_from_names(context, &names, XKB_KEYMAP_COMPILE_NO_FLAGS);
            if (keymap) state = xkb_state_new(keymap);
            if (!state) throw std::runtime_error("cannot create trial US keymap");
            std::unique_ptr<char, decltype(&std::free)> map(
                xkb_keymap_get_as_string(keymap, XKB_KEYMAP_FORMAT_TEXT_V1), &std::free);
            if (!map) throw std::runtime_error("cannot serialize trial keymap");
            const size_t size = std::strlen(map.get()) + 1;
            int fd = memfd_create("sparkwerx-virtual-keymap", MFD_CLOEXEC);
            if (fd < 0) throw std::runtime_error("cannot allocate keymap");
            if (write(fd, map.get(), size) != static_cast<ssize_t>(size)) {
                close(fd);
                throw std::runtime_error("cannot write keymap");
            }
            keyboard = zwp_virtual_keyboard_manager_v1_create_virtual_keyboard(keyboard_manager, seat);
            zwp_virtual_keyboard_v1_keymap(keyboard, WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1, fd, size);
            close(fd);
            pointer = zwlr_virtual_pointer_manager_v1_create_virtual_pointer_with_output(
                pointer_manager, seat, outputs[0]->object);
            modifiers();
            if (wl_display_roundtrip(display) < 0)
                throw std::runtime_error("compositor rejected private virtual input");
        } catch (...) { destroy(); throw; }
    }
    ~WaylandInput() { destroy(); }
    WaylandInput(const WaylandInput &) = delete;
    WaylandInput &operator=(const WaylandInput &) = delete;
    void key(uint16_t code, bool release) {
        std::lock_guard lock(mutex);
        const int key = keycode(code);
        if (key < 0) return;
        // Ignore repeated downs. The compositor provides normal key repeat.
        if (release ? !pressed.erase(key) : !pressed.insert(key).second) return;
        zwp_virtual_keyboard_v1_key(keyboard, clock_ms(), key,
            release ? WL_KEYBOARD_KEY_STATE_RELEASED : WL_KEYBOARD_KEY_STATE_PRESSED);
        xkb_state_update_key(state, key + 8, release ? XKB_KEY_UP : XKB_KEY_DOWN);
        modifiers();
        flush();
    }
    void move(int dx, int dy) {
        std::lock_guard lock(mutex);
        zwlr_virtual_pointer_v1_motion(pointer, clock_ms(), wl_fixed_from_int(dx), wl_fixed_from_int(dy));
        zwlr_virtual_pointer_v1_frame(pointer);
        flush();
    }
    void absolute(double x, double y, int width, int height) {
        std::lock_guard lock(mutex);
        zwlr_virtual_pointer_v1_motion_absolute(pointer, clock_ms(),
            coordinate(x, width), coordinate(y, height), width, height);
        zwlr_virtual_pointer_v1_frame(pointer);
        flush();
    }
    void button(int number, bool release) {
        std::lock_guard lock(mutex);
        // Sunshine's button numbering is left=1, middle=2, right=3.
        constexpr uint32_t buttons[]{0, BTN_LEFT, BTN_MIDDLE, BTN_RIGHT, BTN_SIDE, BTN_EXTRA};
        if (number < 1 || number > 5) return;
        zwlr_virtual_pointer_v1_button(pointer, clock_ms(), buttons[number],
            release ? WL_POINTER_BUTTON_STATE_RELEASED : WL_POINTER_BUTTON_STATE_PRESSED);
        zwlr_virtual_pointer_v1_frame(pointer);
        flush();
    }
    void scroll(int distance, bool horizontal) {
        std::lock_guard lock(mutex);
        zwlr_virtual_pointer_v1_axis_source(pointer, WL_POINTER_AXIS_SOURCE_WHEEL);
        zwlr_virtual_pointer_v1_axis(pointer, clock_ms(), horizontal ?
            WL_POINTER_AXIS_HORIZONTAL_SCROLL : WL_POINTER_AXIS_VERTICAL_SCROLL,
            wl_fixed_from_double(-distance * 15.0 / 120.0));
        zwlr_virtual_pointer_v1_frame(pointer);
        flush();
    }
    void sync() {
        std::lock_guard lock(mutex);
        if (wl_display_roundtrip(display) < 0)
            throw std::runtime_error("private input synchronization failed");
    }
};
} // namespace sparkwerx
