// Arithmétique de l'ATmega328P, telle que le firmware la subit.
//
// Le seul intérêt de ce fichier est de rendre IMPOSSIBLE l'écriture accidentelle
// d'une arithmétique 32 bits là où la cible en fait 16. C'est l'erreur qui a
// produit trois contresens dans docs/01 avant relecture — voir docs/01 §5.5.
#pragma once

#include <cstdint>
#include <string>

namespace ssemu {

// Sur AVR-GCC : int = 16 bits signés, long = 32 bits, char = signé.
using avr_int = std::int16_t;
using avr_ulong = std::uint32_t;
using avr_char = std::int8_t;

// Multiplication de deux `int` : le résultat est calculé en 16 bits AVANT toute
// promotion. C'est très exactement ce qui casse checkTimeBased() au-delà de 32 s.
constexpr avr_int avr_mul(avr_int a, avr_int b) noexcept {
    return static_cast<avr_int>(static_cast<std::uint16_t>(static_cast<std::uint32_t>(a) *
                                                           static_cast<std::uint32_t>(b)));
}

// Comparaison `unsigned long > int` en C : l'int est converti en unsigned long.
// Un int négatif devient donc une valeur énorme, et la condition n'est jamais vraie.
constexpr bool avr_ulong_gt_int(avr_ulong lhs, avr_int rhs) noexcept {
    return lhs > static_cast<avr_ulong>(static_cast<std::int32_t>(rhs));
}

constexpr bool avr_ulong_ge_int(avr_ulong lhs, avr_int rhs) noexcept {
    return lhs >= static_cast<avr_ulong>(static_cast<std::int32_t>(rhs));
}

// avr-libc atoi() renvoie un int 16 bits : les valeurs hors plage se replient
// modulo 2^16. Approximation assumée d'un comportement non spécifié par le C.
avr_int avr_atoi(const char* s) noexcept;

// Formatage identique à Print::print(x, DEC) d'Arduino.
std::string avr_fmt(avr_int v);
std::string avr_fmt(avr_ulong v);

}  // namespace ssemu
