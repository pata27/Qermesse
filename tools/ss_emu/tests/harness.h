// Banc d'essai en temps virtuel pour FirmwareSim.
//
// L'horloge étant injectée, une course de 70 s se rejoue en quelques
// millisecondes de CPU et sans la moindre dépendance système.
#pragma once

#include <array>
#include <cstdint>
#include <string>
#include <vector>

#include "firmware_sim.h"

namespace ssemu::test {

class Harness {
  public:
    // Le firmware réel boucle à plusieurs dizaines de kHz ; checkSerial() ne
    // consomme qu'un octet par tour. 10 tours par milliseconde suffisent à
    // reproduire fidèlement le comportement sans ralentir les tests.
    explicit Harness(std::uint32_t iters_per_ms = 10) : iters_per_ms_(iters_per_ms) {}

    FirmwareSim fw;

    std::uint32_t now_ms() const { return static_cast<std::uint32_t>(sub_ / iters_per_ms_); }

    void step_once() {
        fw.tick(now_ms());
        out_ += fw.drain_tx();
        ++sub_;
    }

    void run_ms(std::uint32_t duration_ms) {
        const std::uint64_t target = sub_ + std::uint64_t(duration_ms) * iters_per_ms_;
        while (sub_ < target) {
            step_once();
        }
    }

    void send(std::string_view s) { fw.feed_rx(s); }

    // Un tour de rouleau : le contact se ferme puis se rouvre. Le firmware ne
    // compte que le front montant (docs/01 §1).
    void pedal_once(int rider) {
        fw.set_sensor(rider, false);
        step_once();
        fw.set_sensor(rider, true);
        step_once();
    }

    void pedal(int rider, int turns) {
        for (int i = 0; i < turns; ++i) {
            pedal_once(rider);
        }
    }

    // Rebond de contact : le signal retombe et remonte sans que le rouleau ait
    // tourné. Aucun anti-rebond firmware, donc un tick fantôme de plus.
    void bounce(int rider) { pedal_once(rider); }

    const std::string& out() const { return out_; }
    void clear_out() { out_.clear(); }

    bool saw(std::string_view needle) const { return out_.find(needle) != std::string::npos; }

    int count(std::string_view needle) const {
        int n = 0;
        for (std::size_t p = out_.find(needle); p != std::string::npos;
             p = out_.find(needle, p + 1)) {
            ++n;
        }
        return n;
    }

    std::vector<std::string> lines() const {
        std::vector<std::string> v;
        std::size_t start = 0;
        for (std::size_t p = out_.find("\r\n"); p != std::string::npos;
             p = out_.find("\r\n", start)) {
            v.emplace_back(out_.substr(start, p - start));
            start = p + 2;
        }
        return v;
    }

  private:
    std::uint32_t iters_per_ms_;
    std::uint64_t sub_ = 0;
    std::string out_;
};

}  // namespace ssemu::test
