#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include "doctest.h"

#include <regex>
#include <string>

#include "harness.h"

using ssemu::avr_mul;
using ssemu::avr_ulong_gt_int;
using ssemu::test::Harness;

// ===========================================================================
// Arithmétique AVR — la cause racine des trois contresens de docs/01
// ===========================================================================

TEST_CASE("avr_mul deborde comme un int 16 bits") {
    CHECK(avr_mul(30, 1000) == 30000);
    CHECK(avr_mul(32, 1000) == 32000);
    // 33000 ne tient pas dans un int16 : 33000 - 65536 = -32536
    CHECK(avr_mul(33, 1000) == -32536);
    // 60000 - 65536 = -5536, la valeur qui casse le mode temps par defaut
    CHECK(avr_mul(60, 1000) == -5536);
    CHECK(avr_mul(300, 1000) == -27680);
}

TEST_CASE("un int negatif compare a un unsigned long devient enorme") {
    // C'est ce qui rend la condition de checkTimeBased() inatteignable.
    CHECK(avr_ulong_gt_int(1000u, 30000) == false);
    CHECK(avr_ulong_gt_int(31000u, 30000) == true);
    CHECK(avr_ulong_gt_int(4000000000u, -5536) == false);
    CHECK(avr_ulong_gt_int(4294961759u, -5536) == false);
    CHECK(avr_ulong_gt_int(4294961761u, -5536) == true);  // ~49,7 jours
}

TEST_CASE("avr_atoi se replie modulo 2^16") {
    CHECK(ssemu::avr_atoi("278") == 278);
    CHECK(ssemu::avr_atoi("32767") == 32767);
    CHECK(ssemu::avr_atoi("32768") == -32768);
    CHECK(ssemu::avr_atoi("99999") == -31073);  // 99999 mod 65536 = 34463
}

// ===========================================================================
// Commandes et accuses de reception — docs/01 §2 et §3
// ===========================================================================

TEST_CASE("v repond la version") {
    Harness h;
    h.send("v\n");
    h.run_ms(5);
    CHECK(h.out() == "V:SS_v0.1.7\r\n");
}

TEST_CASE("l<ticks> est acquitte par L:<ticks>") {
    Harness h;
    h.send("l278\n");
    h.run_ms(5);
    CHECK(h.out() == "L:278\r\n");
    CHECK(h.fw.race_length_ticks() == 278);
}

TEST_CASE("t, d, x et s n'accusent rien") {
    Harness h;
    h.send("t60\nd");
    h.run_ms(5);
    CHECK(h.fw.race_length_secs() == 60);
    CHECK(h.fw.race_type_distance() == true);
    h.send("x");
    h.run_ms(2);
    CHECK(h.fw.race_type_distance() == false);
    h.send("s");
    h.run_ms(2);
    CHECK(h.out().empty());
}

TEST_CASE("m bascule le mock interne") {
    Harness h;
    h.send("m");
    h.run_ms(2);
    CHECK(h.out() == "M:ON\r\n");
    CHECK(h.fw.mock_mode());
    h.clear_out();
    h.send("m");
    h.run_ms(2);
    CHECK(h.out() == "M:OFF\r\n");
}

TEST_CASE("un \\n isole ne produit aucune erreur") {
    Harness h;
    h.send("\n\r\n");
    h.run_ms(5);
    CHECK(h.out().empty());
}

TEST_CASE("commande inconnue imprimable : ERROR:Command invalid <c>") {
    Harness h;
    h.send("q");
    h.run_ms(2);
    CHECK(h.out() == "ERROR:Command invalid q\r\n");
}

TEST_CASE("commande inconnue non imprimable : double prefixe et OCTET BRUT") {
    // docs/01 §3 anomalie 1 : Serial.println(char) emet le caractere, pas son
    // code decimal. Le parseur PC doit survivre a un octet de controle en
    // plein milieu d'une ligne.
    Harness h;
    const std::uint8_t raw = 0x01;
    h.fw.feed_rx(&raw, 1);
    h.run_ms(2);
    std::string expected = "ERROR:Command invalid ERROR:Unprintable ASCII code ";
    expected.push_back(static_cast<char>(0x01));
    expected += "\r\n";
    CHECK(h.out() == expected);
}

TEST_CASE("un octet >127 part aussi en branche non imprimable (char signe sur AVR)") {
    Harness h;
    const std::uint8_t raw = 0xE9;  // 'é' en latin-1, negatif en char signe
    h.fw.feed_rx(&raw, 1);
    h.run_ms(2);
    CHECK(h.saw("ERROR:Unprintable ASCII code "));
}

// ===========================================================================
// Bornage de l/t — docs/01 §2
// ===========================================================================

TEST_CASE("une valeur > 32767 se replie et devient absurde") {
    // Justifie la borne 1..32767 imposee au driver PC. Sans elle, une course
    // de 99999 ticks devient une course de -31073 ticks.
    Harness h;
    h.send("l99999\n");
    h.run_ms(10);
    CHECK(h.fw.race_length_ticks() == -31073);
    CHECK(h.out() == "L:-31073\r\n");
}

TEST_CASE("un argument de 8 chiffres deborde charBuff et est signale") {
    // Sur le vrai AVR c'est un comportement indefini. L'emulateur transforme
    // l'UB en alarme : ce message ne doit JAMAIS apparaitre en fonctionnement
    // normal — s'il apparait, le driver PC a un bug (docs/07 §4.2).
    Harness h;
    CHECK(h.fw.warnings().empty());
    h.send("l12345678\n");
    h.run_ms(20);
    CHECK_FALSE(h.fw.warnings().empty());
    CHECK(h.fw.warnings().front().find("charBuff overflow") != std::string::npos);
}

TEST_CASE("7 chiffres passent sans avertissement") {
    Harness h;
    h.send("l1234567\n");
    h.run_ms(20);
    CHECK(h.fw.warnings().empty());
}

// ===========================================================================
// Decompte — docs/01 §2 et docs/02 (timeout ARMING)
// ===========================================================================

TEST_CASE("le premier CD: arrive APRES 1000 ms, pas avant") {
    // C'est la raison du passage du timeout ARMING de 1 s a 2 s (docs/02).
    Harness h;
    h.send("g");
    h.run_ms(2);
    CHECK(h.fw.race_starting());
    h.run_ms(998);  // t = 1000 ms
    CHECK(h.out().empty());
    h.run_ms(5);  // t = 1005 ms
    CHECK(h.out() == "CD:3\r\n");
}

TEST_CASE("le decompte complet dure ~4 s et se termine par CD:0 puis le depart") {
    Harness h;
    h.send("g");
    h.run_ms(3900);
    CHECK(h.saw("CD:3"));
    CHECK(h.saw("CD:2"));
    CHECK(h.saw("CD:1"));
    CHECK_FALSE(h.saw("CD:0"));
    CHECK(h.fw.race_starting());
    h.run_ms(200);  // t ~ 4100 ms
    CHECK(h.saw("CD:0"));
    CHECK(h.fw.race_started());
    CHECK_FALSE(h.fw.race_starting());
    for (int i = 0; i < 4; ++i) {
        CHECK(h.fw.led_go(i));
    }
}

TEST_CASE("la premiere trame R: part des le tour de boucle du depart") {
    // Fidele au bug lastUpdateMillis = raceStartMillis (absolu) compare a
    // currentTimeMillis (relatif).
    Harness h;
    h.send("g");
    h.run_ms(4005);
    const std::string& o = h.out();
    const std::size_t cd0 = o.find("CD:0\r\n");
    REQUIRE(cd0 != std::string::npos);
    CHECK(o.find("R:0,0,0,0,0\r\n", cd0) == cd0 + 6);
}

// ===========================================================================
// Faux depart — docs/01 §5.3
// ===========================================================================

TEST_CASE("4 fronts pendant le decompte declenchent FS:<i> une seule fois") {
    Harness h;
    h.send("g");
    h.run_ms(50);
    h.pedal(0, 3);
    CHECK_FALSE(h.saw("FS:0"));
    h.pedal(0, 1);
    CHECK(h.count("FS:0\r\n") == 1);
    CHECK_FALSE(h.fw.led_go(0));
    h.pedal(0, 10);
    CHECK(h.count("FS:0\r\n") == 1);
}

TEST_CASE("le depart rallume la LED du faux-partant et remet ses ticks a zero") {
    // Quirk firmware : la sanction du faux depart est effacee par raceStart().
    // C'est pourquoi docs/02 §4 confie la politique de faux depart au PC.
    Harness h;
    h.send("g");
    h.run_ms(50);
    h.pedal(0, 4);
    REQUIRE(h.saw("FS:0"));
    REQUIRE_FALSE(h.fw.led_go(0));
    h.run_ms(4100);
    CHECK(h.fw.race_started());
    CHECK(h.fw.led_go(0));
    CHECK(h.fw.racer_ticks(0) == 0);
}

// ===========================================================================
// Comptage des ticks — docs/01 §1 et §6.3
// ===========================================================================

TEST_CASE("un tick par front montant, et rien sur le front descendant") {
    Harness h;
    h.send("x\nt600\ng\n");
    h.run_ms(4200);
    REQUIRE(h.fw.race_started());
    CHECK(h.fw.racer_ticks(0) == 0);
    h.fw.set_sensor(0, false);
    h.run_ms(5);
    CHECK(h.fw.racer_ticks(0) == 0);  // front descendant : rien
    h.fw.set_sensor(0, true);
    h.run_ms(5);
    CHECK(h.fw.racer_ticks(0) == 1);  // front montant : un tick
    h.run_ms(50);
    CHECK(h.fw.racer_ticks(0) == 1);  // niveau stable : rien
}

TEST_CASE("aucun anti-rebond : un rebond de contact produit un tick fantome") {
    // Raison d'etre du filtre PC de docs/01 §6.3.
    Harness h;
    h.send("x\nt600\ng\n");
    h.run_ms(4200);
    h.pedal(0, 1);
    REQUIRE(h.fw.racer_ticks(0) == 1);
    h.bounce(0);
    CHECK(h.fw.racer_ticks(0) == 2);
}

TEST_CASE("format de la trame R: et cadence ~100 Hz") {
    Harness h;
    h.send("x\nt600\ng\n");
    h.run_ms(4100);
    h.clear_out();
    h.run_ms(1000);
    const std::regex re(R"(^R:\d+,\d+,\d+,\d+,\d+$)");
    int frames = 0;
    for (const std::string& line : h.lines()) {
        CHECK(std::regex_match(line, re));
        ++frames;
    }
    // updateInterval = 10 ms, strictement superieur : ~91 trames par seconde.
    CHECK(frames >= 80);
    CHECK(frames <= 100);
}

// ===========================================================================
// LE bug de la v1 — docs/01 §5.1
// ===========================================================================

TEST_CASE("mode distance a 2 capteurs cables : la course ne se termine JAMAIS") {
    // Le firmware attend les QUATRE pistes. C'est le bug d'usage majeur de la
    // v1 et la raison pour laquelle le PC devient autoritaire en v3.
    Harness h;
    h.send("d\nl5\ng\n");
    h.run_ms(4200);
    REQUIRE(h.fw.race_started());
    h.pedal(0, 10);
    h.pedal(1, 10);
    h.run_ms(2000);

    CHECK(h.saw("0F:"));
    CHECK(h.saw("1F:"));
    CHECK_FALSE(h.saw("2F:"));
    CHECK_FALSE(h.saw("3F:"));
    CHECK(h.fw.race_started());  // <-- toujours en course

    h.clear_out();
    h.run_ms(1000);
    CHECK(h.saw("R:"));  // et le flux R: continue indefiniment
}

TEST_CASE("mode distance a 4 capteurs : la course se termine et le flux R: s'arrete") {
    Harness h;
    h.send("d\nl5\ng\n");
    h.run_ms(4200);
    REQUIRE(h.fw.race_started());
    for (int r = 0; r < 4; ++r) {
        h.pedal(r, 10);
    }
    h.run_ms(100);
    for (int r = 0; r < 4; ++r) {
        CHECK(h.saw(std::to_string(r) + "F:"));
    }
    CHECK_FALSE(h.fw.race_started());

    // docs/01 §3 anomalie 6 : le silence sur R: n'est pas une perte de lien.
    h.clear_out();
    h.run_ms(1000);
    CHECK(h.out().empty());
}

// ===========================================================================
// LE bug decouvert en v3 — docs/01 §5.5
// ===========================================================================

TEST_CASE("mode temps a 30 s : le firmware termine bien") {
    Harness h;
    h.send("x\nt30\ng\n");
    h.run_ms(4100);
    REQUIRE(h.fw.race_started());
    h.run_ms(30100);
    CHECK(h.saw("0F:30000"));
    CHECK(h.saw("3F:30000"));
    CHECK_FALSE(h.fw.race_started());
}

TEST_CASE("mode temps a 60 s (le defaut !) : le firmware ne termine JAMAIS") {
    // raceLengthSecs * 1000 deborde l'int16 et vaut -5536, converti en
    // ~49,7 jours a la comparaison. Consequence normative : en mode temps, le
    // PC est SEUL juge. La 'double detection' de docs/02 §2 n'existait pas.
    Harness h;
    h.send("x\nt60\ng\n");
    h.run_ms(4100);
    REQUIRE(h.fw.race_started());
    h.run_ms(70000);  // bien au-dela des 60 s demandees
    CHECK_FALSE(h.saw("F:"));
    CHECK(h.fw.race_started());
}

TEST_CASE("le plafond t<300> du mode poursuite est inoperant") {
    // docs/02 §3 : le garde-fou anti-course-infinie est entierement cote PC.
    Harness h;
    h.send("x\nt300\ng\n");
    h.run_ms(4100);
    h.run_ms(310000);
    CHECK_FALSE(h.saw("F:"));
    CHECK(h.fw.race_started());
}

TEST_CASE("aucune trame <i>F: negative n'est atteignable") {
    // docs/01 §3 anomalie 5 : la branche existe mais est morte, puisque toute
    // valeur qui deborde rend la condition inatteignable. Le parseur doit
    // quand meme la classer en Unknown si un firmware variant l'emettait.
    for (int secs : {33, 60, 300, 3600}) {
        Harness h;
        h.send("x\nt" + std::to_string(secs) + "\ng\n");
        h.run_ms(4100);
        h.run_ms(40000);
        CAPTURE(secs);
        CHECK_FALSE(h.saw("F:-"));
        CHECK_FALSE(h.saw("F:"));
    }
}

// ===========================================================================
// Arret
// ===========================================================================

TEST_CASE("s arrete la course et eteint les quatre LED") {
    Harness h;
    h.send("x\nt600\ng\n");
    h.run_ms(4100);
    REQUIRE(h.fw.race_started());
    REQUIRE(h.fw.led_go(2));
    h.send("s");
    h.run_ms(5);
    CHECK_FALSE(h.fw.race_started());
    CHECK_FALSE(h.fw.race_starting());
    for (int i = 0; i < 4; ++i) {
        CHECK_FALSE(h.fw.led_go(i));
    }
    h.clear_out();
    h.run_ms(500);
    CHECK(h.out().empty());
}

TEST_CASE("s pendant le decompte annule le depart") {
    Harness h;
    h.send("g");
    h.run_ms(2500);
    REQUIRE(h.fw.race_starting());
    h.send("s");
    h.run_ms(5);
    CHECK_FALSE(h.fw.race_starting());
    h.clear_out();
    h.run_ms(3000);
    CHECK(h.out().empty());
}

// ===========================================================================
// Heartbeat
// ===========================================================================

TEST_CASE("la LED d'etat clignote a 250 ms") {
    Harness h;
    const bool initial = h.fw.led_status();
    h.run_ms(200);
    CHECK(h.fw.led_status() == initial);
    h.run_ms(100);  // t = 300 ms
    CHECK(h.fw.led_status() != initial);
}

// ===========================================================================
// Cadrage des commandes — le piege qui a fait tomber neuf tests a l'ecriture
// ===========================================================================

TEST_CASE("tout octet suivant l ou t est avale par le tampon numerique") {
    // Tant que le terminateur n'est pas arrive, checkSerial() range CHAQUE
    // octet dans charBuff, y compris les espaces et les commandes suivantes.
    // "x t60 g" ne demarre donc aucune course : le 'g' finit dans le nombre.
    // Le driver PC doit emettre l<chiffres>\n et t<chiffres>\n sans rien
    // inserer, et attendre le terminateur avant la commande suivante.
    Harness h;
    h.send("t60 g\n");
    h.run_ms(20);
    CHECK_FALSE(h.fw.race_starting());
    CHECK_FALSE(h.fw.race_started());
    CHECK(h.fw.race_length_secs() == 60);  // atoi s'arrete au premier non-chiffre
    CHECK(h.out().empty());                // et aucune ERROR: n'est emise

    // Cadrage correct.
    Harness ok;
    ok.send("x\nt60\ng\n");
    ok.run_ms(20);
    CHECK(ok.fw.race_starting());
    CHECK(ok.fw.race_length_secs() == 60);
    CHECK_FALSE(ok.fw.race_type_distance());
}
