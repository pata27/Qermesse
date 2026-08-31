// ss_emu — émulateur du firmware SilverSprint sur pseudo-terminal.
// Spécification : docs/07-EMULATEUR-FIRMWARE.md
//
// Rappel qui vaut d'être répété : franchir un scénario avec ss_emu franchit le
// jalon J1-ém, PAS le jalon J1. Le matériel réel reste indispensable (docs/07 §2).

#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstring>
#include <csignal>
#include <deque>
#include <iostream>
#include <string>
#include <thread>
#include <vector>

#include "faults.h"
#include "firmware_sim.h"
#include "port_pty.h"
#include "rider_model.h"

#if !defined(_WIN32)
#include <fcntl.h>
#include <unistd.h>
#endif

namespace {

std::atomic<bool> g_stop{false};

void on_signal(int) { g_stop = true; }

struct Options {
    bool use_pty = false;
    bool use_stdio = false;
    std::string link;
    std::string trace;
    int riders = 2;  // le boîtier de l'utilisateur : deux capteurs câblés
    std::string profile = "egaux";
    double roller_mm = ssemu::kDefaultRollerMm;
    std::uint32_t seed = 42;
    double speed = 1.0;
    double latency_ms = 0.0;
    bool baud_pacing = true;
    bool quiet = false;
    std::vector<ssemu::Fault> faults;
};

void usage() {
    std::cout <<
        R"(ss_emu — emulateur du firmware SilverSprint (SS_v0.1.7) sur pseudo-terminal.

  --pty                  cree un pseudo-terminal et affiche son chemin
  --link <chemin>        lien symbolique stable vers le pseudo-terminal
  --stdio                octets sur stdin/stdout au lieu d'un port
  --riders <1..4>        capteurs cables (defaut 2)
  --profile <nom>        profil de course (defaut egaux) — voir --list-profiles
  --roller-mm <mm>       diametre du rouleau simule (defaut 114.3)
  --seed <n>             graine du bruit, rejeu deterministe (defaut 42)
  --speed <x>            facteur d'acceleration du temps (defaut 1.0)
  --latency-ms <n>       latence de transport simulee (defaut 0)
  --no-baud-pacing       emet sans respecter les 11520 o/s de la ligne
  --inject <panne>[@<t>] injection, cumulable ; <t> en secondes depuis le depart
  --trace <fichier>      journalise tous les octets echanges, horodates
  --quiet                pas de ligne d'etat sur stderr
  --list-profiles        detaille les profils disponibles
  --help

Pannes : faux-depart=<i>  tick-fantome=<i>[@<t>]  perte-lien@<t>  retour-lien@<t>
         trame-corrompue@<t>  octet-nul@<t>  gel@<t>=<ms>  ligne-tronquee@<t>

Exemple :
  ss_emu --pty --link ./.run/ttyEMU --riders 2 --profile domination \
         --inject perte-lien@8 --inject retour-lien@10 --trace ./.run/trace.log
)";
}

bool parse_uint(const char* s, std::uint32_t& out) {
    char* end = nullptr;
    const unsigned long v = std::strtoul(s, &end, 10);
    if (end == s || *end != '\0') {
        return false;
    }
    out = std::uint32_t(v);
    return true;
}

bool parse_double(const char* s, double& out) {
    char* end = nullptr;
    const double v = std::strtod(s, &end);
    if (end == s || *end != '\0') {
        return false;
    }
    out = v;
    return true;
}

std::string escape(std::string_view s) {
    std::string out;
    char buf[8];
    for (unsigned char c : s) {
        if (c == '\r') {
            out += "\\r";
        } else if (c == '\n') {
            out += "\\n";
        } else if (c >= 32 && c < 127) {
            out.push_back(char(c));
        } else {
            std::snprintf(buf, sizeof(buf), "\\x%02X", c);
            out += buf;
        }
    }
    return out;
}

int fail(const std::string& msg) {
    std::cerr << "ss_emu: " << msg << "\n";
    return 2;
}

}  // namespace

int main(int argc, char** argv) {
    Options opt;

    for (int i = 1; i < argc; ++i) {
        const std::string a = argv[i];
        auto next = [&](const char* what) -> const char* {
            if (i + 1 >= argc) {
                std::cerr << "ss_emu: " << what << " attend une valeur\n";
                std::exit(2);
            }
            return argv[++i];
        };
        if (a == "--help" || a == "-h") {
            usage();
            return 0;
        } else if (a == "--list-profiles") {
            for (const ssemu::Profile& p : ssemu::profiles()) {
                std::cout << "  " << p.name << std::string(18 - p.name.size(), ' ')
                          << p.description << "\n";
            }
            return 0;
        } else if (a == "--pty") {
            opt.use_pty = true;
        } else if (a == "--stdio") {
            opt.use_stdio = true;
        } else if (a == "--quiet") {
            opt.quiet = true;
        } else if (a == "--no-baud-pacing") {
            opt.baud_pacing = false;
        } else if (a == "--link") {
            opt.link = next("--link");
        } else if (a == "--trace") {
            opt.trace = next("--trace");
        } else if (a == "--profile") {
            opt.profile = next("--profile");
        } else if (a == "--riders") {
            std::uint32_t v = 0;
            if (!parse_uint(next("--riders"), v) || v < 1 || v > 4) {
                return fail("--riders attend 1..4");
            }
            opt.riders = int(v);
        } else if (a == "--seed") {
            if (!parse_uint(next("--seed"), opt.seed)) {
                return fail("--seed attend un entier");
            }
        } else if (a == "--roller-mm") {
            if (!parse_double(next("--roller-mm"), opt.roller_mm) || opt.roller_mm <= 0.0) {
                return fail("--roller-mm attend un diametre positif");
            }
        } else if (a == "--speed") {
            if (!parse_double(next("--speed"), opt.speed) || opt.speed <= 0.0) {
                return fail("--speed attend un facteur positif");
            }
        } else if (a == "--latency-ms") {
            if (!parse_double(next("--latency-ms"), opt.latency_ms) || opt.latency_ms < 0.0) {
                return fail("--latency-ms attend une valeur positive");
            }
        } else if (a == "--inject") {
            ssemu::Fault f;
            std::string err;
            if (!ssemu::parse_fault(next("--inject"), f, err)) {
                return fail(err);
            }
            opt.faults.push_back(f);
        } else {
            return fail("option inconnue : " + a);
        }
    }

    if (opt.use_pty == opt.use_stdio) {
        usage();
        return fail("choisir exactement un transport : --pty ou --stdio");
    }

    const ssemu::Profile* profile = ssemu::find_profile(opt.profile);
    if (profile == nullptr) {
        return fail("profil inconnu : " + opt.profile + " (voir --list-profiles)");
    }

    std::signal(SIGINT, on_signal);
    std::signal(SIGTERM, on_signal);

    ssemu::FirmwareSim fw;
    ssemu::RiderModel model(*profile, opt.riders, opt.roller_mm, opt.seed);
    ssemu::FaultEngine faults;
    for (const ssemu::Fault& f : opt.faults) {
        faults.add(f);
    }

    ssemu::PtyPort port;
    port.set_baud_pacing(opt.baud_pacing);
    if (opt.use_pty) {
        std::string err;
        if (!opt.link.empty() && !port.set_link(opt.link, err)) {
            return fail(err);
        }
        if (!port.open(err)) {
            return fail(err);
        }
        std::cout << "pseudo-terminal : " << port.device() << "\n";
        if (!opt.link.empty()) {
            std::cout << "lien stable     : " << opt.link << "\n";
        }
        std::cout << "firmware        : " << ssemu::FirmwareSim::kVersion << "\n"
                  << "capteurs cables : " << opt.riders << " (pistes "
                  << (opt.riders > 1 ? "0.." + std::to_string(opt.riders - 1) : std::string("0"))
                  << ", les autres restent a HIGH)\n"
                  << "profil          : " << profile->name << " — " << profile->description << "\n"
                  << "circonference   : " << model.circumference_mm() << " mm\n"
                  << std::flush;
    }

#if !defined(_WIN32)
    if (opt.use_stdio) {
        const int flags = ::fcntl(0, F_GETFL, 0);
        ::fcntl(0, F_SETFL, flags | O_NONBLOCK);
    }
#endif

    std::FILE* trace = nullptr;
    if (!opt.trace.empty()) {
        trace = std::fopen(opt.trace.c_str(), "w");
        if (trace == nullptr) {
            return fail("impossible d'ouvrir la trace : " + opt.trace);
        }
        std::fprintf(trace, "# ss_emu trace — firmware %s, profil %s, riders %d, seed %u\n",
                     ssemu::FirmwareSim::kVersion, profile->name.c_str(), opt.riders, opt.seed);
        std::fprintf(trace, "# t_ms\tsens\toctets\n");
    }

    constexpr int kItersPerMs = 10;  // le vrai firmware boucle bien plus vite
    const auto wall_start = std::chrono::steady_clock::now();

    double sim_ms = 0.0;
    bool was_running = false;
    bool false_start_armed = false;
    double freeze_until_ms = -1.0;
    std::string held;                                    // sortie retenue pendant un gel
    std::deque<std::pair<double, std::string>> delayed;  // latence de transport
    double race_start_ms = 0.0;
    double last_status_ms = -1000.0;
    std::size_t warn_seen = 0;

    std::uint8_t rxbuf[512];

    while (!g_stop) {
        const std::uint32_t ms = std::uint32_t(sim_ms);

        // ---- entrée -------------------------------------------------------
        std::size_t n = 0;
        if (opt.use_pty) {
            n = port.read_available(rxbuf, sizeof(rxbuf));
        }
#if !defined(_WIN32)
        else {
            const ssize_t r = ::read(0, rxbuf, sizeof(rxbuf));
            n = r > 0 ? std::size_t(r) : 0;
        }
#endif
        if (n > 0) {
            fw.feed_rx(rxbuf, n);
            if (trace != nullptr) {
                std::fprintf(trace, "%.1f\tPC->FW\t%s\n", sim_ms,
                             escape(std::string_view(reinterpret_cast<char*>(rxbuf), n)).c_str());
            }
        }

        // ---- état de course, et réarmement du scénario ---------------------
        if (fw.race_started() && !was_running) {
            race_start_ms = sim_ms;
            faults.rearm();
            false_start_armed = false;
        }
        was_running = fw.race_started();
        model.set_race_running(fw.race_started(), sim_ms);

        // Le faux départ n'a de sens que pendant le décompte.
        if (fw.race_starting() && !false_start_armed) {
            for (const ssemu::Fault& f : faults.pre_race()) {
                model.set_false_start(f.rider, true);
            }
            false_start_armed = true;
        }
        if (fw.race_started()) {
            for (int r = 0; r < 4; ++r) {
                model.set_false_start(r, false);
            }
        }

        // ---- pannes échues ------------------------------------------------
        if (fw.race_started()) {
            const double race_t_s = (sim_ms - race_start_ms) / 1000.0;
            for (const ssemu::Fault& f : faults.due(race_t_s)) {
                std::string err;
                switch (f.kind) {
                    case ssemu::FaultKind::LinkLoss:
                        std::cerr << "[panne] perte-lien a t=" << race_t_s << " s\n";
                        port.close();
                        break;
                    case ssemu::FaultKind::LinkReturn:
                        if (!port.reopen(err)) {
                            std::cerr << "[panne] retour-lien impossible : " << err << "\n";
                        } else {
                            std::cerr << "[panne] retour-lien a t=" << race_t_s
                                      << " s, nouveau pseudo-terminal " << port.device() << "\n";
                        }
                        break;
                    case ssemu::FaultKind::PhantomTick:
                        std::cerr << "[panne] tick-fantome rider " << f.rider << "\n";
                        model.inject_phantom_tick(f.rider);
                        break;
                    case ssemu::FaultKind::Freeze:
                        std::cerr << "[panne] gel de " << f.param << " ms\n";
                        freeze_until_ms = sim_ms + f.param;
                        break;
                    case ssemu::FaultKind::CorruptFrame:
                        std::cerr << "[panne] trame corrompue\n";
                        port.queue_tx(std::string("R:\x01\x99\xC3 42,,\r\n", 12));
                        break;
                    case ssemu::FaultKind::NullByte:
                        std::cerr << "[panne] octet nul\n";
                        port.queue_tx(std::string("R:12,\0 34,0,0,900\r\n", 19));
                        break;
                    case ssemu::FaultKind::TruncatedLine:
                        std::cerr << "[panne] ligne tronquee\n";
                        port.queue_tx("R:99,99,99,99");  // sans terminateur
                        break;
                    case ssemu::FaultKind::FalseStart:
                        break;
                }
            }
        }

        // ---- firmware -----------------------------------------------------
        for (int k = 0; k < kItersPerMs; ++k) {
            model.update(sim_ms + double(k) / kItersPerMs, fw);
            fw.tick(ms);
        }

        // ---- sortie -------------------------------------------------------
        std::string tx = fw.drain_tx();
        if (!tx.empty() && trace != nullptr) {
            std::fprintf(trace, "%.1f\tFW->PC\t%s\n", sim_ms, escape(tx).c_str());
        }
        // Gel : le firmware ne parle plus, mais le port reste ouvert. C'est le
        // pire cas pour un watchdog, qui doit le distinguer d'une déconnexion.
        if (sim_ms < freeze_until_ms) {
            held += tx;
            tx.clear();
        } else if (!held.empty()) {
            tx = held + tx;
            held.clear();
        }
        if (!tx.empty()) {
            if (opt.latency_ms > 0.0) {
                delayed.emplace_back(sim_ms + opt.latency_ms, std::move(tx));
            } else if (opt.use_pty) {
                port.queue_tx(tx);
            } else {
                std::fwrite(tx.data(), 1, tx.size(), stdout);
                std::fflush(stdout);
            }
        }
        while (!delayed.empty() && delayed.front().first <= sim_ms) {
            if (opt.use_pty) {
                port.queue_tx(delayed.front().second);
            } else {
                std::fwrite(delayed.front().second.data(), 1, delayed.front().second.size(),
                            stdout);
                std::fflush(stdout);
            }
            delayed.pop_front();
        }
        if (opt.use_pty) {
            port.pump_tx(sim_ms);
        }

        // ---- avertissements du firmware ------------------------------------
        while (warn_seen < fw.warnings().size()) {
            std::cerr << fw.warnings()[warn_seen++] << "\n";
        }

        // ---- ligne d'état ---------------------------------------------------
        if (!opt.quiet && sim_ms - last_status_ms >= 250.0) {
            last_status_ms = sim_ms;
            const char* state = fw.race_started()  ? "COURSE"
                                : fw.race_starting() ? "DECOMPTE"
                                                     : "REPOS";
            std::fprintf(stderr, "\r[%s] %6.1fs  lien:%s ", state,
                         fw.race_started() ? (sim_ms - race_start_ms) / 1000.0 : 0.0,
                         port.is_open() || opt.use_stdio ? "ok  " : "COUPE");
            for (int r = 0; r < opt.riders; ++r) {
                std::fprintf(stderr, " P%d:%5u t %5.1f km/h", r,
                             static_cast<unsigned>(fw.racer_ticks(r)),
                             model.speed_kph(r));
            }
            std::fprintf(stderr, "   ");
            std::fflush(stderr);
        }

        // ---- cadencement temps réel -----------------------------------------
        sim_ms += 1.0;
        const auto target = wall_start + std::chrono::duration_cast<std::chrono::steady_clock::duration>(
                                             std::chrono::duration<double, std::milli>(sim_ms / opt.speed));
        std::this_thread::sleep_until(target);
    }

    std::cerr << "\nss_emu: arret.";
    if (port.dropped_bytes() > 0) {
        std::cerr << " " << port.dropped_bytes() << " octets perdus (personne ne lisait).";
    }
    std::cerr << "\n";
    if (trace != nullptr) {
        std::fclose(trace);
    }
    return 0;
}
