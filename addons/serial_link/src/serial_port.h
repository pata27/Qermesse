// Abstraction du port serie. C++ pur, aucun include Godot.
//
// L'interface est virtuelle pour une raison precise : elle permet d'injecter un
// port factice dans les tests, et donc d'eprouver TOUTE la logique de lien —
// handshake, watchdog, reconnexion, backoff — sans materiel et sans OS
// particulier. C'est la partie qui a coule la v1 ; elle doit etre la mieux
// couverte du projet.
#pragma once

#include <cstddef>
#include <cstdint>
#include <memory>
#include <string>
#include <vector>

namespace sslink {

struct PortInfo {
    std::string path;         // /dev/ttyACM0, COM3, /dev/cu.usbmodem14201
    std::string description;  // libelle constructeur, souvent vide
    std::uint16_t vid = 0;
    std::uint16_t pid = 0;
    bool has_ids = false;  // false pour un port sans identifiant USB (pty, port integre)
};

class SerialPort {
  public:
    virtual ~SerialPort() = default;

    // Ouvre en 115200 8N1, sans controle de flux, en mode brut non bloquant.
    virtual bool open(const std::string& path, std::string& err) = 0;
    virtual void close() = 0;
    virtual bool is_open() const = 0;

    // Non bloquant. Rend 0 quand rien n'est disponible. Rend SIZE_MAX si le
    // port a disparu — un cas qu'il faut distinguer du simple silence.
    static constexpr std::size_t kReadError = static_cast<std::size_t>(-1);
    virtual std::size_t read(std::uint8_t* buf, std::size_t n) = 0;

    virtual bool write(const std::uint8_t* buf, std::size_t n) = 0;

    // Le peripherique est-il toujours la ? DISTINCT de `is_open()`.
    //
    // Un descripteur reste parfaitement valide apres le raccrochage : sur un
    // pseudo-terminal dont le maitre est parti, `read()` rend 0 — un silence,
    // pas une erreur. Hors course aucun watchdog ne veille, si bien qu'un
    // boitier debranche au branchement restait IDENTIFIED indefiniment, START
    // actif, firmware affiche. Constater l'absence du chemin est le seul
    // signal disponible dans ce cas.
    //
    // Vrai par defaut : une implementation qui ne sait pas repondre ne doit
    // jamais faire croire a une disparition.
    virtual bool still_present() const { return true; }
};

// Implementation propre a l'OS.
std::unique_ptr<SerialPort> make_serial_port();
std::vector<PortInfo> enumerate_ports();

}  // namespace sslink
