// Réplique fidèle de ss_basic.ino — cwhitney/SilverSprint, commit 3a6157e,
// md5 bba3bc3980f90eecf67438183b2b1ed1, 323 lignes.
//
// Contrat : ce fichier reproduit le firmware BUGS COMPRIS (docs/07 §4). Aucun
// assainissement. Un émulateur qui corrige sa cible valide du code PC qui
// échouera sur le vrai matériel.
//
// Aucune dépendance système : ni horloge, ni E/S. L'horloge est injectée, donc
// les tests tournent en temps virtuel et une course de 60 s se rejoue en
// quelques millisecondes.
#pragma once

#include <array>
#include <cstddef>
#include <string>
#include <string_view>
#include <vector>

#include "avr_types.h"

namespace ssemu {

class FirmwareSim {
  public:
    static constexpr int kMaxRacers = 4;        // MAX_RACERS
    static constexpr int kFalseStartTicks = 4;  // FALSE_START_TICKS
    static constexpr const char* kVersion = "SS_v0.1.7";

    // Taille réelle du tampon firmware. On alloue plus large et on signale le
    // dépassement au lieu de reproduire un comportement indéfini (docs/07 §4.2).
    static constexpr std::size_t kCharBuffSize = 8;
    static constexpr std::size_t kCharBuffGuarded = 64;

    FirmwareSim() = default;

    // --- Liaison série -----------------------------------------------------
    void feed_rx(const std::uint8_t* data, std::size_t n);
    void feed_rx(std::string_view s);

    std::string drain_tx();
    bool tx_empty() const { return tx_.empty(); }

    // --- Broches -----------------------------------------------------------
    // Capteurs D2..D5, INPUT + pull-up : repos = HIGH, aimant devant = LOW.
    void set_sensor(int idx, bool high);
    bool sensor(int idx) const { return pin_sensor_[static_cast<std::size_t>(idx)]; }
    bool led_go(int idx) const { return pin_led_go_[static_cast<std::size_t>(idx)]; }
    bool led_status() const { return status_led_value_; }

    // --- Une itération de loop(), avec la valeur de millis() ---------------
    void tick(avr_ulong now_ms);

    // --- Observabilité pour les tests (pas d'équivalent matériel) ----------
    bool race_started() const { return race_started_; }
    bool race_starting() const { return race_starting_; }
    bool race_type_distance() const { return race_type_distance_; }
    bool mock_mode() const { return mock_mode_; }
    avr_int race_length_ticks() const { return race_length_ticks_; }
    avr_int race_length_secs() const { return race_length_secs_; }
    avr_int last_count_down() const { return last_count_down_; }
    avr_ulong racer_ticks(int idx) const { return racer_ticks_[static_cast<std::size_t>(idx)]; }
    avr_ulong racer_finish_ms(int idx) const {
        return racer_finish_ms_[static_cast<std::size_t>(idx)];
    }

    // Anomalies détectées dans l'usage du firmware par le PC. Un dépassement de
    // charBuff signalé ici EST un bug du driver PC : docs/01 §2 borne à 7 chiffres.
    const std::vector<std::string>& warnings() const { return warnings_; }

  private:
    void blink_led();
    void check_serial();
    void update_racer_ticks();
    void print_racer_update();
    void race_start();
    void check_distance_based();
    void check_time_based();

    void print(std::string_view s);
    void println(std::string_view s);
    void println_raw_char(avr_char c);

    static bool is_printable(avr_char c) { return c > 32 && c < 127; }

    // --- État, nommé comme dans le .ino ------------------------------------
    avr_ulong now_ = 0;  // millis()

    avr_ulong status_blink_interval_ = 250;
    bool status_led_value_ = false;  // LOW
    avr_ulong previous_status_blink_millis_ = 0;

    bool race_started_ = false;
    bool race_starting_ = false;
    bool mock_mode_ = false;
    avr_ulong race_start_millis_ = 0;
    avr_ulong current_time_millis_ = 0;

    avr_char val_ = 0;

    std::array<bool, kMaxRacers> pin_sensor_{true, true, true, true};
    std::array<bool, kMaxRacers> pin_led_go_{false, false, false, false};
    std::array<bool, kMaxRacers> previous_sensor_values_{true, true, true, true};
    // int values[4] = {0,0,0,0} — le firmware démarre à LOW, pas à HIGH.
    std::array<bool, kMaxRacers> values_{false, false, false, false};
    std::array<avr_ulong, kMaxRacers> racer_ticks_{0, 0, 0, 0};
    std::array<avr_ulong, kMaxRacers> racer_finish_ms_{0, 0, 0, 0};

    avr_ulong last_count_down_millis_ = 0;
    avr_int last_count_down_ = 0;

    std::array<char, kCharBuffGuarded> char_buff_{};
    std::size_t char_buff_pos_ = 0;
    bool receiving_race_length_ = false;
    bool receiving_time_length_ = false;

    avr_int race_length_ticks_ = 20;
    avr_int race_length_secs_ = 60;

    static constexpr avr_int kUpdateInterval = 10;
    avr_ulong last_update_millis_ = 0;

    std::array<float, kMaxRacers> mock_speeds_kph_{40.0f, 56.0f, 48.0f, 32.0f};

    bool race_type_distance_ = true;

    std::string rx_;
    std::size_t rx_pos_ = 0;
    std::string tx_;
    std::vector<std::string> warnings_;
};

}  // namespace ssemu
