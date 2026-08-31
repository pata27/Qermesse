// Découpage du flux série en lignes, et parsing des trames de docs/01 §3.
//
// C++ PUR : aucun include Godot, aucune allocation sur le chemin chaud, aucune
// exception. C'est la condition pour que la CI le teste par un binaire natif,
// sans lancer le moteur — et pour qu'il puisse tourner dans le thread de
// lecture, où l'API Godot est interdite (docs/01 §6.1).
#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <string>

namespace sslink {

enum class FrameKind : int {
    Progress = 0,    // R:<t0>,<t1>,<t2>,<t3>,<elapsedMs>
    Countdown,       // CD:<n>
    FalseStart,      // FS:<idx>
    RiderFinish,     // <idx>F:<ms>
    LengthAck,       // L:<ticks>
    MockAck,         // M:ON / M:OFF
    Version,         // V:<version>
    Error,           // ERROR:...
    KioskStart,      // G seul — jamais emis par ss_basic.ino, docs/01 §3
    KioskStop,       // S seul — idem
    Unknown,         // tout le reste : loggue, ne leve jamais
};

const char* frame_kind_name(FrameKind k);

// Type trivialement copiable : c'est ce qui transite par le ring buffer, donc
// il ne doit RIEN allouer. Le texte vit dans un tampon fixe, tronque au besoin —
// une trame inconnue est faite pour etre logguee, pas conservee integralement.
struct Frame {
    static constexpr std::size_t kTextMax = 96;

    FrameKind kind = FrameKind::Unknown;

    std::array<std::uint32_t, 4> ticks{};  // Progress
    std::uint32_t elapsed_ms = 0;          // Progress
    int value = 0;                         // Countdown : n ; FalseStart/RiderFinish : idx
    std::uint32_t finish_ms = 0;           // RiderFinish
    std::int32_t length_ticks = 0;         // LengthAck — peut etre negatif, docs/01 §2
    bool mock_on = false;                  // MockAck
    bool text_truncated = false;

    // Rempli pour Version, Error et Unknown seulement — jamais pour Progress.
    // Toujours termine par NUL, toujours ASCII imprimable (octets echappes).
    std::array<char, kTextMax> text{};

    // Confort pour les tests et les journaux. Hors chemin chaud.
    std::string text_str() const { return std::string(text.data()); }
};

// Analyse une ligne deja debarrassee de son terminateur.
Frame parse_line(const std::uint8_t* data, std::size_t n);
Frame parse_line(const char* s);

// Assemble les octets en lignes. Tolere \r\n, \n seul, trames coupees entre
// deux lectures, et octets non-UTF-8 en plein milieu.
class LineAssembler {
  public:
    // Le firmware n'emet jamais de ligne longue ; au-dela, c'est du bruit.
    static constexpr std::size_t kMaxLine = 256;

    // Rend le nombre de trames produites. `sink` est appele pour chacune.
    template <typename Sink>
    std::size_t feed(const std::uint8_t* data, std::size_t n, Sink&& sink) {
        std::size_t produced = 0;
        for (std::size_t i = 0; i < n; ++i) {
            const std::uint8_t c = data[i];
            if (c == '\n' || c == '\r') {
                if (len_ > 0 || pending_) {
                    if (!overflowed_) {
                        sink(parse_line(line_.data(), len_));
                        ++produced;
                    } else {
                        ++dropped_overlong_;
                    }
                }
                len_ = 0;
                overflowed_ = false;
                pending_ = false;
                continue;
            }
            pending_ = true;
            if (len_ < kMaxLine) {
                line_[len_++] = c;
            } else {
                overflowed_ = true;
            }
        }
        return produced;
    }

    void reset() {
        len_ = 0;
        overflowed_ = false;
        pending_ = false;
    }

    std::size_t dropped_overlong() const { return dropped_overlong_; }
    std::size_t pending_bytes() const { return len_; }

  private:
    std::array<std::uint8_t, kMaxLine> line_{};
    std::size_t len_ = 0;
    std::size_t dropped_overlong_ = 0;
    bool overflowed_ = false;
    bool pending_ = false;
};

}  // namespace sslink
