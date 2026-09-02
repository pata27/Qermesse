# Recette matériel — checklist du jalon J1

> Référencée par `docs/06` §2. À dérouler **avant chaque release**, et intégralement la première
> fois que le boîtier est branché.
>
> Prévoir **20 minutes** et un rouleau qu'on puisse tourner à la main. Aucune connaissance du code
> n'est nécessaire : chaque étape donne la commande à taper et ce qu'il faut voir.

---

## 0. Avant de brancher

```sh
cmake -S . -B build && cmake --build build -j
cd addons/serial_link && scons target=template_debug -j8 && cd ../..
godot --headless --import
```

Trois vérifications qui ne demandent aucun matériel :

```sh
ctest --test-dir build --output-on-failure          # attendu : 100% tests passed
godot --headless --script tests/run.gd ; echo $?    # attendu : 0
godot --headless --script tools/check_extension.gd  # attendu : « module natif SerialLink : CHARGE »
```

Si l'un des trois échoue, **s'arrêter là** : un problème logiciel connu ne se diagnostique pas au
milieu d'un problème matériel.

---

## 1. Identifier le boîtier

Brancher l'Arduino en USB, puis :

```sh
lsusb                       # Linux
system_profiler SPUSBDataType | grep -A4 -i arduino   # macOS
```

Relever la ligne du boîtier, de la forme `ID 2341:0043`.

- [ ] **Le VID/PID est noté.**
- [ ] **Il figure dans `known_usb_ids()`** de `addons/serial_link/src/port_selection.cpp`.
      Sinon, l'y ajouter avec un libellé, recompiler, et cocher.

> Sans cette étape, le boîtier ne sera jamais choisi automatiquement : il faudra sélectionner le port
> à la main dans le panneau matériel. Ce n'est pas bloquant, mais c'est une manipulation de plus le
> soir de l'événement.

Vérifier ensuite que le logiciel le voit :

```sh
godot --headless --script tools/ss_monitor.gd -- --duree 3
```

- [ ] La ligne du boîtier apparaît, marquée **CANDIDAT**, avec le motif `VID/PID connu`.
- [ ] Les autres ports de la machine sont listés comme `ignore`. **Aucun ne doit être ouvert.**

---

## 2. Handshake

```sh
godot --headless --script tools/ss_monitor.gd -- --duree 10
```

- [ ] `lien -> IDENTIFIED` en moins de deux secondes.
- [ ] `firmware SS_v0.1.7` s'affiche.

**Si la version diffère**, s'arrêter : le boîtier a été reflashé avec un firmware inconnu. Noter la
chaîne exacte et la comparer à `docs/01`. Le driver accepte toute chaîne commençant par `SS_v`, mais
le comportement n'est garanti que pour `0.1.7`.

**Si rien n'arrive**, le port a été ouvert sans réponse : c'est le cas prévu, START reste interdit.
Vérifier le câble, puis l'alimentation.

---

## 3. Compter les capteurs réellement câblés

```sh
godot --headless --script tools/ss_monitor.gd -- --duree 60
```

Tourner **un seul rouleau à la fois**, lentement, une dizaine de tours.

- [ ] Piste 1 : les ticks montent quand on tourne le rouleau 1, et **seulement** celui-là.
- [ ] Piste 2 : idem.
- [ ] Piste 3 : câblée ? oui / non
- [ ] Piste 4 : câblée ? oui / non

Noter le nombre de capteurs câblés — il conditionne la configuration par défaut du roster.

> **Piège classique : le câblage inversé.** Si tourner le rouleau 1 fait monter la piste 2, ce n'est
> pas un bug logiciel. Le panneau matériel de la fenêtre opérateur a un bouton *Test capteurs* fait
> exactement pour ça, à utiliser avant chaque événement.

---

## 4. Cohérence de la mesure

Mesurer le diamètre du rouleau : distance de l'aimant au centre du rouleau, **×2**. Le saisir dans
le panneau matériel.

- [ ] La ligne de calibration affiche le nombre de ticks pour 100 m.
      Repère : **114,3 mm → 278 ticks**.

Puis, rouleau tourné à la main :

- [ ] Compter 10 tours à la main et vérifier que le compteur affiche 10 ticks, à ±1 près.

Un écart systématique signale un aimant qui passe deux fois par tour, ou un capteur qui rebondit.
Dans le second cas, le compteur de trames rejetées du panneau matériel doit grimper.

---

## 5. Une course réelle

Dans la fenêtre opérateur : deux pistes actives, mode **distance**, 100 m.

- [ ] Le bouton **START** est actif. S'il est grisé, son infobulle donne le motif.
- [ ] Le décompte `3, 2, 1` s'affiche, cadencé par le boîtier.
- [ ] Les LED physiques des pistes s'allument au départ.
- [ ] Les distances montent de façon régulière, sans à-coups ni retours en arrière.
- [ ] **La course se termine seule**, sans intervention, dès que les pistes actives ont fini.
      *C'est le bug historique de la v1 : avec deux capteurs, l'ancien logiciel ne terminait jamais.*
- [ ] **Le dernier arrivé est bien déclaré arrivé**, et non bloqué à « reste 1 m ».
      *Le firmware cesse d'émettre ses trames `R:` dans la passe même où le dernier tick fait
      franchir la ligne : la valeur qui atteint la cible n'est jamais transmise (`ss_basic.ino`,
      `checkDistanceBased`). Le PC s'appuie alors sur la trame `<idx>F:` du boîtier, bornée à huit
      ticks de retard. Vérifié contre l'émulateur ; ce point de recette est sa confirmation sur le
      matériel réel. Si le dernier reste à « reste 1 m », noter le compte de ticks affiché et le
      contenu du JSON de course.*
- [ ] Les LED s'éteignent.
- [ ] Le CSV du jour contient `RACE_START`, deux `RIDER_FINISH`, deux `RACE_FINISH`.
- [ ] Les vitesses moyennes sont plausibles — un sprinteur sur rouleaux tourne entre 30 et 70 km/h.
      **Une pointe au-dessus de 90 km/h est un signal d'alarme**, pas une performance.

---

## 6. Perte de lien à chaud — le test qui compte

Relancer une course, et **débrancher l'USB en pleine course**.

- [ ] Le bandeau `LIEN PERDU` apparaît en **moins de 500 ms**.
- [ ] L'affichage se fige sur la dernière valeur connue, il ne revient pas à zéro.

Rebrancher dans les trois secondes.

- [ ] La reconnexion est automatique, sans manipulation.
- [ ] **La course reprend** — elle n'a pas été avortée.
      *Les valeurs de `R:` sont absolues : rien n'a été perdu (`docs/01` §3).*

Puis, sur une nouvelle course, débrancher et attendre **plus de cinq secondes**.

- [ ] La course est marquée `INTERROMPUE` et la ligne `LINK_LOST` figure dans le CSV.

> C'est le point que l'émulateur ne peut pas prouver : il ferme un pseudo-terminal, ce qui n'exerce
> pas le chemin `EIO` du pilote USB réel (`docs/07` §2).

---

## 7. Faux départ

Régler la politique sur **Avertissement**, lancer une course, et faire tourner un rouleau **pendant
le décompte**.

- [ ] `FAUX DEPART piste N` s'affiche.
- [ ] La course part quand même.
- [ ] La ligne `FALSE_START` figure dans le CSV.

Recommencer avec la politique **Relance** :

- [ ] La course est annulée immédiatement et revient au repos.

---

## 8. Les trois modes

- [ ] **Distance** — voir §5.
- [ ] **Temps**, 60 s : la course se termine à 60 s **par décision du PC**.
      *Le firmware, lui, ne terminera jamais : `docs/01` §5.5.*
- [ ] **Poursuite**, écart 50 m : la course se termine dès que l'écart est atteint, et le CSV porte
      `RIDER_ELIMINATED`.

---

## Clôture

- [ ] Le nombre de capteurs câblés est noté dans `tasks/todo.md`.
- [ ] Le VID/PID est dans l'allowlist et commité.
- [ ] Une vidéo ou une capture des points §5 et §6 est jointe à la preuve du jalon.
- [ ] `tasks/preuves/` contient un fichier `AAAA-MM-JJ-J1-materiel-reel.md`.

**Tant que le §6 n'est pas coché sur du matériel réel, J1 n'est pas franchi**, et le lot 4 (scène 3D)
reste fermé.
