// File SPSC sans verrou entre le thread de lecture serie et le thread de jeu.
//
// C'est la piece qui empeche de refaire la faute de la v1 : le thread serie
// ecrit ICI, et nulle part ailleurs. Il ne touche ni a l'etat du jeu, ni a
// l'API Godot (docs/01 §6.1).
//
// Discipline SPSC stricte : le producteur possede `head_`, le consommateur
// possede `tail_`. Aucun des deux n'ecrit dans l'index de l'autre — c'est ce
// qui rend l'ensemble correct sans verrou.
#pragma once

#include <array>
#include <atomic>
#include <cstddef>
#include <type_traits>

namespace sslink {

template <typename T, std::size_t N>
class SpscRing {
    static_assert(N >= 2, "capacite trop petite");
    static_assert((N & (N - 1)) == 0, "N doit etre une puissance de deux");
    static_assert(std::is_trivially_copyable<T>::value,
                  "le thread de lecture ne doit rien allouer : T doit etre trivialement copiable");

  public:
    static constexpr std::size_t capacity() { return N - 1; }

    // Producteur uniquement. Rend false si la file est pleine, SANS rien
    // comptabiliser : un appelant qui reessaie n'a rien perdu.
    //
    // Pourquoi ne pas ecraser la plus ancienne, ce qui garderait l'etat le plus
    // frais : cela obligerait le producteur a deplacer `tail_`, qui appartient
    // au consommateur, et ruinerait la propriete SPSC.
    bool try_push(const T& value) {
        const std::size_t head = head_.load(std::memory_order_relaxed);
        const std::size_t next = (head + 1) & (N - 1);
        if (next == tail_.load(std::memory_order_acquire)) {
            return false;
        }
        slots_[head] = value;
        head_.store(next, std::memory_order_release);
        return true;
    }

    // Pour un producteur qui ne peut pas attendre — le thread de lecture serie,
    // qui doit revenir a son read() sans delai. Un echec ici est une trame
    // REELLEMENT perdue, et c'est ce que compte `dropped()`.
    //
    // La distinction n'est pas cosmetique : `dropped()` est affiche dans le
    // panneau materiel. Un compteur qui additionnerait les reessais afficherait
    // des milliers de pertes imaginaires en pleine course.
    bool push(const T& value) {
        if (try_push(value)) {
            return true;
        }
        dropped_.fetch_add(1, std::memory_order_relaxed);
        return false;
    }

    // Consommateur uniquement.
    bool pop(T& out) {
        const std::size_t tail = tail_.load(std::memory_order_relaxed);
        if (tail == head_.load(std::memory_order_acquire)) {
            return false;
        }
        out = slots_[tail];
        tail_.store((tail + 1) & (N - 1), std::memory_order_release);
        return true;
    }

    bool empty() const {
        return head_.load(std::memory_order_acquire) == tail_.load(std::memory_order_acquire);
    }

    std::size_t size() const {
        const std::size_t head = head_.load(std::memory_order_acquire);
        const std::size_t tail = tail_.load(std::memory_order_acquire);
        return (head - tail) & (N - 1);
    }

    std::size_t dropped() const { return dropped_.load(std::memory_order_relaxed); }

  private:
    // Indices sur des lignes de cache distinctes : sans cela, les deux threads
    // se disputent la meme ligne a chaque trame, 100 fois par seconde.
    static constexpr std::size_t kCacheLine = 64;

    std::array<T, N> slots_{};
    alignas(kCacheLine) std::atomic<std::size_t> head_{0};
    alignas(kCacheLine) std::atomic<std::size_t> tail_{0};
    alignas(kCacheLine) std::atomic<std::size_t> dropped_{0};
};

}  // namespace sslink
