#include "link_driver.h"

#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>

namespace sslink {
namespace {

// Arithmetique de l'ATmega328P : `int` = 16 bits signes. Reproduite ici parce
// que la validation des commandes en depend directement (docs/01 §2 et §5.5).
std::int16_t avr_mul_1000(std::int32_t secs) {
    const std::uint16_t wrapped =
        static_cast<std::uint16_t>(static_cast<std::uint32_t>(secs) * 1000u);
    return static_cast<std::int16_t>(wrapped);
}

bool all_digits(const std::string& s, std::size_t from) {
    if (from >= s.size()) {
        return false;
    }
    for (std::size_t i = from; i < s.size(); ++i) {
        if (s[i] < '0' || s[i] > '9') {
            return false;
        }
    }
    return true;
}

CommandCheck fail(const std::string& msg) { return CommandCheck{false, msg}; }

}  // namespace

const char* link_state_name(LinkState s) {
    switch (s) {
        case LinkState::Disconnected: return "DISCONNECTED";
        case LinkState::PortOpen: return "PORT_OPEN";
        case LinkState::Identified: return "IDENTIFIED";
        case LinkState::LinkLost: return "LINK_LOST";
    }
    return "DISCONNECTED";
}

const char* time_command() { return "t60"; }

CommandCheck validate_command(const std::string& cmd) {
    if (cmd.empty()) {
        return fail("commande vide");
    }
    const char head = cmd[0];

    // Commandes sans argument.
    if (cmd.size() == 1) {
        switch (head) {
            case 'v':
            case 's':
            case 'g':
            case 'd':
            case 'x':
                return CommandCheck{true, ""};
            case 'm':
                // docs/01 §2 : le mock firmware n'est pas utilise en v3, notre
                // simulateur est cote PC. On l'autorise pour le diagnostic.
                return CommandCheck{true, ""};
            default:
                return fail(std::string("commande inconnue : '") + head +
                            "' — liste exhaustive en docs/01 §2");
        }
    }

    if (head != 'l' && head != 't') {
        return fail("seules 'l' et 't' prennent un argument (docs/01 §2)");
    }

    const std::size_t digits = cmd.size() - 1;
    if (!all_digits(cmd, 1)) {
        return fail("argument non numerique : " + cmd);
    }
    // Contrainte 1 : charBuff[8] sans garde de depassement.
    if (digits > 7) {
        return fail("argument de " + std::to_string(digits) +
                    " chiffres : le tampon firmware en accepte 7 au plus "
                    "(charBuff[8], docs/01 §2)");
    }
    // Contrainte 2 : atoi remplit un int 16 bits.
    const long value = std::strtol(cmd.c_str() + 1, nullptr, 10);
    if (value < 1 || value > 32767) {
        return fail("valeur " + std::to_string(value) +
                    " hors plage 1..32767 : atoi remplit un int 16 bits "
                    "(docs/01 §2)");
    }

    if (head == 't') {
        // Contrainte 3, propre a v3 : une duree dont le produit par 1000 ne
        // deborde PAS en negatif fait terminer le firmware, ce qui COUPE le
        // flux R: en pleine course. t600 arreterait tout a 10,2 s.
        if (avr_mul_1000(static_cast<std::int32_t>(value)) >= 0) {
            return fail(
                "t" + std::to_string(value) +
                " ferait terminer le firmware a " +
                std::to_string(static_cast<int>(avr_mul_1000(static_cast<std::int32_t>(value)))) +
                " ms et couperait le flux R: — utiliser " + time_command() +
                " (docs/01 §5.5)");
        }
    }
    return CommandCheck{true, ""};
}

std::string make_length_command(double metres, double roller_mm) {
    if (!(roller_mm > 0.0) || !(metres > 0.0)) {
        return std::string();
    }
    const double circumference_mm = roller_mm * 3.14159265358979323846;
    const long ticks = static_cast<long>(std::floor(metres * 1000.0 / circumference_mm));
    if (ticks < 1 || ticks > 32767) {
        return std::string();
    }
    const std::string cmd = "l" + std::to_string(ticks);
    return validate_command(cmd).ok ? cmd : std::string();
}

// ---------------------------------------------------------------------------

LinkDriver::LinkDriver(std::unique_ptr<SerialPort> port, Enumerator enumerator, LinkConfig cfg)
    : port_(std::move(port)), enumerate_(std::move(enumerator)), cfg_(cfg) {}

void LinkDriver::set_preferred_port(const std::string& path) {
    preferred_path_.set(path.c_str());
}

void LinkDriver::start() { running_.store(true, std::memory_order_release); }

void LinkDriver::stop() {
    running_.store(false, std::memory_order_release);
}

void LinkDriver::set_race_active(bool active) {
    race_active_.store(active, std::memory_order_release);
}

std::string LinkDriver::firmware_version() const { return version_.get(); }
std::string LinkDriver::current_port() const { return published_path_.get(); }

LinkStats LinkDriver::stats() const {
    LinkStats s;
    s.frames_total = st_frames_.load(std::memory_order_relaxed);
    s.frames_progress = st_progress_.load(std::memory_order_relaxed);
    s.frames_unknown = st_unknown_.load(std::memory_order_relaxed);
    s.frames_dropped = frames_.dropped();
    s.lines_overlong = st_overlong_.load(std::memory_order_relaxed);
    s.connects = st_connects_.load(std::memory_order_relaxed);
    s.handshake_failures = st_handshake_failures_.load(std::memory_order_relaxed);
    s.watchdog_trips = st_watchdog_trips_.load(std::memory_order_relaxed);
    s.races_interrupted = st_interrupted_.load(std::memory_order_relaxed);
    return s;
}

bool LinkDriver::queue_command(const std::string& cmd, std::string& err) {
    const CommandCheck check = validate_command(cmd);
    if (!check.ok) {
        err = check.error;
        return false;
    }
    if (cmd.size() + 2 > sizeof(Command::text)) {
        err = "commande trop longue";
        return false;
    }
    Command c{};
    std::snprintf(c.text, sizeof(c.text), "%s\n", cmd.c_str());
    if (!commands_.try_push(c)) {
        err = "file de commandes pleine";
        return false;
    }
    return true;
}

void LinkDriver::enter(LinkState s, std::uint32_t now_ms) {
    if (state_.load(std::memory_order_relaxed) == s) {
        return;
    }
    state_.store(s, std::memory_order_release);
    if (s == LinkState::LinkLost) {
        st_watchdog_trips_.fetch_add(1, std::memory_order_relaxed);
        if (!link_down_) {
            link_down_ = true;
            lost_since_ms_ = now_ms;
            interrupted_reported_ = false;
        }
    } else if (s == LinkState::Identified) {
        st_connects_.fetch_add(1, std::memory_order_relaxed);
        consecutive_failures_ = 0;
        last_progress_ms_ = now_ms;
        link_down_ = false;
    }
}

void LinkDriver::note_failure(const std::string& path) {
    ++consecutive_failures_;
    // Blackliste pour ce cycle de scan : un port qui ne repond pas n'est pas le
    // boitier, inutile d'y revenir immediatement (docs/01 §4).
    if (!path.empty()) {
        blacklist_.push_back(path);
    }
    // Le cycle repart a zero quand tous les candidats ont ete essayes.
    if (blacklist_.size() > 16) {
        blacklist_.clear();
    }
}

void LinkDriver::close_port(std::uint32_t now_ms) {
    (void)now_ms;
    if (port_->is_open()) {
        port_->close();
    }
    assembler_.reset();
    current_path_.clear();
    published_path_.set("");
    version_.set("");
}

void LinkDriver::begin_handshake(std::uint32_t now_ms, bool send_stop) {
    // docs/01 §4 : `s` puis `v`. Le `s` remet un boitier inconnu dans un etat
    // connu — mais il est OMIS pendant une course, sinon la reconnexion abat
    // la course qu'elle vient de recuperer.
    if (send_stop) {
        const char stop[] = "s\n";
        port_->write(reinterpret_cast<const std::uint8_t*>(stop), 2);
    }
    const char ver[] = "v\n";
    port_->write(reinterpret_cast<const std::uint8_t*>(ver), 2);
    handshake_deadline_ = now_ms + cfg_.handshake_timeout_ms;
}

void LinkDriver::try_scan_and_open(std::uint32_t now_ms) {
    std::uint32_t interval = cfg_.scan_interval_ms;
    if (consecutive_failures_ >= cfg_.backoff_after_failures) {
        interval = cfg_.backoff_max_ms;  // docs/01 §6.4
    }
    if (last_scan_ms_ != 0 && now_ms - last_scan_ms_ < interval) {
        return;
    }
    last_scan_ms_ = now_ms;

    const std::vector<PortInfo> ports = enumerate_();
    const std::vector<Candidate> candidates =
        rank_candidates(ports, preferred_path_.get(), blacklist_);
    if (candidates.empty()) {
        blacklist_.clear();  // plus rien a essayer : on recommence au tour suivant
        return;
    }

    std::string err;
    const Candidate& best = candidates.front();
    if (!port_->open(best.info.path, err)) {
        note_failure(best.info.path);
        return;
    }
    current_path_ = best.info.path;
    published_path_.set(current_path_.c_str());
    handshake_attempt_ = 1;
    assembler_.reset();
    enter(LinkState::PortOpen, now_ms);
    // Pas de `s` si une course tourne : voir begin_handshake.
    begin_handshake(now_ms, !race_active_.load(std::memory_order_acquire));
}

void LinkDriver::pump_commands() {
    if (!port_->is_open()) {
        return;
    }
    Command c{};
    while (commands_.pop(c)) {
        port_->write(reinterpret_cast<const std::uint8_t*>(c.text), std::strlen(c.text));
    }
}

void LinkDriver::on_frame(const Frame& f, std::uint32_t now_ms) {
    st_frames_.fetch_add(1, std::memory_order_relaxed);

    if (f.kind == FrameKind::Version) {
        version_.set(f.text.data());
        if (state() != LinkState::Identified) {
            enter(LinkState::Identified, now_ms);
        }
    } else if (f.kind == FrameKind::Progress) {
        st_progress_.fetch_add(1, std::memory_order_relaxed);
        last_progress_ms_ = now_ms;
        if (state() == LinkState::LinkLost) {
            // docs/01 §6.2 : le lien revient, la course reprend. Les valeurs de
            // R: etant absolues, rien n'a ete perdu.
            enter(LinkState::Identified, now_ms);
        }
    } else if (f.kind == FrameKind::Unknown) {
        st_unknown_.fetch_add(1, std::memory_order_relaxed);
    }

    // Toutes les trames partent vers le thread de jeu, y compris Unknown et
    // Error : elles doivent etre logguees, pas avalees en silence.
    frames_.push(f);
}

std::size_t LinkDriver::pump_reads(std::uint32_t now_ms) {
    const std::size_t n = port_->read(read_buf_, sizeof(read_buf_));
    if (n == SerialPort::kReadError) {
        close_port(now_ms);
        enter(race_active_.load(std::memory_order_acquire) ? LinkState::LinkLost
                                                           : LinkState::Disconnected,
              now_ms);
        return 0;
    }
    if (n == 0) {
        return 0;
    }
    const std::size_t produced =
        assembler_.feed(read_buf_, n, [&](const Frame& f) { on_frame(f, now_ms); });
    st_overlong_.store(assembler_.dropped_overlong(), std::memory_order_relaxed);
    return produced;
}

// Constate qu'un boitier a quitte le systeme, meme sans erreur de lecture.
//
// LE CAS HORS COURSE. Le watchdog n'est arme que pendant une course (docs/01
// §6.2) et `read()` ne signale pas toujours un raccrochage — sur un
// pseudo-terminal il rend 0, un silence indistinguable d'un port au repos. Un
// boitier debranche au branchement laissait donc le panneau afficher
// `Lien : IDENTIFIED`, la version du firmware, et START actif : le depart
// partait dans le vide. `MANUEL-OPERATEUR` §2.5 demandait justement ce geste.
//
// Interroge a la cadence du scan, pas a chaque image : c'est un appel systeme.
bool LinkDriver::port_vanished(std::uint32_t now_ms) {
    if (!port_->is_open()) {
        return false;
    }
    if (last_presence_ms_ != 0 && now_ms - last_presence_ms_ < cfg_.scan_interval_ms) {
        return false;
    }
    last_presence_ms_ = now_ms;
    if (port_->still_present()) {
        return false;
    }
    // Meme verdict qu'une erreur de lecture : en course c'est une urgence,
    // hors course une simple deconnexion.
    close_port(now_ms);
    enter(race_active_.load(std::memory_order_acquire) ? LinkState::LinkLost
                                                       : LinkState::Disconnected,
          now_ms);
    return true;
}

void LinkDriver::tick(std::uint32_t now_ms) {
    if (!running_.load(std::memory_order_acquire)) {
        if (port_->is_open()) {
            close_port(now_ms);
            enter(LinkState::Disconnected, now_ms);
        }
        return;
    }

    const bool race_active = race_active_.load(std::memory_order_acquire);
    if (race_active != race_was_active_) {
        race_was_active_ = race_active;
        if (race_active) {
            race_active_since_ms_ = now_ms;
        }
    }

    // Verdict d'interruption, evalue quel que soit l'etat courant : le driver
    // peut tres bien etre reparti en PORT_OPEN sur un autre port pendant que la
    // course, elle, est coupee depuis plus de trois secondes.
    if (link_down_ && !interrupted_reported_ && race_active &&
        now_ms - lost_since_ms_ > cfg_.reconnect_grace_ms) {
        st_interrupted_.fetch_add(1, std::memory_order_relaxed);
        interrupted_reported_ = true;
    }

    if (port_vanished(now_ms)) {
        return;
    }

    switch (state()) {
        case LinkState::Disconnected:
            try_scan_and_open(now_ms);
            break;

        case LinkState::PortOpen: {
            pump_reads(now_ms);
            if (state() != LinkState::PortOpen) {
                break;  // identifie, ou port disparu
            }
            if (now_ms >= handshake_deadline_) {
                ++handshake_attempt_;
                if (handshake_attempt_ > cfg_.handshake_attempts) {
                    // docs/01 §4 : trois essais sans V:, on ferme et on
                    // blackliste. Un port ouvert n'est PAS une preuve.
                    st_handshake_failures_.fetch_add(1, std::memory_order_relaxed);
                    const std::string path = current_path_;
                    close_port(now_ms);
                    note_failure(path);
                    enter(LinkState::Disconnected, now_ms);
                } else {
                    begin_handshake(now_ms, !race_active_.load(std::memory_order_acquire));
                }
            }
            break;
        }

        case LinkState::Identified: {
            pump_commands();
            pump_reads(now_ms);
            if (state() != LinkState::Identified) {
                break;
            }
            // Watchdog arme UNIQUEMENT pendant une course, et seulement une
            // fois qu'au moins une trame R: est arrivee depuis le START : le
            // firmware reste muet pendant les ~4 s de decompte (docs/01 §6.2).
            if (race_active && last_progress_ms_ >= race_active_since_ms_ &&
                last_progress_ms_ != 0 && now_ms - last_progress_ms_ > cfg_.watchdog_ms) {
                enter(LinkState::LinkLost, now_ms);
            }
            break;
        }

        case LinkState::LinkLost: {
            pump_reads(now_ms);
            if (state() != LinkState::LinkLost) {
                break;
            }
            const std::uint32_t silence = now_ms - lost_since_ms_;
            if (port_->is_open() && silence > cfg_.close_after_silence_ms) {
                // Le firmware est peut-etre simplement fige ; au-dela d'une
                // seconde on referme pour rescanner, le boitier ayant pu se
                // renumeroter.
                const std::string path = current_path_;
                close_port(now_ms);
                note_failure(path);
            }
            if (!port_->is_open()) {
                try_scan_and_open(now_ms);
            }
            break;
        }
    }
}

}  // namespace sslink
