# Preuve — le parcours d'un tiers sur un clone vierge

**Date** 2026-09-03 · commit `a937865` · préparatoire au jalon **J6**

J6 demande qu'« un tiers installe sur machine vierge et fasse courir deux personnes sans aide ».
La partie logicielle de ce parcours a été déroulée à la lettre, depuis un clone frais, sans réutiliser
aucun artefact de la machine de développement.

## Ce qui a été exécuté

| Étape du README | Résultat |
|---|---|
| `git clone --recurse-submodules` | sous-module `third_party/godot-cpp` récupéré |
| `cmake -S . -B build && cmake --build build -j` | compile |
| `ctest --test-dir build` | **2/2** |
| `cd addons/serial_link && scons target=template_debug -j8` | **2 min 54** à froid, bibliothèque produite |
| `godot --headless --import` | **une seule fois suffit** |
| `godot --headless --script tests/run.gd` | **200/200** |
| `ss_emu --pty --link ./.run/ttyEMU --riders 2 --profile domination` | pseudo-terminal créé |
| `ss_monitor -- --port ./.run/ttyEMU --distance 100 --duree 25` | `firmware SS_v0.1.7`, deux arrivées, **1 916 trames**, code 0 |

## Ce que ça établit

* Le dépôt se construit et se teste **sans rien d'autre que ce que le README nomme**.
* La suite headless passe **avant** toute compilation du module natif : un tiers voit le projet vert
  en quelques minutes, et ne compile le C++ que s'il veut brancher un boîtier.
* Le déplacement de `godot-cpp` vers `third_party/` n'a pas cassé la chaîne SCons sur un clone frais.

## Deux choses trouvées en le faisant

1. **Chemin de clone trop long.** À 99 caractères de chemin, l'édition de liens de `godot-cpp` échoue
   sur `sh: Argument list too long` — des milliers de fichiers objets passés en une commande. À 25,
   elle passe. Le message ne dit rien de la cause : le README prévient désormais.
2. **`ss_monitor --port` listait les trente-deux ports** avant d'en venir au sujet. La liste détaillée
   sert à *chercher* le boîtier (`RECETTE` §1, sans `--port`) ; quand le port est nommé, elle est
   supprimée.

## Ce qui reste pour J6

Le matériel, et un tiers. Rien dans le logiciel n'a bloqué ce parcours.
