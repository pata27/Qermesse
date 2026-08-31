#include "line_parser.h"

namespace sslink {
namespace {

bool starts_with(const std::uint8_t* d, std::size_t n, const char* prefix) {
    std::size_t i = 0;
    for (; prefix[i] != '\0'; ++i) {
        if (i >= n || d[i] != static_cast<std::uint8_t>(prefix[i])) {
            return false;
        }
    }
    return true;
}

bool is_digit(std::uint8_t c) { return c >= '0' && c <= '9'; }

// Exige QUE des chiffres, et au moins un. Toute permissivite ici finirait par
// laisser passer une trame corrompue pour une mesure valide.
bool parse_u32(const std::uint8_t* d, std::size_t n, std::uint32_t& out) {
    if (n == 0 || n > 10) {
        return false;
    }
    std::uint64_t acc = 0;
    for (std::size_t i = 0; i < n; ++i) {
        if (!is_digit(d[i])) {
            return false;
        }
        acc = acc * 10 + std::uint64_t(d[i] - '0');
        if (acc > 0xFFFFFFFFull) {
            return false;
        }
    }
    out = std::uint32_t(acc);
    return true;
}

bool parse_i32(const std::uint8_t* d, std::size_t n, std::int32_t& out) {
    if (n == 0) {
        return false;
    }
    bool negative = false;
    std::size_t i = 0;
    if (d[0] == '-' || d[0] == '+') {
        negative = (d[0] == '-');
        i = 1;
    }
    std::uint32_t magnitude = 0;
    if (!parse_u32(d + i, n - i, magnitude) || magnitude > 2147483647u) {
        return false;
    }
    out = negative ? -std::int32_t(magnitude) : std::int32_t(magnitude);
    return true;
}

// Le firmware peut emettre des octets bruts non imprimables au milieu d'une
// ligne (docs/01 §3, anomalie 1). Les transmettre tels quels a une String Godot
// produirait de l'UTF-8 invalide : on echappe avant de sortir du C++ pur.
// Ecriture dans un tampon fixe — zero allocation, appelable depuis le thread
// de lecture.
void escape_into(Frame& f, const std::uint8_t* d, std::size_t n) {
    static const char kHex[] = "0123456789ABCDEF";
    std::size_t w = 0;
    const std::size_t limit = Frame::kTextMax - 1;
    for (std::size_t i = 0; i < n; ++i) {
        const std::uint8_t c = d[i];
        const std::size_t need = (c >= 32 && c < 127) ? 1u : 4u;
        if (w + need > limit) {
            f.text_truncated = true;
            break;
        }
        if (need == 1) {
            f.text[w++] = char(c);
        } else {
            f.text[w++] = '\\';
            f.text[w++] = 'x';
            f.text[w++] = kHex[c >> 4];
            f.text[w++] = kHex[c & 0x0F];
        }
    }
    f.text[w] = '\0';
}

Frame unknown(const std::uint8_t* d, std::size_t n) {
    Frame f;
    f.kind = FrameKind::Unknown;
    escape_into(f, d, n);
    return f;
}

}  // namespace

const char* frame_kind_name(FrameKind k) {
    switch (k) {
        case FrameKind::Progress: return "Progress";
        case FrameKind::Countdown: return "Countdown";
        case FrameKind::FalseStart: return "FalseStart";
        case FrameKind::RiderFinish: return "RiderFinish";
        case FrameKind::LengthAck: return "LengthAck";
        case FrameKind::MockAck: return "MockAck";
        case FrameKind::Version: return "Version";
        case FrameKind::Error: return "Error";
        case FrameKind::KioskStart: return "KioskStart";
        case FrameKind::KioskStop: return "KioskStop";
        case FrameKind::Unknown: return "Unknown";
    }
    return "Unknown";
}

Frame parse_line(const std::uint8_t* d, std::size_t n) {
    if (n == 0) {
        return unknown(d, n);
    }

    // `G` et `S` seuls : mode kiosque du driver v1. ss_basic.ino ne les emet
    // jamais ; on les reconnait et on les loggue, sans rien en faire tant que
    // le materiel correspondant n'est pas confirme (docs/01 §3, anomalie 3).
    if (n == 1 && d[0] == 'G') {
        Frame f;
        f.kind = FrameKind::KioskStart;
        return f;
    }
    if (n == 1 && d[0] == 'S') {
        Frame f;
        f.kind = FrameKind::KioskStop;
        return f;
    }

    // `<idx>F:<ms>` AVANT toute decoupe sur ':' — sinon collision de prefixes
    // (docs/01 §3, anomalie 2).
    if (n >= 3 && d[0] >= '0' && d[0] <= '3' && d[1] == 'F' && d[2] == ':') {
        std::uint32_t ms = 0;
        if (!parse_u32(d + 3, n - 3, ms)) {
            // Cas du `0F:-5536` : la branche existe cote firmware mais est
            // morte (docs/01 §3, anomalie 5). On classe en Unknown, on loggue.
            return unknown(d, n);
        }
        Frame f;
        f.kind = FrameKind::RiderFinish;
        f.value = int(d[0] - '0');
        f.finish_ms = ms;
        return f;
    }

    if (starts_with(d, n, "R:")) {
        Frame f;
        f.kind = FrameKind::Progress;
        std::size_t field = 0;
        std::size_t start = 2;
        for (std::size_t i = 2; i <= n; ++i) {
            if (i == n || d[i] == ',') {
                if (field > 4) {
                    return unknown(d, n);  // plus de cinq champs
                }
                std::uint32_t v = 0;
                if (!parse_u32(d + start, i - start, v)) {
                    return unknown(d, n);
                }
                if (field < 4) {
                    f.ticks[field] = v;
                } else {
                    f.elapsed_ms = v;
                }
                ++field;
                start = i + 1;
            }
        }
        if (field != 5) {
            return unknown(d, n);
        }
        return f;
    }

    if (starts_with(d, n, "CD:")) {
        std::int32_t v = 0;
        if (!parse_i32(d + 3, n - 3, v)) {
            return unknown(d, n);
        }
        Frame f;
        f.kind = FrameKind::Countdown;
        f.value = int(v);
        return f;
    }

    if (starts_with(d, n, "FS:")) {
        std::uint32_t v = 0;
        if (!parse_u32(d + 3, n - 3, v) || v > 3) {
            return unknown(d, n);
        }
        Frame f;
        f.kind = FrameKind::FalseStart;
        f.value = int(v);
        return f;
    }

    // `ERROR:` avant `L:`/`M:`/`V:` : la ligne malformee a double prefixe de
    // docs/01 §3 doit rester un Error, pas devenir autre chose.
    if (starts_with(d, n, "ERROR:")) {
        Frame f;
        f.kind = FrameKind::Error;
        escape_into(f, d, n);
        return f;
    }

    if (starts_with(d, n, "L:")) {
        std::int32_t v = 0;
        if (!parse_i32(d + 2, n - 2, v)) {
            return unknown(d, n);
        }
        Frame f;
        f.kind = FrameKind::LengthAck;
        f.length_ticks = v;
        return f;
    }

    if (starts_with(d, n, "M:")) {
        if (n == 4 && starts_with(d + 2, n - 2, "ON")) {
            Frame f;
            f.kind = FrameKind::MockAck;
            f.mock_on = true;
            return f;
        }
        if (n == 5 && starts_with(d + 2, n - 2, "OFF")) {
            Frame f;
            f.kind = FrameKind::MockAck;
            f.mock_on = false;
            return f;
        }
        return unknown(d, n);
    }

    if (starts_with(d, n, "V:")) {
        Frame f;
        f.kind = FrameKind::Version;
        escape_into(f, d + 2, n - 2);
        return f;
    }

    return unknown(d, n);
}

Frame parse_line(const char* s) {
    std::size_t n = 0;
    while (s[n] != '\0') {
        ++n;
    }
    return parse_line(reinterpret_cast<const std::uint8_t*>(s), n);
}

}  // namespace sslink
