#include "doctest.h"

#include <cmath>
#include <string>

#include "faults.h"
#include "harness.h"
#include "rider_model.h"

using namespace ssemu;

namespace {

// Boucle d'entraînement minimale : le même enchaînement que main.cpp, en temps
// virtuel. Sert à prouver que modèle et firmware s'accordent bout en bout.
struct Rig {
    FirmwareSim fw;
    RiderModel model;
    double sim_ms = 0.0;
    std::string out;
    static constexpr int kIters = 10;

    Rig(const std::string& profile, int wired, std::uint32_t seed = 42)
        : model(*find_profile(profile), wired, kDefaultRollerMm, seed) {}

    void send(std::string_view s) { fw.feed_rx(s); }

    void run_ms(double duration) {
        const double target = sim_ms + duration;
        while (sim_ms < target) {
            model.set_race_running(fw.race_started(), sim_ms);
            for (int k = 0; k < kIters; ++k) {
                model.update(sim_ms + double(k) / kIters, fw);
                fw.tick(std::uint32_t(sim_ms));
            }
            out += fw.drain_tx();
            sim_ms += 1.0;
        }
    }

    bool saw(std::string_view n) const { return out.find(n) != std::string::npos; }
};

}  // namespace

// ===========================================================================
// Profils
// ===========================================================================

TEST_CASE("les cinq profils de docs/07 §5 existent") {
    for (const char* n :
         {"egaux", "ecart-leger", "domination", "remontee-finale", "abandon"}) {
        CAPTURE(n);
        CHECK(find_profile(n) != nullptr);
    }
    CHECK(find_profile("inexistant") == nullptr);
    CHECK(profiles().size() == 5);
}

TEST_CASE("circonference : 114.3 mm donne bien 359.0 mm") {
    RiderModel m(*find_profile("egaux"), 2, kDefaultRollerMm, 1);
    CHECK(m.circumference_mm() == doctest::Approx(359.08).epsilon(0.001));
}

// ===========================================================================
// Modele physique
// ===========================================================================

TEST_CASE("un rider a ~45 km/h produit un nombre de ticks plausible") {
    Rig rig("egaux", 2);
    rig.send("x\nt60\ng\n");
    rig.run_ms(4200);
    REQUIRE(rig.fw.race_started());
    rig.run_ms(10000);
    // 45 km/h pendant 10 s = 125 m, moins la phase d'acceleration (~2 s).
    // 125 m / 0.35908 m = 348 ticks ; on tolere large, le profil a de la gigue.
    const std::uint32_t t = rig.fw.racer_ticks(0);
    CAPTURE(t);
    CHECK(t > 250);
    CHECK(t < 360);
}

TEST_CASE("les pistes non cablees ne produisent jamais un seul tick") {
    // Configuration du boitier de l'utilisateur : deux capteurs.
    Rig rig("egaux", 2);
    rig.send("x\nt60\ng\n");
    rig.run_ms(20000);
    CHECK(rig.fw.racer_ticks(0) > 0);
    CHECK(rig.fw.racer_ticks(1) > 0);
    CHECK(rig.fw.racer_ticks(2) == 0);
    CHECK(rig.fw.racer_ticks(3) == 0);
}

TEST_CASE("le modele est deterministe a graine fixee") {
    // La gigue est petite et de moyenne nulle : deux graines donnent souvent le
    // meme nombre entier de ticks. C'est la trajectoire de vitesse qu'il faut
    // comparer, pas son integrale arrondie.
    auto trace = [](std::uint32_t seed) {
        Rig rig("ecart-leger", 4, seed);
        rig.send("x\nt60\ng\n");
        rig.run_ms(4200);
        std::vector<double> v;
        for (int i = 0; i < 20; ++i) {
            rig.run_ms(500);
            v.push_back(rig.model.speed_kph(0));
        }
        return v;
    };
    const std::vector<double> a = trace(42);
    const std::vector<double> b = trace(42);
    const std::vector<double> c = trace(7);
    CHECK(a == b);
    CHECK(a != c);
}

TEST_CASE("les rouleaux sont a l'arret tant que la course n'est pas partie") {
    Rig rig("domination", 4);
    rig.run_ms(5000);  // aucune commande envoyee
    for (int r = 0; r < 4; ++r) {
        CHECK(rig.fw.racer_ticks(r) == 0);
    }
    rig.send("g");
    rig.run_ms(3500);  // en plein decompte
    for (int r = 0; r < 4; ++r) {
        CHECK(rig.fw.racer_ticks(r) == 0);  // aucun faux depart involontaire
    }
}

TEST_CASE("profil abandon : le rider 1 s'arrete net a mi-course") {
    Rig rig("abandon", 4);
    rig.send("x\nt60\ng\n");
    rig.run_ms(4200);
    rig.run_ms(19000);  // t course ~ 19 s, juste avant l'arret a 20 s
    const std::uint32_t before = rig.fw.racer_ticks(1);
    CHECK(before > 0);
    rig.run_ms(2000);  // franchit les 20 s
    const std::uint32_t at_stop = rig.fw.racer_ticks(1);
    rig.run_ms(8000);
    CHECK(rig.fw.racer_ticks(1) == at_stop);   // plus aucun tick
    CHECK(rig.fw.racer_ticks(0) > at_stop);    // les autres continuent
}

TEST_CASE("profil domination : le rider 1 creuse un ecart net") {
    Rig rig("domination", 4);
    rig.send("x\nt60\ng\n");
    rig.run_ms(4200);
    rig.run_ms(30000);
    const double lead = rig.model.distance_m(1);
    const double back = rig.model.distance_m(0);
    CAPTURE(lead);
    CAPTURE(back);
    CHECK(lead - back > 50.0);  // depasse le G par defaut du mode poursuite
}

TEST_CASE("un tick fantome injecte incremente le compteur sans mouvement") {
    Rig rig("egaux", 2);
    rig.send("x\nt60\ng\n");
    rig.run_ms(4200);
    rig.run_ms(2000);
    const std::uint32_t before = rig.fw.racer_ticks(2);  // piste non cablee : fige
    CHECK(before == 0);
    rig.model.inject_phantom_tick(2);
    rig.run_ms(20);
    CHECK(rig.fw.racer_ticks(2) == 1);
}

TEST_CASE("faux depart : le rider pedale pendant le decompte et declenche FS:") {
    Rig rig("egaux", 2);
    rig.model.set_false_start(0, true);
    rig.send("g");
    rig.run_ms(2000);
    CHECK(rig.saw("FS:0\r\n"));
}

// ===========================================================================
// Bout en bout : LE bug de la v1, vu depuis le modele physique
// ===========================================================================

TEST_CASE("course en distance a 2 capteurs : les riders finissent, pas la course") {
    Rig rig("egaux", 2);
    rig.send("d\nl278\ng\n");  // 100 m avec un rouleau de 114.3 mm
    rig.run_ms(4200);
    REQUIRE(rig.fw.race_started());
    rig.run_ms(20000);
    CHECK(rig.saw("0F:"));
    CHECK(rig.saw("1F:"));
    CHECK(rig.fw.race_started());  // le firmware attend deux pistes fantomes
}

TEST_CASE("course en distance a 4 capteurs : la course se termine") {
    Rig rig("egaux", 4);
    rig.send("d\nl278\ng\n");
    rig.run_ms(4200);
    rig.run_ms(20000);
    for (int r = 0; r < 4; ++r) {
        CHECK(rig.saw(std::to_string(r) + "F:"));
    }
    CHECK_FALSE(rig.fw.race_started());
}

// ===========================================================================
// Injection de pannes — analyse des specifications
// ===========================================================================

TEST_CASE("parse_fault accepte les formes valides") {
    Fault f;
    std::string err;

    REQUIRE(parse_fault("faux-depart=2", f, err));
    CHECK(f.kind == FaultKind::FalseStart);
    CHECK(f.rider == 2);

    REQUIRE(parse_fault("perte-lien@8", f, err));
    CHECK(f.kind == FaultKind::LinkLoss);
    CHECK(f.at_s == doctest::Approx(8.0));

    REQUIRE(parse_fault("retour-lien@10.5s", f, err));
    CHECK(f.at_s == doctest::Approx(10.5));

    REQUIRE(parse_fault("gel@12=800", f, err));
    CHECK(f.kind == FaultKind::Freeze);
    CHECK(f.at_s == doctest::Approx(12.0));
    CHECK(f.param == doctest::Approx(800.0));

    REQUIRE(parse_fault("tick-fantome=3@4", f, err));
    CHECK(f.kind == FaultKind::PhantomTick);
    CHECK(f.rider == 3);
    CHECK(f.at_s == doctest::Approx(4.0));
}

TEST_CASE("parse_fault rejette les formes invalides avec un message utile") {
    Fault f;
    std::string err;
    CHECK_FALSE(parse_fault("panne-imaginaire@3", f, err));
    CHECK(err.find("inconnue") != std::string::npos);

    CHECK_FALSE(parse_fault("faux-depart", f, err));
    CHECK(err.find("rider") != std::string::npos);

    CHECK_FALSE(parse_fault("faux-depart=9", f, err));
    CHECK(err.find("0..3") != std::string::npos);

    CHECK_FALSE(parse_fault("perte-lien", f, err));
    CHECK(err.find("instant") != std::string::npos);

    CHECK_FALSE(parse_fault("gel@12", f, err));
    CHECK(err.find("duree") != std::string::npos);

    CHECK_FALSE(parse_fault("perte-lien@bientot", f, err));
    CHECK(err.find("illisible") != std::string::npos);
}

TEST_CASE("chaque panne n'est rendue qu'une fois, et rearm() rejoue le scenario") {
    FaultEngine e;
    Fault a;
    std::string err;
    REQUIRE(parse_fault("perte-lien@5", a, err));
    e.add(a);
    REQUIRE(parse_fault("retour-lien@7", a, err));
    e.add(a);
    REQUIRE(parse_fault("faux-depart=1", a, err));
    e.add(a);

    CHECK(e.due(1.0).empty());
    CHECK(e.due(5.0).size() == 1);
    CHECK(e.due(6.0).empty());
    CHECK(e.due(7.5).size() == 1);
    CHECK(e.due(99.0).empty());

    // Le faux depart n'est jamais rendu par due() : il vit pendant le decompte.
    CHECK(e.pre_race().size() == 1);
    CHECK(e.pre_race().front().rider == 1);

    e.rearm();
    CHECK(e.due(9.0).size() == 2);
}
