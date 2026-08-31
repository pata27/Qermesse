#include "avr_types.h"

#include <cctype>

namespace ssemu {

avr_int avr_atoi(const char* s) noexcept {
    if (s == nullptr) {
        return 0;
    }
    while (*s != '\0' && std::isspace(static_cast<unsigned char>(*s)) != 0) {
        ++s;
    }
    bool negative = false;
    if (*s == '+' || *s == '-') {
        negative = (*s == '-');
        ++s;
    }
    // avr-libc accumule dans des registres 16 bits : le repliement est progressif.
    // Le modulo étant compatible avec * et +, c'est équivalent au modulo final.
    std::uint16_t acc = 0;
    while (*s >= '0' && *s <= '9') {
        acc = static_cast<std::uint16_t>(acc * 10U + static_cast<std::uint16_t>(*s - '0'));
        ++s;
    }
    if (negative) {
        acc = static_cast<std::uint16_t>(0U - acc);
    }
    return static_cast<avr_int>(acc);
}

std::string avr_fmt(avr_int v) { return std::to_string(static_cast<int>(v)); }

std::string avr_fmt(avr_ulong v) { return std::to_string(static_cast<unsigned long>(v)); }

}  // namespace ssemu
