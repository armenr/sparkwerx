// Replaces only Sunshine's Linux platform input implementation in the separate
// trial output. Capture/encoding/transport/authentication remain upstream code.
#include "wayland-input.hpp"
#include "src/platform/common.h"
#include "src/logging.h"

namespace platf {
namespace {
sparkwerx::WaylandInput &backend(input_t &input) {
    return *static_cast<sparkwerx::WaylandInput *>(input.get());
}
// A lost/stalled private input socket is a failed trial, never a fallback to
// kernel input devices. The surrounding service owns cleanup of the session.
template<class F> void deliver(F &&fn) {
    try { fn(); }
    catch (const std::exception &) {
        BOOST_LOG(fatal) << "Sparkwerx private Wayland input failed";
        std::_Exit(70);
    }
}
}
input_t input() {
    auto result = input_t{new sparkwerx::WaylandInput()};
    BOOST_LOG(info) << "Sparkwerx session-local Wayland keyboard/pointer ready";
    return result;
}
void freeInput(void *p) { delete static_cast<sparkwerx::WaylandInput *>(p); }
void move_mouse(input_t &p, int x, int y) { deliver([&] { backend(p).move(x, y); }); }
void abs_mouse(input_t &p, const touch_port_t &port, float x, float y) {
    deliver([&] { backend(p).absolute(x, y, port.width, port.height); });
}
void button_mouse(input_t &p, int button, bool release) {
    deliver([&] { backend(p).button(button, release); });
}
void scroll(input_t &p, int distance) { deliver([&] { backend(p).scroll(distance, false); }); }
void hscroll(input_t &p, int distance) { deliver([&] { backend(p).scroll(distance, true); }); }
void keyboard_update(input_t &p, uint16_t code, bool release, uint8_t) {
    deliver([&] { backend(p).key(code, release); });
}
util::point_t get_mouse_loc(input_t &) { return {0, 0}; }
std::unique_ptr<client_input_t> allocate_client_input_context(input_t &) {
    return std::make_unique<client_input_t>();
}
// Deliberate trial limits: no clipboard text injection, touch, pen or gamepads.
void unicode(input_t &, char *, int) {
    BOOST_LOG(warning) << "Clipboard text injection is not enabled in the Sparkwerx trial";
}
platform_caps::caps_t get_capabilities() { return 0; }
std::vector<supported_gamepad_t> &supported_gamepads(input_t *) {
    // Upstream config initialization reads front() even for --version. Keep a
    // disabled descriptor so that query is valid; no controller can be opened.
    static std::vector<supported_gamepad_t> disabled{
        {"disabled", false, "Gamepads are not enabled in the Sparkwerx trial"}
    };
    return disabled;
}
int alloc_gamepad(input_t &, const gamepad_id_t &, const gamepad_arrival_t &, feedback_queue_t) { return -1; }
void free_gamepad(input_t &, int) {}
void gamepad_update(input_t &, int, const gamepad_state_t &) {}
void gamepad_touch(input_t &, const gamepad_touch_t &) {}
void gamepad_motion(input_t &, const gamepad_motion_t &) {}
void gamepad_battery(input_t &, const gamepad_battery_t &) {}
void touch_update(client_input_t *, const touch_port_t &, const touch_input_t &) {}
void pen_update(client_input_t *, const touch_port_t &, const pen_input_t &) {}
} // namespace platf
