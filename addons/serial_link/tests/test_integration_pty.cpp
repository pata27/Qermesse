// Test d'INTEGRATION : le driver serie complet, sur un VRAI peripherique.
//
// Le firmware emule (tools/ss_emu) parle sur un pseudo-terminal ; le driver
// (addons/serial_link) l'ouvre comme il ouvrirait un Arduino. Ouverture du
// port, configuration termios, decoupage du flux, handshake, watchdog et
// reconnexion sont donc reellement traverses — pas simules.
//
// C'est tout ce que le mode mock de la v2 ne testait pas, et c'est la raison
// pour laquelle ce fichier existe.
//
// POSIX uniquement : sous Windows la CI se limite aux tests a port factice.
#if !defined(_WIN32)

#include "doctest.h"

#include <chrono>
#include <string>
#include <thread>
#include <vector>

#include "faults.h"
#include "firmware_sim.h"
#include "link_driver.h"
#include "port_pty.h"
#include "rider_model.h"

namespace {

// Fait tourner l'emulateur et le driver dans le meme processus, mais relies
// par un vrai peripherique serie. L'horloge est virtuelle des deux cotes.
class PtyRig {
  public:
    ssemu::FirmwareSim fw;
    ssemu::RiderModel model;
    ssemu::PtyPort pty;
    sslink::LinkDriver drv;
    double sim_ms = 0.0;

    PtyRig(const char* profile, int wired)
        : model(*ssemu::find_profile(profile), wired, ssemu::kDefaultRollerMm, 42),
          drv(sslink::make_serial_port(), [] { return sslink::enumerate_ports(); }) {
        std::string err;
        REQUIRE_MESSAGE(pty.open(err), err);
        pty.set_baud_pacing(false);  // temps virtuel : le cadencement n'a pas de sens ici
        drv.set_preferred_port(pty.device());
        drv.start();
    }

    void run_ms(double duration) {
        const double target = sim_ms + duration;
        while (sim_ms < target) {
            // --- cote firmware emule ---
            model.set_race_running(fw.race_started(), sim_ms);
            for (int k = 0; k < 10; ++k) {
                model.update(sim_ms + double(k) / 10.0, fw);
                fw.tick(std::uint32_t(sim_ms));
            }
            std::uint8_t buf[512];
            const std::size_t got = pty.read_available(buf, sizeof(buf));
            if (got > 0) {
                fw.feed_rx(buf, got);
            }
            pty.queue_tx(fw.drain_tx());
            pty.pump_tx(sim_ms);

            // --- cote driver PC ---
            drv.tick(std::uint32_t(sim_ms));

            sim_ms += 1.0;
        }
    }

    std::vector<sslink::Frame> drain() {
        std::vector<sslink::Frame> out;
        sslink::Frame f;
        while (drv.frames().pop(f)) {
            out.push_back(f);
        }
        return out;
    }
};

}  // namespace

TEST_CASE("integration : handshake complet sur un vrai pseudo-terminal") {
    PtyRig rig("egaux", 2);
    CHECK(rig.drv.state() == sslink::LinkState::Disconnected);
    CHECK_FALSE(rig.drv.can_start_race());

    rig.run_ms(1500);

    CHECK(rig.drv.state() == sslink::LinkState::Identified);
    CHECK(rig.drv.firmware_version() == "SS_v0.1.7");
    CHECK(rig.drv.can_start_race());
    CHECK(rig.drv.current_port() == rig.pty.device());
}

TEST_CASE("integration : une course en distance, de bout en bout") {
    PtyRig rig("egaux", 2);
    rig.run_ms(1500);
    REQUIRE(rig.drv.state() == sslink::LinkState::Identified);

    std::string err;
    REQUIRE(rig.drv.queue_command("d", err));
    REQUIRE(rig.drv.queue_command(sslink::make_length_command(100.0, 114.3), err));
    REQUIRE(rig.drv.queue_command("g", err));
    rig.run_ms(100);
    rig.drv.set_race_active(true);

    // Decompte (~4 s) puis 100 m a ~45 km/h (~9 s).
    rig.run_ms(15000);

    const std::vector<sslink::Frame> frames = rig.drain();
    int countdowns = 0;
    int progress = 0;
    int finishes = 0;
    std::uint32_t last_ticks0 = 0;
    for (const sslink::Frame& f : frames) {
        switch (f.kind) {
            case sslink::FrameKind::Countdown: ++countdowns; break;
            case sslink::FrameKind::RiderFinish: ++finishes; break;
            case sslink::FrameKind::Progress:
                ++progress;
                last_ticks0 = f.ticks[0];
                break;
            default: break;
        }
    }
    CHECK(countdowns == 4);            // CD:3 a CD:0
    CHECK(progress > 800);             // ~100 Hz pendant ~11 s
    CHECK(finishes == 2);              // deux pistes cablees ont franchi la ligne
    CHECK(last_ticks0 > 278);          // au-dela des 100 m demandes

    // Le firmware attend les QUATRE pistes : la course ne se termine pas de
    // son cote. C'est au PC de trancher — docs/01 §5.1.
    CHECK(rig.drv.state() == sslink::LinkState::Identified);
    CHECK(rig.drv.stats().frames_dropped == 0);
    CHECK(rig.drv.stats().frames_unknown == 0);
}

TEST_CASE("integration : une trame corrompue ne casse rien") {
    PtyRig rig("egaux", 2);
    rig.run_ms(1500);
    std::string err;
    REQUIRE(rig.drv.queue_command("x", err));
    REQUIRE(rig.drv.queue_command(sslink::time_command(), err));
    REQUIRE(rig.drv.queue_command("g", err));
    rig.run_ms(4500);
    rig.drv.set_race_active(true);
    rig.drain();

    // Exactement les octets que ss_emu injecte avec --inject trame-corrompue.
    rig.pty.queue_tx(std::string("R:\x01\x99\xC3 42,,\r\n", 12));
    rig.run_ms(500);

    const std::vector<sslink::Frame> frames = rig.drain();
    int unknown = 0;
    int progress = 0;
    for (const sslink::Frame& f : frames) {
        if (f.kind == sslink::FrameKind::Unknown) {
            ++unknown;
            CHECK(f.text_str() == "R:\\x01\\x99\\xC3 42,,");
        }
        if (f.kind == sslink::FrameKind::Progress) {
            ++progress;
        }
    }
    CHECK(unknown == 1);
    CHECK(progress > 30);  // le flux continue normalement de part et d'autre
    CHECK(rig.drv.state() == sslink::LinkState::Identified);
}

TEST_CASE("integration : coupure du lien detectee en moins de 500 ms") {
    PtyRig rig("egaux", 2);
    rig.run_ms(1500);
    std::string err;
    REQUIRE(rig.drv.queue_command("x", err));
    REQUIRE(rig.drv.queue_command(sslink::time_command(), err));
    REQUIRE(rig.drv.queue_command("g", err));
    rig.run_ms(4500);
    rig.drv.set_race_active(true);
    rig.run_ms(1000);
    REQUIRE(rig.drv.state() == sslink::LinkState::Identified);

    const double cut_at = rig.sim_ms;
    rig.pty.close();  // le cable est arrache

    rig.run_ms(400);
    // Tolerance : la detection peut arriver un peu avant 500 ms de silence si
    // la derniere trame datait deja de quelques dizaines de ms.
    rig.run_ms(200);
    CHECK(rig.drv.state() == sslink::LinkState::LinkLost);
    CHECK(rig.sim_ms - cut_at < 700.0);
    CHECK(rig.drv.stats().watchdog_trips == 1);
}

TEST_CASE("integration : la course survit a une reconnexion, sans s parasite") {
    PtyRig rig("egaux", 2);
    rig.run_ms(1500);
    std::string err;
    REQUIRE(rig.drv.queue_command("x", err));
    REQUIRE(rig.drv.queue_command(sslink::time_command(), err));
    REQUIRE(rig.drv.queue_command("g", err));
    rig.run_ms(4500);
    rig.drv.set_race_active(true);
    rig.run_ms(2000);
    REQUIRE(rig.fw.race_started());

    rig.pty.close();
    rig.run_ms(800);
    REQUIRE(rig.drv.state() == sslink::LinkState::LinkLost);

    // Le boitier revient sur un pseudo-terminal RENUMEROTE, comme un Arduino
    // qui se re-enumere. Le driver doit le retrouver par le port force.
    std::string reopen_err;
    REQUIRE_MESSAGE(rig.pty.open(reopen_err), reopen_err);
    rig.drv.set_preferred_port(rig.pty.device());
    rig.run_ms(3000);

    CHECK(rig.drv.state() == sslink::LinkState::Identified);
    // Le point crucial : la course tourne toujours cote firmware. Un `s` emis
    // pendant la reconnexion l'aurait abattue.
    CHECK(rig.fw.race_started());
}

#endif  // !_WIN32
