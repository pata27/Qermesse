#include "rider_model.h"

#include <algorithm>
#include <cmath>

#include "firmware_sim.h"

namespace ssemu {
namespace {

RiderSpec idle_rider() {
    RiderSpec s;
    s.cruise_kph = 0.0;
    s.accel_kph_s = 0.0;
    s.jitter_pct = 0.0;
    return s;
}

RiderSpec rider(double cruise, double accel = 22.0, double fatigue = 0.0, double jitter = 1.5) {
    RiderSpec s;
    s.cruise_kph = cruise;
    s.accel_kph_s = accel;
    s.fatigue_kph_min = fatigue;
    s.jitter_pct = jitter;
    return s;
}

std::vector<Profile> build_profiles() {
    std::vector<Profile> v;

    Profile egaux{"egaux", "Ecarts sous le metre — eprouve le photo-finish", {}};
    egaux.riders = {rider(45.0), rider(44.92), rider(45.06), rider(44.97)};
    v.push_back(egaux);

    Profile leger{"ecart-leger", "Un rider 5 % plus rapide", {}};
    leger.riders = {rider(45.0), rider(47.25), rider(44.6), rider(45.3)};
    v.push_back(leger);

    Profile domination{"domination", "Un rider tres superieur — fin rapide en poursuite", {}};
    domination.riders = {rider(40.0), rider(55.0, 26.0), rider(41.5), rider(39.0)};
    v.push_back(domination);

    Profile remontee{"remontee-finale", "Le retardataire repasse devant dans les derniers metres",
                     {}};
    remontee.riders = {rider(48.0, 24.0, 6.0), rider(43.0), rider(44.0), rider(43.5)};
    remontee.riders[1].surge_at_s = 25.0;
    remontee.riders[1].surge_kph = 12.0;
    v.push_back(remontee);

    Profile abandon{"abandon", "Un rider s'arrete net a mi-course", {}};
    abandon.riders = {rider(45.0), rider(46.0), rider(44.0), rider(45.5)};
    abandon.riders[1].stop_at_s = 20.0;
    v.push_back(abandon);

    // PROFILS DE PARTITION — ajoutes au lot 5 pour eprouver l'ecran scindé,
    // et repris ici a l'identique de `link_sim.gd`. Sans eux, ces scenarios ne
    // pouvaient etre joues qu'a travers le simulateur GDScript, qui
    // court-circuite la couche serie : la scene 3D n'avait jamais tourne sur un
    // peloton qui se defait EN PASSANT PAR un vrai pseudo-terminal.
    Profile deux{"deux-groupes", "Deux paquets nets — la cassure tombe entre 2 et 3", {}};
    deux.riders = {rider(52.0), rider(51.4), rider(40.0), rider(39.6)};
    v.push_back(deux);

    Profile eparpille{"eparpille", "Quatre coureurs qui s'egrenent — quatre volets", {}};
    eparpille.riders = {rider(52.0), rider(47.0), rider(42.0), rider(37.0)};
    v.push_back(eparpille);

    Profile trois{"trois-plus-un", "Trois ensemble, un lache", {}};
    trois.riders = {rider(46.0), rider(46.3), rider(45.8), rider(38.0)};
    v.push_back(trois);

    Profile deux_un_un{"deux-un-un", "Deux ensemble, puis deux laches separement", {}};
    deux_un_un.riders = {rider(50.0), rider(50.3), rider(44.0), rider(38.0)};
    v.push_back(deux_un_un);

    Profile un_un_deux{"un-un-deux", "Un solo devant un isole devant une paire", {}};
    un_un_deux.riders = {rider(52.0), rider(46.0), rider(40.0), rider(40.2)};
    v.push_back(un_un_deux);

    Profile casse{"casse-par-etapes", "Le peloton se defait un coureur a la fois", {}};
    casse.riders = {rider(46.0), rider(46.0), rider(46.0), rider(46.0)};
    casse.riders[3].steps = {{5.0, 36.0}};
    casse.riders[2].steps = {{11.0, 40.0}};
    casse.riders[1].steps = {{17.0, 42.0}};
    v.push_back(casse);

    Profile accordeon{"accordeon", "Il se defait puis SE RECOLLE", {}};
    accordeon.riders = {rider(46.0), rider(46.0), rider(46.0), rider(46.0)};
    accordeon.riders[3].steps = {{2.0, 38.0}, {14.0, 58.0}};
    accordeon.riders[2].steps = {{4.0, 41.0}, {17.0, 55.0}};
    accordeon.riders[1].steps = {{6.0, 43.0}, {20.0, 52.0}};
    v.push_back(accordeon);

    return v;
}

}  // namespace

const std::vector<Profile>& profiles() {
    static const std::vector<Profile> kProfiles = build_profiles();
    return kProfiles;
}

const Profile* find_profile(const std::string& name) {
    for (const Profile& p : profiles()) {
        if (p.name == name) {
            return &p;
        }
    }
    return nullptr;
}

RiderModel::RiderModel(const Profile& profile, int wired_riders, double roller_mm,
                       std::uint32_t seed)
    : profile_(profile),
      wired_(std::clamp(wired_riders, 0, 4)),
      circumference_mm_(roller_mm * 3.14159265358979323846),
      seed_(seed) {
    // Les pistes non câblées sont un connecteur vide : la broche reste à HIGH,
    // exactement comme sur le boîtier de l'utilisateur (docs/07 §5).
    for (int i = wired_; i < 4; ++i) {
        profile_.riders[std::size_t(i)] = idle_rider();
    }
    next_tick_mm_.fill(circumference_mm_);
    low_until_ms_.fill(-1.0);
}

// Bruit lisse et déterministe : somme de sinusoïdes incommensurables, décalées
// par la graine. Pas de générateur aléatoire, donc pas d'état à resynchroniser.
double RiderModel::noise(int rider, double t_s) const {
    const double phase = double(seed_ % 1000) * 0.017 + double(rider) * 1.7;
    return 0.6 * std::sin(t_s * 2.3 + phase) + 0.3 * std::sin(t_s * 7.1 + phase * 1.9) +
           0.1 * std::sin(t_s * 17.3 + phase * 0.4);
}

double RiderModel::speed_at(int rider, double t_s) const {
    const RiderSpec& s = profile_.riders[std::size_t(rider)];
    if (s.cruise_kph <= 0.0) {
        return 0.0;
    }
    if (s.stop_at_s >= 0.0 && t_s >= s.stop_at_s) {
        return 0.0;
    }
    double v = s.cruise_kph;
    for (const std::pair<double, double>& step : s.steps) {
        if (t_s >= step.first) {
            v = step.second;
        }
    }
    if (s.accel_kph_s > 0.0) {
        v = std::min(v, s.accel_kph_s * t_s);
    }
    v -= s.fatigue_kph_min * (t_s / 60.0);
    if (s.surge_at_s >= 0.0 && t_s >= s.surge_at_s) {
        v += s.surge_kph;
    }
    v += v * (s.jitter_pct / 100.0) * noise(rider, t_s);
    return std::max(0.0, v);
}

double RiderModel::distance_m(int r) const {
    return double(ticks_[std::size_t(r)]) * circumference_mm_ / 1000.0;
}

void RiderModel::set_false_start(int rider, bool on) {
    if (rider >= 0 && rider < 4) {
        false_start_[std::size_t(rider)] = on;
    }
}

void RiderModel::inject_phantom_tick(int rider) {
    if (rider >= 0 && rider < 4) {
        low_until_ms_[std::size_t(rider)] = last_t_ms_ + kPulseLowMs;
    }
}

void RiderModel::set_race_running(bool running, double t_ms) {
    if (running == running_) {
        return;
    }
    running_ = running;
    if (running) {
        race_start_ms_ = t_ms;
        distance_mm_.fill(0.0);
        next_tick_mm_.fill(circumference_mm_);
        ticks_.fill(0);
    }
}

void RiderModel::update(double t_ms, FirmwareSim& fw) {
    const double dt_ms = t_ms - last_t_ms_;
    last_t_ms_ = t_ms;
    if (dt_ms <= 0.0) {
        return;
    }
    // Temps relatif au départ : hors course, les rouleaux sont à l'arrêt.
    const double t_s = running_ ? (t_ms - race_start_ms_) / 1000.0 : -1.0;

    for (int i = 0; i < 4; ++i) {
        const std::size_t u = std::size_t(i);

        // Le faux départ fait pédaler avant le départ : le monde physique ignore
        // l'état de la FSM firmware, exactement comme la réalité.
        double kph = 0.0;
        if (!frozen_) {
            if (t_s >= 0.0) {
                kph = speed_at(i, t_s);
            } else if (false_start_[u] && i < wired_) {
                kph = 12.0;
            }
        }
        last_speed_[u] = kph;

        // 1 km/h = 1000000 mm / 3600000 ms = 0.277778 mm/ms
        distance_mm_[u] += kph * 0.2777777777777778 * dt_ms;
        if (distance_mm_[u] >= next_tick_mm_[u]) {
            next_tick_mm_[u] += circumference_mm_;
            low_until_ms_[u] = t_ms + kPulseLowMs;
            ++ticks_[u];
        }

        fw.set_sensor(i, !(t_ms < low_until_ms_[u]));
    }
}

}  // namespace ssemu
