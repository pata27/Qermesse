#include "doctest.h"

#include <atomic>
#include <cstdint>
#include <thread>
#include <vector>

#include "line_parser.h"
#include "ring_buffer.h"

using namespace sslink;

TEST_CASE("une file vide ne rend rien") {
    SpscRing<int, 8> q;
    int out = -1;
    CHECK(q.empty());
    CHECK(q.size() == 0);
    CHECK_FALSE(q.pop(out));
    CHECK(out == -1);
}

TEST_CASE("ordre FIFO strict") {
    SpscRing<int, 8> q;
    for (int i = 0; i < 5; ++i) {
        REQUIRE(q.push(i));
    }
    CHECK(q.size() == 5);
    for (int i = 0; i < 5; ++i) {
        int out = -1;
        REQUIRE(q.pop(out));
        CHECK(out == i);
    }
    CHECK(q.empty());
}

TEST_CASE("la capacite utile est N-1, et le debordement perd la trame NEUVE") {
    SpscRing<int, 8> q;
    CHECK(SpscRing<int, 8>::capacity() == 7);
    for (int i = 0; i < 7; ++i) {
        REQUIRE(q.push(i));
    }
    CHECK_FALSE(q.push(999));
    CHECK(q.dropped() == 1);

    // Les anciennes sont intactes : c'est le contrat, et c'est ce qui permet
    // au consommateur de posseder `tail_` sans partage.
    int out = -1;
    REQUIRE(q.pop(out));
    CHECK(out == 0);
    CHECK(q.push(1000));
}

TEST_CASE("l'indice s'enroule sans perdre l'ordre") {
    SpscRing<int, 4> q;
    for (int cycle = 0; cycle < 50; ++cycle) {
        REQUIRE(q.push(cycle));
        int out = -1;
        REQUIRE(q.pop(out));
        CHECK(out == cycle);
    }
    CHECK(q.dropped() == 0);
}

TEST_CASE("deux threads, cent mille trames : rien n'est perdu ni desordonne") {
    // C'est LE test qui manquait a la v2 : elle avait sept tests sur un parseur
    // pur et zero sur le threading serie, qui etait le vrai risque.
    constexpr int kCount = 100000;
    SpscRing<std::uint32_t, 1024> q;
    std::atomic<bool> producer_done{false};

    std::thread producer([&] {
        for (int i = 0; i < kCount; ++i) {
            // try_push : le producteur reessaie, donc rien n'est perdu et rien
            // ne doit etre comptabilise comme perte.
            while (!q.try_push(std::uint32_t(i))) {
                std::this_thread::yield();
            }
        }
        producer_done.store(true, std::memory_order_release);
    });

    std::vector<std::uint32_t> received;
    received.reserve(kCount);
    while (int(received.size()) < kCount) {
        std::uint32_t v = 0;
        if (q.pop(v)) {
            received.push_back(v);
        } else if (producer_done.load(std::memory_order_acquire) && q.empty()) {
            break;
        }
    }
    producer.join();

    REQUIRE(received.size() == std::size_t(kCount));
    bool ordered = true;
    for (int i = 0; i < kCount; ++i) {
        if (received[std::size_t(i)] != std::uint32_t(i)) {
            ordered = false;
            break;
        }
    }
    CHECK(ordered);
    CHECK(q.dropped() == 0);
}

TEST_CASE("une file de Frame ne coute aucune allocation") {
    // Le thread de lecture pousse des Frame telles quelles : elles doivent
    // etre trivialement copiables, sinon la contrainte 'aucune allocation dans
    // le thread de lecture' de docs/03 §4 tombe.
    SpscRing<Frame, 16> q;
    Frame f = parse_line("R:7,8,9,10,1234");
    REQUIRE(q.push(f));
    Frame got;
    REQUIRE(q.pop(got));
    CHECK(got.kind == FrameKind::Progress);
    CHECK(got.ticks[3] == 10);
    CHECK(got.elapsed_ms == 1234);
}

TEST_CASE("dimensionnement retenu : 4096 trames, soit ~41 s a 100 Hz") {
    // Un debordement signifie que le thread de jeu est fige depuis 40 secondes.
    // A ce stade la course est perdue de toute facon ; le compteur le dit.
    CHECK(SpscRing<Frame, 4096>::capacity() == 4095);
    CHECK(SpscRing<Frame, 4096>::capacity() >= 4000);  // au moins 40 s a 100 Hz
}

TEST_CASE("try_push ne compte aucune perte, push en compte une") {
    // Le piege corrige a l'ecriture de ce fichier : un compteur qui additionne
    // les reessais afficherait des milliers de pertes imaginaires.
    SpscRing<int, 4> q;
    for (int i = 0; i < 3; ++i) {
        REQUIRE(q.try_push(i));
    }
    CHECK_FALSE(q.try_push(99));
    CHECK(q.dropped() == 0);

    CHECK_FALSE(q.push(99));
    CHECK(q.dropped() == 1);
}
