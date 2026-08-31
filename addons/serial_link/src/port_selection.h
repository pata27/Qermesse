// Choix du port parmi ceux enumeres — docs/01 §4.
//
// Trois criteres, du plus fiable au plus laxiste. Le repli v1 « prendre le
// dernier port de la liste » est SUPPRIME : il ouvrait n'importe quel
// peripherique serie de la machine, souris Bluetooth comprise.
#pragma once

#include <cstdint>
#include <string>
#include <vector>

#include "serial_port.h"

namespace sslink {

struct UsbId {
    std::uint16_t vid;
    std::uint16_t pid;
    const char* label;
};

// docs/01 §4. A completer en branchant le materiel reel de l'utilisateur.
const std::vector<UsbId>& known_usb_ids();
bool is_known_usb_id(std::uint16_t vid, std::uint16_t pid);

// Vrai si le nom ressemble a un port serie USB. Critere le plus laxiste des
// trois : il ne suffit jamais a lui seul, seule la reponse `V:` fait foi.
bool name_looks_like_serial(const std::string& path);

enum class SelectionReason : int {
    None = 0,
    Preferred,  // choisi explicitement par l'operateur, persiste
    UsbId,      // VID/PID dans l'allowlist
    NamePattern,  // le nom ressemble a un port serie
};

struct Candidate {
    PortInfo info;
    SelectionReason reason = SelectionReason::None;
};

// Rend les candidats tries par ordre de confiance decroissant. Un port
// blackliste pour ce cycle de scan est exclu.
std::vector<Candidate> rank_candidates(const std::vector<PortInfo>& ports,
                                       const std::string& preferred_path,
                                       const std::vector<std::string>& blacklisted);

const char* selection_reason_name(SelectionReason r);

}  // namespace sslink
