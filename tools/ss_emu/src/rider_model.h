// Cyclistes synthétiques : produisent les fronts sur les broches capteurs D2..D5.
//
// Le modèle est déterministe à graine fixée — c'est ce qui rend un scénario
// rejouable, donc utilisable comme preuve reproductible (docs/07 §7).
#pragma once

#include <array>
#include <cstdint>
#include <string>
#include <utility>
#include <vector>

namespace ssemu {

class FirmwareSim;

// Diamètre par défaut du rouleau, docs/01 §7.
inline constexpr double kDefaultRollerMm = 114.3;

struct RiderSpec {
    double cruise_kph = 45.0;    // vitesse de croisière visée
    double accel_kph_s = 22.0;   // montée en régime
    double fatigue_kph_min = 0.0;  // perte de vitesse par minute
    double jitter_pct = 1.5;     // gigue de cadence, en % de la vitesse
    double surge_at_s = -1.0;    // instant d'une accélération finale
    double surge_kph = 0.0;      // gain de vitesse à cet instant
    double stop_at_s = -1.0;     // abandon
    // Paliers de vitesse : {instant, nouvelle croisiere}. Le dernier palier
    // atteint REMPLACE la croisiere — c'est ainsi qu'un peloton se defait puis
    // se recolle. `link_sim.gd` a le meme mecanisme sous le nom `SCHEDULES` ;
    // les deux simulateurs doivent offrir les memes profils, sans quoi une
    // commande qui marche avec l'un echoue avec l'autre (docs/03 §5).
    std::vector<std::pair<double, double>> steps;
};

struct Profile {
    std::string name;
    std::string description;
    std::array<RiderSpec, 4> riders;
};

// Profils exigés par docs/03 §5 et docs/07 §5.
const std::vector<Profile>& profiles();
const Profile* find_profile(const std::string& name);

class RiderModel {
  public:
    RiderModel(const Profile& profile, int wired_riders, double roller_mm, std::uint32_t seed);

    // Avance le modèle jusqu'à t_ms et pose l'état des quatre capteurs.
    void update(double t_ms, FirmwareSim& fw);

    // Les riders ne pédalent qu'une fois la course lancée. Le passage à true
    // remet distances et compteurs à zéro, comme raceStart() côté firmware.
    void set_race_running(bool running, double t_ms);
    bool race_running() const { return running_; }

    // Le rider pédale pendant le décompte : provoque un FS:<i>.
    void set_false_start(int rider, bool on);
    // Rebond de contact : un front parasite, sans que le rouleau ait tourné.
    void inject_phantom_tick(int rider);
    // Fige le monde physique : plus aucun rider ne bouge.
    void set_frozen(bool frozen) { frozen_ = frozen; }

    double circumference_mm() const { return circumference_mm_; }
    int wired_riders() const { return wired_; }
    double distance_m(int rider) const;
    double speed_kph(int rider) const { return last_speed_[std::size_t(rider)]; }
    std::uint32_t ticks(int rider) const { return ticks_[std::size_t(rider)]; }

  private:
    double speed_at(int rider, double t_s) const;
    double noise(int rider, double t_s) const;

    Profile profile_;
    int wired_;
    double circumference_mm_;
    std::uint32_t seed_;
    bool frozen_ = false;

    // Le contact reste fermé quelques millisecondes : sans cela, le front
    // pourrait tomber entre deux tours de loop() et le tick serait perdu.
    static constexpr double kPulseLowMs = 2.0;

    bool running_ = false;
    double race_start_ms_ = 0.0;
    double last_t_ms_ = 0.0;
    std::array<double, 4> distance_mm_{};
    std::array<double, 4> next_tick_mm_{};
    std::array<double, 4> low_until_ms_{};
    std::array<double, 4> last_speed_{};
    std::array<std::uint32_t, 4> ticks_{};
    std::array<bool, 4> false_start_{};
};

}  // namespace ssemu
