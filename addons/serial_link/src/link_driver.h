// Machine a etats du lien serie — docs/01 §4 et §6.
//
// C++ PUR et TESTABLE SANS MATERIEL : le port et l'enumeration sont injectes.
// Toute la logique risquee vit ici — handshake, watchdog, reconnexion, backoff,
// validation des commandes — precisement pour qu'elle soit couverte par des
// tests natifs plutot que decouverte le soir d'un evenement.
//
// Ce fichier est appele depuis le THREAD DE LECTURE. Il n'appelle aucune API
// Godot et n'ecrit dans rien d'autre que ses propres files (docs/01 §6.1).
#pragma once

#include <atomic>
#include <cstdint>
#include <functional>
#include <memory>
#include <string>
#include <vector>

#include "line_parser.h"
#include "port_selection.h"
#include "ring_buffer.h"
#include "serial_port.h"

namespace sslink {

enum class LinkState : int {
    Disconnected = 0,
    PortOpen,    // ouvert, mais pas encore identifie — START INTERDIT
    Identified,  // V:SS_v... recu. SEUL etat ou START est autorise (docs/01 §4)
    LinkLost,    // etait identifie, ne recoit plus rien
};

const char* link_state_name(LinkState s);

struct LinkConfig {
    std::uint32_t handshake_timeout_ms = 2000;
    int handshake_attempts = 3;
    std::uint32_t watchdog_ms = 500;       // docs/01 §6.2
    std::uint32_t close_after_silence_ms = 1000;  // gel court : on laisse une chance
    std::uint32_t reconnect_grace_ms = 3000;      // au-dela, course INTERROMPUE
    std::uint32_t scan_interval_ms = 1000;        // docs/01 §6.4
    std::uint32_t backoff_max_ms = 5000;
    int backoff_after_failures = 10;
};

struct LinkStats {
    std::uint64_t frames_total = 0;
    std::uint64_t frames_progress = 0;
    std::uint64_t frames_unknown = 0;
    std::uint64_t frames_dropped = 0;  // file pleine : le thread de jeu est fige
    std::uint64_t lines_overlong = 0;
    std::uint32_t connects = 0;
    std::uint32_t handshake_failures = 0;
    std::uint32_t watchdog_trips = 0;
    std::uint32_t races_interrupted = 0;
};

// Validation d'une commande AVANT emission — docs/01 §2 et §5.5.
struct CommandCheck {
    bool ok = false;
    std::string error;
};
CommandCheck validate_command(const std::string& cmd);

// Construit la commande de longueur pour une distance en metres.
// Rend une chaine vide si la conversion sort des bornes firmware.
std::string make_length_command(double metres, double roller_mm);

// La commande de duree que le PC emet TOUJOURS, quelle que soit la duree
// demandee par l'operateur — docs/01 §5.5.
const char* time_command();

// Chaine publiee du thread de lecture vers le thread de jeu.
//
// Un simple char[] partage serait une course de donnees : le lecteur ecrit
// pendant que le jeu lit. Sequenceur pair/impair + octets atomiques — le cout
// est nul (ecriture rare) et il n'y a aucun comportement indefini.
class PublishedString {
  public:
    static constexpr std::size_t kMax = 128;

    void set(const char* s) {
        seq_.fetch_add(1, std::memory_order_release);  // impair : ecriture en cours
        std::size_t i = 0;
        for (; s[i] != '\0' && i < kMax - 1; ++i) {
            buf_[i].store(s[i], std::memory_order_relaxed);
        }
        buf_[i].store('\0', std::memory_order_relaxed);
        seq_.fetch_add(1, std::memory_order_release);  // pair : stable
    }

    std::string get() const {
        for (;;) {
            const std::uint32_t before = seq_.load(std::memory_order_acquire);
            if ((before & 1u) != 0u) {
                continue;
            }
            std::string out;
            for (std::size_t i = 0; i < kMax; ++i) {
                const char c = buf_[i].load(std::memory_order_relaxed);
                if (c == '\0') {
                    break;
                }
                out.push_back(c);
            }
            if (seq_.load(std::memory_order_acquire) == before) {
                return out;
            }
        }
    }

  private:
    std::atomic<std::uint32_t> seq_{0};
    std::atomic<char> buf_[kMax]{};
};

class LinkDriver {
  public:
    static constexpr std::size_t kFrameQueue = 4096;  // ~41 s a 100 Hz
    static constexpr std::size_t kCommandQueue = 64;

    using Enumerator = std::function<std::vector<PortInfo>()>;

    LinkDriver(std::unique_ptr<SerialPort> port, Enumerator enumerator, LinkConfig cfg = {});

    // --- appele depuis le thread principal ---------------------------------
    void set_preferred_port(const std::string& path);
    void start();
    void stop();
    // Arme le watchdog. Desarme des que la FSM de course quitte RUNNING :
    // sinon, la fin normale du flux R: a l'arrivee d'une course distance a
    // 4 riders declencherait un faux LINK_LOST (docs/01 §6.2).
    //
    // Peut etre appele des le START sans danger : le watchdog ne s'arme
    // reellement qu'a la PREMIERE trame R: qui suit. Le firmware n'emet rien
    // pendant les ~4 s de decompte, et un watchdog naif tomberait la, chaque
    // fois, avant meme le depart.
    void set_race_active(bool active);

    // Valide puis met en file. L'erreur remonte immediatement a l'appelant.
    bool queue_command(const std::string& cmd, std::string& err);

    LinkState state() const { return state_.load(std::memory_order_acquire); }
    bool can_start_race() const { return state() == LinkState::Identified; }
    std::string firmware_version() const;
    std::string current_port() const;
    LinkStats stats() const;

    SpscRing<Frame, kFrameQueue>& frames() { return frames_; }

    // --- appele en boucle depuis le thread de lecture ----------------------
    void tick(std::uint32_t now_ms);

  private:
    void enter(LinkState s, std::uint32_t now_ms);
    void try_scan_and_open(std::uint32_t now_ms);
    void begin_handshake(std::uint32_t now_ms, bool send_stop);
    void pump_commands();
    std::size_t pump_reads(std::uint32_t now_ms);
    void on_frame(const Frame& f, std::uint32_t now_ms);
    void close_port(std::uint32_t now_ms);
    void note_failure(const std::string& path);

    std::unique_ptr<SerialPort> port_;
    Enumerator enumerate_;
    LinkConfig cfg_;

    std::atomic<LinkState> state_{LinkState::Disconnected};
    std::atomic<bool> running_{false};
    std::atomic<bool> race_active_{false};

    LineAssembler assembler_;
    SpscRing<Frame, kFrameQueue> frames_;

    struct Command {
        char text[16];
    };
    SpscRing<Command, kCommandQueue> commands_;

    // Etat interne, touche uniquement par le thread de lecture.
    std::string current_path_;
    std::vector<std::string> blacklist_;
    int handshake_attempt_ = 0;
    std::uint32_t handshake_deadline_ = 0;
    std::uint32_t last_scan_ms_ = 0;
    std::uint32_t last_progress_ms_ = 0;
    std::uint32_t lost_since_ms_ = 0;
    // Instant ou la course a ete declaree active. Tant qu'aucune trame R:
    // n'est arrivee APRES cet instant, le watchdog reste desarme.
    std::uint32_t race_active_since_ms_ = 0;
    bool race_was_active_ = false;
    int consecutive_failures_ = 0;
    // Le lien est tombe et n'est pas revenu. Suivi SEPAREMENT de l'etat : le
    // driver quitte LINK_LOST des qu'il rescanne un port, mais la course, elle,
    // est toujours coupee. Confondre les deux faisait disparaitre la marque
    // INTERROMPUE au bout d'une seconde.
    bool link_down_ = false;
    bool interrupted_reported_ = false;
    std::uint8_t read_buf_[1024]{};

    // Partage avec le thread principal : ecrit par le lecteur, lu par le jeu.
    PublishedString version_;
    PublishedString published_path_;
    // Ecrit par le thread principal avant start(), lu par le lecteur.
    PublishedString preferred_path_;
    std::atomic<std::uint64_t> st_overlong_{0};

    std::atomic<std::uint64_t> st_frames_{0};
    std::atomic<std::uint64_t> st_progress_{0};
    std::atomic<std::uint64_t> st_unknown_{0};
    std::atomic<std::uint32_t> st_connects_{0};
    std::atomic<std::uint32_t> st_handshake_failures_{0};
    std::atomic<std::uint32_t> st_watchdog_trips_{0};
    std::atomic<std::uint32_t> st_interrupted_{0};
};

}  // namespace sslink
