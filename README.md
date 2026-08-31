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

Preuves dans `tasks/preuves/`.

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

## Outils

| | |
|---|---|
| `tools/ss_emu/` | émulateur du firmware sur pseudo-terminal — permet de développer et de tester tout le lien série sans matériel branché |
| `tools/ss_probe.py` | sonde console indépendante : handshake, ticks en direct, watchdog. Témoin croisé, sans code commun avec l'émulateur |

```sh
cmake -S tools/ss_emu -B tools/ss_emu/build && cmake --build tools/ss_emu/build -j
./tools/ss_emu/build/ss_emu_tests
./tools/ss_emu/build/ss_emu --pty --link ./.run/ttyEMU --riders 2 --profile egaux
python3 tools/ss_probe.py ./.run/ttyEMU
```

## Historique

* **v1** — [cwhitney/SilverSprint](https://github.com/cwhitney/SilverSprint), C++/Cinder, macOS + Windows
* **v2** — prototype C++/SDL2/ImGui, abandonné (post-mortem intégré aux specs)
* **v3** — cette version
