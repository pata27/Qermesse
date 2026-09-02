// Selection du port serie — docs/01 §5 et docs/03 : port choisi, puis allowlist
// VID/PID, puis motif de nom. JAMAIS de repli sur « le dernier port de la
// liste », qui etait le comportement de la v1 et qui branchait le logiciel sur
// n'importe quoi.
//
// Ce fichier est le filet de J1 : l'allowlist sera amendee avec le VID/PID du
// boitier reel, et l'ordre de confiance ne doit pas bouger a cette occasion.
#include "doctest.h"

#include <string>
#include <vector>

#include "port_selection.h"
#include "serial_port.h"

using namespace sslink;

namespace {

PortInfo port(const std::string& path, std::uint16_t vid = 0, std::uint16_t pid = 0) {
    PortInfo p;
    p.path = path;
    p.vid = vid;
    p.pid = pid;
    p.has_ids = vid != 0 || pid != 0;
    return p;
}

}  // namespace

TEST_CASE("l'allowlist connait les cartes Uno officielles et leurs clones") {
    CHECK(is_known_usb_id(0x2341, 0x0043));  // Uno R3 officiel
    CHECK(is_known_usb_id(0x1A86, 0x7523));  // CH340, le clone le plus repandu
    CHECK(is_known_usb_id(0x0403, 0x6001));  // FTDI FT232R
    CHECK_FALSE(is_known_usb_id(0x1234, 0x5678));
    CHECK_FALSE(is_known_usb_id(0, 0));
}

TEST_CASE("les noms de port plausibles des trois OS sont reconnus, les autres non") {
    CHECK(name_looks_like_serial("/dev/ttyACM0"));
    CHECK(name_looks_like_serial("/dev/ttyUSB1"));
    CHECK(name_looks_like_serial("/dev/cu.usbmodem14201"));
    CHECK(name_looks_like_serial("/dev/tty.usbserial-A50285BI"));
    CHECK(name_looks_like_serial("COM3"));
    CHECK(name_looks_like_serial("COM12"));

    CHECK_FALSE(name_looks_like_serial("/dev/ttyS0"));  // port integre, pas USB
    CHECK_FALSE(name_looks_like_serial("/dev/pts/3"));  // pseudo-terminal : seul l'operateur peut le choisir
    CHECK_FALSE(name_looks_like_serial("/dev/null"));
    CHECK_FALSE(name_looks_like_serial("COM"));  // pas de numero
}

TEST_CASE("le classement va du plus sur au moins sur : choisi, VID/PID, nom") {
    std::vector<PortInfo> ports = {
        port("/dev/ttyUSB0"),                 // nom plausible seulement
        port("/dev/ttyACM0", 0x2341, 0x0043),  // VID/PID connu
        port("/dev/ttyACM1", 0x1A86, 0x7523),  // VID/PID connu, choisi par l'operateur
    };
    auto ranked = rank_candidates(ports, "/dev/ttyACM1", {});

    REQUIRE(ranked.size() == 3);
    CHECK(ranked[0].info.path == "/dev/ttyACM1");
    CHECK(ranked[0].reason == SelectionReason::Preferred);
    CHECK(ranked[1].info.path == "/dev/ttyACM0");
    CHECK(ranked[1].reason == SelectionReason::UsbId);
    CHECK(ranked[2].info.path == "/dev/ttyUSB0");
    CHECK(ranked[2].reason == SelectionReason::NamePattern);
}

TEST_CASE("aucun repli : un port qui ne coche aucun critere n'est pas un candidat") {
    // Le bug de la v1 : « prendre le dernier port de la liste ». Trente-deux
    // ports sur une machine de developpement, aucun ne doit etre retenu.
    std::vector<PortInfo> ports;
    for (int i = 0; i < 32; ++i) {
        ports.push_back(port("/dev/ttyS" + std::to_string(i)));
    }
    ports.push_back(port("/dev/pts/7"));
    ports.push_back(port("/dev/ttyUSB9", 0x1234, 0x5678));  // nom plausible MAIS ids inconnus

    auto ranked = rank_candidates(ports, "", {});

    // Le nom plausible reste un critere : ttyUSB9 est retenu pour son nom,
    // pas pour ses identifiants. Les 33 autres sont ecartes.
    REQUIRE(ranked.size() == 1);
    CHECK(ranked[0].info.path == "/dev/ttyUSB9");
    CHECK(ranked[0].reason == SelectionReason::NamePattern);
}

TEST_CASE("un port choisi par l'operateur est essaye meme absent de l'enumeration") {
    // L'emulateur parle sur un pseudo-terminal, qui n'est pas dans
    // /sys/class/tty : le choix humain explicite prime sur l'enumeration.
    auto ranked = rank_candidates({}, "/dev/pts/4", {});
    REQUIRE(ranked.size() == 1);
    CHECK(ranked[0].info.path == "/dev/pts/4");
    CHECK(ranked[0].reason == SelectionReason::Preferred);
}

TEST_CASE("un port blackliste pour ce cycle est exclu, meme choisi par l'operateur") {
    std::vector<PortInfo> ports = {port("/dev/ttyACM0", 0x2341, 0x0043)};
    auto ranked = rank_candidates(ports, "/dev/ttyACM0", {"/dev/ttyACM0"});
    CHECK(ranked.empty());
    // Et le port force absent de l'enumeration n'echappe pas non plus a la liste noire.
    auto forced = rank_candidates({}, "/dev/pts/4", {"/dev/pts/4"});
    CHECK(forced.empty());
}

TEST_CASE("chaque motif a un libelle lisible par l'operateur") {
    // Le panneau Materiel affiche ce libelle a cote du port : un motif sans
    // texte se lirait comme un port sans explication.
    for (SelectionReason r : {SelectionReason::None, SelectionReason::Preferred,
                              SelectionReason::UsbId, SelectionReason::NamePattern}) {
        const char* name = selection_reason_name(r);
        REQUIRE(name != nullptr);
        CHECK(std::string(name).size() > 3);
    }
    CHECK(std::string(selection_reason_name(SelectionReason::UsbId)) == "VID/PID connu");
}
