#include "firmware_sim.h"

#include <cmath>

namespace ssemu {
namespace {

// Constante PI d'Arduino.h, à l'identique.
constexpr double kArduinoPi = 3.1415926535897932384626433832795;
constexpr double kMockRollerDiameterMm = 114.3;

constexpr bool kHigh = true;
constexpr bool kLow = false;

}  // namespace

// ---------------------------------------------------------------- transport

void FirmwareSim::feed_rx(const std::uint8_t* data, std::size_t n) {
    rx_.append(reinterpret_cast<const char*>(data), n);
}

void FirmwareSim::feed_rx(std::string_view s) { rx_.append(s); }

std::string FirmwareSim::drain_tx() {
    std::string out;
    out.swap(tx_);
    return out;
}

void FirmwareSim::set_sensor(int idx, bool high) {
    if (idx >= 0 && idx < kMaxRacers) {
        pin_sensor_[static_cast<std::size_t>(idx)] = high;
    }
}

void FirmwareSim::print(std::string_view s) { tx_.append(s); }

void FirmwareSim::println(std::string_view s) {
    tx_.append(s);
    tx_.append("\r\n");
}

// Serial.println(char) d'Arduino émet L'OCTET, pas son code décimal. Pour un
// caractère non imprimable la ligne contient donc un octet de contrôle brut.
void FirmwareSim::println_raw_char(avr_char c) {
    tx_.push_back(static_cast<char>(static_cast<std::uint8_t>(c)));
    tx_.append("\r\n");
}

// ---------------------------------------------------------------- blinkLED

void FirmwareSim::blink_led() {
    if (now_ - previous_status_blink_millis_ > status_blink_interval_) {
        previous_status_blink_millis_ = now_;
        status_led_value_ = !status_led_value_;
    }
}

// -------------------------------------------------------------- checkSerial

void FirmwareSim::check_serial() {
    // Serial.available() > 0 : un seul octet consommé par tour de loop().
    if (rx_pos_ >= rx_.size()) {
        return;
    }
    val_ = static_cast<avr_char>(static_cast<std::uint8_t>(rx_[rx_pos_]));
    ++rx_pos_;
    if (rx_pos_ == rx_.size()) {
        rx_.clear();
        rx_pos_ = 0;
    }

    if (val_ == '\r' || val_ == '\n') {
        if (receiving_race_length_) {
            receiving_race_length_ = false;
            char_buff_[char_buff_pos_] = '\0';
            race_length_ticks_ = avr_atoi(char_buff_.data());
            print("L:");
            println(avr_fmt(race_length_ticks_));
        } else if (receiving_time_length_) {
            receiving_time_length_ = false;
            char_buff_[char_buff_pos_] = '\0';
            race_length_secs_ = avr_atoi(char_buff_.data());
        }
        return;
    }

    if (receiving_race_length_ || receiving_time_length_) {
        // Le firmware n'a AUCUNE garde ici : charBuffPos dépasse charBuff[8] en
        // silence. On signale au lieu de reproduire un comportement indéfini.
        if (char_buff_pos_ >= kCharBuffSize - 1) {
            warnings_.push_back("EMU-WARN: charBuff overflow (pos=" +
                                std::to_string(char_buff_pos_) +
                                ") — le driver PC doit borner a 7 chiffres, docs/01 §2");
        }
        if (char_buff_pos_ < kCharBuffGuarded - 1) {
            char_buff_[char_buff_pos_] = static_cast<char>(val_);
            ++char_buff_pos_;
        }
        return;
    }

    switch (val_) {
        case 'l':
            char_buff_.fill('\0');
            char_buff_pos_ = 0;
            receiving_race_length_ = true;
            break;
        case 't':
            char_buff_.fill('\0');
            char_buff_pos_ = 0;
            receiving_time_length_ = true;
            break;
        case 'v':
            print("V:");
            println(kVersion);
            break;
        case 'g':
            for (std::size_t i = 0; i < kMaxRacers; ++i) {
                racer_ticks_[i] = 0;
                racer_finish_ms_[i] = 0;
            }
            race_starting_ = true;
            race_started_ = false;
            last_count_down_ = 4;
            last_count_down_millis_ = now_;
            break;
        case 'm':
            mock_mode_ = !mock_mode_;
            println(mock_mode_ ? "M:ON" : "M:OFF");
            break;
        case 's':
            race_started_ = false;
            race_starting_ = false;
            pin_led_go_.fill(false);
            break;
        case 'x':
            race_type_distance_ = false;
            break;
        case 'd':
            race_type_distance_ = true;
            break;
        default:
            print("ERROR:Command invalid ");
            if (is_printable(val_)) {
                println_raw_char(val_);
            } else {
                print("ERROR:Unprintable ASCII code ");
                println_raw_char(val_);
            }
            break;
    }
}

// --------------------------------------------------------- updateRacerTicks

void FirmwareSim::update_racer_ticks() {
    for (std::size_t i = 0; i < kMaxRacers; ++i) {
        previous_sensor_values_[i] = values_[i];
        values_[i] = pin_sensor_[i];

        if (mock_mode_) {
            racer_ticks_[i] = static_cast<avr_ulong>(
                std::floor(static_cast<double>(current_time_millis_) *
                           static_cast<double>(mock_speeds_kph_[i]) * 0.2778 /
                           (kMockRollerDiameterMm * kArduinoPi)));
        }

        // Front montant uniquement. AUCUN anti-rebond : un rebond de contact
        // produit un tick fantôme, c'est la raison d'être du filtre PC (01 §6.3).
        if (values_[i] == kHigh && previous_sensor_values_[i] == kLow) {
            ++racer_ticks_[i];
        }
    }
}

// -------------------------------------------------------- printRacerUpdate

void FirmwareSim::print_racer_update() {
    if (avr_ulong_gt_int(current_time_millis_ - last_update_millis_, kUpdateInterval)) {
        last_update_millis_ = current_time_millis_;
        print("R:");
        for (std::size_t i = 0; i < kMaxRacers; ++i) {
            print(avr_fmt(racer_ticks_[i]));
            print(",");
        }
        println(avr_fmt(current_time_millis_));
    }
}

// ---------------------------------------------------------------- raceStart

void FirmwareSim::race_start() {
    race_start_millis_ = now_;
    // Fidèle : lastUpdateMillis reçoit une valeur ABSOLUE alors qu'il sera
    // comparé à un temps RELATIF. La première trame R: part donc immédiatement.
    last_update_millis_ = race_start_millis_;

    race_starting_ = false;
    race_started_ = true;

    for (std::size_t i = 0; i < kMaxRacers; ++i) {
        racer_ticks_[i] = 0;
        racer_finish_ms_[i] = 0;
    }
    pin_led_go_.fill(true);
}

// ------------------------------------------------------- checkDistanceBased

void FirmwareSim::check_distance_based() {
    bool finished = true;
    for (std::size_t i = 0; i < kMaxRacers; ++i) {
        if (racer_finish_ms_[i] == 0 &&
            avr_ulong_ge_int(racer_ticks_[i], race_length_ticks_)) {
            racer_finish_ms_[i] = current_time_millis_;
            print(avr_fmt(static_cast<avr_int>(i)));
            print("F:");
            println(avr_fmt(racer_finish_ms_[i]));
            pin_led_go_[i] = false;
        }
        if (racer_finish_ms_[i] == 0) {
            finished = false;
        }
    }
    // Attend LES QUATRE pistes matérielles. Avec 2 capteurs câblés, cette
    // condition n'est jamais vraie : c'est le bug d'usage majeur de la v1,
    // et la raison pour laquelle le PC est autoritaire (docs/01 §5.1).
    if (finished) {
        race_starting_ = false;
        race_started_ = false;
    }
}

// ----------------------------------------------------------- checkTimeBased

void FirmwareSim::check_time_based() {
    // raceLengthSecs * 1000 : multiplication de deux int 16 bits. Déborde dès
    // 33 s, devient négatif, et la comparaison avec un unsigned long le change
    // en une valeur énorme. La course ne se termine alors jamais (docs/01 §5.5).
    const avr_int limit_ms = avr_mul(race_length_secs_, 1000);
    if (avr_ulong_gt_int(current_time_millis_, limit_ms)) {
        race_started_ = false;
        for (std::size_t i = 0; i < kMaxRacers; ++i) {
            print(avr_fmt(static_cast<avr_int>(i)));
            print("F:");
            println(avr_fmt(limit_ms));
        }
        race_starting_ = false;
        race_started_ = false;
    }
}

// --------------------------------------------------------------------- loop

void FirmwareSim::tick(avr_ulong now_ms) {
    now_ = now_ms;

    blink_led();
    check_serial();

    if (race_starting_) {
        for (std::size_t i = 0; i < kMaxRacers; ++i) {
            values_[i] = pin_sensor_[i];
            if (racer_ticks_[i] < static_cast<avr_ulong>(kFalseStartTicks)) {
                if (values_[i] == kHigh && previous_sensor_values_[i] == kLow) {
                    ++racer_ticks_[i];
                    if (racer_ticks_[i] == static_cast<avr_ulong>(kFalseStartTicks)) {
                        print("FS:");
                        println(avr_fmt(static_cast<avr_int>(i)));
                        pin_led_go_[i] = false;
                    }
                }
            }
            previous_sensor_values_[i] = values_[i];
        }
        if (now_ - last_count_down_millis_ > 1000) {
            last_count_down_ = static_cast<avr_int>(last_count_down_ - 1);
            last_count_down_millis_ = now_;
            print("CD:");
            println(avr_fmt(last_count_down_));
        }
        if (last_count_down_ == 0) {
            race_start();
        }
    }
    // Pas de `else` : raceStart() vient peut-être de basculer raceStarted, et le
    // firmware enchaîne dans la même itération de loop().
    if (race_started_) {
        current_time_millis_ = now_ - race_start_millis_;

        update_racer_ticks();

        if (race_type_distance_) {
            check_distance_based();
        } else {
            check_time_based();
        }

        print_racer_update();
    }
}

}  // namespace ssemu
