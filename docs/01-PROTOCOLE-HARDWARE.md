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

* Le buffer de parsing numérique du firmware fait **8 octets sans garde de dépassement**
  (`char charBuff[8]`). Le driver PC **doit** borner `<ticks>` et `<secs>` à **7 chiffres max**
  et refuser toute valeur hors bornes avant émission. Non négociable : dépassement = corruption mémoire AVR.
* `d`, `x`, `t`, `s` sont *fire-and-forget*. Ne jamais attendre d'ack sur ces commandes.
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
2. **`<idx>F:` se parse par regex `^([0-3])F:(\d+)$`**, jamais par `split(':')` naïf — sinon collision
   avec les autres préfixes.
3. **`G` et `S` seuls** sont gérés par le driver v1 (mode « kiosque », bouton physique) mais
   **ne sont jamais émis par `ss_basic.ino`**. En v3 : les parser (retour `Kiosk::Start` / `Kiosk::Stop`),
   les logger, ne rien en faire tant que le matériel correspondant n'est pas confirmé. Coût : 4 lignes.
4. Une trame reçue peut ne contenir aucun `:`. Gérer proprement.

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
| Temps | `x` + `t<secs>` + `g` | le firmware **et** le PC (redondance, on prend le premier des deux) |
| **Poursuite** | `x` + `t<plafond_secs>` + `g` | **le PC exclusivement**, sur le critère d'écart. `t` sert de garde-fou anti-course-infinie. |

Cette table est le cœur du plan. Un dev qui l'ignore reproduira les bugs de la v1.

---

## 6. Robustesse exigée du driver

### 6.1 Threading

Un thread dédié à la lecture série, communication avec le thread de jeu par **file SPSC lock-free**
(le `EventQueue<T, N>` de la v2 est correct et réutilisable tel quel).
**Aucun appel à l'API du moteur depuis le thread série.** C'est précisément la faute de la v1
(appels Cinder et mutation du singleton `Model` depuis le thread série → data races et crashs aléatoires).

### 6.2 Watchdog

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
