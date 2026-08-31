// Injection de pannes — docs/07 §6.
//
// Le moteur ne connaît ni le modèle physique ni le transport : il se contente
// de dire QUELLE panne est due et QUAND. C'est l'appelant qui l'applique.
// Cette séparation garde faults.cpp testable et sans dépendance système.
#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace ssemu {

enum class FaultKind {
    FalseStart,      // faux-depart=<i>
    PhantomTick,     // tick-fantome=<i>[@<t>]
    LinkLoss,        // perte-lien@<t>
    LinkReturn,      // retour-lien@<t>
    CorruptFrame,    // trame-corrompue@<t>
    NullByte,        // octet-nul@<t>
    Freeze,          // gel@<t>=<ms>
    TruncatedLine,   // ligne-tronquee@<t>
};

struct Fault {
    FaultKind kind{};
    double at_s = 0.0;   // secondes depuis le départ de la course (CD:0)
    int rider = -1;
    double param = 0.0;  // durée du gel, en ms
    bool fired = false;
};

const char* fault_name(FaultKind k);

// Rend false et remplit `err` si la spécification est invalide.
bool parse_fault(const std::string& spec, Fault& out, std::string& err);

class FaultEngine {
  public:
    void add(const Fault& f) { faults_.push_back(f); }
    bool empty() const { return faults_.empty(); }
    const std::vector<Fault>& all() const { return faults_; }

    // Pannes sans horodatage, actives dès le décompte.
    std::vector<Fault> pre_race() const;

    // Pannes dont l'échéance est atteinte. Chacune n'est rendue qu'une fois.
    std::vector<Fault> due(double race_t_s);

    // Remet les échéances à zéro : une nouvelle course rejoue le scénario.
    void rearm();

  private:
    std::vector<Fault> faults_;
};

}  // namespace ssemu
