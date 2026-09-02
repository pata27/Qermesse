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
      *(preuve : 32 ports réels sur la machine, 0 candidat retenu — et depuis le 2026-09-02, sept cas
      doctest dans `tests/test_port_selection.cpp` : ordre de confiance, absence de repli, liste noire,
      port forcé absent de l'énumération, libellés des motifs)*
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
- [x] `link_sim.gd` : profils de course + injection de pannes (`docs/03` §5)
      *(les quatre pannes exigées — faux départ, tick fantôme, trame corrompue, perte/retour de
      lien — existent avec leurs tests dans `tests/unit/test_link_sim.gd` ; la case était restée
      décochée.)*
- [x] Test de conformité `link_sim.gd` ↔ `ss_emu` sur scénario à graine fixée
      *(`tests/unit/test_conformite_emulateur.gd` : `ss_emu --stdio`, graine 7, 2 coureurs, 100 m.
      Même suite d'événements, mêmes compteurs dans la dernière `R:` avant l'arrivée — 277/277, le
      bug de la dernière trame reproduit DES DEUX CÔTÉS —, temps d'arrivée à 20 ms près. Sauté
      explicitement là où le binaire n'est pas construit, jamais vert par absence.)*
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

- [x] Roster 1–4 riders : noms, dossards, couleurs, activation de piste
- [x] Sélection du mode et de ses paramètres (`D`, `T`, `G`, politique de faux départ) — seuls les
      réglages du mode choisi sont affichés
- [x] Panneau matériel : ports **avec le motif de leur retenue ou de leur rejet**, état du lien,
      version firmware, statistiques du lien
- [x] Test capteurs : bouton dédié, activité par piste, pour détecter un câblage inversé
      **avant** la course
- [x] Calibration du diamètre de rouleau, avec aide à la mesure et retour immédiat en ticks
- [x] Contrôle de course : START / STOP / relance. START grisé tant que le départ est interdit,
      avec le motif en infobulle
- [x] Écran de résultats, historique du jour, chemin du CSV affiché en clair
- [x] Bascule simulateur / matériel en un clic
- [x] **J3** — course complète menée au simulateur sans clavier, CSV correct
      *(preuve : `tasks/preuves/2026-08-31-J3-interface-operateur.md`, 4 captures + CSV)*

## Lot 4 — Scène 3D *(6–8 j)*

- [x] Piste de vélodrome, couloirs, ligne d'arrivée — `track_builder.gd`, `track.gdshader`
      *(preuve : captures de `tasks/preuves/images/`. Le sens des couloirs a été corrigé le
      2026-09-01 : la caméra regarde vers les Z croissants, son axe droite est donc −X et la piste
      était dessinée en miroir depuis le premier jour.)*
- [x] Tribunes et foule instanciée réactive — `crowd.gd`, `crowd.gdshader`, MultiMesh
      *(la foule défile spectateur par spectateur dans son vertex shader ; un défilement par modulo
      du nœud entier la téléportait de 10 m toutes les 0,8 s, puisqu'elle n'est pas périodique.)*
- [x] Rider : modèle, pédalage indexé sur la vitesse réelle, inclinaison — `rider_rig.gd`
      *(une seule ombre par coureur, en `SHADOWS_ONLY` : les 26 pièces qui projetaient chacune la
      leur coûtaient plus de 400 appels de rendu sur les 495 de la scène.)*
- [x] Matériaux et shaders néon, bloom, volumétrique, vignettage — `art/shaders/`
- [x] Effets de vitesse : traînées, lignes de vitesse, flou radial, FOV dynamique
      *(seuil des lignes à 32 km/h — à 45 elles n'apparaissaient jamais, un sprinteur sur rouleaux
      tournant précisément autour de 45.)*
- [x] Rig de caméra + comportements par mode (`docs/04` §4) — `camera_rig.gd`
      *(cadrage par projection décentrée et non par rotation : faire pivoter la caméra plaçait bien
      le sujet mais le regardait de biais.)*
- [x] Interpolation entre trames — `rider_interpolator.gd`, couverte par `tests/unit/test_interpolation.gd`
- [x] Trois niveaux de qualité + détection automatique — `render_quality.gd`, `perf_monitor.gd`
      *(plus un allègement selon le nombre de volets ouverts, voir J4.)*
- [x] **Hors plan initial — écran scindé à N volets** — `split_screen.gd`
      *(demandé en séance. Autant de volets que de paquets, jusqu'à 4 ; recomposition dans les deux
      sens en cours de course. Relevé horodaté : `[4]` à t=0, `[3,1]` à 7,26 s, `[2,1,1]` à 14,66 s,
      `[1,1,1,1]` à 22,47 s ; en accordéon, retour au plein cadre à 20,82 s.)*
- [x] **J4** — 60 fps stables 1080p sur GPU intégré, 4 riders
      *(preuve : `tasks/preuves/J4-scene-3d.md` + `tasks/preuves/j4-course.mp4`. Trois profils,
      fenêtre de 30 s : 1 % bas à 132–136 fps, budget TENU dans les trois cas. Coût par nombre de
      volets : 8,4 à 9,7 ms — courbe plate.)*

## Lot 5 — Habillage, poursuite, audio *(4 j)*

- [x] Habillage de la fenêtre spectacle (`docs/04` §5) — bandeau, chrono géant, carte par coureur
      avec nom, piste, vitesse, distance et **cadence**
      *(la cadence est déduite du développement déclaré par l'opérateur : le capteur compte des tours
      de rouleau et ne connaît aucun braquet — `docs/01` §6. Deux tests verrouillent le fait qu'elle
      ne touche à aucun calcul de course.)*
- [x] Décompte plein écran synchronisé sur les trames `CD:`
      *(preuve : `tasks/preuves/images/lot5-decompte.png`. Voile plein écran sur sa PROPRE couche :
      construit avant les cartes, il se retrouvait dessous.)*
- [x] Poursuite : écart géant au centre, barre de tension, caméra qui décroche
      *(preuve : `tasks/preuves/images/lot5-poursuite.png`. La barre est SIGNÉE, entre −G et +G : elle
      se remplit depuis le centre vers celui qui mène et prend sa couleur. Une barre de 0 à G ne
      disait que la taille de l'écart, pas de quel côté il penche.)*
- [x] Photo-finish : écart < 1 m → ralenti et plan latéral
      *(preuve : `tasks/preuves/images/lot5-photo-finish.png`. Le ralenti n'agit que sur le temps de
      la SCÈNE — pas sur `Engine.time_scale`, qui engourdirait aussi l'interface opérateur, dans le
      même processus sur l'autre écran.)*
- [x] Podium et écran de fin — place, coureur, temps, moyenne, pointe
      *(preuve : `tasks/preuves/images/lot5-podium.png`. Les chiffres viennent du `RaceResult`, donc
      du moteur : rien n'est recalculé à l'affichage. Il attend 5 s que la célébration et le regroupement se jouent.)*
- [x] Audio complet + coupure globale d'un bouton — `audio/sound_forge.gd`, `audio/race_audio.gd`
      *(nappe indexée sur la vitesse — sur l'ÉCART en poursuite —, bips de décompte montant d'un
      demi-ton, klaxon, cloche des 50 derniers mètres, clameurs sur dépassement, accélération et
      franchissement, souffle de vent. Tout est SYNTHÉTISÉ : aucun fichier audio au dépôt, rien à
      télécharger, rien qui puisse manquer à l'export. 7 tests headless, sans carte son.
      **Muet par défaut** — `docs/04` §6 : en événementiel la sono est gérée séparément.)*
- [x] Deuxième fenêtre : choix de l'écran, plein écran, persistance, mode dégradé mono-écran
      — `scenes/spectacle_window.gd`, `scenes/operator/panel_spectacle.gd`
      *(preuve : `tasks/preuves/images/lot5-deux-fenetres.png`, capture des DEUX fenêtres sur une
      même course. `is_embedded() = false`, identifiant système 1, écran 2 sur une machine à trois
      écrans. Il a fallu `display/window/subwindows/embed_subwindows=false` : par défaut Godot
      dessine une fenêtre fille À L'INTÉRIEUR de la principale, ce qui rendait le second écran
      inatteignable.)*
- [x] **J5** — les 3 modes en configuration deux écrans, avec le son
      *(preuve : `tasks/preuves/J5-habillage.md` + `tasks/preuves/j5-trois-modes.mp4`, 36 s. Le son est
      vérifié sur pièces — tests de synthèse, bus présent, coupure par défaut — pas à l'écoute : tout a
      été produit en muet, par consigne.)*

## Lot 6 — Terrain, packaging, sortie *(4 j)*

- [ ] **Session de test avec le matériel réel et de vrais cyclistes**
- [ ] Corrections issues du terrain
- [~] Export Windows `.exe` — preset écrit et **accepté par Godot**, export non encore produit
      *(les modèles d'exportation, 1,3 Go, ne sont pas installés localement)*
- [~] Export Linux — preset écrit et accepté. `.AppImage` non fait : l'export Godot produit un
      binaire autonome, l'empaquetage AppImage reste à ajouter
- [~] Export macOS `.app` dans un `.zip` — preset écrit. `.dmg`, signature et notarisation :
      dépendent d'un compte développeur Apple *(décision `docs/06` §5, toujours ouverte)*
- [~] Release automatique par la CI sur tag — `.github/workflows/release.yml` écrit, YAML validé,
      **jamais exécuté** : il ne se déclenche que sur un tag `v*`
- [x] Manuel opérateur — `docs/MANUEL-OPERATEUR.md` *(court, panneau par panneau, écrit d'après ce
      que l'application fait ; les pannes renvoient à `DEPANNAGE.md`)*
- [x] `docs/DEPANNAGE.md` — dépannage terrain, écrit pour l'opérateur
- [x] `docs/RECETTE.md` — checklist matériel du jalon J1, à dérouler avant chaque release
- [ ] **J6** — un tiers installe sur machine vierge et fait courir deux personnes sans aide
      *(la partie logicielle du parcours est vérifiée sur un clone vierge :
      `tasks/preuves/2026-09-03-clone-vierge.md`. Restent le matériel et le tiers.)*

---

## Consolidation continue *(31 août – 3 septembre)*

Trente tours d'une boucle « trouver, corriger, prouver ». Aucun de ces points n'était au plan :
ce sont des défauts trouvés en relisant les documents normatifs, en regardant des captures et en
se servant du logiciel. Chacun est couvert par un test rouge avant correction.

**Ce que le logiciel dit maintenant à l'opérateur** — `DEPANNAGE` demandait de le remarquer soi-même
- [x] Une piste cochée mais vide est signalée dix secondes après le départ *(c'est le bug de la v1
      déplacé d'un cran : le PC attend toutes les pistes actives)*
- [x] Une pointe humainement invraisemblable est signalée, **sans être effacée** — à distinguer du
      filtre de `01` §6.3, qui rejette l'impossible
- [x] Des trames perdues sont signalées en course : le seul cas qui fausse réellement une mesure
- [x] Un fichier de réglages illisible, un journal impossible à écrire, un tick rejeté
- [x] Le panneau course tient un journal de cinq lignes : une alerte n'est plus effacée par la suivante

**Traces et rejeu**
- [x] Une course **interrompue** garde sa trace, et se rejoue en rendant son classement partiel
- [x] `tools/ss_replay.gd` — rejoue une course et vérifie son classement *(93 courses réelles
      rejouées sans divergence)*
- [x] Deux **traces de référence** au dépôt, antérieures à plusieurs changements du moteur, rejouées
      à chaque exécution de la suite — le format d'hier se relit, l'arbitrage n'a pas dérivé
- [x] Le panneau résultats donne le chemin du fichier à envoyer au développeur

**Ce qu'une soirée enchaînée révèle**
- [x] La course suivante part sans « interrompre » la précédente *(FSM `docs/02` respectée)*
- [x] Tout ce qu'un second départ doit remettre à zéro : roue libre, vitesses lissées, tension,
      lames, secousse, problèmes d'enregistrement
- [x] Fermer le logiciel en pleine course arrête aussi le boîtier
- [x] « Courses du jour » relu du disque, à l'heure locale, avec les noms du départ

**Réglages, écrans, fichiers**
- [x] Volume, niveau de qualité et plein écran persistés — trois réglages exposés sans être écrits
- [x] Les noms affichés sont ceux du départ et tiennent dans leur place *(quatre écrans, une seule
      composition)*
- [x] Une course décidée au plafond n'est plus annoncée « INTERROMPUE » *(cinq afficheurs, une seule
      question posée dans `RaceResult`)*
- [x] Horodatage du CSV à l'heure de la salle, avec son décalage
- [x] Les démos n'écrivent plus dans les données de l'opérateur

**Vérifications**
- [x] Parcours d'un tiers sur clone vierge — `tasks/preuves/2026-09-03-clone-vierge.md`
- [x] État au 3 septembre : **201 tests GUT**, **2/2 natifs**, lint propre sur cinq dossiers,
      application lancée sans erreur, traces de référence conformes

---

## Décisions en attente (`docs/06` §5)

- [x] Poursuite 3–4 riders → **élimination progressive** *(tranché, session initiale ; `docs/02` §3 mis à jour)*
- [ ] VID/PID du boîtier réel (`lsusb`) *(avant J1 — boîtier non disponible à la session initiale)*
- [x] Nombre de capteurs réellement câblés → **2** *(tranché, session initiale ; défaut de `ss_emu --riders`)*
- [ ] Compte développeur Apple disponible ? *(avant lot 6)*
- [ ] Logo, nom affiché, sponsors éventuels *(avant lot 5)*

---

## Revue

### Lot 3 — 2026-08-31

**J3 franchi.** Une course complète se mène à la souris, du roster au CSV. Preuve en quatre captures
de la vraie fenêtre plus le CSV produit, et une suite de dix tests headless qui n'agissent que sur
les widgets. La CI mène en plus une course complète à l'interface, en headless, sur les trois OS.

**Écart de spec assumé.** La fenêtre opérateur est construite en code et non en `.tscn` — motif
consigné dans `docs/03` §2. La fenêtre spectacle relèvera du choix inverse.

**Deux défauts trouvés en menant la course pour de vrai, pas en relisant :**
la vitesse de pointe mesurée sur l'instantanée donnait 117 km/h pour un cycliste à 45 ;
et Godot ne déclenche ni `_enter_tree` ni `_ready` de façon synchrone depuis
`SceneTree._initialize()`, si bien que l'interface se bâtissait contre un contrôleur vide et
affichait « aucun port détecté » sans rien signaler.

**Amorcé pour la suite.** `docs/RECETTE.md` — la checklist qui fera de J1 une session de vingt
minutes le jour où le boîtier sera là. `docs/DEPANNAGE.md`. Les presets d'export et la CI de release
sur tag, écrits et validés syntaxiquement mais **non exécutés**, faute des 1,3 Go de modèles
d'exportation.

**Bloqué.** Le lot 4 (scène 3D) reste fermé : `docs/05` et `docs/07` §2 exigent J1 sur matériel réel.

> *Écrit le 31 août, et vrai à cette date.* Le verrou a été levé le jour même à la demande de
> l'utilisateur, décision consignée dans `docs/05` — « Dérogation au verrou *la donnée avant le
> pixel* ». Les lots 4 et 5 ont suivi ; **J1 reste ouvert**. Ce paragraphe est conservé tel quel :
> une revue datée se lit comme un état à une date, pas comme une vérité permanente.

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
