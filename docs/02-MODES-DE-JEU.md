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
**Timeout 2 s** : si aucun `CD:` n'arrive, retour `IDLE` + erreur explicite à l'opérateur.

> Le timeout était fixé à 1 s dans la version initiale de ce document : c'était un faux négatif
> systématique. À la réception de `g`, le firmware pose `lastCountDownMillis = millis()` et
> n'émet `CD:3` qu'à la condition `(millis() - lastCountDownMillis) > 1000`. Le premier `CD:`
> arrive donc **juste après** la seconde, plus la latence série. 2 s laisse une marge honnête
> sans rendre l'attente pénible pour l'opérateur.

> Corollaire : le décompte complet dure **~4 s** (`CD:3` à t+1 s … `CD:0` à t+4 s), pas 3 s.
> L'habillage plein écran du lot 5 doit être calé sur les trames reçues, jamais sur un minuteur local.

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

**Séquence série.** `x` → **`t60`** → `g`. La constante `60` n'a rien à voir avec `T` : c'est la
valeur qui garantit que le firmware ne termine jamais de lui-même et que le flux `R:` ne s'interrompt
pas. Recette et démonstration en `01` §5.5. `T` reste entièrement géré par le PC.

**Condition de fin.** **Calculée par le PC seul :** `elapsedMs ≥ T × 1000`. Le PC envoie ensuite `s`.

> Une version antérieure de ce document décrivait une « double détection » PC + firmware dont on
> retenait la première. **Elle n'existe pas.** Le firmware déborde son `int` 16 bits sur
> `raceLengthSecs * 1000` et ne termine jamais une course de plus de 32 secondes — démonstration
> complète en `01` §5.5. Avec le défaut à 60 s, le firmware n'émettra jamais ses `<i>F:`.
> Quand ils arrivent (T ≤ 32 s), ils sont traités comme une confirmation loggée, jamais comme
> une condition de fin.

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

> **Tranché avec l'utilisateur (session initiale) : élimination progressive.** C'est la règle par
> défaut et la seule livrée au lot 2. L'alternative « premier à mettre `G` à *tous* les autres
> gagne, sans élimination » reste implémentable derrière l'interface `PursuitRule`, qui doit rendre
> les deux variantes interchangeables — mais elle n'est pas écrite tant qu'elle n'est pas demandée
> (règle « pas de code mort »).

**Séquence série.** `x` → **`t60`** → `g`.
Le mode temps est utilisé comme *véhicule* parce que c'est le seul qui ne fait pas terminer le
firmware sur une condition de distance. Quand le PC décide la fin, il envoie `s`.

> **Ne jamais envoyer `t300`.** Le plafond de 300 s envisagé initialement est un piège :
> `300 × 1000` déborde l'`int` 16 bits en `-27680`… mais d'autres valeurs débordent vers un
> **entier positif court**, et `t600` ferait terminer le firmware au bout de 10,2 s en coupant le
> flux `R:` en pleine course (`01` §5.5). On envoie donc la constante `t60`, sûre par construction.
> **Les deux plafonds ci-dessous sont entièrement à la charge du PC — ce sont eux, et eux seuls,
> qui empêchent une course infinie.**

**Plafonds de sécurité, appliqués par le PC (l'un ou l'autre déclenche la fin).**
* Durée : `plafond_secs` (défaut 300 s), mesuré sur `elapsedMs`. Vainqueur = celui qui mène.
* Distance : 5000 m cumulés. Idem.
* Ces deux plafonds sont couverts par des tests dédiés au jalon J2.

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
