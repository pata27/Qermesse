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

## Historique

* **v1** — [cwhitney/SilverSprint](https://github.com/cwhitney/SilverSprint), C++/Cinder, macOS + Windows
* **v2** — prototype C++/SDL2/ImGui, abandonné (post-mortem intégré aux specs)
* **v3** — cette version
