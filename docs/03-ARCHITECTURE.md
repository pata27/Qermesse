# 03 — Architecture technique

## 1. Stack retenue

| Couche | Choix | Justification |
|---|---|---|
| Moteur | **Godot 4.5** (renderer Forward+) | 3D, shaders, particules, audio, UI et export natif Win/Linux/macOS depuis une seule machine. Gratuit, sans royalties, projet ouvert. |
| Gameplay / UI | **GDScript** | itération rapide, hot-reload, largement suffisant pour de la logique à 100 Hz |
| Cœur métier | **GDScript, en `RefCounted` purs sans dépendance à la scène** | testable en headless |
| Port série | **GDExtension C++**, couche série écrite à la main | Godot n'a pas d'accès série natif. Module isolé, testable seul. Voir ci-dessous : `libserialport` a été écarté. |
| Build natif | **SCons** (chaîne standard godot-cpp, sous-module dans `third_party/`, hors ressources) | |
| CI | **GitHub Actions**, matrice ubuntu / windows / macos | |

### Pourquoi pas `libserialport`

Le choix initial était `libserialport`. Il est abandonné, pour une raison unique mais dirimante :
**la contrainte « aucune dépendance à reconstruire par réseau »** de `06` §4. `libserialport` se
construit par autotools et son `config.h` est généré ; l'intégrer à une chaîne SCons multiplateforme
suppose d'écrire ce `config.h` à la main pour chaque OS, ce qui est exactement le genre de bricolage
qui casse la veille d'un événement, sur un portable, sans réseau.

Ce qu'il apportait vraiment se réduit à deux choses : ouvrir un port, et l'énumérer avec son VID/PID.
La première est banale (`termios` sur POSIX, `SetCommState` sur Windows). La seconde est la seule
partie réellement fastidieuse, et elle tient en trois implémentations courtes :

| OS | Énumération VID/PID |
|---|---|
| Linux | `/sys/class/tty/<port>/device/../{idVendor,idProduct}` |
| macOS | IOKit — `IOServiceMatching("IOSerialBSDClient")`, propriétés `idVendor` / `idProduct` |
| Windows | SetupAPI — identifiant matériel `USB\VID_2341&PID_0043` |

Coût estimé : environ 400 lignes au total, contre un système de build tiers à dompter sur trois OS.
Le module reste isolé derrière une interface étroite (`serial_port.h`), donc réversible : si cette
couche s'avérait fragile, le repli reste le pont TCP décrit au §4.

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
├── third_party/                   # .gdignore — godot-cpp (sous-module), doctest : hors ressources
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
│   ├── main.tscn                  # routeur
│   ├── main.gd
│   ├── app_controller.gd          # assemblage lien ⇄ cœur métier — le SEUL point de rencontre
│   ├── operator/                  # fenêtre opérateur (roster, réglages, contrôle, résultats)
│   │   ├── operator_panel.gd
│   │   └── panel_{roster,mode,hardware,race,results}.gd
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

`core/` ne **journalise** pas non plus : un `push_warning` y imposerait un canal de sortie à du code
qui doit rester utilisable en headless, en test et en rejeu. Les modules rapportent un motif, la
couche applicative décide de l'afficher.

`scenes/app_controller.gd` est le seul fichier qui connaisse à la fois `hardware/` et `core/`. Toute
l'interface passe par lui et ne mute jamais l'état directement — c'est aussi ce qui rend le jalon J3
démontrable sans écran : les tests appellent exactement ce que les boutons appellent.

### Pourquoi la fenêtre opérateur est construite en code et non en `.tscn`

C'est un formulaire dense, piloté de bout en bout par `Settings` et `Roster`. En scène, chaque champ
existerait deux fois — une fois dans le `.tscn`, une fois dans le script qui le remplit — et il
faudrait charger une ressource pour le tester. En code, la fenêtre s'instancie en headless, ce qui
permet à la CI de mener une course complète à l'interface sur les trois OS.

La fenêtre **spectacle** relèvera d'un choix inverse : elle est du travail visuel, pas de la saisie,
et sera une vraie scène (lot 4).

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
L'anticipation est **bornée à un tick** au-delà de la dernière mesure : c'est exactement ce qu'il
faut pour remplir l'attente du tick suivant à basse vitesse, et jamais assez pour faire franchir
la ligne à un rider qui ne l'a pas atteinte. Corollaire : lien perdu (`01` §6.2), le rider s'arrête
à un tick de sa dernière mesure — il ne glisse pas dans le vide à sa dernière vitesse, et n'a rien à
rattraper au retour.

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
rien tester de bout en bout.

### Deux simulateurs, deux rôles — ne pas les confondre

`link_sim.gd` court-circuite par construction la couche série : c'est ce qui le rend gratuit à
exécuter en CI, et c'est aussi ce qui fait qu'il **ne teste pas la partie risquée**. C'est très
exactement l'erreur de la v2, dont le mode mock injectait des structures déjà parsées.

D'où un second simulateur, situé un cran plus bas : **`tools/ss_emu`**, un émulateur du firmware
qui parle sur un vrai pseudo-terminal, à 115200 bauds, octet par octet. Le code Godot ne sait pas
qu'il ne parle pas à un Arduino. Ouverture de port, threading, découpage de flux, handshake,
watchdog et reconnexion sont donc traversés pour de vrai, sans matériel branché.

Spécification complète : **`docs/07-EMULATEUR-FIRMWARE.md`**.

`link_sim.gd` reste indispensable — il est instantané, disponible sur les trois OS et sert les
tests headless du cœur métier. Il doit produire des trames **identiques** à celles de `ss_emu`,
bugs firmware compris ; un test de conformité compare les deux sur un scénario à graine fixée.

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
