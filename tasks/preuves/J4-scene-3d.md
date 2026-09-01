# Preuve du jalon J4 — scène 3D

> **Énoncé** (`docs/05` §Lot 4) : « 60 fps stables en 1080p sur GPU intégré, mesurés et consignés,
> pendant une course à 4 riders au simulateur. Vidéo de 30 s produite comme preuve. »

Date : 2026-09-01. Machine : AMD Radeon Graphics (RADV REMBRANDT) — **GPU intégré**, conforme à
l'énoncé. Godot 4.5 stable, pilote Vulkan, Forward+.

## 1. Ce que « stables » veut dire ici

Le budget se juge sur le **premier centile**, pas sur la moyenne : une moyenne à 62 fps avec des
chutes à 30 se voit à l'écran et pas dans le chiffre (`PerfMonitor.budget_met`). Le fps est déduit du
delta de **chaque image** — `Engine.get_frames_per_second()` est lissé sur une seconde et un centile
calculé dessus porterait sur des valeurs répétées.

La résolution de rendu est **forcée à 1920×1080** indépendamment de la taille de fenêtre
(`content_scale_size`) : le gestionnaire de fenêtres bride souvent celle-ci, et une mesure prise à
941×1144 ne dirait rien du budget.

## 2. Relevés — fenêtre de 30 s, 4 coureurs, qualité « moyen »

Reproductible par :

```
./.tools/Godot_v4.5-stable_linux.x86_64 --script tools/ss_race3d_demo.gd -- \
    --mesure --riders 4 --qualite moyen --mode-course distance --profil <profil>
```

| Profil | Ce qu'il éprouve | Images | Moyenne | **1 % bas** | Minimum | Budget |
|---|---|---|---|---|---|---|
| `egaux` | peloton groupé, un seul volet | 5 670 | 192,1 fps | **135,6** | 46,5 | **TENU** |
| `casse-par-etapes` | 1 → 2 → 3 → 4 volets dans une course | 5 723 | 195,5 fps | **132,1** | 28,0 | **TENU** |
| `eparpille` | quatre volets ouverts en permanence | 5 612 | 190,7 fps | **136,4** | 30,0 | **TENU** |

Le minimum est une image isolée — ouverture d'un volet, première compilation d'un shader. Le premier
centile, lui, reste au-dessus de 130 fps dans les trois cas, soit **plus du double du budget**.

## 3. Coût par nombre de volets

C'est le relevé qui compte réellement, parce qu'une moyenne sur toute une course masque le pire cas.
Mesuré image par image (`SS_FRAMES`), médiane sur quatre tours :

| Volets ouverts | ms par image | fps médian | fps minimum |
|---|---|---|---|
| 1 | 8,93 | 112 | 85 |
| 2 | 9,65 | 104 | 75 |
| 3 | 8,50 | 118 | 100 |
| 4 | 8,39 | 119 | 82 |

La courbe est **plate** : quatre volets ne coûtent pas plus cher qu'un seul, parce que la scène
s'allège à mesure qu'elle se scinde (`RaceScene._relieve_for_panes`).

## 4. Comment on y est arrivé, et ce que la mesure a démenti

Deux fausses pistes, consignées parce qu'elles ont coûté du temps :

* **« Ce sont les appels de rendu. »** Faux. Supprimer 96 projeteurs d'ombre sur 104 a fait tomber
  les appels de 495 à 225 **sans changer le temps par image**. À 76 triangles par appel, cette scène
  n'est pas limitée par la géométrie. Le correctif est conservé — il supprime un coût réel — mais il
  ne visait pas le goulot.
* **« Ce sont les lignes de vitesse, 15 ms sur 21. »** Faux, et c'était un artefact de mesure : un
  banc tournait en tâche de fond pendant que d'autres instances de Godot s'exécutaient. Repris en
  alternant les configurations, l'écart entre elles (19,3 à 22,7 ms) s'est révélé plus petit que
  l'écart entre deux relevés d'une même configuration (17,0 à 32,7 ms).

Ce que la mesure a établi :

* Le coût est **proportionnel au nombre de volets** et tient au **remplissage** — à quatre volets,
  177 fps en 1080p, 289 en 720p, 344 en 540p (`--rendu LxH`).
* **Aucun réglage ne domine** : ombres −10 %, anticrénelage −7 %, les deux ensemble −9 %. Mais le
  niveau « bas » complet gagne 42 %. Il n'y avait pas de coupable unique à trouver.
* D'où le correctif : **alléger l'ensemble en fonction du nombre de volets**, ce que `docs/04` §4
  prescrit explicitement.

Un premier placement des paliers a été mesuré puis corrigé : couper la foule à trois volets et le
reste à quatre faisait de **trois volets le pire cas de tous** (59 fps, contre 105 à quatre volets
entièrement allégé). Un palier mal placé creuse un trou au lieu de le combler.

## 5. Outillage de mesure ajouté

| Levier | Ce qu'il sert à trancher |
|---|---|
| `SS_FRAMES=<fichier>` | relevé image par image : temps, appels de rendu, primitives, nombre de volets |
| `--rendu LxH` | résolution de rendu — sépare le remplissage de la géométrie |
| `--fenetre S` | durée de la fenêtre — permet de RÉPÉTER un relevé |
| `SS_QOPT="glow=0,msaa=0"` | surcharge un réglage de qualité à la fois |
| `RaceScene.census()` | recensement des instances visuelles par branche |

## 6. Ce que ce jalon ne dit pas

* Mesuré sur **un seul GPU intégré**. `docs/04` §4 ne demande pas davantage, mais la marge observée
  ici ne se transpose pas telle quelle à un autre matériel.
* La dégradation automatique par `PerfMonitor` reste le filet : elle n'a pas eu à intervenir.
* **J1 reste ouvert.** La scène 3D ne lit jamais le port série, conformément à la dérogation inscrite
  dans `docs/05`, mais rien de ce qui suit ne vaut recette matériel — voir `docs/RECETTE.md`.
