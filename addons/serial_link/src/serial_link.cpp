#include "serial_link.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

SerialLink::SerialLink() {
    driver_ = std::make_unique<sslink::LinkDriver>(
        sslink::make_serial_port(), [] { return sslink::enumerate_ports(); });
    epoch_ = std::chrono::steady_clock::now();
}

SerialLink::~SerialLink() { stop_thread(); }

void SerialLink::_bind_methods() {
    ClassDB::bind_method(D_METHOD("list_ports"), &SerialLink::list_ports);
    ClassDB::bind_method(D_METHOD("set_preferred_port", "port"), &SerialLink::set_preferred_port);
    ClassDB::bind_method(D_METHOD("start_autoconnect"), &SerialLink::start_autoconnect);
    ClassDB::bind_method(D_METHOD("stop"), &SerialLink::stop);
    ClassDB::bind_method(D_METHOD("send_command", "cmd"), &SerialLink::send_command);
    ClassDB::bind_method(D_METHOD("get_last_error"), &SerialLink::get_last_error);
    ClassDB::bind_method(D_METHOD("get_firmware_version"), &SerialLink::get_firmware_version);
    ClassDB::bind_method(D_METHOD("get_current_port"), &SerialLink::get_current_port);
    ClassDB::bind_method(D_METHOD("get_link_state"), &SerialLink::get_link_state);
    ClassDB::bind_method(D_METHOD("can_start_race"), &SerialLink::can_start_race);
    ClassDB::bind_method(D_METHOD("set_race_active", "active"), &SerialLink::set_race_active);
    ClassDB::bind_method(D_METHOD("get_stats"), &SerialLink::get_stats);

    ADD_SIGNAL(MethodInfo("frame_received", PropertyInfo(Variant::INT, "kind"),
                          PropertyInfo(Variant::DICTIONARY, "payload")));
    ADD_SIGNAL(MethodInfo("state_changed", PropertyInfo(Variant::INT, "state")));

    BIND_ENUM_CONSTANT(FRAME_PROGRESS);
    BIND_ENUM_CONSTANT(FRAME_COUNTDOWN);
    BIND_ENUM_CONSTANT(FRAME_FALSE_START);
    BIND_ENUM_CONSTANT(FRAME_RIDER_FINISH);
    BIND_ENUM_CONSTANT(FRAME_LENGTH_ACK);
    BIND_ENUM_CONSTANT(FRAME_MOCK_ACK);
    BIND_ENUM_CONSTANT(FRAME_VERSION);
    BIND_ENUM_CONSTANT(FRAME_ERROR);
    BIND_ENUM_CONSTANT(FRAME_KIOSK_START);
    BIND_ENUM_CONSTANT(FRAME_KIOSK_STOP);
    BIND_ENUM_CONSTANT(FRAME_UNKNOWN);

    BIND_ENUM_CONSTANT(STATE_DISCONNECTED);
    BIND_ENUM_CONSTANT(STATE_PORT_OPEN);
    BIND_ENUM_CONSTANT(STATE_IDENTIFIED);
    BIND_ENUM_CONSTANT(STATE_LINK_LOST);
}

void SerialLink::start_thread() {
    if (!thread_stop_.load()) {
        return;
    }
    thread_stop_.store(false);
    thread_ = std::thread([this] { thread_main(); });
}

void SerialLink::stop_thread() {
    if (thread_stop_.exchange(true)) {
        return;
    }
    if (thread_.joinable()) {
        thread_.join();
    }
}

void SerialLink::thread_main() {
    // AUCUN appel a l'API Godot dans cette fonction. Elle ne touche que le
    // driver, qui n'ecrit que dans ses propres files sans verrou.
    while (!thread_stop_.load(std::memory_order_acquire)) {
        const auto now = std::chrono::steady_clock::now();
        const auto ms =
            std::chrono::duration_cast<std::chrono::milliseconds>(now - epoch_).count();
        driver_->tick(static_cast<std::uint32_t>(ms));
        std::this_thread::sleep_for(std::chrono::microseconds(500));
    }
}

void SerialLink::start_autoconnect() {
    driver_->start();
    start_thread();
}

void SerialLink::stop() {
    driver_->stop();
    stop_thread();
}

void SerialLink::_exit_tree() { stop_thread(); }

void SerialLink::set_preferred_port(const String& port) {
    driver_->set_preferred_port(std::string(port.utf8().get_data()));
}

void SerialLink::set_race_active(bool active) { driver_->set_race_active(active); }

bool SerialLink::send_command(const String& cmd) {
    std::string err;
    const bool ok = driver_->queue_command(std::string(cmd.utf8().get_data()), err);
    if (!ok) {
        last_error_ = String::utf8(err.c_str());
        // Une commande refusee est une erreur de programmation cote GDScript,
        // pas un incident materiel : elle doit etre bruyante.
        UtilityFunctions::push_error("SerialLink: commande refusee — " + last_error_);
    }
    return ok;
}

String SerialLink::get_firmware_version() const {
    return String::utf8(driver_->firmware_version().c_str());
}

String SerialLink::get_current_port() const { return String::utf8(driver_->current_port().c_str()); }

int SerialLink::get_link_state() const { return static_cast<int>(driver_->state()); }

bool SerialLink::can_start_race() const { return driver_->can_start_race(); }

TypedArray<Dictionary> SerialLink::list_ports() const {
    TypedArray<Dictionary> out;
    const std::vector<sslink::PortInfo> ports = sslink::enumerate_ports();
    const std::vector<sslink::Candidate> ranked =
        sslink::rank_candidates(ports, driver_->current_port(), {});

    for (const sslink::PortInfo& p : ports) {
        Dictionary d;
        d["port"] = String::utf8(p.path.c_str());
        d["description"] = String::utf8(p.description.c_str());
        d["vid"] = p.has_ids ? int(p.vid) : -1;
        d["pid"] = p.has_ids ? int(p.pid) : -1;
        d["known_device"] = p.has_ids && sslink::is_known_usb_id(p.vid, p.pid);
        // Le panneau materiel doit pouvoir dire POURQUOI un port est retenu,
        // ou pourquoi il ne l'est pas : c'est la moitie du depannage terrain.
        d["candidate"] = false;
        d["reason"] = String::utf8("aucun critere, ce port ne sera pas essaye");
        for (const sslink::Candidate& c : ranked) {
            if (c.info.path == p.path) {
                d["candidate"] = true;
                d["reason"] = String::utf8(sslink::selection_reason_name(c.reason));
                break;
            }
        }
        out.push_back(d);
    }
    return out;
}

Dictionary SerialLink::get_stats() const {
    const sslink::LinkStats s = driver_->stats();
    Dictionary d;
    d["frames_total"] = int64_t(s.frames_total);
    d["frames_progress"] = int64_t(s.frames_progress);
    d["frames_unknown"] = int64_t(s.frames_unknown);
    d["frames_dropped"] = int64_t(s.frames_dropped);
    d["lines_overlong"] = int64_t(s.lines_overlong);
    d["connects"] = int64_t(s.connects);
    d["handshake_failures"] = int64_t(s.handshake_failures);
    d["watchdog_trips"] = int64_t(s.watchdog_trips);
    d["races_interrupted"] = int64_t(s.races_interrupted);
    return d;
}

void SerialLink::_process(double /*delta*/) {
    // Drainage de la file SPSC : c'est ICI, sur le thread principal, que les
    // trames deviennent des signaux Godot.
    const int state = get_link_state();
    if (state != last_state_) {
        last_state_ = state;
        emit_signal("state_changed", state);
    }

    sslink::Frame f;
    int budget = 512;  // borne le travail par image, meme apres un gel
    while (budget-- > 0 && driver_->frames().pop(f)) {
        Dictionary payload;
        switch (f.kind) {
            case sslink::FrameKind::Progress: {
                PackedInt64Array ticks;
                ticks.resize(4);
                for (int i = 0; i < 4; ++i) {
                    ticks[i] = int64_t(f.ticks[size_t(i)]);
                }
                payload["ticks"] = ticks;
                payload["elapsed_ms"] = int64_t(f.elapsed_ms);
                break;
            }
            case sslink::FrameKind::Countdown:
                payload["value"] = f.value;
                break;
            case sslink::FrameKind::FalseStart:
                payload["rider"] = f.value;
                break;
            case sslink::FrameKind::RiderFinish:
                payload["rider"] = f.value;
                payload["elapsed_ms"] = int64_t(f.finish_ms);
                break;
            case sslink::FrameKind::LengthAck:
                payload["ticks"] = int64_t(f.length_ticks);
                break;
            case sslink::FrameKind::MockAck:
                payload["on"] = f.mock_on;
                break;
            case sslink::FrameKind::Version:
            case sslink::FrameKind::Error:
            case sslink::FrameKind::Unknown:
                payload["text"] = String::utf8(f.text.data());
                payload["truncated"] = f.text_truncated;
                break;
            default:
                break;
        }
        emit_signal("frame_received", int(f.kind), payload);
    }
}
