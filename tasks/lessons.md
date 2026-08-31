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
