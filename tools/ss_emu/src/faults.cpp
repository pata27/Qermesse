#include "faults.h"

#include <cstdlib>

namespace ssemu {
namespace {

struct Entry {
    const char* name;
    FaultKind kind;
    bool needs_rider;
    bool needs_time;
};

constexpr Entry kTable[] = {
    {"faux-depart", FaultKind::FalseStart, true, false},
    {"tick-fantome", FaultKind::PhantomTick, true, false},
    {"perte-lien", FaultKind::LinkLoss, false, true},
    {"retour-lien", FaultKind::LinkReturn, false, true},
    {"trame-corrompue", FaultKind::CorruptFrame, false, true},
    {"octet-nul", FaultKind::NullByte, false, true},
    {"gel", FaultKind::Freeze, false, true},
    {"ligne-tronquee", FaultKind::TruncatedLine, false, true},
};

bool to_double(const std::string& s, double& out) {
    if (s.empty()) {
        return false;
    }
    char* end = nullptr;
    const double v = std::strtod(s.c_str(), &end);
    if (end == s.c_str()) {
        return false;
    }
    // Suffixe 's' toléré : perte-lien@10s se lit comme perte-lien@10.
    if (*end != '\0' && !(*end == 's' && end[1] == '\0')) {
        return false;
    }
    out = v;
    return true;
}

}  // namespace

const char* fault_name(FaultKind k) {
    for (const Entry& e : kTable) {
        if (e.kind == k) {
            return e.name;
        }
    }
    return "?";
}

bool parse_fault(const std::string& spec, Fault& out, std::string& err) {
    // Formes acceptées : nom, nom=<v>, nom@<t>, nom=<v>@<t>, nom@<t>=<v>
    std::string name = spec;
    std::string time_part;
    std::string value_part;

    const std::size_t at = name.find('@');
    if (at != std::string::npos) {
        time_part = name.substr(at + 1);
        name = name.substr(0, at);
    }
    // Le '=' peut se trouver de part et d'autre du '@'.
    const std::size_t eq_name = name.find('=');
    if (eq_name != std::string::npos) {
        value_part = name.substr(eq_name + 1);
        name = name.substr(0, eq_name);
    }
    const std::size_t eq_time = time_part.find('=');
    if (eq_time != std::string::npos) {
        value_part = time_part.substr(eq_time + 1);
        time_part = time_part.substr(0, eq_time);
    }

    const Entry* entry = nullptr;
    for (const Entry& e : kTable) {
        if (name == e.name) {
            entry = &e;
            break;
        }
    }
    if (entry == nullptr) {
        err = "panne inconnue : " + name;
        return false;
    }

    out = Fault{};
    out.kind = entry->kind;

    if (!time_part.empty()) {
        if (!to_double(time_part, out.at_s)) {
            err = "instant illisible dans : " + spec;
            return false;
        }
    }

    if (entry->needs_rider) {
        if (value_part.empty()) {
            err = std::string(entry->name) + " exige un numero de rider, ex. " + entry->name + "=0";
            return false;
        }
        double r = 0.0;
        if (!to_double(value_part, r) || r < 0.0 || r > 3.0) {
            err = "numero de rider hors bornes 0..3 dans : " + spec;
            return false;
        }
        out.rider = int(r);
    } else if (!value_part.empty()) {
        if (!to_double(value_part, out.param)) {
            err = "valeur illisible dans : " + spec;
            return false;
        }
    }

    if (entry->kind == FaultKind::Freeze && out.param <= 0.0) {
        err = "gel exige une duree en ms, ex. gel@10=800";
        return false;
    }
    if (entry->needs_time && time_part.empty()) {
        err = std::string(entry->name) + " exige un instant, ex. " + entry->name + "@10";
        return false;
    }
    return true;
}

std::vector<Fault> FaultEngine::pre_race() const {
    std::vector<Fault> v;
    for (const Fault& f : faults_) {
        if (f.kind == FaultKind::FalseStart) {
            v.push_back(f);
        }
    }
    return v;
}

std::vector<Fault> FaultEngine::due(double race_t_s) {
    std::vector<Fault> v;
    for (Fault& f : faults_) {
        if (f.kind == FaultKind::FalseStart || f.fired) {
            continue;
        }
        if (race_t_s >= f.at_s) {
            f.fired = true;
            v.push_back(f);
        }
    }
    return v;
}

void FaultEngine::rearm() {
    for (Fault& f : faults_) {
        f.fired = false;
    }
}

}  // namespace ssemu
