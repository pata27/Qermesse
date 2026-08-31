# 07 — Émulateur de firmware (`ss_emu`)

> **Statut : directeur.** Le comportement de référence est `docs/01`, lui-même adossé au firmware
> amont `cwhitney/SilverSprint`, `apps/Arduino/ss_basic/ss_basic.ino`, commit `3a6157e`,
> md5 `bba3bc3980f90eecf67438183b2b1ed1`, 323 lignes.
> En cas de désaccord entre ce document et `01`, c'est `01` qui gagne — et si `01` désaccorde avec
> le `.ino`, c'est le `.ino` qui gagne et `01` qui est corrigé.

---

## 1. Pourquoi un émulateur, et pourquoi à ce niveau-là

Le matériel n'est pas disponible en permanence. Sans lui, le lot 1 — le lot le plus risqué du
projet — ne peut ni être développé ni être testé. L'émulateur lève ce blocage.

**La décision qui fait tout l'intérêt du dispositif : on émule au niveau du port série, pas au
niveau du parseur.** `ss_emu` ouvre un pseudo-terminal, s'y comporte exactement comme un Arduino
Uno branché en USB, et parle le protocole octet par octet à 115200 bauds. Le code Godot ne sait pas
qu'il parle à un émulateur.

C'est précisément l'erreur que la v2 n'a pas su éviter. Son « mode mock » court-circuitait la
couche série et injectait des structures déjà parsées dans le moteur : il testait le code sans
risque et laissait le code risqué — ouverture du port, threading, découpage de flux, handshake,
watchdog, reconnexion — entièrement non couvert. `ss_emu` inverse ce rapport : **tout ce qui est
risqué est traversé pour de vrai.**

| Ce que `ss_emu` exerce réellement | Ce qu'un mock au niveau parseur n'exerce pas |
|---|---|
| Énumération et ouverture du port | — |
| Configuration termios 115200 8N1 | — |
| Thread de lecture, ring buffer SPSC, drain | — |
| Découpage d'un flux en lignes `\r\n`, trames coupées en deux lectures | — |
| Handshake `s` → `v` → `V:SS_v0.1.7`, timeouts, réessais | — |
| Watchdog 500 ms, débranchement à chaud, reconnexion | — |
| Octets non-UTF-8 au milieu d'une ligne | — |

---

## 2. Ce que l'émulateur ne prouve pas

À écrire noir sur blanc, parce que la tentation de cocher J1 sera forte :

* **`ss_emu` ne franchit pas le jalon J1.** J1 exige le matériel réel de l'utilisateur. L'émulateur
  produit un jalon intermédiaire, noté **J1-ém.**, qui autorise le lot 2 à démarrer.
  *Il n'autorisait pas le lot 4 ; celui-ci a été ouvert le 2026-08-31 par une dérogation explicite
  de l'utilisateur, consignée dans `docs/05`. Le reste de cette section demeure entièrement valable :
  ce que l'émulateur ne prouve pas, il ne le prouve toujours pas.*
* Il ne dit rien du câblage réel, du nombre de capteurs branchés, ni de la qualité des contacts.
* Il ne reproduit pas les rebonds mécaniques réels d'un reed switch : il en produit un modèle
  paramétrable, ce qui est utile pour tester le filtre, pas pour le calibrer.
* Il ne valide pas les pilotes USB-série de Windows et macOS.
* Il ne dit rien d'un boîtier reflashé avec un firmware divergent — risque listé en `06` §4.

---

## 3. Architecture

```
tools/ss_emu/
├── src/
│   ├── avr_types.h        # int16/uint32 explicites, sémantique arithmétique AVR
│   ├── firmware_sim.h/.cpp  # réplique fidèle de ss_basic.ino — AUCUNE dépendance OS
│   ├── rider_model.h/.cpp   # cyclistes synthétiques, pilotent les broches capteurs
│   ├── faults.h/.cpp        # injection de pannes
│   ├── port_pty.h/.cpp      # frontal pseudo-terminal (POSIX)
│   └── main.cpp             # CLI
├── tests/                   # doctest, binaire natif, tourne sans Godot ni port série
└── CMakeLists.txt
```

Trois couches, strictement séparées :

1. **`FirmwareSim`** — le firmware. Pur, déterministe, sans horloge système ni E/S. On lui pousse
   des octets d'entrée et un temps `millis()`, il rend des octets de sortie et l'état des broches.
   C'est cette couche que les tests attaquent.
2. **`RiderModel` + `Faults`** — le monde physique. Décide, en fonction du temps, l'état des quatre
   broches capteurs et les avaries à injecter.
3. **`PortPty`** — le transport. Crée le pseudo-terminal, cadence la boucle en temps réel.

L'horloge est **injectée** dans les deux premières couches. Conséquence : les tests tournent en
temps virtuel, instantanément, et une course de 60 s se rejoue en quelques millisecondes.

### Build

**CMake**, et non SCons. SCons reste imposé pour le GDExtension par la chaîne godot-cpp ; pour un
outil autonome, CMake est disponible sans installation sur les trois runners GitHub et compile
sous MSVC sans travail supplémentaire. Écart assumé vis-à-vis de `03` §1, consigné ici.

---

## 4. Contrat de fidélité

L'émulateur reproduit le firmware **bugs compris**. Un émulateur qui « corrige » sa cible est un
piège : il valide un code PC qui échouera sur le vrai matériel.

### 4.1 Reproduit à l'identique

| Comportement | Détail |
|---|---|
| Largeur des types | `int` = 16 bits signés, `unsigned long` = 32 bits. Débordements inclus. |
| `checkTimeBased()` | `raceLengthSecs * 1000` calculé en `int16` → jamais de fin au-delà de 32 s (`01` §5.5) |
| `atoi()` | Repliement modulo 2¹⁶ sur les valeurs hors plage |
| Un octet par tour de boucle | `checkSerial()` ne consomme qu'un caractère par appel de `loop()` |
| Décompte | `lastCountDown = 4` à `g`, `CD:3` après 1000 ms, `CD:0` à ~4 s, puis `raceStart()` |
| Faux départ | ≥ 4 fronts pendant `raceStarting` → `FS:<i>` une seule fois, LED éteinte |
| Détection de front | LOW → HIGH uniquement, **aucun anti-rebond** |
| Cadence `R:` | `currentTimeMillis - lastUpdateMillis > 10` |
| Amorce de `lastUpdateMillis` | `raceStart()` l'initialise à `raceStartMillis`, valeur **absolue**, comparée ensuite à un temps **relatif** : la première trame `R:` part immédiatement. Reproduit. |
| Fin en distance | Attend **les quatre** pistes ; avec 2 capteurs la course ne finit jamais — le bug de la v1 |
| Arrêt du flux `R:` | Plus aucune trame après la fin firmware |
| `ERROR:` malformé | Double préfixe, et l'octet **brut** émis par `Serial.println(char)` |
| `<i>F:` négatif | En mode temps ≤ 32 s, `raceLengthSecs * 1000` peut sortir négatif |
| `m` | Mode mock interne, y compris le double comptage tick calculé + tick sur front |
| Terminateurs | `\r\n` en sortie, `\r` comme `\n` accepté en entrée |
| Commandes sans accusé | `s`, `t`, `d`, `x` ne répondent rien |

### 4.2 Écarts assumés, et pourquoi

| Écart | Raison |
|---|---|
| **Dépassement de `charBuff`** : le tableau réel fait 8 octets et `charBuffPos` n'est pas borné. On alloue un tampon gardé de 64 octets, on détecte le dépassement, on émet `EMU-WARN: charBuff overflow (pos=N)` sur *stderr* et on poursuit. | Reproduire un comportement indéfini n'a pas de sens : sur AVR le résultat dépend de l'agencement mémoire du compilateur. Le PC ne doit de toute façon **jamais** émettre plus de 7 chiffres (`01` §2). L'émulateur transforme donc une UB en **alarme visible** : si ce message apparaît, le driver PC a un bug. |
| Broche 13 (heartbeat) déclarée `INPUT` puis écrite | Le firmware le fait vraiment ; sur AVR cela ne bascule que la résistance de tirage. Sans effet observable sur le port série, exposé en état interne pour les tests. |
| Latence USB-série et gigue d'ordonnancement | Modélisées en option (`--latency-ms`), pas par défaut. |

---

## 5. Cyclistes synthétiques

Le modèle produit des fronts sur les broches 2 à 5. Par rider : accélération, vitesse de croisière,
fatigue, gigue de cadence.

Profils prédéfinis (`--profile`) — ce sont ceux exigés par `03` §5 :

| Profil | Intention |
|---|---|
| `egaux` | Écarts sous le mètre, éprouve le photo-finish |
| `ecart-leger` | Un rider 5 % plus rapide |
| `domination` | Un rider très supérieur ; en poursuite, fin rapide |
| `remontee-finale` | Le retardataire repasse devant dans les derniers mètres |
| `abandon` | Un rider s'arrête net à mi-course |

`--riders <n>` fixe le nombre de capteurs **câblés**. Les broches au-delà restent bloquées à HIGH,
comme un connecteur vide. **Le défaut est 2**, qui correspond au boîtier de l'utilisateur et qui est
exactement la configuration où la v1 se bloquait.

## 6. Injection de pannes

`--inject <panne>[@<temps>]`, cumulable :

| Panne | Effet |
|---|---|
| `faux-depart=<i>` | Le rider `i` pédale pendant le décompte → `FS:<i>` |
| `tick-fantome=<i>` | Rebond de contact : un front parasite, sans mouvement |
| `perte-lien@<t>` | Ferme le pseudo-terminal → doit produire `LINK_LOST` en < 500 ms |
| `retour-lien@<t>` | Rouvre le port → doit produire une reconnexion et une reprise |
| `trame-corrompue@<t>` | Insère des octets aléatoires, dont des non-imprimables, au milieu d'une ligne |
| `octet-nul@<t>` | Émet un `0x00` en pleine trame |
| `gel@<t>=<ms>` | Le firmware cesse d'émettre `<ms>` sans fermer le port — le pire cas pour le watchdog |
| `ligne-tronquee@<t>` | Une ligne sans `\r\n`, suivie de la trame normale |

## 7. Interface en ligne de commande

```
ss_emu --pty [--link <chemin>]     crée un pseudo-terminal ; --link pose un lien symbolique stable
ss_emu --stdio                     octets sur stdin/stdout — pour les tests et les tubes
ss_emu --riders <1..4>             capteurs câblés (défaut 2)
ss_emu --profile <nom>             profil de course (défaut egaux)
ss_emu --roller-mm <mm>            diamètre du rouleau simulé (défaut 114.3)
ss_emu --seed <n>                  graine du bruit — rejeu déterministe
ss_emu --speed <x>                 facteur d'accélération du temps (défaut 1.0)
ss_emu --latency-ms <n>            latence de transport simulée
ss_emu --inject <panne>[@<t>]      injection, cumulable
ss_emu --trace <fichier>           journalise tous les octets échangés, horodatés
```

`--trace` est la contrepartie de l'exigence « aucune case cochée sans preuve » : la trace est un
artefact reproductible, joignable à un rapport de test, et rejouable.

## 8. Articulation avec `link_sim.gd`

Les deux coexistent, avec des rôles distincts — `03` §5 est amendé en ce sens.

| | `tools/ss_emu` | `hardware/link_sim.gd` |
|---|---|---|
| Niveau | Port série réel (pty) | En processus, derrière la façade `link.gd` |
| Traverse le GDExtension | **oui** | non |
| Plateformes | POSIX pour le pty, partout pour `--stdio` | partout |
| Usage | Développement et recette du lot 1, substitut du matériel | Tests headless du cœur métier, démos sans matériel sur les 3 OS |
| Coût d'exécution | Un processus, temps réel | Nul |

`link_sim.gd` produit **exactement les mêmes trames** que `ss_emu`, mêmes bugs compris. Toute
divergence entre les deux est un bug de `link_sim.gd`, et un test de conformité les compare sur
un même scénario à graine fixée.
