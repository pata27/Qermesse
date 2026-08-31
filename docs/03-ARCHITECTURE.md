# 03 — Architecture technique

## 1. Stack retenue

| Couche | Choix | Justification |
|---|---|---|
| Moteur | **Godot 4.5** (renderer Forward+) | 3D, shaders, particules, audio, UI et export natif Win/Linux/macOS depuis une seule machine. Gratuit, sans royalties, projet ouvert. |
| Gameplay / UI | **GDScript** | itération rapide, hot-reload, largement suffisant pour de la logique à 100 Hz |
| Cœur métier | **GDScript, en `RefCounted` purs sans dépendance à la scène** | testable en headless |
| Port série | **GDExtension C++** (`libserialport`) | Godot n'a pas d'accès série natif. Module isolé, ~400 lignes, testable seul |
| Build natif | **SCons** (chaîne standard godot-cpp) | |
| CI | **GitHub Actions**, matrice ubuntu / windows / macos | |

### Pourquoi pas la stack de la v2 (SDL2 + OpenGL + Dear ImGui)

Le post-mortem est net : le choix n'était pas absurde pour un kiosque, mais il oblige à réécrire à
la main tout ce qu'un moteur donne gratuitement. La v2 a fini par dessiner un vélo en primitives
vectorielles dans `ImDrawList` — 500 lignes pour une silhouette 2D. L'objectif v3 étant une vue 3D
immersive, cette voie coûte plusieurs mois avant le premier rendu convaincant.

### Ce qu'on reprend de la v2 (concepts, pas code)

* La séparation stricte cœur métier testable / couche de rendu.
* Le pattern vue → commande : une vue ne mute jamais l'état, elle émet une intention.
* La file SPSC lock-free entre thread série et thread principal.
* La persistance des réglages en JSON avec chemins par OS.

---

## 2. Arborescence du projet

```
SilverSprint-v3/
├── docs/                          # ces specs — source de vérité
├── tasks/
│   ├── todo.md                    # avancement, coché au fil de l'eau
│   └── lessons.md                 # corrections reçues, à relire au début de chaque session
├── addons/serial_link/            # GDExtension C++
│   ├── src/serial_link.{h,cpp}    # noeud SerialLink exposé à Godot
│   ├── src/ring_buffer.h          # SPSC lock-free
│   ├── src/line_parser.{h,cpp}    # découpage \r\n + parsing des trames — SANS dépendance Godot
│   ├── SConstruct
│   └── tests/                     # tests C++ natifs (doctest), tournent hors Godot
├── project.godot
├── core/                          # AUCUNE dépendance à un Node ou à une scène
│   ├── protocol.gd                # encodage/décodage des trames — miroir GDScript de line_parser
│   ├── race_engine.gd             # FSM + arbitrage, le cœur
│   ├── rules/
│   │   ├── rule_distance.gd
│   │   ├── rule_time.gd
│   │   └── rule_pursuit.gd
│   ├── physics.gd                 # ticks ⇄ mètres ⇄ km/h
│   ├── roster.gd
│   ├── settings.gd
│   └── recorder.gd                # CSV + JSON
├── hardware/
│   ├── link.gd                    # façade : SerialLink réel OU simulateur, même interface
│   ├── link_serial.gd
│   └── link_sim.gd                # simulateur de riders (voir §5)
├── scenes/
│   ├── main.tscn                  # routeur, autoload
│   ├── operator/                  # fenêtre opérateur (roster, réglages, contrôle, résultats)
│   ├── race3d/                    # scène 3D plein écran
│   └── shared/                    # composants UI réutilisables
├── art/
│   ├── track/  models/  materials/  shaders/  vfx/
├── audio/
└── tests/
    ├── unit/                      # GUT, headless
    └── replay/                    # rejeu de courses JSON enregistrées
```

**Règle d'or :** `core/` ne connaît ni Godot-la-scène, ni le port série, ni le rendu. Il reçoit des
`TickSample` et émet des événements. Il doit tourner en headless et être testable sans écran.
C'est la condition pour ne pas refaire l'erreur de la v1 (état mutable partagé entre threads).

---

## 3. Flux de données

```
  Arduino ──série 115200──▶ [thread C++ lecture]
                                   │  découpe \r\n, parse, valide
                                   ▼
                            [ring buffer SPSC]
                                   │
   Godot _process() ──── drain ────┤
                                   ▼
                          hardware/link.gd  (façade)
                                   │  signal tick_sample(t0..t3, elapsed_ms)
                                   ▼
                        core/race_engine.gd  ── FSM + règle active
                                   │  signaux : countdown, started, rider_finished,
                                   │            rider_eliminated, gap_changed, finished
                    ┌──────────────┴──────────────┐
                    ▼                             ▼
            scenes/race3d (rendu)        core/recorder.gd (CSV + JSON)
                    │
                    ▼
            scenes/operator (2e fenêtre)
```

Un seul sens de circulation. Le rendu **lit** l'état, ne l'écrit jamais.

### Interpolation

Les trames arrivent à 100 Hz, le rendu tourne à 60–144 Hz. La position 3D d'un rider est
**interpolée** entre les deux dernières trames à partir de sa vitesse lissée, jamais téléportée.
Sans ça le rendu saccade visiblement à basse vitesse. C'est un vrai piège : à 5 km/h, un rider
produit un tick toutes les ~260 ms, soit un point de donnée toutes les 15 images.

---

## 4. Le module `SerialLink` (GDExtension)

API exposée à GDScript :

```gdscript
signal frame_received(kind: int, payload: Dictionary)
signal state_changed(state: int)          # DISCONNECTED / PORT_OPEN / IDENTIFIED / LINK_LOST

func list_ports() -> Array[Dictionary]     # {port, description, vid, pid}
func set_preferred_port(port: String) -> void
func start_autoconnect() -> void
func stop() -> void
func send_command(cmd: String) -> bool     # valide et borne AVANT émission
func get_firmware_version() -> String
```

Contraintes d'implémentation :

* Le parsing de ligne (`line_parser`) est **du C++ pur, sans include Godot**, pour être testable
  par un binaire natif dans la CI, sans lancer le moteur.
* `send_command` **rejette** toute commande hors de la liste du document `01` §2, et borne les
  arguments numériques à 7 chiffres (dépassement du `char charBuff[8]` firmware).
* Aucune allocation dans le thread de lecture pendant une course.
* Aucun appel à l'API Godot depuis le thread de lecture : le thread écrit dans le ring buffer,
  le thread principal draine et émet les signaux.

### Repli si le GDExtension pose problème sur une plateforme

Plan B documenté, non implémenté par défaut : un petit binaire pont (`silversprint-bridge`) qui
lit le port série et expose les trames sur une socket TCP locale, Godot s'y connectant en
`StreamPeerTCP`. Coûte un process supplémentaire mais élimine tout risque de compilation native
par plateforme. **À n'activer que si le lot 1 dérape** — voir `04`, jalon J1.

---

## 5. Simulateur (`link_sim.gd`) — à écrire dès le lot 1

Implémente la même interface que le lien série et génère un flux `R:` synthétique crédible :

* courbe de puissance par rider avec accélération, plafond de vitesse et fatigue,
* jitter et bruit sur la cadence pour ressembler à du vrai capteur,
* profils prédéfinis : `égaux`, `écart léger`, `domination`, `remontée finale`, `abandon`,
* injection de pannes à la demande : trame corrompue, perte de lien, faux départ, tick fantôme.

Sans ça, aucun développement ni aucune démo n'est possible sans matériel branché, et la CI ne peut
rien tester de bout en bout. **C'est ce qui a manqué à la v2** : son mode mock court-circuitait la
couche série au lieu de la simuler, donc ne testait justement pas la partie risquée.

---

## 6. Deux fenêtres

Godot 4 gère nativement plusieurs fenêtres (`Window`).

* **Fenêtre opérateur** — écran du portable. Roster, sélection du mode, réglages, port série,
  bouton START/STOP, chrono, résultats, export.
* **Fenêtre spectacle** — vidéoprojecteur / grand écran, plein écran sans décoration, vue 3D pure.
  Aucun élément d'interface opérateur ne doit y apparaître.

Choix de l'écran de destination persisté. Mode dégradé mono-écran (tout dans une fenêtre, la 3D en
fond et l'UI opérateur en surimpression rétractable) pour le développement et les petits événements.

**Lisibilité à 3 mètres** : toute information de la fenêtre spectacle doit rester lisible à distance
sur un projecteur médiocre. Taille de police minimale 32 px à 1080p, contraste ≥ 4.5:1, aucune
information portée par la seule couleur (un rider est identifié par sa couleur **et** son numéro de piste).
