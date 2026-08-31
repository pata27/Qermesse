# 02 — Modes de jeu (SPEC NORMATIVE)

Trois modes. Les deux premiers reprennent la v1 à l'identique côté règles, le troisième est nouveau.
Tous les trois sont arbitrés **par le PC** à partir du flux de ticks (voir `01`, §5.4).

Vocabulaire :
* **rider actif** — piste occupée et déclarée dans le roster. Les pistes inactives sont ignorées
  partout : classement, condition de fin, rendu.
* **`t_i`** — ticks cumulés du rider `i`, valeur absolue issue de la dernière trame `R:`.
* **`d_i`** — distance du rider `i` en mètres = `t_i × circonférence_mm / 1000`.
* **`elapsedMs`** — horloge firmware, seule horloge de course.

---

## Machine à états commune

```
IDLE ──START──▶ ARMING ──▶ COUNTDOWN(3,2,1) ──CD:0──▶ RUNNING ──▶ FINISHED ──▶ RESULTS
  ▲                │                │                    │                          │
  └────────────────┴── ABORT ───────┴────────────────────┴──── NEW RACE ◀───────────┘
                                    │
                              FALSE_START (optionnel, cf. §4)
```

`ARMING` couvre l'aller-retour série (`d`/`x`, `l`/`t`, `g`) avant réception du premier `CD:`.
Timeout 1 s : si aucun `CD:` n'arrive, retour `IDLE` + erreur explicite à l'opérateur.

> **Nettoyage vs v2 :** la v2 déclarait un état `GO` dessiné par l'UI mais jamais atteint par le moteur.
> En v3, un état non atteignable est un bug de conception : la FSM ci-dessus est exhaustive et testée
> exhaustivement (tout état est atteint par au moins un test).

---

## 1. Mode DISTANCE

**Règle.** Premier rider à parcourir `D` mètres. `D` réglable, défaut **500 m**, bornes 50–5000 m.

**Séquence série.** `d` → `l<ticks>` avec `ticks = floor(D × 1000 / circonférence_mm)` → `g`.

**Condition de fin (calculée par le PC) :** la course se termine quand **tous les riders actifs** ont
atteint `ticks`. Chaque rider est figé à son franchissement, avec son `elapsedMs` de passage.

> C'est ici que la v1 était cassée : elle attendait les 4 pistes matérielles, donc ne se terminait
> jamais à 2 riders. Le PC ne doit compter **que les riders actifs**.

**Classement.** Croissant par temps de passage. Ex æquo au tick près départagé par l'ordre d'arrivée
de la trame `R:` (documenté comme tel dans l'UI : « photo-finish »).

**Plafond de sécurité.** 10 minutes. Au-delà : `s` envoyé, course marquée `INTERROMPUE`.

---

## 2. Mode TEMPS

**Règle.** Distance maximale parcourue en `T` secondes. `T` réglable, défaut **60 s**, bornes 10–3600 s.

**Séquence série.** `x` → `t<T>` → `g`.

**Condition de fin.** Double détection, on retient la première :
* le PC voit `elapsedMs ≥ T × 1000` ;
* le firmware émet ses `<i>F:` de fin de course.

**Classement.** Décroissant par ticks cumulés. Ex æquo → vitesse de pointe la plus élevée.

---

## 3. Mode POURSUITE (nouveau)

**Intention.** La course continue tant qu'aucun rider n'a pris un écart décisif. Format nerveux,
spectaculaire, durée variable — c'est le mode « showcase » du logiciel.

**Règle à 2 riders.** La course se termine dès que `|d_0 − d_1| ≥ G`.
`G` réglable, **défaut 50 m**, bornes 10–500 m. Vainqueur : celui qui est devant.

**Règle à 3–4 riders — élimination progressive.** Dès que l'écart entre le **leader** et le
**dernier rider encore en course** atteint `G`, ce dernier est **éliminé** (rang = nombre de riders
restants + 1). La course continue avec les riders restants, jusqu'à ce qu'il n'en reste qu'un.
Un rider éliminé garde son écran mais est grisé, sa piste 3D s'estompe.

> **Point à valider avec l'utilisateur avant implémentation.** L'alternative est
> « premier à mettre `G` à *tous* les autres gagne, sans élimination ». L'élimination progressive
> est retenue par défaut parce qu'elle donne une tension croissante et un vrai classement final,
> mais c'est un choix de game design, pas une contrainte technique. Le moteur doit rendre les
> deux règles interchangeables derrière une même interface (`PursuitRule`).

**Séquence série.** `x` → `t<plafond_secs>` → `g`.
Le mode temps est utilisé comme *véhicule* parce que c'est le seul qui ne fait pas terminer le
firmware sur une condition de distance. `plafond_secs` = **300 s** par défaut : garde-fou pur, jamais
atteint en pratique. Quand le PC décide la fin, il envoie `s`.

**Plafonds de sécurité (l'un ou l'autre déclenche la fin).**
* Durée : `plafond_secs` (défaut 300 s). Vainqueur = celui qui mène à cet instant.
* Distance : 5000 m cumulés. Idem.

Sans ces plafonds, deux riders de niveau égal courent jusqu'à épuisement — inacceptable en
événementiel. Ils doivent être visibles dans l'UI (jauge « temps restant avant décision »).

**Rendu spécifique — c'est ce mode qui vend le logiciel.**
* L'écart en mètres est l'élément dominant à l'écran, gros chiffre central, animé.
* Barre de tension horizontale : curseur entre `−G` et `+G`, qui vire au rouge à l'approche.
* La caméra 3D cadre dynamiquement les deux riders : plan large quand ils sont collés, la caméra
  décroche et s'élève quand l'écart se creuse.
* Audio : intensité de la nappe indexée sur `|écart| / G`.

---

## 4. Faux départ

Le firmware émet `FS:<idx>` quand un rider fait ≥ 4 ticks pendant le décompte. En v1 c'était
purement informatif. En v3, comportement paramétrable en réglages, **défaut : `AVERTISSEMENT`**.

| Politique | Comportement |
|---|---|
| `IGNORE` | loggué uniquement (comportement v1) |
| `AVERTISSEMENT` *(défaut)* | bandeau + son, la course continue |
| `RELANCE` | `s` immédiat, retour `IDLE`, message « faux départ rider N », relance manuelle |
| `PENALITE` | la course part, le rider fautif démarre avec un handicap de `P` mètres (défaut 10 m) |

Le défaut est `AVERTISSEMENT` : en événementiel, relancer une course pour un rider qui a bougé
énerve le public. `RELANCE` existe pour les usages compétitifs.

---

## 5. Persistance des résultats

**CSV** — reprise du format v1 pour continuité, mais avec les événements réellement écrits
(la v1 déclarait 5 types d'événements et n'en écrivait qu'un).

Fichier : `<données_app>/logs/YYYY_MM_DD_SilverSprintRaceLog.csv`, **append réel**
(la v1 rechargeait et réécrivait tout le fichier à chaque ligne — à ne pas reproduire).

Colonnes : `timestamp_iso, event, mode, rider, dossard, distance_m, temps_ms, vitesse_moy_kph, vitesse_max_kph, rang, note`

Événements écrits : `RACE_START`, `FALSE_START`, `RIDER_FINISH`, `RIDER_ELIMINATED`,
`RACE_FINISH`, `RACE_ABORTED`, `LINK_LOST`.

**JSON** — un fichier par course dans `<données_app>/races/<uuid>.json`, contenant en plus
**la trace complète des trames `R:`** (ticks + elapsedMs). Permet le rejeu d'une course, le débogage
post-événement, et la génération de replays. ~100 Hz × 60 s × 4 riders ≈ 6000 échantillons,
soit quelques centaines de Ko : négligeable.

**Réglages** — JSON, chemins standards par OS :
* Linux `~/.config/silversprint/settings.json`
* macOS `~/Library/Application Support/SilverSprint/settings.json`
* Windows `%APPDATA%\SilverSprint\settings.json`

Les noms des riders **sont persistés** (roster réutilisable d'une course à l'autre) — la v1 les
perdait à chaque lancement.
