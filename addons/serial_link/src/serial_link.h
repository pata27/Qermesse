// Noeud Godot exposant le lien serie a GDScript.
//
// Volontairement MINCE. Toute la logique vit dans link_driver.cpp, qui est du
// C++ pur couvert par des tests natifs. Ce fichier ne fait que trois choses :
// tenir le thread de lecture, drainer la file SPSC dans _process, et traduire
// les trames en signaux Godot.
//
// Regle absolue (docs/01 §6.1) : le thread de lecture n'appelle AUCUNE API
// Godot. Il n'ecrit que dans les files du driver. C'est la faute qui faisait
// planter la v1 aleatoirement.
#pragma once

#include <atomic>
#include <chrono>
#include <memory>
#include <thread>

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/typed_array.hpp>

#include "link_driver.h"

namespace godot {

class SerialLink : public Node {
    GDCLASS(SerialLink, Node)

  public:
    // Miroir de sslink::FrameKind, expose a GDScript.
    enum FrameKindGD {
        FRAME_PROGRESS = 0,
        FRAME_COUNTDOWN,
        FRAME_FALSE_START,
        FRAME_RIDER_FINISH,
        FRAME_LENGTH_ACK,
        FRAME_MOCK_ACK,
        FRAME_VERSION,
        FRAME_ERROR,
        FRAME_KIOSK_START,
        FRAME_KIOSK_STOP,
        FRAME_UNKNOWN,
    };

    // Miroir de sslink::LinkState.
    enum LinkStateGD {
        STATE_DISCONNECTED = 0,
        STATE_PORT_OPEN,
        STATE_IDENTIFIED,
        STATE_LINK_LOST,
    };

    SerialLink();
    ~SerialLink() override;

    void _process(double delta) override;
    void _exit_tree() override;

    TypedArray<Dictionary> list_ports() const;
    void set_preferred_port(const String& port);
    void start_autoconnect();
    void stop();
    bool send_command(const String& cmd);
    String get_last_error() const { return last_error_; }
    String get_firmware_version() const;
    String get_current_port() const;
    int get_link_state() const;
    bool can_start_race() const;
    void set_race_active(bool active);
    Dictionary get_stats() const;

  protected:
    static void _bind_methods();

  private:
    void start_thread();
    void stop_thread();
    void thread_main();

    std::unique_ptr<sslink::LinkDriver> driver_;
    std::thread thread_;
    std::atomic<bool> thread_stop_{true};
    std::chrono::steady_clock::time_point epoch_;
    int last_state_ = -1;
    String last_error_;
};

}  // namespace godot

VARIANT_ENUM_CAST(godot::SerialLink::FrameKindGD);
VARIANT_ENUM_CAST(godot::SerialLink::LinkStateGD);
