#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include "doctest.h"

#include <string>
#include <vector>

#include "line_parser.h"

using namespace sslink;

namespace {

std::vector<Frame> feed_all(LineAssembler& a, const std::string& bytes) {
    std::vector<Frame> out;
    a.feed(reinterpret_cast<const std::uint8_t*>(bytes.data()), bytes.size(),
           [&](const Frame& f) { out.push_back(f); });
    return out;
}

}  // namespace

// ===========================================================================
// Contrat de type : ce qui traverse le ring buffer ne doit rien allouer
// ===========================================================================

TEST_CASE("Frame est trivialement copiable, donc utilisable dans la file SPSC") {
    CHECK(std::is_trivially_copyable<Frame>::value);
}

// ===========================================================================
// Toutes les trames de docs/01 §3
// ===========================================================================

TEST_CASE("R: — ticks cumules et horloge firmware") {
    const Frame f = parse_line("R:12,0,345,6789,10203");
    REQUIRE(f.kind == FrameKind::Progress);
    CHECK(f.ticks[0] == 12);
    CHECK(f.ticks[1] == 0);
    CHECK(f.ticks[2] == 345);
    CHECK(f.ticks[3] == 6789);
    CHECK(f.elapsed_ms == 10203);
}

TEST_CASE("R: — les valeurs sont ABSOLUES, jamais des deltas") {
    // docs/01 §3 : perdre une trame est sans effet, l'etat est ecrase.
    const Frame a = parse_line("R:100,100,0,0,1000");
    const Frame b = parse_line("R:250,240,0,0,2000");
    CHECK(b.ticks[0] - a.ticks[0] == 150);  // le delta se CALCULE, il n'arrive pas
}

TEST_CASE("CD: — decompte") {
    for (int n : {3, 2, 1, 0}) {
        const Frame f = parse_line(("CD:" + std::to_string(n)).c_str());
        CAPTURE(n);
        REQUIRE(f.kind == FrameKind::Countdown);
        CHECK(f.value == n);
    }
}

TEST_CASE("FS: — faux depart, index borne a 0..3") {
    const Frame f = parse_line("FS:2");
    REQUIRE(f.kind == FrameKind::FalseStart);
    CHECK(f.value == 2);
    CHECK(parse_line("FS:4").kind == FrameKind::Unknown);
    CHECK(parse_line("FS:").kind == FrameKind::Unknown);
}

TEST_CASE("<idx>F: — arrivee, parse sans decoupe naive sur ':'") {
    // docs/01 §3 anomalie 2 : un split(':') confondrait ces trames.
    for (int i = 0; i < 4; ++i) {
        const std::string line = std::to_string(i) + "F:9002";
        const Frame f = parse_line(line.c_str());
        CAPTURE(line);
        REQUIRE(f.kind == FrameKind::RiderFinish);
        CHECK(f.value == i);
        CHECK(f.finish_ms == 9002);
    }
    CHECK(parse_line("4F:100").kind == FrameKind::Unknown);
    CHECK(parse_line("F:100").kind == FrameKind::Unknown);
}

TEST_CASE("<idx>F: negatif — classe Unknown, jamais leve") {
    // docs/01 §3 anomalie 5 : branche morte cote firmware, mais un boitier
    // reflashe pourrait l'emettre. On loggue, on ne casse pas.
    const Frame f = parse_line("0F:-5536");
    CHECK(f.kind == FrameKind::Unknown);
    CHECK(f.text_str() == "0F:-5536");
}

TEST_CASE("L: — accuse de longueur, y compris negatif") {
    CHECK(parse_line("L:278").kind == FrameKind::LengthAck);
    CHECK(parse_line("L:278").length_ticks == 278);
    // docs/01 §2 : atoi replie modulo 2^16, le firmware acquitte la valeur repliee.
    CHECK(parse_line("L:-31073").length_ticks == -31073);
}

TEST_CASE("M: — accuse du mock firmware") {
    CHECK(parse_line("M:ON").mock_on == true);
    CHECK(parse_line("M:ON").kind == FrameKind::MockAck);
    CHECK(parse_line("M:OFF").mock_on == false);
    CHECK(parse_line("M:OFF").kind == FrameKind::MockAck);
    CHECK(parse_line("M:MAYBE").kind == FrameKind::Unknown);
}

TEST_CASE("V: — version, seule preuve qu'on parle au bon boitier") {
    const Frame f = parse_line("V:SS_v0.1.7");
    REQUIRE(f.kind == FrameKind::Version);
    CHECK(f.text_str() == "SS_v0.1.7");
}

TEST_CASE("G et S seuls — mode kiosque, reconnus et loggues") {
    // docs/01 §3 anomalie 3 : jamais emis par ss_basic.ino. On les parse pour
    // ne pas les confondre avec du bruit, sans rien en faire.
    CHECK(parse_line("G").kind == FrameKind::KioskStart);
    CHECK(parse_line("S").kind == FrameKind::KioskStop);
    CHECK(parse_line("GG").kind == FrameKind::Unknown);
}

// ===========================================================================
// Les cas tordus — c'est pour eux que ce parseur existe
// ===========================================================================

TEST_CASE("ERROR: sur commande imprimable") {
    const Frame f = parse_line("ERROR:Command invalid q");
    REQUIRE(f.kind == FrameKind::Error);
    CHECK(f.text_str() == "ERROR:Command invalid q");
}

TEST_CASE("ERROR: malforme a double prefixe, avec octet BRUT") {
    // docs/01 §3 anomalie 1 : Serial.println(char) emet l'octet, pas son code.
    std::string line = "ERROR:Command invalid ERROR:Unprintable ASCII code ";
    line.push_back(char(0x01));
    const Frame f = parse_line(reinterpret_cast<const std::uint8_t*>(line.data()), line.size());
    REQUIRE(f.kind == FrameKind::Error);
    // L'octet de controle est echappe : sortir de l'UTF-8 invalide vers une
    // String Godot planterait le moteur.
    CHECK(f.text_str() == "ERROR:Command invalid ERROR:Unprintable ASCII code \\x01");
}

TEST_CASE("une trame sans ':' ne fait pas tomber le parseur") {
    // docs/01 §3 anomalie 4.
    CHECK(parse_line("bonjour").kind == FrameKind::Unknown);
    CHECK(parse_line("").kind == FrameKind::Unknown);
    CHECK(parse_line(":::::").kind == FrameKind::Unknown);
}

TEST_CASE("R: malformee — champs manquants, en trop, ou non numeriques") {
    CHECK(parse_line("R:1,2,3,4").kind == FrameKind::Unknown);        // 4 champs
    CHECK(parse_line("R:1,2,3,4,5,6").kind == FrameKind::Unknown);    // 6 champs
    CHECK(parse_line("R:1,2,,4,5").kind == FrameKind::Unknown);       // champ vide
    CHECK(parse_line("R:1,2,3,4,-5").kind == FrameKind::Unknown);     // negatif
    CHECK(parse_line("R:1,2,3,4,abc").kind == FrameKind::Unknown);    // non numerique
    CHECK(parse_line("R:").kind == FrameKind::Unknown);
    CHECK(parse_line("R:99999999999,0,0,0,0").kind == FrameKind::Unknown);  // deborde 32 bits
}

TEST_CASE("la trame corrompue exacte produite par ss_emu est absorbee") {
    const std::string line = std::string("R:\x01\x99\xC3 42,,", 10);
    const Frame f = parse_line(reinterpret_cast<const std::uint8_t*>(line.data()), line.size());
    CHECK(f.kind == FrameKind::Unknown);
    CHECK(f.text_str() == "R:\\x01\\x99\\xC3 42,,");
}

TEST_CASE("un texte tres long est tronque, jamais deborde") {
    const std::string line(500, 'x');
    const Frame f = parse_line(reinterpret_cast<const std::uint8_t*>(line.data()), line.size());
    CHECK(f.kind == FrameKind::Unknown);
    CHECK(f.text_truncated);
    CHECK(f.text_str().size() < Frame::kTextMax);
}

// ===========================================================================
// Assemblage du flux
// ===========================================================================

TEST_CASE("decoupe sur \\r\\n") {
    LineAssembler a;
    const auto frames = feed_all(a, "V:SS_v0.1.7\r\nCD:3\r\nR:1,2,3,4,5\r\n");
    REQUIRE(frames.size() == 3);
    CHECK(frames[0].kind == FrameKind::Version);
    CHECK(frames[1].kind == FrameKind::Countdown);
    CHECK(frames[2].kind == FrameKind::Progress);
}

TEST_CASE("une trame coupee entre deux lectures est recollee") {
    // Le cas qui casse tous les parseurs naifs : une lecture serie ne rend pas
    // des lignes, elle rend des octets.
    LineAssembler a;
    auto f1 = feed_all(a, "R:10,20,3");
    CHECK(f1.empty());
    CHECK(a.pending_bytes() == 9);
    auto f2 = feed_all(a, "0,40,555\r\n");
    REQUIRE(f2.size() == 1);
    CHECK(f2[0].kind == FrameKind::Progress);
    CHECK(f2[0].ticks[2] == 30);
    CHECK(f2[0].elapsed_ms == 555);
}

TEST_CASE("decoupe octet par octet — le pire cas") {
    LineAssembler a;
    const std::string stream = "CD:2\r\nR:1,1,1,1,99\r\n0F:4242\r\n";
    std::vector<Frame> frames;
    for (char c : stream) {
        const auto u = static_cast<std::uint8_t>(c);
        a.feed(&u, 1, [&](const Frame& f) { frames.push_back(f); });
    }
    REQUIRE(frames.size() == 3);
    CHECK(frames[0].kind == FrameKind::Countdown);
    CHECK(frames[1].kind == FrameKind::Progress);
    CHECK(frames[2].kind == FrameKind::RiderFinish);
    CHECK(frames[2].finish_ms == 4242);
}

TEST_CASE("un \\n seul suffit, et les lignes vides sont ignorees") {
    LineAssembler a;
    const auto frames = feed_all(a, "\r\n\r\nCD:1\n\n\nCD:0\n");
    REQUIRE(frames.size() == 2);
    CHECK(frames[0].value == 1);
    CHECK(frames[1].value == 0);
}

TEST_CASE("une ligne tronquee sans terminateur reste en attente, sans rien casser") {
    // Panne ligne-tronquee de ss_emu : la ligne suivante la recolle. Le
    // parseur classe le tout en Unknown et le flux repart.
    LineAssembler a;
    auto f = feed_all(a, "R:99,99,99,99");
    CHECK(f.empty());
    f = feed_all(a, "R:1,2,3,4,5\r\nCD:3\r\n");
    REQUIRE(f.size() == 2);
    CHECK(f[0].kind == FrameKind::Unknown);   // les deux lignes collees
    CHECK(f[1].kind == FrameKind::Countdown); // et le flux est resynchronise
}

TEST_CASE("une ligne demesurement longue est jetee, comptee, et n'empeche pas la suite") {
    LineAssembler a;
    const std::string flood(LineAssembler::kMaxLine * 3, 'A');
    auto f = feed_all(a, flood + "\r\nCD:3\r\n");
    REQUIRE(f.size() == 1);
    CHECK(f[0].kind == FrameKind::Countdown);
    CHECK(a.dropped_overlong() == 1);
}

TEST_CASE("des octets nuls en plein flux ne coupent rien") {
    LineAssembler a;
    std::string s = "R:1,2,3,4,5\r\n";
    s.push_back('\0');
    s += "CD:3\r\n";
    const auto frames = feed_all(a, s);
    REQUIRE(frames.size() == 2);
    CHECK(frames[0].kind == FrameKind::Progress);
    CHECK(frames[1].kind == FrameKind::Unknown);  // "\0CD:3" -> echappe, loggue
    CHECK(frames[1].text_str() == "\\x00CD:3");
}
