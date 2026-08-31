# Prompt de démarrage — agent de développement

*(à copier-coller tel quel dans la session de l'agent, depuis `/home/antoine/Code/SilverSprint-v3`)*

---

Tu développes **SilverSprint v3**, une refonte complète d'un logiciel de course de rouleaux
(goldsprints) : deux à quatre cyclistes pédalent sur des rouleaux instrumentés, un boîtier Arduino
compte les tours et le logiciel affiche la course. Le matériel et le firmware existants sont
conservés à l'identique ; tout le logiciel PC est réécrit.

Le répertoire de travail est `/home/antoine/Code/SilverSprint-v3`. Il contient déjà les
spécifications complètes dans `docs/` et le suivi d'avancement dans `tasks/todo.md`.
**Il ne contient encore aucun code.**

## Avant toute action

Lis intégralement, dans l'ordre :

1. `docs/00-BRIEF.md` — brief d'entrée et décisions déjà prises
2. `docs/01-PROTOCOLE-HARDWARE.md` — **normatif**, le contrat série avec l'Arduino
3. `docs/02-MODES-DE-JEU.md` — **normatif**, les règles des trois modes de course
4. `docs/03-ARCHITECTURE.md` — stack, arborescence, flux de données
5. `docs/05-PLAN-EXECUTION.md` — les sept lots et leurs jalons
6. `docs/06-QUALITE-RISQUES.md` — règles de développement, tests, risques
7. `tasks/todo.md` et `tasks/lessons.md`

`docs/04-DIRECTION-ARTISTIQUE.md` ne te servira qu'au lot 4 : tu peux le survoler pour l'instant.

Deux dépôts servent de référence en **lecture seule** — ne les modifie sous aucun prétexte :
* `/home/antoine/Code/SilverSprint` — la v1 d'origine (C++/Cinder). Contient le **firmware Arduino**
  dans `apps/Arduino/ss_basic/ss_basic.ino` : c'est la source de vérité du matériel, à lire.
* `/home/antoine/Code/SilverSprint-v2` — un prototype abandonné (C++/SDL2/ImGui). Utile pour
  quelques concepts, mais son post-mortem est déjà intégré aux specs. N'en recopie pas le code.

## Les décisions sont prises, ne les rouvre pas

* Moteur **Godot 4.5**, GDScript, avec un module **GDExtension C++** pour le port série
* Firmware Arduino **conservé tel quel**, jamais modifié
* Direction artistique : vélodrome stylisé néon, low-poly, haute lisibilité
* 1 à 4 riders, configurables individuellement
* Deux fenêtres : opérateur + spectacle plein écran
* Simulateur de matériel intégré, obligatoire dès le lot 1
* Trois modes : distance, temps, poursuite

## Le point d'architecture à ne surtout pas rater

Le firmware **ne sait pas combien de riders sont actifs** : en mode distance, il attend que les
quatre pistes aient franchi la ligne pour terminer la course, donc avec deux riders **la course ne
se termine jamais**. C'est le bug d'usage majeur de la v1. Et il ne connaîtra jamais le mode
poursuite, puisqu'on ne le modifie pas.

Conséquence, qui structure tout le code : **le PC est autoritaire**. L'Arduino est traité comme un
simple capteur qui fournit un flux de ticks cumulés horodatés à 100 Hz, cadence le décompte et
pilote les LED physiques. Tout l'arbitrage — condition de fin, classement, élimination, écarts,
disqualification — est calculé sur le PC, qui envoie `s` au firmware quand *lui* décide que la
course est finie. Détails en `docs/01` §5.4.

## Règles de travail

* **La donnée avant le pixel.** Aucun travail de rendu 3D avant que le jalon J1 (lien série validé
  sur l'Arduino réel) et le jalon J2 (cœur métier vert) soient franchis. Le prototype v2 est mort
  exactement de cette erreur.
* **Avance lot par lot**, dans l'ordre de `docs/05`. Ne commence pas un lot avant que le jalon du
  précédent soit franchi.
* **Aucune case de `tasks/todo.md` cochée sans preuve** : sortie de test, capture d'écran, ou
  commande reproductible. Jamais « ça devrait marcher ».
* **`core/` ne dépend de rien** : ni scène Godot, ni port série, ni rendu. Il doit tourner et être
  testé en headless.
* **Un seul thread mute l'état.** Le thread série écrit dans un ring buffer, rien d'autre. Aucun
  appel à l'API Godot depuis ce thread — c'est la faute qui faisait planter la v1.
* **Tests d'abord** sur tout ce qui est logique métier ou parsing.
* Si une spec te paraît fausse ou incomplète, **corrige le document d'abord**, code ensuite.
  Les documents `01` et `02` sont normatifs : on ne s'en écarte pas silencieusement.
* Après chaque correction que je te fais, écris la leçon dans `tasks/lessons.md`.
* Si ça part de travers, arrête-toi et re-planifie plutôt que de forcer.
* Commits conventionnels, un commit par unité cohérente, en français ou en anglais mais de façon
  homogène sur tout le projet.

## Ce que je te demande pour cette session

Réalise les **lots 0, 1 et 2** de `docs/05-PLAN-EXECUTION.md`, en t'arrêtant à chaque jalon pour me
montrer la preuve avant d'enchaîner :

* **Lot 0** — fondations : dépôt git, projet Godot 4.5, arborescence, GUT, CI GitHub Actions sur
  les trois OS. Jalon J0 : les tests headless sortent en code 0 dans la CI.
* **Lot 1** — le lien série, le lot le plus risqué du projet, donc traité en premier : GDExtension
  C++, parseur de trames, ring buffer SPSC, handshake strict, watchdog, reconnexion, et le
  simulateur `link_sim.gd`. Jalon J1 : validation sur mon Arduino réel — je serai là pour brancher
  le matériel et tourner les rouleaux, prépare-moi un outil console qui affiche les ticks en direct.
* **Lot 2** — le cœur métier : conversions physiques, machine à états, les trois règles de course,
  filtrage des ticks aberrants, enregistrement CSV et JSON. Jalon J2 : la suite de tests headless
  est verte, et couvre notamment la course en distance à deux riders qui se termine — le bug
  historique de la v1.

Ne touche pas au rendu 3D pour l'instant. Le lot 3 (interface opérateur) et le lot 4 (scène 3D)
feront l'objet de sessions séparées.

## Trois questions à me poser avant de commencer

Elles sont listées dans `docs/06` §5. Pose-les-moi dès le début, ne les devine pas :

1. **Mode poursuite à trois ou quatre riders** : élimination progressive du dernier dès qu'il prend
   `G` mètres de retard sur le leader, ou bien « le premier qui met `G` à tous les autres gagne » ?
   La spec retient l'élimination progressive par défaut, mais c'est un choix de game design.
2. **Identifiant USB de mon boîtier** : je peux brancher l'Arduino et te donner la sortie de `lsusb`,
   pour que tu alimentes l'allowlist VID/PID de la sélection de port.
3. **Nombre de capteurs réellement câblés** sur mon boîtier : deux ou quatre ? Ça conditionne
   l'effort de test à quatre riders.

Commence par lire les documents, puis pose tes questions, puis propose-moi ton plan pour le lot 0
avant de créer le moindre fichier.
