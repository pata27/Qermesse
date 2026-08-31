// Frontal pseudo-terminal : c'est lui qui fait de ss_emu autre chose qu'un mock.
//
// Le port apparaît comme un vrai périphérique série sous /dev/pts/N. Le code
// Godot l'ouvre, le configure en 115200 8N1 et lit des octets — il ne peut pas
// savoir qu'il ne parle pas à un Arduino. Ouverture de port, threading,
// découpage de flux, handshake, watchdog et reconnexion sont donc réellement
// exercés, ce qui est exactement ce que le mock de la v2 ne faisait pas.
#pragma once

#include <cstdint>
#include <string>
#include <string_view>

namespace ssemu {

class PtyPort {
  public:
    ~PtyPort();

    bool open(std::string& err);
    void close();
    bool is_open() const { return master_fd_ >= 0; }

    // Ferme puis rouvre : le pseudo-terminal change de numéro, exactement comme
    // un Arduino débranché puis rebranché change de /dev/ttyACM*. Le lien
    // symbolique, lui, est repointé — c'est ce qui rend la reconnexion testable.
    bool reopen(std::string& err);

    const std::string& device() const { return device_; }

    // Chemin stable donné au driver PC. Recréé à chaque reopen().
    bool set_link(const std::string& path, std::string& err);
    const std::string& link() const { return link_; }

    std::size_t read_available(std::uint8_t* buf, std::size_t n);

    void queue_tx(std::string_view data) { outbox_.append(data); }
    // Libère les octets à la cadence de la ligne : 115200 8N1 = 11520 o/s.
    void pump_tx(double now_ms);
    void set_baud_pacing(bool on) { baud_pacing_ = on; }

    std::size_t dropped_bytes() const { return dropped_; }

  private:
    bool create_pty(std::string& err);
    bool refresh_link(std::string& err);

    int master_fd_ = -1;
    int slave_fd_ = -1;  // gardé ouvert : évite un EIO quand le client se déconnecte
    std::string device_;
    std::string link_;
    std::string outbox_;
    bool baud_pacing_ = true;
    double credit_bytes_ = 0.0;
    double last_pump_ms_ = -1.0;
    std::size_t dropped_ = 0;
};

}  // namespace ssemu
