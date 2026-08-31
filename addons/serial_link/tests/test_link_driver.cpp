#include "doctest.h"

#include <algorithm>
#include <cstring>
#include <deque>
#include <memory>
#include <string>

#include "link_driver.h"

using namespace sslink;

namespace {

// Port factice : c'est lui qui permet d'eprouver TOUT le lien — handshake,
// watchdog, reconnexion, backoff — sans materiel, sans OS, en temps virtuel.
class FakePort : public SerialPort {
  public:
    // Scenario pilote par les tests.
    bool open_should_fail = false;
    bool read_should_error = false;
    bool answers_version = true;   // false : port ouvert mais muet -> handshake echoue
    std::string written;           // tout ce que le PC a emis
    std::string to_read;           // ce que le firmware repondra
    int open_count = 0;
    int close_count = 0;
    std::string last_path;

    bool open(const std::string& path, std::string& err) override {
        if (open_should_fail) {
            err = "refus simule";
            return false;
        }
        ++open_count;
        last_path = path;
        open_ = true;
        return true;
    }

    void close() override {
        if (open_) {
            ++close_count;
        }
        open_ = false;
        to_read.clear();
    }

    bool is_open() const override { return open_; }

    std::size_t read(std::uint8_t* buf, std::size_t n) override {
        if (read_should_error) {
            return SerialPort::kReadError;
        }
        if (!open_ || to_read.empty()) {
            return 0;
        }
        const std::size_t count = std::min(n, to_read.size());
        std::memcpy(buf, to_read.data(), count);
        to_read.erase(0, count);
        return count;
    }

    bool write(const std::uint8_t* buf, std::size_t n) override {
        if (!open_) {
            return false;
        }
        written.append(reinterpret_cast<const char*>(buf), n);
        // Le firmware repond a `v` — sauf si le test le fait taire.
        for (std::size_t i = 0; i < n; ++i) {
            if (buf[i] == 'v' && answers_version) {
                to_read += "V:SS_v0.1.7\r\n";
            }
        }
        return true;
    }

    void emit(const std::string& s) { to_read += s; }

  private:
    bool open_ = false;
};

std::vector<PortInfo> one_arduino() {
    PortInfo p;
    p.path = "/dev/ttyACM0";
    p.vid = 0x2341;
    p.pid = 0x0043;
    p.has_ids = true;
    return {p};
}

struct Rig {
    FakePort* port;
    std::unique_ptr<LinkDriver> drv;
    std::uint32_t now = 0;

    explicit Rig(std::vector<PortInfo> ports = one_arduino(), LinkConfig cfg = {}) {
        auto owned = std::make_unique<FakePort>();
        port = owned.get();
        drv = std::make_unique<LinkDriver>(std::move(owned), [ports]() { return ports; }, cfg);
        drv->start();
    }

    void run_ms(std::uint32_t duration, std::uint32_t step = 5) {
        const std::uint32_t target = now + duration;
        while (now < target) {
            now += step;
            drv->tick(now);
        }
    }

    std::size_t drain(std::vector<Frame>& out) {
        Frame f;
        std::size_t n = 0;
        while (drv->frames().pop(f)) {
            out.push_back(f);
            ++n;
        }
        return n;
    }
};

}  // namespace

// ===========================================================================
// Validation des commandes — docs/01 §2 et §5.5
// ===========================================================================

TEST_CASE("les commandes sans argument de docs/01 §2 sont acceptees") {
    for (const char* c : {"v", "s", "g", "d", "x", "m"}) {
        CAPTURE(c);
        CHECK(validate_command(c).ok);
    }
}

TEST_CASE("toute commande hors de la liste est refusee") {
    for (const char* c : {"", "q", "z", "gg", "V", "S", "G"}) {
        CAPTURE(c);
        CHECK_FALSE(validate_command(c).ok);
    }
}

TEST_CASE("l<ticks> : borne haute a 7 chiffres, tampon firmware charBuff[8]") {
    CHECK(validate_command("l278").ok);

    // 8 chiffres : le tampon charBuff[8] deborde AVANT meme qu'atoi ne parle.
    const CommandCheck huit = validate_command("l12345678");
    CHECK_FALSE(huit.ok);
    CHECK(huit.error.find("chiffres") != std::string::npos);
    CHECK(huit.error.find("charBuff") != std::string::npos);

    // 7 chiffres passent la contrainte de tampon, mais aucune valeur a
    // 7 chiffres ne tient dans un int 16 bits : c'est la borne de valeur qui
    // les arrete. Les deux contraintes de docs/01 §2 sont donc bien distinctes,
    // et la plus stricte des deux gagne selon le cas.
    const CommandCheck sept = validate_command("l1234567");
    CHECK_FALSE(sept.ok);
    CHECK(sept.error.find("32767") != std::string::npos);
}

TEST_CASE("l<ticks> : borne de valeur a 32767, atoi remplit un int 16 bits") {
    CHECK(validate_command("l32767").ok);
    const CommandCheck c = validate_command("l32768");
    CHECK_FALSE(c.ok);
    CHECK(c.error.find("32767") != std::string::npos);
    CHECK_FALSE(validate_command("l0").ok);
    CHECK_FALSE(validate_command("l-5").ok);
    CHECK_FALSE(validate_command("labc").ok);
}

TEST_CASE("t<secs> : toute duree qui ferait terminer le firmware est REFUSEE") {
    // Le coeur de docs/01 §5.5. t600 couperait le flux R: a 10,2 s, en pleine
    // course, sans le moindre message d'erreur. Le driver l'interdit.
    const CommandCheck c = validate_command("t600");
    CHECK_FALSE(c.ok);
    CHECK(c.error.find("10176") != std::string::npos);
    CHECK(c.error.find("t60") != std::string::npos);

    CHECK_FALSE(validate_command("t30").ok);   // termine a 30 s
    CHECK_FALSE(validate_command("t400").ok);  // termine a 6,8 s
    CHECK_FALSE(validate_command("t1000").ok); // termine a 17 s

    // Celles dont le produit deborde en negatif sont sures.
    CHECK(validate_command("t60").ok);
    CHECK(validate_command("t33").ok);
    CHECK(validate_command("t300").ok);
}

TEST_CASE("la commande de duree emise par le PC est la constante t60") {
    CHECK(std::string(time_command()) == "t60");
    CHECK(validate_command(time_command()).ok);
}

TEST_CASE("make_length_command : 100 m @ 114.3 mm donne l278") {
    CHECK(make_length_command(100.0, 114.3) == "l278");
    CHECK(make_length_command(500.0, 114.3) == "l1392");
    CHECK(make_length_command(5000.0, 114.3) == "l13924");  // borne haute de docs/02
    CHECK(make_length_command(0.0, 114.3).empty());
    CHECK(make_length_command(100.0, 0.0).empty());
    // Au-dela de 32767 ticks, il n'existe pas de commande valide.
    CHECK(make_length_command(20000.0, 114.3).empty());
}

// ===========================================================================
// Handshake — docs/01 §4
// ===========================================================================

TEST_CASE("handshake nominal : s puis v, puis V: donne IDENTIFIED") {
    Rig rig;
    CHECK(rig.drv->state() == LinkState::Disconnected);
    CHECK_FALSE(rig.drv->can_start_race());

    rig.run_ms(20);
    CHECK(rig.port->open_count == 1);
    CHECK(rig.port->last_path == "/dev/ttyACM0");
    CHECK(rig.port->written.substr(0, 4) == "s\nv\n");

    rig.run_ms(20);
    CHECK(rig.drv->state() == LinkState::Identified);
    CHECK(rig.drv->firmware_version() == "SS_v0.1.7");
    CHECK(rig.drv->current_port() == "/dev/ttyACM0");
    CHECK(rig.drv->can_start_race());
}

TEST_CASE("un port ouvert mais muet ne donne JAMAIS le droit de demarrer") {
    // La faute de la v1 : elle autorisait le depart des que le port etait
    // ouvert. Ici, trois essais sans V: et le port est ferme puis blackliste.
    Rig rig;
    rig.port->answers_version = false;

    rig.run_ms(20);
    CHECK(rig.drv->state() == LinkState::PortOpen);
    CHECK_FALSE(rig.drv->can_start_race());

    rig.run_ms(7000);
    CHECK_FALSE(rig.drv->can_start_race());
    CHECK(rig.drv->state() != LinkState::Identified);
    CHECK(rig.drv->stats().handshake_failures >= 1);
    CHECK(rig.port->close_count >= 1);
}

TEST_CASE("trois tentatives de v avant d'abandonner le port") {
    Rig rig;
    rig.port->answers_version = false;
    rig.run_ms(20);
    const std::size_t first = rig.port->written.size();
    rig.run_ms(4500);  // deux timeouts de 2 s
    CHECK(rig.port->written.size() > first);
    int v_count = 0;
    for (char c : rig.port->written) {
        if (c == 'v') {
            ++v_count;
        }
    }
    CHECK(v_count == 3);
}

TEST_CASE("aucun port candidat : on n'ouvre rien, jamais de repli sur le dernier") {
    PortInfo souris;
    souris.path = "/dev/rfcomm0";  // ni VID/PID connu, ni nom plausible
    Rig rig({souris});
    rig.run_ms(5000);
    CHECK(rig.port->open_count == 0);
    CHECK(rig.drv->state() == LinkState::Disconnected);
}

TEST_CASE("le port choisi par l'operateur passe avant le VID/PID") {
    PortInfo arduino;
    arduino.path = "/dev/ttyACM0";
    arduino.vid = 0x2341;
    arduino.pid = 0x0043;
    arduino.has_ids = true;
    PortInfo autre;
    autre.path = "/dev/ttyUSB9";

    Rig rig({arduino, autre});
    rig.drv->set_preferred_port("/dev/ttyUSB9");
    rig.run_ms(20);
    CHECK(rig.port->last_path == "/dev/ttyUSB9");
}

// ===========================================================================
// Flux, watchdog et reconnexion — docs/01 §6
// ===========================================================================

TEST_CASE("les trames remontent au thread de jeu par la file SPSC") {
    Rig rig;
    rig.run_ms(40);
    REQUIRE(rig.drv->state() == LinkState::Identified);

    rig.port->emit("CD:3\r\nR:10,20,0,0,1234\r\nERROR:Command invalid q\r\n");
    rig.run_ms(20);

    std::vector<Frame> frames;
    rig.drain(frames);
    // La trame V: du handshake est aussi transmise : elle doit etre logguee.
    REQUIRE(frames.size() >= 4);
    bool saw_progress = false;
    bool saw_error = false;
    for (const Frame& f : frames) {
        if (f.kind == FrameKind::Progress && f.ticks[1] == 20 && f.elapsed_ms == 1234) {
            saw_progress = true;
        }
        if (f.kind == FrameKind::Error) {
            saw_error = true;
        }
    }
    CHECK(saw_progress);
    CHECK(saw_error);  // les trames d'erreur ne sont jamais avalees en silence
}

TEST_CASE("le watchdog ne se declenche PAS hors course") {
    // docs/01 §6.2 : hors course le silence est normal. Un watchdog toujours
    // arme afficherait une alerte permanente au repos.
    Rig rig;
    rig.run_ms(40);
    REQUIRE(rig.drv->state() == LinkState::Identified);
    rig.run_ms(5000);
    CHECK(rig.drv->state() == LinkState::Identified);
    CHECK(rig.drv->stats().watchdog_trips == 0);
}

TEST_CASE("le watchdog se declenche a 500 ms pendant une course") {
    Rig rig;
    rig.run_ms(40);
    rig.drv->set_race_active(true);
    rig.port->emit("R:1,1,0,0,10\r\n");
    rig.run_ms(20);
    REQUIRE(rig.drv->state() == LinkState::Identified);

    rig.run_ms(400);
    CHECK(rig.drv->state() == LinkState::Identified);
    rig.run_ms(150);  // total > 500 ms sans R:
    CHECK(rig.drv->state() == LinkState::LinkLost);
    CHECK(rig.drv->stats().watchdog_trips == 1);
}

TEST_CASE("un gel court : le lien revient et la course reprend") {
    // docs/01 §6.2 : les valeurs de R: etant absolues, rien n'est perdu.
    Rig rig;
    rig.run_ms(40);
    rig.drv->set_race_active(true);
    rig.port->emit("R:1,1,0,0,10\r\n");
    rig.run_ms(600);
    REQUIRE(rig.drv->state() == LinkState::LinkLost);

    rig.port->emit("R:60,58,0,0,700\r\n");
    rig.run_ms(20);
    CHECK(rig.drv->state() == LinkState::Identified);
    CHECK(rig.drv->stats().races_interrupted == 0);
}

TEST_CASE("un silence de plus de 3 s marque la course INTERROMPUE") {
    Rig rig;
    rig.run_ms(40);
    rig.drv->set_race_active(true);
    rig.port->emit("R:1,1,0,0,10\r\n");
    rig.run_ms(20);
    rig.port->answers_version = false;  // le boitier ne repond plus du tout

    rig.run_ms(4000);
    CHECK(rig.drv->stats().races_interrupted == 1);
}

TEST_CASE("le port disparait : LINK_LOST en course, DISCONNECTED au repos") {
    {
        Rig rig;
        rig.run_ms(40);
        rig.drv->set_race_active(true);
        rig.port->read_should_error = true;
        rig.run_ms(20);
        CHECK(rig.drv->state() == LinkState::LinkLost);
    }
    {
        Rig rig;
        rig.run_ms(40);
        rig.port->read_should_error = true;
        rig.run_ms(20);
        CHECK(rig.drv->state() == LinkState::Disconnected);
    }
}

TEST_CASE("reconnexion en course : le handshake n'emet PAS de s") {
    // Le point trouve en executant le scenario perte-lien/retour-lien de
    // ss_emu : rejouer le `s` abattrait la course qu'on vient de recuperer.
    Rig rig;
    rig.run_ms(40);
    REQUIRE(rig.drv->state() == LinkState::Identified);
    rig.drv->set_race_active(true);
    rig.port->emit("R:1,1,0,0,10\r\n");
    rig.run_ms(20);

    rig.port->written.clear();
    rig.port->read_should_error = true;
    rig.run_ms(20);
    REQUIRE(rig.drv->state() == LinkState::LinkLost);
    rig.port->read_should_error = false;

    rig.run_ms(3000);
    CHECK(rig.port->open_count >= 2);
    CHECK(rig.port->written.find('s') == std::string::npos);
    CHECK(rig.port->written.find('v') != std::string::npos);
}

TEST_CASE("reconnexion hors course : le s du handshake est bien emis") {
    Rig rig;
    rig.run_ms(40);
    rig.port->written.clear();
    rig.port->read_should_error = true;
    rig.run_ms(20);
    REQUIRE(rig.drv->state() == LinkState::Disconnected);
    rig.port->read_should_error = false;
    rig.run_ms(3000);
    CHECK(rig.port->written.find('s') != std::string::npos);
}

// ===========================================================================
// Emission de commandes
// ===========================================================================

TEST_CASE("une commande invalide est refusee AVANT d'atteindre le port") {
    Rig rig;
    rig.run_ms(40);
    rig.port->written.clear();
    std::string err;
    CHECK_FALSE(rig.drv->queue_command("t600", err));
    CHECK(err.find("t60") != std::string::npos);
    rig.run_ms(50);
    CHECK(rig.port->written.empty());
}

TEST_CASE("la sequence d'armement d'une course en distance part dans l'ordre") {
    // docs/01 §2 : d ou x, puis l ou t, puis g. Chaque commande terminee par
    // \\n et emise d'un bloc — tout octet intercale serait avale par le tampon
    // numerique du firmware.
    Rig rig;
    rig.run_ms(40);
    rig.port->written.clear();
    std::string err;
    REQUIRE(rig.drv->queue_command("d", err));
    REQUIRE(rig.drv->queue_command(make_length_command(100.0, 114.3), err));
    REQUIRE(rig.drv->queue_command("g", err));
    rig.run_ms(50);
    CHECK(rig.port->written == "d\nl278\ng\n");
}

TEST_CASE("la sequence d'armement en poursuite utilise t60") {
    Rig rig;
    rig.run_ms(40);
    rig.port->written.clear();
    std::string err;
    REQUIRE(rig.drv->queue_command("x", err));
    REQUIRE(rig.drv->queue_command(time_command(), err));
    REQUIRE(rig.drv->queue_command("g", err));
    rig.run_ms(50);
    CHECK(rig.port->written == "x\nt60\ng\n");
}

// ===========================================================================
// Etats atteints — docs/06 §1 : pas d'etat mort
// ===========================================================================

TEST_CASE("les quatre etats du lien sont atteints par les tests") {
    Rig rig;
    CHECK(rig.drv->state() == LinkState::Disconnected);
    rig.port->answers_version = false;
    rig.run_ms(20);
    CHECK(rig.drv->state() == LinkState::PortOpen);
    rig.port->answers_version = true;
    rig.run_ms(2200);
    CHECK(rig.drv->state() == LinkState::Identified);
    rig.drv->set_race_active(true);
    rig.port->emit("R:0,0,0,0,1\r\n");
    rig.run_ms(20);
    rig.run_ms(600);
    CHECK(rig.drv->state() == LinkState::LinkLost);
}

TEST_CASE("le watchdog ne tombe pas pendant le decompte, meme arme des le START") {
    // Regression du premier test d'integration sur pseudo-terminal : le
    // firmware n'emet aucun R: pendant les ~4 s de decompte. Un watchdog arme
    // au START tombait a CD:2, avant meme le depart.
    Rig rig;
    rig.run_ms(40);
    REQUIRE(rig.drv->state() == LinkState::Identified);

    rig.drv->set_race_active(true);  // l'UI arme des le clic sur START
    rig.port->emit("CD:3\r\n");
    rig.run_ms(1000);
    rig.port->emit("CD:2\r\n");
    rig.run_ms(1000);
    rig.port->emit("CD:1\r\n");
    rig.run_ms(1000);
    rig.port->emit("CD:0\r\n");
    rig.run_ms(1000);

    CHECK(rig.drv->state() == LinkState::Identified);
    CHECK(rig.drv->stats().watchdog_trips == 0);

    // La premiere trame R: arme reellement le watchdog.
    rig.port->emit("R:0,0,0,0,0\r\n");
    rig.run_ms(20);
    rig.run_ms(600);
    CHECK(rig.drv->state() == LinkState::LinkLost);
}
