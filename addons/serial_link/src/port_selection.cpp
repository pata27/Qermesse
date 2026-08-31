#include "port_selection.h"

#include <algorithm>
#include <cctype>

namespace sslink {
namespace {

bool has_prefix(const std::string& s, const char* prefix) {
    const std::size_t n = std::char_traits<char>::length(prefix);
    return s.size() >= n && s.compare(0, n, prefix) == 0;
}

// Extrait le nom de fichier d'un chemin, pour matcher sur ttyACM0 plutot que
// sur /dev/ttyACM0.
std::string basename_of(const std::string& path) {
    const std::size_t slash = path.find_last_of("/\\");
    return slash == std::string::npos ? path : path.substr(slash + 1);
}

}  // namespace

const std::vector<UsbId>& known_usb_ids() {
    // docs/01 §4. Le boitier de l'utilisateur n'ayant pas encore ete branche,
    // cette liste est celle des identifiants generiques ; elle sera completee
    // par un `lsusb` sur le materiel reel avant le jalon J1.
    static const std::vector<UsbId> kIds = {
        {0x2341, 0x0043, "Arduino Uno (officiel, R3)"},
        {0x2341, 0x0001, "Arduino Uno (officiel, R1/R2)"},
        {0x2A03, 0x0043, "Arduino Uno (arduino.org)"},
        {0x1A86, 0x7523, "CH340 (clone Uno)"},
        {0x1A86, 0x5523, "CH341 (clone Uno)"},
        {0x0403, 0x6001, "FTDI FT232R"},
        {0x10C4, 0xEA60, "Silicon Labs CP210x"},
    };
    return kIds;
}

bool is_known_usb_id(std::uint16_t vid, std::uint16_t pid) {
    for (const UsbId& id : known_usb_ids()) {
        if (id.vid == vid && id.pid == pid) {
            return true;
        }
    }
    return false;
}

bool name_looks_like_serial(const std::string& path) {
    const std::string name = basename_of(path);
    if (name.empty()) {
        return false;
    }
    if (has_prefix(name, "ttyUSB") || has_prefix(name, "ttyACM")) {
        return true;  // Linux
    }
    if (has_prefix(name, "cu.usbmodem") || has_prefix(name, "cu.usbserial") ||
        has_prefix(name, "tty.usbmodem") || has_prefix(name, "tty.usbserial")) {
        return true;  // macOS
    }
    if (has_prefix(name, "COM") && name.size() > 3) {
        bool digits = true;
        for (std::size_t i = 3; i < name.size(); ++i) {
            if (std::isdigit(static_cast<unsigned char>(name[i])) == 0) {
                digits = false;
                break;
            }
        }
        if (digits) {
            return true;  // Windows
        }
    }
    // Un libelle explicite reste un indice acceptable.
    return name.find("Arduino") != std::string::npos;
}

const char* selection_reason_name(SelectionReason r) {
    switch (r) {
        case SelectionReason::Preferred: return "port choisi par l'operateur";
        case SelectionReason::UsbId: return "VID/PID connu";
        case SelectionReason::NamePattern: return "nom de port plausible";
        case SelectionReason::None: return "aucun";
    }
    return "aucun";
}

std::vector<Candidate> rank_candidates(const std::vector<PortInfo>& ports,
                                       const std::string& preferred_path,
                                       const std::vector<std::string>& blacklisted) {
    std::vector<Candidate> out;
    out.reserve(ports.size() + 1);

    // Un port choisi explicitement par l'operateur est essaye MEME s'il
    // n'apparait pas dans l'enumeration. Deux cas reels le justifient : un
    // pseudo-terminal (l'emulateur ss_emu) n'est pas dans /sys/class/tty, et
    // certains adaptateurs s'enumerent mal selon le pilote. C'est un choix
    // humain explicite ; le handshake reste seul juge de ce qu'il y a au bout.
    bool preferred_present = preferred_path.empty();
    for (const PortInfo& p : ports) {
        if (p.path == preferred_path) {
            preferred_present = true;
            break;
        }
    }
    if (!preferred_present &&
        std::find(blacklisted.begin(), blacklisted.end(), preferred_path) == blacklisted.end()) {
        Candidate c;
        c.info.path = preferred_path;
        c.info.description = "port force par l'operateur (absent de l'enumeration)";
        c.reason = SelectionReason::Preferred;
        out.push_back(c);
    }

    for (const PortInfo& p : ports) {
        if (std::find(blacklisted.begin(), blacklisted.end(), p.path) != blacklisted.end()) {
            continue;
        }
        Candidate c;
        c.info = p;
        if (!preferred_path.empty() && p.path == preferred_path) {
            c.reason = SelectionReason::Preferred;
        } else if (p.has_ids && is_known_usb_id(p.vid, p.pid)) {
            c.reason = SelectionReason::UsbId;
        } else if (name_looks_like_serial(p.path)) {
            c.reason = SelectionReason::NamePattern;
        } else {
            // INTERDIT : le repli v1 « prendre le dernier port de la liste ».
            // Un port qui ne coche aucun critere n'est pas un candidat.
            continue;
        }
        out.push_back(c);
    }

    std::stable_sort(out.begin(), out.end(), [](const Candidate& a, const Candidate& b) {
        return static_cast<int>(a.reason) < static_cast<int>(b.reason);
    });
    return out;
}

}  // namespace sslink
