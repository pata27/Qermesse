# 05 — Plan d'exécution

Sept lots. Chaque lot se termine par un **jalon vérifiable** : tant que la preuve n'est pas produite,
le lot n'est pas fini. Pas de « ça devrait marcher ».

**Principe directeur, tiré du post-mortem v2 :** *la donnée avant le pixel.* La v2 a passé sa
dernière session à embellir un affichage dont la source de données n'avait jamais été validée
contre du matériel réel. En v3, **aucun travail de rendu 3D ne commence avant que le lot 2 soit
validé sur l'Arduino réel.**

---

## Lot 0 — Fondations *(0.5 j)*

* Dépôt git, `.gitignore` Godot, licence, `README.md`.
* Projet Godot 4.5, renderer Forward+, arborescence du document `03` §2.
* GUT installé, un test bidon vert en headless.
* GitHub Actions : lint GDScript + tests headless sur push.
* `tasks/todo.md` et `tasks/lessons.md` initialisés.

**Jalon J0 :** `godot --headless --script tests/run.gd` sort en code 0 dans la CI, sur les trois OS.

---

## Lot 1 — Lien série *(3–4 j — le lot le plus risqué, donc le premier)*

* GDExtension `serial_link` : SConstruct, godot-cpp en submodule, build Linux/Windows/macOS.
* `line_parser` en C++ pur : découpe `\r\n`, parse **toutes** les trames du document `01` §3,
  y compris le message d'erreur malformé et les trames sans `:`.
* Ring buffer SPSC, thread de lecture, drain côté thread principal.
* Énumération des ports avec VID/PID, sélection par allowlist puis regex, **jamais de fallback
  « dernier port »**.
* Handshake : `s` puis `v`, attente de `V:SS_v...`, 3 essais, timeout 2 s. `IDENTIFIED` est la seule
  condition d'autorisation du départ.
* `send_command` avec validation stricte et bornage à 7 chiffres.
* Watchdog 500 ms, reconnexion avec backoff.
* Tests C++ natifs du parseur dans la CI, sans lancer Godot.
* **`tools/ss_emu` — émulateur de firmware sur pseudo-terminal** (document `07`). Écrit *en premier*
  dans le lot, parce que sans matériel disponible il conditionne tout le reste du lot 1.
  Réplique fidèle de `ss_basic.ino`, bugs compris, cyclistes synthétiques, injection de pannes.
* `link_sim.gd` complet (document `03` §5) : profils de course et injection de pannes, trames
  identiques à celles de `ss_emu` (test de conformité entre les deux).

**Jalon J1-ém — intermédiaire, franchissable sans matériel.** Contre `ss_emu` sur pseudo-terminal :
handshake complet et version firmware affichée, ticks des pistes câblées en direct, `perte-lien`
injectée → `LINK_LOST` en moins de 500 ms, `retour-lien` → reconnexion et reprise, trame corrompue
absorbée sans plantage. Preuve : trace `--trace` + sortie console. **J1-ém autorise le lot 2 à
démarrer. Il n'autorise pas le lot 4 : le verrou « la donnée avant le pixel » reste J1.**

**Jalon J1 — le plus important du projet.** Sur l'Arduino **réel** de l'utilisateur, avec deux
rouleaux tournés à la main : un outil console affiche en direct les ticks des 4 pistes, la version
firmware, l'état du lien. On débranche l'USB à chaud → `LINK_LOST` en moins de 500 ms ; on rebranche
→ reconnexion automatique et reprise. Capture d'écran ou vidéo produite comme preuve.

> Si J1 dérape au-delà de 6 jours à cause de la compilation native multiplateforme, basculer sur le
> plan B « binaire pont TCP » du document `03` §4 plutôt que de s'enliser. Décision à prendre
> explicitement, pas subie.

---

## Lot 2 — Cœur métier *(3 j)*

* `physics.gd` : conversions ticks ⇄ mètres ⇄ km/h, lissage sur 20 échantillons.
* `race_engine.gd` : FSM du document `02`, autoritaire côté PC, riders actifs uniquement.
* Les trois règles derrière une interface commune : `rule_distance`, `rule_time`, `rule_pursuit`
  (avec ses deux variantes 3–4 riders interchangeables).
* Filtrage des ticks aberrants (> 120 km/h, incohérence tick/temps).
* Politiques de faux départ.
* `recorder.gd` : CSV en append réel + JSON par course avec la trace complète des trames.
* `settings.gd` et `roster.gd`, persistance par OS, noms des riders conservés.

**Jalon J2.** Suite de tests headless verte, couvrant au minimum :
* `100 m @ rouleau 114.3 mm = 278 ticks` (non-régression v1/v2) ;
* **course distance à 2 riders qui se termine** — c'est le bug historique de la v1, il doit être
  couvert par un test qui échouerait sur l'ancien comportement ;
* poursuite 2 riders : fin exacte au franchissement des 50 m d'écart, au tick près ;
* poursuite 4 riders : ordre d'élimination correct ;
* plafonds de sécurité de la poursuite (temps et distance) ;
* chaque état de la FSM atteint par au moins un test (aucun état mort, cf. le `GO` orphelin de la v2) ;
* rejeu d'une course JSON enregistrée reproduisant exactement le même classement.

---

## Lot 3 — Interface opérateur *(4 j)*

* Roster : 1 à 4 riders, noms, couleurs, activation/désactivation de piste.
* Sélection du mode et de ses paramètres (`D`, `T`, `G`, politique de faux départ).
* Panneau matériel : liste des ports, port choisi, état du lien, version firmware, bouton de test
  capteurs (fait tourner chaque rouleau et vérifie que les ticks arrivent sur la bonne piste).
* Calibration du diamètre de rouleau, avec l'aide à la mesure.
* Contrôle de course : START, STOP, relance.
* Écran de résultats, historique des courses du jour, export CSV.
* Bascule simulateur / matériel accessible en un clic.

**Jalon J3.** Une course complète est menée de bout en bout **au simulateur**, sans toucher au
clavier hors des boutons prévus, et le CSV produit est correct.

---

## Lot 4 — Scène 3D *(6–8 j — le gros morceau)*

> ### Dérogation au verrou « la donnée avant le pixel » — 2026-08-31
>
> **Décidée explicitement par l'utilisateur**, à qui la question a été posée et qui a répondu
> « tu peux lever le verrou ». Elle est consignée ici plutôt que subie en silence : une dérogation
> non écrite est une règle qui s'érode.
>
> **Ce qui est acquis au moment de la lever.** J0, J1-ém et J2 sont franchis, et J3 aussi : le lien
> série est validé de bout en bout contre un émulateur de firmware qui parle sur un vrai
> pseudo-terminal, le cœur métier est couvert par 86 tests headless, et une course complète se mène
> à l'interface opérateur. La chaîne de données n'est donc **pas** dans l'état où était celle de la
> v2 quand elle s'est mise à polir un affichage — c'est ce qui rend la dérogation défendable.
>
> **Ce qui manque, et qui ne change pas.** Le boîtier de l'utilisateur n'a jamais été branché.
> **J1 reste ouvert**, et avec lui : l'allowlist VID/PID, le nombre réel de capteurs câblés,
> l'affectation des pistes, et surtout le débranchement USB **physique** à chaud — le seul chemin
> que l'émulateur ne peut pas exercer (`docs/07` §2).
>
> **Conséquence à tenir.** Le lot 4 ne doit rien construire qui dépende d'une hypothèse non vérifiée
> sur le matériel. Concrètement : la scène 3D lit l'état de course, elle ne lit jamais le port série ;
> elle doit rester correcte quel que soit le nombre de pistes réellement câblées ; et
> `docs/RECETTE.md` reste à dérouler avant tout usage en événement.

* Piste de vélodrome, couloirs, ligne d'arrivée, tribunes, foule instanciée.
* Rider : modèle, animation de pédalage indexée sur la vitesse réelle, inclinaison.
* Matériaux et shaders néon, bloom, volumétrique léger, vignettage.
* Effets de vitesse : traînées, lignes de vitesse, flou radial, variation de FOV.
* Rig de caméra avec les comportements par mode du document `04` §4.
* Interpolation de position entre trames — **à vérifier explicitement à basse vitesse**.
* Trois niveaux de qualité, détection automatique.

**Jalon J4.** 60 fps stables en 1080p sur GPU intégré, mesurés et consignés, pendant une course à
4 riders au simulateur. Vidéo de 30 s produite comme preuve.

---

## Lot 5 — Habillage, poursuite et audio *(4 j)*

* Habillage complet de la fenêtre spectacle (document `04` §5).
* Décompte plein écran synchronisé sur les trames `CD:`.
* Rendu spécifique du mode poursuite : écart géant, barre de tension, caméra qui décroche.
* Photo-finish : détection de l'écart < 1 m à l'arrivée, ralenti, plan latéral.
* Podium et écran de fin.
* Audio complet, avec coupure globale.
* Deuxième fenêtre : choix de l'écran, plein écran, persistance, mode dégradé mono-écran.

**Jalon J5.** Les trois modes tournent en configuration deux écrans, avec le son.

---

## Lot 6 — Terrain, packaging, sortie *(4 j)*

* **Session de test avec le matériel réel et de vrais cyclistes** — le seul jalon qui compte vraiment.
* Corrections issues du terrain.
* Export : `.exe` + installeur Windows, `.AppImage` Linux, `.app` + `.dmg` macOS.
  Signature et notarisation macOS si un compte développeur est disponible ; sinon, documenter la
  procédure de contournement Gatekeeper pour l'utilisateur.
* Build automatique et publication de release par la CI sur tag.
* Manuel opérateur court : branchement, calibration, déroulé d'une course, que faire si ça coince.
* `docs/DEPANNAGE.md` : port introuvable, ticks sur la mauvaise piste, lien qui tombe, projecteur
  non détecté.

**Jalon J6.** Un tiers, sur une machine vierge, installe le logiciel et fait courir deux personnes
sans aide. C'est le critère de sortie.

---

## Charge indicative

| Lot | Charge |
|---|---|
| 0 — Fondations | 0.5 j |
| 1 — Lien série | 3–4 j |
| 2 — Cœur métier | 3 j |
| 3 — Interface opérateur | 4 j |
| 4 — Scène 3D | 6–8 j |
| 5 — Habillage, poursuite, audio | 4 j |
| 6 — Terrain, packaging | 4 j |
| **Total** | **~25–28 jours-homme** |

Les lots 0 à 2 (≈ 7 j) produisent un logiciel qui fonctionne déjà en console : c'est le socle qui
doit être irréprochable. Les lots 4 et 5 sont ceux qu'on peut étaler ou dégrader sans casser le produit.

---

## Ordre de dépendance

```
L0 ──▶ L1 ──▶ L2 ──▶ L3 ──▶ L6
              │       │
              └──▶ L4 ──▶ L5 ──▶ L6
```

L3 et L4 sont parallélisables une fois L2 validé, si deux personnes travaillent dessus.
