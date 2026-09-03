# SilverSprint v3

Logiciel de course de rouleaux (goldsprints) — refonte complète.

* **Moteur** Godot 4.5, module série en GDExtension C++
* **Plateformes** Windows, Linux, macOS — natif
* **Matériel** compatible avec les boîtiers SilverSprint / OpenSprints existants,
  firmware `SS_v0.1.7` non modifié
* **Modes** course en distance, course en temps, poursuite

## Démarrer

Lire `docs/00-BRIEF.md`, puis suivre `docs/05-PLAN-EXECUTION.md`.
Le suivi d'avancement est dans `tasks/todo.md`.

> **Cloner dans un chemin court.** La compilation de `godot-cpp` passe des milliers de fichiers
> objets à l'éditeur de liens : au-delà d'une centaine de caractères de chemin, elle échoue sur
> `sh: Argument list too long`, sans indiquer la cause. `~/Code/` va bien.

```sh
git clone --recurse-submodules <url> && cd SilverSprint-v3

# Tests natifs C++ — parseur, file SPSC, machine à états du lien, émulateur.
# Ne lancent ni Godot, ni port série.
cmake -S . -B build && cmake --build build -j && ctest --test-dir build --output-on-failure

# Module série natif.
cd addons/serial_link && scons target=template_debug -j8 && cd ../..

# Suite headless GDScript.
godot --headless --import && godot --headless --script tests/run.gd
```

### Sans matériel

```sh
# L'émulateur expose un vrai périphérique série.
./build/tools/ss_emu/ss_emu --pty --link ./.run/ttyEMU --riders 2 --profile domination

# L'outil console s'y connecte via le module natif.
godot --headless --script tools/ss_monitor.gd -- --port ./.run/ttyEMU --distance 100 --duree 20

# Ou, sans aucun port série, avec le simulateur GDScript :
godot --headless --script tools/ss_monitor.gd -- --sim --distance 100 --duree 20
```

## État

| Jalon | État |
|---|---|
| J0 — CI headless verte sur trois OS | **franchi** |
| J1-ém — lien série validé contre l'émulateur, via le GDExtension | **franchi** |
| J1 — validation sur l'Arduino réel | en attente du matériel |
| J2 — cœur métier vert en headless | **franchi** |
| J3 — course complète à l'interface opérateur, au simulateur | **franchi** |
| J4 — 60 fps stables en 1080p sur GPU intégré, 4 coureurs | **franchi** |
| J5 — trois modes, deux fenêtres, son | **franchi** (son vérifié sur pièces) |
| J6 — un tiers installe sur machine vierge et fait courir deux personnes | à faire |

Preuves dans `tasks/preuves/`.

## Ce que fait le logiciel

* **Deux fenêtres** : le panneau de pilotage sur l'écran de l'opérateur, la scène sur le
  projecteur — écran et plein écran choisis depuis le panneau. *Sous Wayland, le compositeur
  décide : voir `docs/DEPANNAGE.md`.*
* **Trois modes** : distance, temps, poursuite à élimination progressive. L'écran se scinde en
  autant de volets que de paquets, jusqu'à quatre.
* **Le son démarre coupé.** En événementiel la sono est gérée séparément ; un bouton l'active.
  Tout est synthétisé, aucun fichier audio.
* **Trois niveaux de qualité**, détectés au premier lancement, et une scène qui s'allège d'elle-même
  quand l'image se scinde.
* **Sans matériel** : un simulateur intégré et un émulateur de firmware sur vrai port série.

## Documentation

| | |
|---|---|
| `docs/00-BRIEF.md` | brief d'entrée, décisions prises |
| `docs/01-PROTOCOLE-HARDWARE.md` | contrat série — **normatif** |
| `docs/02-MODES-DE-JEU.md` | règles de course — **normatif** |
| `docs/03-ARCHITECTURE.md` | stack et structure |
| `docs/04-DIRECTION-ARTISTIQUE.md` | rendu, UX, audio |
| `docs/05-PLAN-EXECUTION.md` | lots et jalons |
| `docs/06-QUALITE-RISQUES.md` | tests, CI, risques |
| `docs/07-EMULATEUR-FIRMWARE.md` | émulateur de firmware `ss_emu` |
| `docs/RECETTE.md` | checklist matériel — jalon J1 et avant chaque release |
| `docs/DEPANNAGE.md` | dépannage terrain, écrit pour l'opérateur |
| `docs/MANUEL-OPERATEUR.md` | déroulé d'une soirée, panneau par panneau |

## Outils

| | |
|---|---|
| `tools/ss_emu/` | émulateur du firmware sur pseudo-terminal — permet de développer et de tester tout le lien série sans matériel branché |
| `tools/ss_probe.py` | sonde console indépendante : handshake, ticks en direct, watchdog. Témoin croisé, sans code commun avec l'émulateur. Codes de sortie : 0 course vue, 1 pas de `V:` sur ce port, 2 aucune arrivée pendant la fenêtre |
| `tools/ss_replay.gd` | rejoue une course enregistrée et vérifie qu'elle redonne le même classement. Sur un dossier, chaque course réelle devient un cas de test permanent |

```sh
cmake -S tools/ss_emu -B tools/ss_emu/build && cmake --build tools/ss_emu/build -j
./tools/ss_emu/build/ss_emu_tests
./tools/ss_emu/build/ss_emu --pty --link ./.run/ttyEMU --riders 2 --profile egaux
python3 tools/ss_probe.py ./.run/ttyEMU

# Rejeu : recalcule tout depuis les trames et compare au classement enregistré.
# Code 0 si tout concorde, 1 si une course diverge.
godot --headless --script tools/ss_replay.gd -- --dossier ~/.local/share/silversprint/races
```

## Historique

* **v1** — [cwhitney/SilverSprint](https://github.com/cwhitney/SilverSprint), C++/Cinder, macOS + Windows
* **v2** — prototype C++/SDL2/ImGui, abandonné (post-mortem intégré aux specs)
* **v3** — cette version
