# 06 — Qualité, CI, risques

## 1. Règles de développement non négociables

1. **La donnée avant le pixel.** Aucun travail de rendu 3D avant validation du lot 2 sur matériel réel.
2. **`core/` ne dépend de rien.** Ni scène, ni port série, ni rendu. Testable en headless.
3. **Un seul thread mute l'état.** Le thread série écrit dans un ring buffer, point final.
4. **Pas d'état mort.** Tout état de la FSM est atteint par au moins un test.
5. **Pas d'asset orphelin.** Un fichier non référencé est supprimé, pas laissé « au cas où ».
6. **Le protocole série est documenté avant d'être codé**, et `docs/01` reste la source de vérité.
7. **Aucune tâche cochée sans preuve** : sortie de test, capture, ou vidéo.

## 2. Tests

| Niveau | Outil | Portée |
|---|---|---|
| Unitaire C++ | doctest, binaire natif | `line_parser`, ring buffer, `FirmwareSim` — sans Godot |
| Bout en bout série | `tools/ss_emu` sur pseudo-terminal | ouverture de port, handshake, threading, watchdog, reconnexion — la partie risquée |
| Unitaire GDScript | GUT headless | `physics`, `race_engine`, les trois règles, `recorder`, `settings` |
| Rejeu | GUT + courses JSON | une course enregistrée rejouée doit donner exactement le même classement — **y compris interrompue**, où le rejeu reproduit l'interruption et rend le classement partiel |
| Injection de pannes | `link_sim` | trame corrompue, perte de lien, tick fantôme, faux départ |
| Manuel matériel | checklist `docs/RECETTE.md` | avant chaque release |

Le rejeu est le filet de sécurité le plus rentable du projet : chaque course réelle enregistrée en
JSON devient un cas de test permanent. Après le premier événement, on dispose d'une batterie de cas
réels que personne n'aurait su écrire à la main.

## 3. CI

Matrice `ubuntu-latest` / `windows-latest` / `macos-latest` :
build du GDExtension, tests C++, import du projet Godot, tests GUT headless, export des binaires.
Sur tag : publication d'une release avec les trois artefacts.

## 4. Risques et parades

| Risque | Impact | Parade |
|---|---|---|
| **Compilation du GDExtension pénible sur les 3 OS** | fort, bloque tout | attaqué en lot 1, CI sur les 3 OS dès J0, plan B « pont TCP » documenté et décidé explicitement si dérapage > 6 j |
| **Le firmware réel diverge de `ss_basic.ino`** (boîtier reflashé, variante) | fort | J1 valide contre le matériel réel avant toute autre chose ; le parseur logue toute trame inconnue au lieu de l'ignorer |
| **Matériel indisponible pendant le développement** | fort, bloque le lot 1 | `tools/ss_emu` (document `07`) émule le firmware sur un vrai pseudo-terminal : tout le code risqué est traversé sans matériel. Jalon intermédiaire J1-ém, qui **ne remplace pas J1** |
| **Se satisfaire de l'émulateur et ne jamais brancher le boîtier** | fort | J1-ém est explicitement marqué insuffisant pour ouvrir le lot 4 ; `07` §2 liste ce que l'émulateur ne prouve pas |
| **Trames `G`/`S` réellement émises par un shield kiosque** | moyen | parsées et loggées dès le lot 1, comportement activé seulement si observé |
| **Perf 3D insuffisante sur GPU intégré** | moyen | budget fixé et mesuré à J4, trois niveaux de qualité, effets coupables identifiés (volumétrique, foule, flou radial) |
| **Le mode poursuite ne « prend » pas au test terrain** | moyen | règle 3–4 riders paramétrable derrière `PursuitRule`, `G` réglable en direct, les deux variantes livrées |
| **Ticks fantômes par rebond de contact** (aucun debounce firmware) | moyen | filtre PC §6.3 du document `01`, tout rejet loggué et visible dans le panneau matériel |
| **Dérive artistique** (le piège de la v2) | moyen | direction figée par `docs/04` avant le lot 4, tout asset non utilisé supprimé |
| **Signature/notarisation macOS sans compte développeur** | faible | procédure Gatekeeper documentée pour l'utilisateur, à défaut |
| **Événement sans réseau, build à refaire sur place** | faible | dépendances vendorisées ou en submodule épinglé, aucun `FetchContent` qui reclone (erreur de la v2) |

## 5. Décisions à confirmer avec l'utilisateur

Ces points ne bloquent pas le démarrage — les lots 0 à 2 peuvent commencer — mais doivent être
tranchés avant les lots concernés.

1. **Poursuite à 3–4 riders** : élimination progressive (retenue par défaut) ou « premier à mettre
   `G` à tous les autres ». *Avant le lot 2.*
2. **VID/PID du matériel réel** : brancher le boîtier et relever l'identifiant USB
   (`lsusb` sur Linux) pour alimenter l'allowlist. *Avant le jalon J1.*
3. **Nombre de capteurs réellement câblés** sur le boîtier de l'utilisateur : 2 ou 4 ?
   Conditionne l'effort de test à 4 riders. *Avant le lot 3.*
4. **Compte développeur Apple** disponible ou non. *Avant le lot 6.*
5. **Marque et habillage** : logo, nom affiché, éventuels sponsors à afficher sur l'écran spectacle.
   *Avant le lot 5.*

## 6. Hors périmètre de cette version

Notés pour ne pas être improvisés en cours de route :

* mode tournoi / brackets / qualifications à plusieurs manches ;
* multijoueur en réseau entre plusieurs boîtiers distants ;
* diffusion en direct, incrustation OBS, overlay web ;
* classements en ligne, comptes utilisateurs ;
* réécriture du firmware (envisageable en v3.1, avec négociation de version au handshake —
  l'architecture le permet déjà, le driver n'en dépend pas).
