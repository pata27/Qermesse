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

> Corollaire, et c'est le même piège déplacé d'un cran : une piste **cochée mais vide** fait
> attendre tout le monde jusqu'au plafond de sécurité. Dix secondes après le départ, toute piste
> active restée à zéro tick est signalée à l'opérateur — une fois, sans interrompre la course, qui
> peut légitimement démarrer lentement.

**Classement.** Croissant par temps de passage. Ex æquo au tick près départagé par l'ordre d'arrivée
de la trame `R:`. Deux riders qui franchissent dans **la même trame** sont ex æquo : rien dans le
flux ne les sépare. Ils sont rangés par numéro de piste — un ordre arbitraire mais déterministe — et
l'UI le dit : podium et tableau marquent « photo-finish ».

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

**Classement.** Décroissant par **distance de course** — les mètres roulés, **handicap déduit**
(§4) : un pénalisé de 10 m qui en a roulé 105 se classe à 95, derrière un coureur régulier à 100.
C'est la distance que podium et tableau affichent ; classer sur les ticks bruts faisait gagner,
devant le public, celui dont le chiffre affiché était le plus petit. Ex æquo → vitesse de pointe la
plus élevée, et à pointe égale → numéro de piste : arbitraire, mais **déterministe**, comme pour
l'ex æquo d'arrivée du mode distance. Ce mode n'a en revanche **pas de photo-finish** : tout le monde s'arrête à
l'instant du gong, l'égalité des temps y est la règle et non un fait de course.

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

> Une course décidée au plafond **n'est pas une course arrêtée** : elle a un vainqueur, et les
> écrans le disent ainsi — podium titré `ARRIVÉE`, motif du plafond en pied, entrée normale dans les
> courses du jour. Seul un abandon — arrêt opérateur, lien perdu, fermeture du logiciel — s'annonce
> `INTERROMPUE`, parce que là personne n'a gagné. Le champ `interrupted` couvre les deux cas ; c'est
> `end_reason` qui les sépare. L'arrêt de la vitrine en pleine manche de démonstration, lui, n'est
> pas un abandon qui se raconte : la course n'a pas eu lieu, l'écran public revient au repos.

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

Le handicap se paie **en ticks** : le fautif doit couvrir `D + P` mètres pour franchir la ligne. Il
n'est pas seulement dessiné en arrière — une pénalité qui ne coûterait rien à l'arrivée n'en serait
pas une. Sa distance au tableau reste celle de l'épreuve ; c'est son temps qui porte le prix.
En **temps**, où c'est la distance qui classe (§2), le prix se paie là : le fautif est classé et
affiché à `P` mètres de moins que ce qu'il a roulé.

En **poursuite**, une pénalité supérieure ou égale à l'écart décisif est **refusée à l'armement** :
le fautif partirait déjà à la distance d'élimination, la course se terminerait à la première trame
— onze millisecondes, vainqueur à 0,0 m et 0,0 km/h. Ce n'est pas une course, et l'opérateur doit
l'apprendre avant, pas devant le public.

La **vitesse moyenne** se calcule sur la distance réellement roulée, handicap déduit : la position
d'un pénalisé est négative tant qu'il n'a pas remonté son retard, et une moyenne calculée dessus
donnait `−3272 km/h` au podium et au CSV.

**Aucune distance négative ne sort du résultat**, pour la même raison et parce que la moitié du
défaut ci-dessus était restée. La position d'un pénalisé est négative tant qu'il n'a pas rattrapé la
ligne ; si la course s'arrête là — abandon, élimination en poursuite, gong d'une course en temps
courte — c'est cette valeur qui partait au podium public, au tableau de l'opérateur, au CSV et au
JSON. Une distance parcourue négative n'a aucun sens : le handicap est un décalage de départ, pas
une distance. Le classement n'en dépend pas, il est arrêté sur l'état avant d'être rangé.

Le défaut est `AVERTISSEMENT` : en événementiel, relancer une course pour un rider qui a bougé
énerve le public. `RELANCE` existe pour les usages compétitifs.

---

## 5. Persistance des résultats

**CSV** — reprise du format v1 pour continuité, mais avec les événements réellement écrits
(la v1 déclarait 5 types d'événements et n'en écrivait qu'un).

Fichier : `<données_app>/logs/YYYY_MM_DD_QermesseRaceLog.csv`, **append réel**
(la v1 rechargeait et réécrivait tout le fichier à chaque ligne — à ne pas reproduire).

Colonnes : `timestamp_iso, event, mode, rider, dossard, distance_m, temps_ms, vitesse_moy_kph, vitesse_max_kph, rang, note`

`timestamp_iso` est en **heure locale avec son décalage** (`2026-09-02T22:49:00+02:00`) : le CSV est
le fichier que l'opérateur ouvre dans un tableur, et il est nommé par la journée d'exploitation —
les deux doivent concorder. Le JSON de course, lui, horodate en **UTC** : c'est un artefact
machine, et l'historique du jour fait la conversion à la relecture.

**La journée d'exploitation n'est pas la journée du calendrier.** Elle commence à **5 h locales**
et se termine à 5 h le lendemain. Une soirée de goldsprints passe minuit ; découper au douzième
coup ferait de la course de 00 h 10 la première d'une nouvelle journée, sur un nouveau fichier,
dans un historique vide — au beau milieu de l'événement. Une course de 00 h 10 appartient donc à
la journée de la veille, et son CSV porte la date de la veille. Aucun goldsprint ne court à
5 h du matin : la coupure est là où il ne se passe jamais rien.

Événements écrits : `RACE_START`, `FALSE_START`, `RIDER_FINISH`, `RIDER_ELIMINATED`,
`RACE_FINISH`, `RACE_ABORTED`, `LINK_LOST`, `TICK_REJECTED`.
Une ligne `TICK_REJECTED` porte le rider et, en `note`, la raison du filtre (`01` §6.3) : un tick
rejeté est loggué, jamais silencieusement absorbé.

La `note` d'une ligne `RACE_FINISH` **décrit ce rider**, pas la course : l'instant de sa sortie
s'il est éliminé, le motif s'il y a eu arrêt, et **`photo-finish`** s'il n'a pas pu être départagé.
Sans cette mention, deux temps identiques avec les rangs 1 et 2 se relisent six mois plus tard
comme une coïncidence d'arrondi — alors que sur cinquante mètres, où un tick vaut 36 cm et les
trames tombent à 100 Hz, l'ex aequo est fréquent. Le panneau matériel en tient le compte de la
session, avec le dernier motif — un capteur qui rebondit se voit avant de fausser une course.

**Sens des colonnes sur une ligne `RACE_FINISH` — une par rider.** `temps_ms` est le **temps
couru** par ce rider : son temps d'arrivée s'il a fini, l'instant de son élimination s'il a été
éliminé (en mode temps, l'instant du gong pour tout le monde ; pour les survivants d'un plafond de
poursuite, l'instant du plafond). Jamais 0 pour un rider classé.
`vitesse_moy_kph` est calculée sur ce temps couru — et sur la distance figée à cet instant —, jamais
sur la durée totale de la course : la moyenne d'un rider éliminé à 14 s n'est pas diluée par les
25 s pendant lesquelles il regardait les autres. `distance_m` est la distance à cet instant.
Une ligne `RIDER_ELIMINATED` porte, en `note`, l'écart au leader au moment de l'élimination. Sur une
ligne `RACE_FINISH`, la `note` décrit **ce rider** et non la course : `elimine a 14.01 s` pour un
éliminé, le motif de fin sinon. Chaque ligne d'un CSV se lit seule, une fois triée dans un tableur.

**JSON** — un fichier par course dans `<données_app>/races/<uuid>.json`, **y compris pour une course
interrompue** dès lors qu'elle a couru : arrêt opérateur, lien perdu au-delà du délai de grâce. Son
résultat partiel porte `interrupted` et `interruption_note`, et sa trace est celle qu'on veut
justement rejouer après un incident. Une course interrompue pendant l'armement ou le décompte n'a
rien à raconter et n'écrit rien. Le fichier contient en plus
**la trace complète des trames `R:`** (ticks + elapsedMs), **telles que le boîtier les a
envoyées** : avant le filtre du `01` §6.3, et avant le gel d'un rider arrivé. La trace portait
auparavant les valeurs retenues par le moteur — deux trames par course y étaient donc retouchées,
et un tick rejeté n'y laissait aucune trace, dans le fichier même que `DEPANNAGE` fait envoyer au
développeur pour diagnostiquer ce rejet. Le rejeu rejoue le filtre, il ne le suppose pas. Le résultat y est porté par rider :
`finished_ms`, `eliminated_ms` (0 tant que le rider court), `distance_m`, `avg_kph`, `max_kph`,
`eliminated`, `false_started`, avec les mêmes conventions que le CSV. La trace comprend aussi
`hardware_finishes` — les trames `<idx>F:` du boîtier, `[rider, elapsed_ms]` : le rejeu les rejoue à
leur instant, sans quoi le dernier tick, que le firmware ne transmet jamais (`docs/01` §5.6),
manquerait et la course rejouée ne se terminerait pas. Permet le rejeu d'une course, le débogage
post-événement, et la génération de replays. ~100 Hz × 60 s × 4 riders ≈ 6000 échantillons,
soit quelques centaines de Ko : négligeable.

**Historique du jour.** La liste « Courses du jour » du panneau de résultats est **relue depuis
les JSON au lancement**, pas seulement alimentée par les courses de la session : un redémarrage du
logiciel en pleine soirée — plantage, changement de machine, mise à jour — ne la vide pas, **y
compris après minuit**. Le « jour » est la journée d'exploitation définie plus haut, celle qui
nomme le CSV : de 5 h locales à 5 h le lendemain. `started_at` étant écrit en UTC, la conversion
est faite à la relecture. Les courses sont listées dans l'ordre de départ. Seuls les
fichiers dont le nom horodaté (`YYYYMMDD-HHMMSS-xxxx.json`, UTC) peut tomber dans la journée
d'exploitation sont ouverts : le dossier `races/` grossit de plusieurs Mo par soirée et ne s'élague jamais.
Un résultat porte **les noms des riders tels qu'ils étaient au départ** : l'écran de résultats et
l'historique affichent ceux-là, jamais le roster courant — renommer les pistes entre deux courses
ne réécrit pas l'histoire.

**Réglages** — JSON **lisible sans connaître le code** : le mode et la politique de faux départ y
sont écrits en toutes lettres (`"mode": "poursuite"`), comme dans la trace d'une course. Les
fichiers écrits par une version antérieure, qui portaient des entiers, restent relus — une mise à
jour ne fait pas perdre ses réglages à l'opérateur. Chemins standards par OS :
* Linux `~/.config/qermesse/settings.json`
* macOS `~/Library/Application Support/Qermesse/settings.json`
* Windows `%APPDATA%\Qermesse\settings.json`

Les noms des riders **sont persistés** (roster réutilisable d'une course à l'autre) — la v1 les
perdait à chaque lancement. La **couleur**, en revanche, est écrite mais jamais relue : elle vient
de la palette figée par piste (`04` §2), qui sert à identifier un coureur avec son numéro (`03` §6).
Un fichier ne doit pas pouvoir donner la même couleur à deux pistes, ni figer une palette qui
changerait. Réglages et roster sont écrits **à chaque fin de course** et à la
fermeture, pas seulement à la fermeture : un plantage ou une coupure en soirée ne perd rien de ce
qui a servi. Une écriture qui échoue est dite à l'opérateur.
