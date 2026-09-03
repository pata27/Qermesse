# 06 — Qualité, CI, risques

## 1. Règles de développement non négociables

1. **La donnée avant le pixel.** Aucun travail de rendu 3D avant validation du lot 2 sur matériel réel.
2. **`core/` ne dépend de rien.** Ni scène, ni port série, ni rendu. Testable en headless.
3. **Un seul thread mute l'état.** Le thread série écrit dans un ring buffer, point final.
4. **Pas d'état mort.** Tout état de la FSM est atteint par au moins un test.
5. **Pas d'asset orphelin.** Un fichier non référencé est supprimé, pas laissé « au cas où ».
   Cela vaut aussi pour une **constante** : `TARGET_FPS := 60.0` qui n'est lu par rien annonce un
   budget que personne n'applique, et `REFRESH_S` un rafraîchissement que personne ne respecte.
   Chacune est soit lue, soit supprimée — un test le vérifie, commentaires exclus du décompte.
   **Idem pour une fonction** : un accesseur sans appelant est une API qu'on croit avoir et qui
   n'a jamais servi. Soit elle décrit un comportement qui mérite son test — c'était le cas de
   trois des douze trouvées —, soit elle fait double emploi et disparaît. Les méthodes virtuelles
   de Godot sont hors décompte : c'est le moteur qui les appelle.
6. **Le protocole série est documenté avant d'être codé**, et `docs/01` reste la source de vérité.
7. **Un indice n'est pas un numéro de piste.** Le code compte les pistes de 0 à 3 ; tout texte lu
   par un humain — bandeau public, note du CSV, message d'erreur, sortie d'outil — les nomme de 1
   à 4. Un faux départ sur la piste 2 a longtemps accusé « piste 1 » au bandeau et dans le fichier.
   Un test vérifie que toute chaîne contenant `piste %d` formate `rider + 1`. Seules les colonnes
   d'une ligne d'état qui suit les champs d'une trame `R:` restent en 0..3, et leur outil le dit.
8. **Aucune tâche cochée sans preuve** : sortie de test, capture, ou vidéo. Et **un test sauté
   n'est pas une preuve** : les tests dont le décor peut manquer se déclarent `pending`, jamais
   `pass_test`. La ligne `Risky/Pending` du résumé les compte — verts par absence, ils auraient
   affirmé exactement ce qu'ils n'ont pas vérifié.

## 2. Tests

| Niveau | Outil | Portée |
|---|---|---|
| Unitaire C++ | doctest, binaire natif | `line_parser`, ring buffer, `FirmwareSim` — sans Godot |
| Bout en bout série | `tools/ss_emu` sur pseudo-terminal | ouverture de port, handshake, threading, watchdog, reconnexion — la partie risquée. **Automatisé** (`test_lien_pseudo_terminal.gd`) : la suite lance l'émulateur sur un vrai pseudo-terminal et fait passer le module natif par un vrai port, jusqu'à la coupure en pleine course. Se saute explicitement sous Windows, qui n'a pas de pseudo-terminal POSIX, et là où l'émulateur ou le module natif ne sont pas construits |
| Unitaire GDScript | GUT headless | `physics`, `race_engine`, les trois règles, `recorder`, `settings` |
| Rejeu | GUT + courses JSON | une course enregistrée rejouée doit donner exactement le même classement — **y compris interrompue**, où le rejeu reproduit l'interruption et rend le classement partiel |
| Outil de rejeu | GUT en sous-processus + CI | `tools/ss_replay` lui-même, verdicts ET codes de sortie, éprouvé sur une trace saine et une trace truquée. La suite exerçait `core/replay.gd` ; la ligne de commande que `DEPANNAGE` promet à l'opérateur n'était gardée par rien |
| Deux fenêtres | GUT headless | `Main.open_spectacle()` monte la fenêtre spectacle et sa scène, avec le niveau de qualité et le plein écran issus des réglages. Une régression y casse l'écran du public, et se vérifiait jusqu'ici en branchant un vidéoprojecteur |
| Traces de référence | GUT + `tests/fixtures/` | deux courses réelles enregistrées **avant** plusieurs changements du moteur, rejouées à chaque exécution : le format d'hier reste lisible et l'arbitrage n'a pas dérivé. Un test généré ne le prouve pas — il produit sa trace avec le code du jour |
| Injection de pannes | `link_sim` | trame corrompue, perte de lien, tick fantôme, faux départ, trames perdues. Chacune doit être **atteignable depuis l'application** : un test compare par réflexion les `inject_*` du simulateur, les relais de `Link` et les coutures `simulate_*` du contrôleur. Deux manquaient — une panne qu'on ne peut pas provoquer est une panne qu'on ne saura pas diagnostiquer le soir venu |
| Arborescence | GUT headless | la **règle 5** du §1, tenue par la machine : aucun `.uid` sans sa ressource — Godot les crée à l'import et ne les efface jamais —, aucun fichier de `art/` que plus rien ne nomme, par son nom ou par son uid. `addons/` est hors périmètre : code tiers vendorisé |
| Manuel matériel | checklist `docs/RECETTE.md` | avant chaque release |

Le rejeu est le filet de sécurité le plus rentable du projet : chaque course réelle enregistrée en
JSON devient un cas de test permanent. Après le premier événement, on dispose d'une batterie de cas
réels que personne n'aurait su écrire à la main.

## 3. CI

Matrice `ubuntu-latest` / `windows-latest` / `macos-latest` :
build du GDExtension, tests C++, émulateur construit seul comme le dit le README, import du projet
Godot, tests GUT headless, rejeu des traces de référence par `ss_replay`, témoin indépendant
`ss_probe.py` sur un vrai pseudo-terminal (Linux), course complète à l'interface, export des
binaires.
Sur tag : publication d'une release avec les trois artefacts.

## 4. Risques et parades

| Risque | Impact | Parade |
|---|---|---|
| **Compilation du GDExtension pénible sur les 3 OS** | fort, bloque tout | attaqué en lot 1, CI sur les 3 OS dès J0, plan B « pont TCP » documenté et décidé explicitement si dérapage > 6 j |
| **Le firmware réel diverge de `ss_basic.ino`** (boîtier reflashé, variante) | fort | J1 valide contre le matériel réel avant toute autre chose ; le parseur logue toute trame inconnue au lieu de l'ignorer |
| **Matériel indisponible pendant le développement** | fort, bloque le lot 1 | `tools/ss_emu` (document `07`) émule le firmware sur un vrai pseudo-terminal : tout le code risqué est traversé sans matériel. Jalon intermédiaire J1-ém, qui **ne remplace pas J1** |
| **Se satisfaire de l'émulateur et ne jamais brancher le boîtier** | fort | J1-ém est explicitement marqué insuffisant pour ouvrir le lot 4 ; `07` §2 liste ce que l'émulateur ne prouve pas |
| **Trames `G`/`S` réellement émises par un shield kiosque** | moyen | parsées et loggées dès le lot 1, comportement activé seulement si observé. `ss_monitor` les journalise, et **l'application les compte** : le panneau Matériel les affiche dès qu'il y en a — c'est en soirée qu'un tel boîtier se révélerait, et le monitor n'y tourne pas. Un test vérifie qu'aucune des onze sortes de trames ne tombe dans le silence du `match` : chacune est traitée, ou nommée avec la raison de l'ignorer |
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
