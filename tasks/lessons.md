# Leçons

À relire en début de chaque session. Une entrée par correction reçue, avec le motif sous-jacent.

## Héritées de l'analyse v1 / v2 (avant la première ligne de code)

* **La donnée avant le pixel.** La v2 a poli un affichage dont la source de données n'avait jamais
  été validée sur matériel réel. Rien de visuel ne commence avant J1 + J2.
* **Tester ce qui est risqué, pas ce qui est facile.** La v2 avait 7 tests sur un parseur pur et
  zéro sur le threading série. La couverture doit suivre le risque, pas la commodité.
* **Un état non atteignable est un bug.** La v2 dessinait un état `GO` que son moteur ne produisait
  jamais. Chaque état de la FSM doit être atteint par un test.
* **Un asset non référencé est une perte.** La v2 embarquait tout un jeu d'images jamais chargées :
  direction artistique changée en cours de route. Figer la DA avant de produire, supprimer l'orphelin.
* **Ne pas faire confiance à « le port est ouvert ».** La v1 autorisait le départ d'une course sur
  n'importe quel périphérique série. Seule la réponse `V:SS_v...` prouve qu'on parle au bon boîtier.
* **Documenter le protocole avant de le coder.** La v1 comme la v2 n'ont jamais écrit le contrat
  série ; il a fallu le reconstituer par lecture croisée du firmware et du driver.

## Session initiale (2026-08-31)

* **Vérifier la largeur des types avant de croire une spec reconstituée.** `docs/01` décrivait une
  « double détection » de fin de course en mode temps, PC et firmware. Elle n'existe pas :
  `raceLengthSecs * 1000` est une multiplication entre deux `int` 16 bits sur AVR, qui déborde dès
  33 secondes. Au défaut de 60 s, le firmware ne termine jamais. Une spec reconstituée par lecture
  décrit des *intentions* ; seule la relecture ligne à ligne, types compris, décrit le *comportement*.
  Trois erreurs de `01`/`02` venaient de la même cause. Motif : lire le code cible avec les règles
  d'arithmétique de sa plateforme, pas avec celles de sa machine de développement.
* **Émuler au niveau du transport, jamais au niveau du parseur.** Le mock de la v2 injectait des
  structures déjà parsées : il testait le code sans risque et laissait sans couverture l'ouverture
  de port, le threading, le découpage de flux, le handshake et le watchdog. `ss_emu` parle sur un
  vrai pseudo-terminal à 115200 bauds. Motif : un simulateur doit se brancher au point le plus bas
  possible, sinon il ne simule que ce qu'on maîtrise déjà.
* **Un émulateur ne corrige jamais sa cible.** `ss_emu` reproduit les bugs du firmware, débordements
  `int16` compris. Un émulateur qui assainit valide un code PC qui échouera sur le vrai matériel.
* **Nommer ce qu'une preuve ne prouve pas.** J1-ém est écrit dans `docs/05` comme explicitement
  insuffisant pour ouvrir le lot 4, et `docs/07` §2 liste ce que l'émulateur ne couvre pas. Sans ça,
  la tentation de cocher J1 sur une preuve d'émulateur est quasi certaine.
* **Le firmware avale silencieusement les octets qui suivent `l` ou `t`.** Neuf tests sont tombés
  d'un coup à la première exécution parce que j'écrivais `"x t600 g"` : l'espace et le `g` sont
  entrés dans le tampon numérique, la course n'a jamais démarré, et le firmware n'a émis *aucune*
  erreur. Le piège est réel, il touchera le driver PC comme il a touché le test. Corrigé dans
  `docs/01` §2 et couvert par un test dédié. Motif : quand une série de tests tombe d'un bloc,
  chercher la cause unique côté banc d'essai avant de soupçonner le code testé.
