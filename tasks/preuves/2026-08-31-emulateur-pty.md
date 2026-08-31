# Preuve — émulateur `ss_emu` bout en bout sur pseudo-terminal

**Date** 2026-08-31 · **Jalon** aucun — étape intermédiaire vers J1-ém, pas J1.

> Ce que cette preuve établit : le firmware émulé se comporte comme `ss_basic.ino` sur un
> **vrai port série**, et un client indépendant mène le handshake, encaisse une trame corrompue,
> détecte une coupure sous 500 ms, se reconnecte et voit la course se poursuivre.
>
> Ce qu'elle n'établit pas : rien du GDExtension C++ (pas encore écrit), rien du matériel réel.
> **J1-ém sera franchi quand ce même scénario passera à travers le GDExtension**, et J1 quand il
> passera sur l'Arduino de l'utilisateur.

## Commandes reproductibles

```
cmake -S tools/ss_emu -B tools/ss_emu/build && cmake --build tools/ss_emu/build -j
./tools/ss_emu/build/ss_emu_tests                       # 50 cas, 309 assertions, exit 0

./tools/ss_emu/build/ss_emu --pty --link ./.run/ttyEMU --riders 2 --profile egaux \
    --inject trame-corrompue@3 --inject perte-lien@5 --inject retour-lien@7 \
    --inject tick-fantome=0@9 --inject gel@11=700 --trace ./.run/trace.log

python3 tools/ss_probe.py ./.run/ttyEMU --duration 20 --mode distance --metres 100
```

## Sortie de la sonde

```
port            : .run/ttyEMU
firmware        : SS_v0.1.7
etat            : IDENTIFIED  (seul etat ou START est autorise)
course          : distance, 100 m = 278 ticks
depart demande, decompte en cours

[  0.02s] ack L:278
[  1.01s] decompte CD:3
[  2.02s] decompte CD:2
[  3.02s] decompte CD:1
[  4.01s] decompte CD:0
[  7.03s] TRAME INCONNUE (loggee, pas levee) : b'R:\x01\x99\xc3 42,,'
[  9.49s] LINK_LOST — 505 ms sans R:
[ 10.00s] silence prolonge, on referme et on rescanne
[ 11.51s] RECONNECTE sur .run/ttyEMU, firmware SS_v0.1.7
[ 11.53s] LIEN RETABLI, flux R: repris
[ 13.01s] arrivee 0F:9002
[ 13.03s] arrivee 1F:9023
[ 15.52s] LINK_LOST — 505 ms sans R:
[ 15.72s] LIEN RETABLI, flux R: repris
trames inconnues : 1
```

## Lecture

| Observation | Ce qu'elle prouve |
|---|---|
| `firmware : SS_v0.1.7` puis `IDENTIFIED` | handshake `s` → `v` → `V:` de `docs/01` §4 |
| `ack L:278` | 100 m avec un rouleau de 114.3 mm = **278 ticks**, la non-régression v1/v2 |
| `CD:3` … `CD:0` à 1 s d'intervalle | décompte firmware, ~4 s au total, cadencé par le matériel |
| `TRAME INCONNUE : b'R:\x01\x99\xc3 42,,'` | octets non-UTF-8 en pleine ligne, classés `Unknown` et loggués — **rien n'a levé** |
| `LINK_LOST — 505 ms sans R:` | watchdog de `docs/01` §6.2, seuil 500 ms |
| `RECONNECTE … firmware SS_v0.1.7` | le pseudo-terminal a changé de numéro comme un Arduino qui ré-énumère ; le lien symbolique a suivi |
| `arrivee 0F:9002` / `1F:9023` après la reconnexion | **la course a survécu à la coupure** : la reconnexion n'a émis que `v`, jamais `s` |
| aucune fin de course après les deux arrivées | le firmware attend les 4 pistes — le bug de la v1, reproduit fidèlement |
| second `LINK_LOST` à 15.52 s puis reprise 200 ms plus tard | `gel@11=700` : firmware muet, port toujours ouvert. Le watchdog doit distinguer ce cas d'une déconnexion. |

## Pannes déclenchées, côté émulateur

```
[panne] trame corrompue
[panne] perte-lien a t=5 s
[panne] retour-lien a t=7 s, nouveau pseudo-terminal /dev/pts/13
[panne] tick-fantome rider 0
[panne] gel de 700 ms
```

Le tick fantôme est visible dans la ligne d'état : à t=9.0 s les deux riders sont à 277 ticks,
à t=9.2 s le rider 0 est à 287 et le rider 1 à 285. L'écart d'un tick injecté persiste — c'est
exactement ce que le filtre PC de `docs/01` §6.3 devra rattraper au lot 2.

## Extrait de trace — la reconnexion

```
4492.0   PC->FW   s\nv\n          <- handshake initial
4497.0   PC->FW   d\nl278\ng\n    <- armement de la course
16006.0  PC->FW   v\n             <- reconnexion : v SEUL, pas de s
```

2471 lignes de trace au total, dont 2467 trames firmware → PC.
