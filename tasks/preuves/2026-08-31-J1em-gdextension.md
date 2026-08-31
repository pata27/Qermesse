# Preuve — Jalon **J1-ém** franchi

**Date** 2026-08-31 · **Scénario** émulateur de firmware sur pseudo-terminal, driver réel via GDExtension

`docs/05` lot 1 : *« Contre `ss_emu` sur pseudo-terminal : handshake complet et version firmware
affichée, ticks des pistes câblées en direct, `perte-lien` injectée → `LINK_LOST` en moins de
500 ms, `retour-lien` → reconnexion et reprise, trame corrompue absorbée sans plantage. »*

> **J1-ém n'est pas J1.** Le matériel réel de l'utilisateur n'a pas été branché : le boîtier n'était
> pas disponible. J1-ém autorise le lot 2 à démarrer ; **il n'autorise pas le lot 4.** Ce que
> l'émulateur ne prouve pas est listé en `docs/07` §2.

## Ce qui a été traversé

Contrairement à la sonde `ss_probe.py`, ce scénario passe par **le code réellement embarqué** :
GDExtension C++, thread de lecture, ring buffer SPSC, drain dans `_process`, signaux Godot.

## Commandes reproductibles

```sh
cmake -S . -B build && cmake --build build -j
./build/tools/ss_emu/ss_emu --pty --link ./.run/ttyEMU --riders 2 --profile ecart-leger \
    --inject trame-corrompue@3 --inject perte-lien@6 --inject retour-lien@8 \
    --trace ./.run/trace-j1em.log &

cd addons/serial_link && scons target=template_debug -j8 && cd ../..
./.tools/Godot_v4.5-stable_linux.x86_64 --headless --script tools/ss_monitor.gd \
    -- --port "$PWD/.run/ttyEMU" --distance 100 --duree 22
```

## Sortie

```
mode            : MATERIEL (via GDExtension)
ports detectes  : 32, dont 0 candidat(s)
  aucun port ne coche de critere — aucun ne sera ouvert au hasard
  (un pseudo-terminal n'apparait pas ici : utiliser --port)
port force      : /home/antoine/Code/SilverSprint-v3/.run/ttyEMU
[   0.02 s] lien -> DISCONNECTED
[   0.03 s] lien -> IDENTIFIED
[   0.03 s] firmware SS_v0.1.7 sur /home/antoine/Code/SilverSprint-v3/.run/ttyEMU
[   0.03 s] course armee : 100 m = 278 ticks
[   0.03 s] version : SS_v0.1.7
[   0.03 s] ack longueur : 278 ticks
[   1.03 s] decompte 3
[   2.03 s] decompte 2
[   3.03 s] decompte 1
[   4.03 s] decompte 0
[   7.03 s] Unknown : R:\x01\x99\xC3 42,,
[  10.52 s] lien -> LINK_LOST
[  12.53 s] lien -> IDENTIFIED
[  12.53 s] version : SS_v0.1.7
[  12.71 s] ARRIVEE piste 1 a 8678 ms
[  13.04 s] ARRIVEE piste 0 a 9009 ms
statistiques du lien
  frames_total         1418
  frames_progress      1408
  frames_unknown       1
  frames_dropped       0
  lines_overlong       0
  connects             2
  handshake_failures   0
  watchdog_trips       1
  races_interrupted    0
```

## Lecture

| Observation | Ce qu'elle prouve |
|---|---|
| `32 ports, dont 0 candidat` | **Le bug de sélection de la v1 est mort.** 32 ports `/dev/ttyS*` réels sur cette machine ; le repli « prendre le dernier de la liste » aurait ouvert `/dev/ttyS9`. Aucun n'est ouvert. |
| `DISCONNECTED` → `IDENTIFIED` en 10 ms | Handshake `s` → `v` → `V:SS_v0.1.7` de `docs/01` §4, à travers le GDExtension |
| `ack longueur : 278 ticks` | 100 m @ rouleau 114.3 mm — non-régression v1/v2 |
| `decompte 3` … `0`, à 1 s d'intervalle | Cadencé par le firmware, pas par un minuteur local |
| `Unknown : R:\x01\x99\xC3 42,,` | Octets non-UTF-8 en pleine ligne, échappés avant d'atteindre une `String` Godot. **1** trame inconnue, aucun plantage. |
| `LINK_LOST` puis `IDENTIFIED` 2 s plus tard | Watchdog, puis reconnexion sur un pseudo-terminal **renuméroté** — comme un Arduino qui ré-énumère |
| Arrivées **après** la reconnexion | La course a survécu à la coupure : la reconnexion n'émet que `v`, jamais `s` |
| piste 1 à 8678 ms, piste 0 à 9009 ms | Profil `ecart-leger`, rider 1 est 5 % plus rapide — l'écart de 3,8 % sur le temps est cohérent |
| Aucune fin de course après les deux arrivées | Le firmware attend les 4 pistes. **Le bug historique de la v1, fidèlement reproduit** — c'est au PC de trancher, ce sera le lot 2. |
| `frames_dropped 0` sur 1418 trames | Le ring buffer SPSC n'a rien perdu ; le thread de jeu suit le rythme |
| `races_interrupted 0` | La coupure de 2 s est restée sous les 3 s de grâce : course conservée, pas marquée `INTERROMPUE` |

## Vérifications complémentaires

`tools/check_extension.gd`, exécuté en CI sur les trois OS :

```
module natif SerialLink : CHARGE
  ports enumeres : 32
  etat initial   : DISCONNECTED
  START autorise : non (attendu au demarrage)
```

Compiler la bibliothèque ne suffit pas : ce contrôle prouve que Godot la **charge** et que le code
natif s'exécute. Une ABI incompatible ou un `entry_symbol` erroné donnerait sinon une CI verte et un
logiciel muet le jour J.

## Ce qui reste ouvert pour J1

* Brancher le boîtier réel, relever `lsusb`, compléter l'allowlist VID/PID de `port_selection.cpp`.
* Débranchement USB **physique** à chaud : l'émulateur ferme un pseudo-terminal, ce qui n'exerce pas
  le chemin `EIO` du pilote USB réel.
* Vérifier que les ticks arrivent sur la bonne piste, et le nombre de capteurs réellement câblés.
