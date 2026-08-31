# 01 — Contrat Hardware / Firmware (SPEC NORMATIVE)

> **Statut : figé. Le firmware n'est PAS modifié en v3.**
> Ce document est la source de vérité du protocole série. Il a été reconstitué par lecture
> croisée du firmware `apps/Arduino/ss_basic/ss_basic.ino` (323 lignes) et du driver PC
> `apps/Silversprints/src/data/SerialReader.cpp` du dépôt v1 (`/home/antoine/Code/SilverSprint`).
> Toute divergence constatée sur du matériel réel doit être corrigée **ici en premier**, puis dans le code.

---

## 1. Couche physique

| Paramètre | Valeur |
|---|---|
| Baudrate | **115200** |
| Format | 8 data bits, no parity, 1 stop bit (8N1) |
| Contrôle de flux | aucun |
| Terminateur **PC → Arduino** | `\n` (le firmware accepte aussi `\r`) |
| Terminateur **Arduino → PC** | `\r\n` (`Serial.println`) |
| Encodage | ASCII pur, pas de binaire, **pas de checksum** |
| Débit max des trames de progression | ~100 Hz (throttle firmware `updateInterval = 10 ms`) |

Version firmware attendue : chaîne `SS_v0.1.7` (constante `VERSION` du .ino).
Le driver doit accepter toute chaîne commençant par `SS_v` et parser le semver derrière.

### Pinout (informatif, ne pas modifier)

| Pin | Rôle |
|---|---|
| D2, D3, D4, D5 | Capteurs riders 0..3 (INPUT + pull-up interne → repos = HIGH, tick = front montant après un LOW) |
| D9, D10, D11, D12 | LED « GO » riders 0..3 |
| D13 | LED heartbeat (blink 250 ms) |

Capteur = contact sec (reed switch / Hall tout-ou-rien), **1 impulsion par tour de rouleau**.
**Aucun debounce firmware** — le filtrage anti-rebond doit être fait côté PC (voir §6.3).

---

## 2. Commandes PC → Arduino (liste exhaustive)

Toutes terminées par `\n`.

| Trame | Sens métier | Effet firmware | Accusé de réception |
|---|---|---|---|
| `v` | Demande version | — | `V:SS_v0.1.7` |
| `g` | GO — lance le décompte | reset des 4 compteurs, `raceStarting = true`, `lastCountDown = 4` | flux `CD:3` → `CD:0` puis `R:` |
| `s` | STOP / abort | `raceStarted = raceStarting = false`, éteint les 4 LED | **aucun** |
| `l<ticks>` | Longueur de course en ticks (mode distance) | `raceLengthTicks = atoi(...)` | `L:<ticks>` |
| `t<secs>` | Durée de course en secondes (mode temps) | `raceLengthSecs = atoi(...)` | **aucun** |
| `d` | Sélectionne mode DISTANCE | `bRaceTypeDistance = true` | **aucun** |
| `x` | Sélectionne mode TEMPS | `bRaceTypeDistance = false` | **aucun** |
| `m` | Toggle mock interne du firmware | bascule `mockMode` | `M:ON` / `M:OFF` |

**Ordre d'émission obligatoire au démarrage d'une course :** `d` ou `x` → `l<n>` ou `t<n>` → `g`.

### Pièges à respecter

* **Double bornage obligatoire de `l<ticks>` et `t<secs>`.** Deux contraintes indépendantes,
  toutes deux à respecter :
  1. *Longueur* — le buffer de parsing fait **8 octets sans garde de dépassement**
     (`char charBuff[8]`, `charBuffPos` incrémenté sans test). Au terminateur, le firmware écrit
     `charBuff[charBuffPos] = '\0'` : à 8 chiffres il écrit hors du tableau. Donc **7 chiffres max**.
  2. *Valeur* — `atoi()` remplit un `int`, qui fait **16 bits signés sur AVR**. `raceLengthTicks`
     et `raceLengthSecs` sont des `int`. Toute valeur > 32767 est repliée modulo 2¹⁶ et devient
     potentiellement négative. Donc **plage utile `1..32767`**.

  Le driver PC refuse l'émission hors de ces bornes. Non négociable : dépassement = corruption
  mémoire AVR d'un côté, condition de fin absurde de l'autre.
  Repère : 5000 m avec un rouleau de 114.3 mm = 13927 ticks — on reste sous 32767, la borne
  ne gêne aucun usage réel.
* `d`, `x`, `t`, `s` sont *fire-and-forget*. Ne jamais attendre d'ack sur ces commandes.
* **Cadrage strict de `l` et `t`.** Dès que le firmware a lu `l` ou `t`, il bascule dans un mode où
  **tout octet reçu part dans le tampon numérique**, jusqu'au terminateur — espaces et commandes
  suivantes compris. `x t60 g` ne démarre donc aucune course : le `g` finit à l'intérieur du nombre,
  et aucune `ERROR:` n'est émise pour le signaler. Le driver émet `l<chiffres>\n` / `t<chiffres>\n`
  d'un bloc, sans rien intercaler, et n'envoie la commande suivante qu'après le terminateur.
  Vérifié par le test `tout octet suivant l ou t est avale par le tampon numerique`.
* La commande `m` (mock firmware) **n'est pas utilisée en v3** : notre simulateur est côté PC (voir `04`),
  ce qui permet de développer sans aucun matériel branché.

---

## 3. Messages Arduino → PC (liste exhaustive)

| Trame | Signification | Fréquence |
|---|---|---|
| `R:<t0>,<t1>,<t2>,<t3>,<elapsedMs>` | **Ticks CUMULÉS** des 4 riders + ms écoulées depuis le top départ | ≤ 100 Hz pendant la course |
| `CD:<n>` | Décompte, `n` ∈ {3, 2, 1, 0}. `CD:0` = top départ. | 1 Hz pendant le décompte |
| `FS:<idx>` | Faux départ du rider `idx` (≥ 4 ticks pendant le décompte) | événementiel |
| `<idx>F:<ms>` | Rider `idx` a fini, à `ms` ms du départ. Littéralement `0F:`, `1F:`, `2F:`, `3F:` | événementiel |
| `L:<ticks>` | Ack de `l<ticks>` | événementiel |
| `M:ON` / `M:OFF` | Ack de `m` | événementiel |
| `V:<version>` | Ack de `v` | événementiel |
| `ERROR:Command invalid <c>` | Commande inconnue reçue | événementiel |

### Anomalies firmware à absorber sans planter

1. **Message d'erreur malformé.** Pour un octet non imprimable, le firmware émet une ligne unique
   avec deux préfixes concaténés :
   `ERROR:Command invalid ERROR:Unprintable ASCII code <val>`.
   Le parseur doit la classer en `Unknown` et logger, jamais lever.
   **`<val>` n'est pas un nombre.** `val` est déclaré `char` et `Serial.println(char)` d'Arduino
   émet *le caractère*, pas son code décimal. La ligne contient donc l'octet de contrôle brut,
   suivi de `\r\n`. Le parseur doit survivre à des octets non-UTF-8 au milieu d'une ligne :
   travailler sur des `uint8_t`, jamais supposer du texte valide.
2. **`<idx>F:` se parse par regex `^([0-3])F:(\d+)$`**, jamais par `split(':')` naïf — sinon collision
   avec les autres préfixes.
3. **`G` et `S` seuls** sont gérés par le driver v1 (mode « kiosque », bouton physique) mais
   **ne sont jamais émis par `ss_basic.ino`**. En v3 : les parser (retour `Kiosk::Start` / `Kiosk::Stop`),
   les logger, ne rien en faire tant que le matériel correspondant n'est pas confirmé. Coût : 4 lignes.
4. Une trame reçue peut ne contenir aucun `:`. Gérer proprement.
5. **`<i>F:` peut porter un nombre négatif en mode temps.** Le firmware imprime
   `Serial.println(raceLengthSecs * 1000, DEC)` — arithmétique `int` 16 bits, qui déborde dès
   `raceLengthSecs > 32`. Pour `T = 60` la trame serait `0F:-5536`. La regex `^([0-3])F:(\d+)$`
   ne matche pas : la trame part en `Unknown` et est logguée. C'est le comportement voulu — mais
   voir §5.5, en pratique cette branche n'est jamais atteinte.
6. **Fin du flux `R:` sans perte de lien.** En mode distance, le firmware arrête d'émettre dès que
   *les quatre* pistes ont franchi la ligne (`checkDistanceBased()` met `raceStarted = false`).
   Un silence sur `R:` n'est donc pas nécessairement une perte de lien. Voir §6.2.

### `R:` porte des **valeurs absolues**, pas des deltas

Conséquence directe : la perte d'une trame est sans effet, l'état PC est simplement écrasé par la
dernière valeur reçue. **Ne jamais accumuler de deltas côté PC.** C'est ce qui rend le système robuste ;
le préserver est une contrainte d'architecture, pas un détail d'implémentation.

### `elapsedMs` est l'horloge de référence

L'horloge du PC ne sert **jamais** à dater la course. Le chrono affiché, les temps de passage et
tous les calculs de vitesse dérivent de `elapsedMs` du firmware. L'horloge PC ne sert qu'à
détecter la perte de lien (watchdog, §6.2) et à interpoler entre deux trames pour le rendu.

---

## 4. Handshake et cycle de vie de la connexion

```
        ┌──────────────┐
        │ DISCONNECTED │◀──────────────────────────────┐
        └──────┬───────┘                               │
               │ scan ports (1 Hz)                     │ IOException / watchdog
               ▼                                       │
        ┌──────────────┐                               │
        │  PORT_OPEN   │  envoie "s" puis "v"          │
        └──────┬───────┘                               │
               │ reçoit V:SS_v...  (timeout 2 s, 3 essais)
               ▼                                       │
        ┌──────────────┐                               │
        │  IDENTIFIED  │───────────────────────────────┘
        └──────────────┘   seul état où START est autorisé
```

**Correction obligatoire vs v1 :** le logiciel v1 autorisait le démarrage d'une course dès que le
port était ouvert, sans avoir reçu `V:`. En v3, **`IDENTIFIED` est la seule condition d'activation
du bouton START.** Un port ouvert sans réponse `V:` après 3 tentatives est fermé et blacklisté
pour ce cycle de scan.

### Sélection du port

Ordre de priorité, du plus fiable au plus laxiste :

1. Port explicitement choisi par l'opérateur dans les réglages (persisté).
2. Match sur **VID/PID USB** — disponible via `hardware_id` mais **jamais exploité en v1**.
   VID/PID connus à allowlister : Arduino Uno officiel `2341:0043`, `2341:0001` ;
   clones CH340 `1a86:7523` ; FTDI `0403:6001` ; CP210x `10c4:ea60`.
   *À compléter en branchant le matériel réel de l'utilisateur (`lsusb` / gestionnaire de périphériques).*
3. Match regex sur le nom de port (`Arduino.*`, `ttyUSB.*`, `ttyACM.*`, `usbserial.*`, `COM\d+`).
4. **Interdit :** le fallback v1 « prendre le dernier port de la liste ». Il ouvrait n'importe quel
   périphérique série de la machine. Supprimé.

Sur chaque candidat, l'identification par `V:` fait foi. Un port qui ne répond pas n'est pas le boîtier.

---

## 5. Limitations firmware — et pourquoi le PC devient autoritaire

Ce sont les découvertes déterminantes de l'analyse. Elles dictent l'architecture de la v3.

### 5.1 Le firmware ignore le nombre de riders actifs

Il n'existe **aucune commande** pour lui transmettre `numRacers`. Il boucle toujours sur les 4 pistes.
En mode distance, sa condition de fin est *« les 4 riders ont franchi la ligne »*
(`checkDistanceBased()`). Avec 2 riders et 2 capteurs non câblés, **la course ne se termine jamais** :
il faut l'arrêter à la main. C'est un bug d'usage majeur du logiciel existant.

### 5.2 Le firmware ne connaît pas le mode poursuite

Et il ne le connaîtra pas, puisqu'on ne le modifie pas.

### 5.3 Le faux départ n'a aucune conséquence

Le firmware émet `FS:<idx>` et éteint la LED, mais le rider continue de courir et le v1 se contentait
de logguer l'événement (le code de disqualification est commenté).

### 5.4 → Décision d'architecture : **PC autoritaire, firmware = capteur**

Le firmware n'est utilisé que pour ce qu'il fait bien :

* fournir un flux de ticks cumulés horodatés à 100 Hz,
* cadencer le décompte et piloter les LED physiques,
* détecter les faux départs.

**Toute l'arbitrage de course est calculé sur le PC** à partir du flux `R:` : conditions de fin,
classement, élimination, écarts, disqualification. Le PC envoie `s` quand *lui* décide que c'est fini.

Recette d'exploitation qui en découle :

| Mode de jeu | Ce qu'on envoie au firmware | Qui décide la fin |
|---|---|---|
| Distance | `d` + `l<ticks>` + `g` | **le PC** (dès que les riders *actifs* ont fini). Le firmware peut aussi émettre ses `<i>F:` — on les utilise comme confirmation, jamais comme condition. |
| Temps | `x` + `t<secs>` + `g` | **le PC exclusivement.** La redondance firmware est illusoire au-delà de 32 s — voir §5.5. |
| **Poursuite** | `x` + `t<plafond_secs>` + `g` | **le PC exclusivement**, sur le critère d'écart. `t` **ne sert à rien** (§5.5) : le garde-fou anti-course-infinie est entièrement côté PC. On émet quand même `t` pour laisser le firmware dans un état cohérent. |

Cette table est le cœur du plan. Un dev qui l'ignore reproduira les bugs de la v1.

### 5.5 Le firmware ne termine jamais une course en temps au-delà de 32 secondes

Découvert à la relecture ligne à ligne de `ss_basic.ino` (v3, session initiale). C'est un bug
firmware supplémentaire, du même ordre de gravité que §5.1.

```c
int raceLengthSecs = 60;              // int = 16 bits signés sur AVR
...
void checkTimeBased() {
    if(currentTimeMillis > raceLengthSecs * 1000){   // ← débordement int
```

`raceLengthSecs * 1000` est une multiplication **entre deux `int`** : le résultat est calculé en
16 bits *avant* toute promotion. Pour `T = 60`, `60000` déborde et vaut `-5536`. La comparaison
avec `currentTimeMillis`, un `unsigned long`, convertit ce `-5536` en `4294961760` — environ
49,7 jours. **La condition n'est jamais vraie.**

| `T` demandé | `T × 1000` en `int16` | Comportement firmware |
|---|---|---|
| ≤ 32 s | correct (≤ 32000) | la course se termine, `<i>F:` émis pour les 4 pistes |
| ≥ 33 s | déborde, négatif | **la course ne se termine jamais**, aucun `<i>F:` |

Conséquences normatives :

* En **mode temps**, la condition de fin est calculée **par le PC seul** (`elapsedMs ≥ T × 1000`).
  La « double détection » décrite dans une version antérieure de `02` §2 n'existe pas. Les `<i>F:`
  éventuels (T ≤ 32 s) sont acceptés comme confirmation, jamais comme condition.
* En **mode poursuite**, `t<plafond_secs>` avec un plafond de 300 s est **inopérant**. Le garde-fou
  anti-course-infinie doit être implémenté côté PC, sans exception. On continue d'émettre `t` par
  hygiène de protocole, pas pour son effet.
* Le driver **n'attend jamais** de `<i>F:` pour conclure quoi que ce soit, dans aucun mode.

Le firmware n'étant pas modifié en v3, ce bug est une contrainte permanente, pas un incident.

---

## 6. Robustesse exigée du driver

### 6.1 Threading

Un thread dédié à la lecture série, communication avec le thread de jeu par **file SPSC lock-free**
(le `EventQueue<T, N>` de la v2 est correct et réutilisable tel quel).
**Aucun appel à l'API du moteur depuis le thread série.** C'est précisément la faute de la v1
(appels Cinder et mutation du singleton `Model` depuis le thread série → data races et crashs aléatoires).

### 6.2 Watchdog

Le watchdog n'est **armé que pendant l'état `RUNNING` de la FSM du PC**, et il est **désarmé dès
que le PC quitte `RUNNING`** — pas seulement à l'émission de `s`. Raison : en mode distance, le
firmware cesse d'émettre `R:` sitôt que les quatre pistes matérielles ont fini (§3, anomalie 6).
Avec quatre riders actifs, ce silence peut précéder de quelques millisecondes la conclusion du PC.
Un watchdog encore armé afficherait alors un faux `LINK_LOST` à l'instant précis de l'arrivée —
sur l'écran spectacle, au pire moment possible.

Si aucune trame `R:` n'est reçue pendant **500 ms alors qu'une course est en cours** :
bascule en `LINK_LOST`, gel du rendu de course sur la dernière valeur connue, bandeau d'alerte,
tentative de reconnexion. Si le lien revient sous 3 s, la course reprend
(l'`elapsedMs` firmware garantit qu'aucune donnée n'est perdue — voir §3, valeurs absolues).
Au-delà : course annulée, résultat marqué `INTERROMPUE` dans le log.

### 6.3 Filtrage des ticks aberrants

Sans debounce firmware, un rebond de contact peut produire un tick fantôme. Filtre côté PC :
rejeter toute trame `R:` impliquant une vitesse instantanée **> 120 km/h** ou un delta de ticks
incompatible avec le `elapsedMs` écoulé. Un tick rejeté est loggué, jamais silencieusement absorbé.

### 6.4 Reconnexion

Scan des ports à 1 Hz en `DISCONNECTED`. Backoff exponentiel plafonné à 5 s après 10 échecs
consécutifs sur le même port.

---

## 7. Constantes physiques (identiques à v1, à préserver)

```
diamètre rouleau par défaut   : 114.3 mm   (4.5")
circonférence                 : diamètre × π
1 tick                        : 1 tour de rouleau = 1 circonférence
distance (m)                  : ticks × circonférence_mm / 1000
vitesse (km/h)                : (Δticks × circonférence_mm / 1000) / Δs × 3.6
ticks pour N mètres           : floor(N × 1000 / circonférence_mm)
```

Vérification de non-régression : **100 m avec un rouleau de 114.3 mm = 278 ticks**
(valeur confirmée par le test v2 `tests/test_settings.cpp:56-62`). À reprendre en test unitaire v3.

Pas de gear ratio, pas de ratio de transmission : la seule calibration est le **diamètre du rouleau
en mm**, mesuré physiquement (distance aimant → centre du rouleau, ×2).

Lissage de la vitesse affichée : moyenne mobile. v1 utilisait 60 échantillons (~600 ms à 100 Hz),
v2 utilisait 10 (~100 ms). **Retenir 20 échantillons (~200 ms)** : v1 était trop mou pour un rendu
de jeu, v2 trop nerveux. Paramètre exposé en réglage avancé.
