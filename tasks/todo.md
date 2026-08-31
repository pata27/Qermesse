# SilverSprint v3 — Suivi

Spécifications : `docs/`. Brief d'entrée : `docs/00-BRIEF.md`.
**Aucune case cochée sans preuve** (sortie de test, capture, vidéo).

---

## Lot 0 — Fondations *(0.5 j)*

- [x] Dépôt git, `.gitignore` Godot, licence MIT, `README.md`
- [x] Projet Godot 4.5, renderer Forward+
- [x] Arborescence conforme à `docs/03` §2
- [x] GUT 9.6.1 vendorisé, test témoin vert en headless
- [x] GitHub Actions : lint + tests C++ + tests headless, matrice 3 OS
- [x] **J0** — `godot --headless --script tests/run.gd` sort en 0 sur les 3 OS
      *(preuve : `tasks/preuves/2026-08-31-J0-ci-trois-os.md`, run CI 33390935079, 7 jobs verts)*

## Lot 1 — Lien série *(3–4 j — lot le plus risqué)*

- [x] godot-cpp en submodule épinglé (`godot-4.5-stable`, `e83fd09`), SConstruct, build sur les 3 OS
- [x] `line_parser` C++ pur : toutes les trames de `docs/01` §3
- [x] Cas tordus couverts : erreur malformée à double préfixe portant un **octet brut**, trames sans
      `:`, `<idx>F:` parsé avant toute découpe sur `:`, `<i>F:` négatif, `G`/`S` kiosque
- [x] Ring buffer SPSC + thread de lecture + drain thread principal
      *(test de charge 2 threads / 100 000 trames)*
- [x] Énumération des ports avec VID/PID — `/sys/class/tty`, IOKit, SetupAPI
- [x] Sélection : port choisi → allowlist VID/PID → motif de nom. **Pas de fallback « dernier port »**
      *(preuve : 32 ports réels sur la machine, 0 candidat retenu)*
- [x] Handshake `s` puis `v`, attente `V:SS_v...`, 3 essais, timeout 2 s
- [x] `IDENTIFIED` = seule condition d'autorisation du départ
- [x] `send_command` : allowlist + bornage 7 chiffres **et** 1..32767, refus des `t` dangereux
- [x] Watchdog 500 ms armé à la première trame `R:`, reconnexion avec backoff plafonné à 5 s
- [x] Tests C++ natifs du parseur dans la CI, sans Godot
- [x] Test d'intégration driver ↔ émulateur sur vrai pseudo-terminal, en CI
- [x] `tools/ss_monitor.gd` — outil console du jalon, via le GDExtension
- [x] `tools/check_extension.gd` — vérifie que Godot CHARGE le module, pas seulement qu'il compile
- [x] `tools/ss_emu` — cœur `FirmwareSim`, réplique fidèle de `ss_basic.ino` bugs compris (`docs/07` §4)
      *(preuve : 50 cas doctest, 309 assertions, exit 0)*
- [x] `tools/ss_emu` — cyclistes synthétiques et 5 profils de course (`docs/07` §5)
- [x] `tools/ss_emu` — injection de 8 pannes (`docs/07` §6)
- [x] `tools/ss_emu` — frontal pseudo-terminal, CLI, `--trace`
      *(preuve : `tasks/preuves/2026-08-31-emulateur-pty.md`)*
- [x] Tests doctest de `FirmwareSim`, en temps virtuel *(à raccorder à la CI au lot 0)*
- [x] Sonde console indépendante `tools/ss_probe.py` — témoin croisé, pas l'outil de J1
- [ ] `link_sim.gd` : profils de course + injection de pannes (`docs/03` §5)
- [ ] Test de conformité `link_sim.gd` ↔ `ss_emu` sur scénario à graine fixée
- [x] **J1-ém** — contre `ss_emu`, **via le GDExtension** : handshake, ticks en direct, `LINK_LOST`,
      reconnexion sur pty renuméroté avec course survivante, trame corrompue absorbée
      *(preuve : `tasks/preuves/2026-08-31-J1em-gdextension.md`)*. Autorise le lot 2, **pas le lot 4**.
- [ ] **J1** — sur l'Arduino réel : ticks des pistes en direct, version firmware affichée,
      débranchement USB **physique** à chaud → `LINK_LOST` < 500 ms, rebranchement → reprise
      *(preuve : vidéo)*. **BLOQUÉ : boîtier non disponible.** Reste à faire : relever `lsusb`,
      compléter l'allowlist VID/PID de `port_selection.cpp`, vérifier l'affectation des pistes.

## Lot 2 — Cœur métier *(3 j)*

- [x] `physics.gd` : ticks ⇄ mètres ⇄ km/h, lissage 20 échantillons (`speed_smoother.gd`)
- [x] `race_engine.gd` : FSM de `docs/02`, PC autoritaire, riders actifs uniquement
- [x] `rule_distance.gd`
- [x] `rule_time.gd`
- [x] `rule_pursuit.gd` — élimination progressive. La variante « `G` à tous » reste implémentable
      derrière `RaceRule` mais n'est pas écrite : pas de code mort (`docs/06` §1)
- [x] Plafonds de sécurité de la poursuite (temps 300 s, distance 5000 m), marqués `INTERROMPUE`
- [x] Filtrage des ticks aberrants, rejets loggués — **avec tolérance d'un tick**, sans quoi le
      filtre rejetait une course entière ; `docs/01` §6.3 corrigé en conséquence
- [x] Politiques de faux départ : `IGNORE` / `AVERTISSEMENT` / `RELANCE` / `PENALITE`
- [x] `recorder.gd` : CSV en append **réel** + JSON par course avec trace complète des trames
- [x] `settings.gd` + `roster.gd` + `json_store.gd` (écriture atomique), chemins par OS,
      noms des riders persistés
- [x] `replay.gd` — rejeu qui recalcule tout, sans réinjecter le résultat enregistré
- [x] Test : `100 m @ 114.3 mm = 278 ticks`
- [x] Test : **course distance à 2 riders qui se termine** *(le bug historique de la v1)*
- [x] Test : poursuite 2 riders, fin au franchissement des 50 m
- [x] Test : poursuite 4 riders, ordre d'élimination et rangs corrects
- [x] Test : chaque état de la FSM atteint au moins une fois
- [x] Test : rejeu d'une course JSON → classement identique
- [x] **J2** — suite headless verte, 75 tests / 3160 assertions, exit 0
      *(preuve : `tasks/preuves/2026-08-31-J2-coeur-metier.md`)*

## Lot 3 — Interface opérateur *(4 j)*

- [ ] Roster 1–4 riders : noms, couleurs, activation de piste
- [ ] Sélection du mode et de ses paramètres (`D`, `T`, `G`, politique de faux départ)
- [ ] Panneau matériel : ports, état du lien, version firmware
- [ ] Test capteurs : tourner chaque rouleau, vérifier que les ticks arrivent sur la bonne piste
- [ ] Calibration du diamètre de rouleau, avec aide à la mesure
- [ ] Contrôle de course : START / STOP / relance
- [ ] Écran de résultats, historique du jour, export CSV
- [ ] Bascule simulateur / matériel en un clic
- [ ] **J3** — course complète menée au simulateur sans clavier, CSV correct *(preuve : CSV + capture)*

## Lot 4 — Scène 3D *(6–8 j)*

- [ ] Piste de vélodrome, couloirs, ligne d'arrivée
- [ ] Tribunes et foule instanciée réactive
- [ ] Rider : modèle, pédalage indexé sur la vitesse réelle, inclinaison
- [ ] Matériaux et shaders néon, bloom, volumétrique, vignettage
- [ ] Effets de vitesse : traînées, lignes de vitesse, flou radial, FOV dynamique
- [ ] Rig de caméra + comportements par mode (`docs/04` §4)
- [ ] Interpolation entre trames — **vérifiée explicitement à basse vitesse**
- [ ] Trois niveaux de qualité + détection automatique
- [ ] **J4** — 60 fps stables 1080p sur GPU intégré, 4 riders *(preuve : vidéo 30 s + relevé fps)*

## Lot 5 — Habillage, poursuite, audio *(4 j)*

- [ ] Habillage de la fenêtre spectacle (`docs/04` §5)
- [ ] Décompte plein écran synchronisé sur les trames `CD:`
- [ ] Poursuite : écart géant au centre, barre de tension, caméra qui décroche
- [ ] Photo-finish : écart < 1 m → ralenti et plan latéral
- [ ] Podium et écran de fin
- [ ] Audio complet + coupure globale d'un bouton
- [ ] Deuxième fenêtre : choix de l'écran, plein écran, persistance, mode dégradé mono-écran
- [ ] **J5** — les 3 modes en configuration deux écrans, avec le son *(preuve : vidéo)*

## Lot 6 — Terrain, packaging, sortie *(4 j)*

- [ ] **Session de test avec le matériel réel et de vrais cyclistes**
- [ ] Corrections issues du terrain
- [ ] Export Windows `.exe` + installeur
- [ ] Export Linux `.AppImage`
- [ ] Export macOS `.app` + `.dmg`, signature/notarisation si compte disponible
- [ ] Release automatique par la CI sur tag
- [ ] Manuel opérateur
- [ ] `docs/DEPANNAGE.md`
- [ ] **J6** — un tiers installe sur machine vierge et fait courir deux personnes sans aide

---

## Décisions en attente (`docs/06` §5)

- [x] Poursuite 3–4 riders → **élimination progressive** *(tranché, session initiale ; `docs/02` §3 mis à jour)*
- [ ] VID/PID du boîtier réel (`lsusb`) *(avant J1 — boîtier non disponible à la session initiale)*
- [x] Nombre de capteurs réellement câblés → **2** *(tranché, session initiale ; défaut de `ss_emu --riders`)*
- [ ] Compte développeur Apple disponible ? *(avant lot 6)*
- [ ] Logo, nom affiché, sponsors éventuels *(avant lot 5)*

---

## Revue

### Lots 0, 1 et 2 — 2026-08-31

**Jalons franchis.** J0 (CI verte sur trois OS), J1-ém (lien série validé contre l'émulateur de
firmware, à travers le GDExtension), J2 (75 tests headless, 3160 assertions, exit 0).
**J1 reste ouvert** : le boîtier n'était pas disponible.

**Ce qui a dévié de la spec, et pourquoi.** Sept corrections aux documents normatifs, toutes
faites *avant* d'écrire le code correspondant :

| Document | Correction | Origine |
|---|---|---|
| `01` §5.5 *(nouveau)* | Le firmware ne termine jamais une course en temps au-delà de 32 s : `raceLengthSecs * 1000` déborde un `int` 16 bits. La « double détection » du mode temps n'existait pas. | relecture ligne à ligne du `.ino` |
| `01` §5.5 | `t600` termine la course à **10,2 s** et coupe le flux `R:`. Toutes les valeurs ne débordent pas vers l'infini. D'où la constante `t60`, sûre par construction. | test de balayage |
| `01` §2 | Bornage de `l`/`t` : 7 chiffres **et** 1..32767. La première borne seule était insuffisante. | relecture |
| `01` §2 | Cadrage strict : tout octet suivant `l` ou `t` est avalé par le tampon numérique. | neuf tests tombés d'un coup |
| `01` §4 | Une reconnexion en cours de course émet `v` **seul** : rejouer le `s` abattrait la course récupérée. | scénario de panne exécuté |
| `01` §6.2 | Watchdog armé à la première trame `R:` suivant le START, pas au START — le firmware est muet pendant les ~4 s de décompte. | premier test d'intégration sur pty |
| `01` §6.3 | Le filtre ne peut pas rattraper un tick fantôme isolé : à 100 Hz, un seul tick implique déjà 129 km/h. Promesse retirée, tolérance d'un tick ajoutée. | onze tests tombés d'un coup |
| `02` | Timeout `ARMING` 1 s → 2 s ; mode temps arbitré par le PC seul ; plafonds de poursuite à la charge du PC. | conséquences des ci-dessus |
| `03` §1 | `libserialport` écarté : son intégration autotools sur trois OS contredit « aucune dépendance à reconstruire par réseau » pour un apport réduit à l'ouverture de port et l'énumération VID/PID. | décision d'architecture |
| `07` *(nouveau)* | Spécification de l'émulateur de firmware `ss_emu`. | matériel indisponible |

**Ce qui a été ajouté hors plan.** L'émulateur `tools/ss_emu` (~1400 lignes C++ + tests) et la sonde
`tools/ss_probe.py`. Non prévus par `docs/05`, rendus nécessaires par l'absence de matériel — et
utiles bien au-delà : ils resteront le moyen de développer et de démontrer sans boîtier.

**Décision structurante prise en cours de route.** Émuler au niveau du **port série** (pseudo-terminal
à 115200 bauds) et non au niveau du parseur. Le code Godot ne sait pas qu'il ne parle pas à un
Arduino : ouverture de port, threading, découpage de flux, handshake, watchdog et reconnexion sont
réellement traversés. C'est exactement ce que le mock de la v2 laissait sans couverture.

**Ce que la CI trois OS a rattrapé** — et qui n'aurait pas été vu en local :
`tcgetattr` sur le maître d'un pseudo-terminal répond `ENOTTY` sur macOS ; `GUID_DEVCLASS_PORTS`
exige `initguid.h` avant `devguid.h` ; `advapi32` n'est pas lié par défaut sous SCons.

**Ce qui reste.**

* **J1** — brancher le boîtier, relever `lsusb`, compléter l'allowlist VID/PID, vérifier
  l'affectation des pistes et le nombre réel de capteurs, débranchement USB physique à chaud.
* Lot 3 (interface opérateur) et lot 4 (scène 3D) — sessions séparées. Le verrou « la donnée avant
  le pixel » interdit le lot 4 tant que J1 n'est pas franchi ; **J1-ém ne le lève pas**.
* Variante de poursuite « `G` à tous les autres » : implémentable derrière `RaceRule`, non écrite
  tant qu'elle n'est pas demandée.
* Les dossiers `art/`, `audio/`, `scenes/` ne contiennent que des `.gitkeep`, conformément à la
  règle « pas d'asset orphelin ».

**Chiffres.** 112 cas doctest / 757 assertions en C++ ; 75 tests GUT / 3160 assertions en GDScript ;
sept jobs CI sur trois OS.
