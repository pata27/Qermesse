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

- [ ] godot-cpp en submodule épinglé, SConstruct, build sur les 3 OS
- [ ] `line_parser` C++ pur : toutes les trames de `docs/01` §3
- [ ] Cas tordus couverts : erreur malformée à double préfixe, trames sans `:`, regex `^([0-3])F:(\d+)$`
- [ ] Ring buffer SPSC + thread de lecture + drain thread principal
- [ ] Énumération des ports avec VID/PID
- [ ] Sélection : port choisi → allowlist VID/PID → regex nom. **Pas de fallback « dernier port »**
- [ ] Handshake `s` puis `v`, attente `V:SS_v...`, 3 essais, timeout 2 s
- [ ] `IDENTIFIED` = seule condition d'autorisation du départ
- [ ] `send_command` : allowlist de commandes + bornage à 7 chiffres (débordement `charBuff[8]`)
- [ ] Watchdog 500 ms, reconnexion avec backoff plafonné à 5 s
- [ ] Tests C++ natifs du parseur dans la CI, sans Godot
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
- [ ] **J1-ém** — contre `ss_emu` : handshake, ticks en direct, `LINK_LOST` < 500 ms, reconnexion,
      trame corrompue absorbée *(preuve : trace `--trace` + console)*. Autorise le lot 2, **pas le lot 4**.
- [ ] **J1** — sur l'Arduino réel : ticks des 4 pistes en direct, version firmware affichée,
      débranchement à chaud → `LINK_LOST` < 500 ms, rebranchement → reprise *(preuve : vidéo)*

## Lot 2 — Cœur métier *(3 j)*

- [ ] `physics.gd` : ticks ⇄ mètres ⇄ km/h, lissage 20 échantillons
- [ ] `race_engine.gd` : FSM de `docs/02`, PC autoritaire, riders actifs uniquement
- [ ] `rule_distance.gd`
- [ ] `rule_time.gd`
- [ ] `rule_pursuit.gd` + les deux variantes 3–4 riders interchangeables
- [ ] Plafonds de sécurité de la poursuite (temps 300 s, distance 5000 m)
- [ ] Filtrage des ticks aberrants (> 120 km/h, incohérence tick/temps), rejets loggués
- [ ] Politiques de faux départ : `IGNORE` / `AVERTISSEMENT` / `RELANCE` / `PENALITE`
- [ ] `recorder.gd` : CSV en append **réel** + JSON par course avec trace complète des trames
- [ ] `settings.gd` + `roster.gd`, chemins par OS, noms des riders persistés
- [ ] Test : `100 m @ 114.3 mm = 278 ticks`
- [ ] Test : **course distance à 2 riders qui se termine** *(le bug historique de la v1)*
- [ ] Test : poursuite 2 riders, fin au tick près sur les 50 m d'écart
- [ ] Test : poursuite 4 riders, ordre d'élimination correct
- [ ] Test : chaque état de la FSM atteint au moins une fois
- [ ] Test : rejeu d'une course JSON → classement identique
- [ ] **J2** — suite headless verte *(preuve : sortie de test)*

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

*(à remplir à la fin de chaque lot : ce qui a été fait, ce qui a dévié de la spec, ce qui reste)*
