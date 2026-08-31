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
* **Une reconnexion en cours de course ne rejoue pas le handshake complet.** Le `s` initial remet un
  boîtier inconnu dans un état connu ; rejoué après une coupure, il abat la course qu'on vient de
  récupérer. Découvert en exécutant le scénario `perte-lien` / `retour-lien` de `ss_emu`, pas en
  relisant la spec. Corrigé dans `docs/01` §4. Motif : un scénario de panne exécuté révèle des
  couplages qu'aucune relecture ne montre.
* **`t600` ne veut pas dire 600 secondes.** `600000 mod 65536 = 10176` : le firmware coupe la course
  à 10,2 s et arrête le flux `R:`. Toutes les valeurs qui débordent ne débordent pas vers l'infini —
  certaines tombent sur un entier positif court, ce qui est bien pire qu'un plafond inopérant.
  D'où la constante `t60`, vérifiée par test, imposée par `docs/01` §5.5. Motif : face à un
  débordement, ne jamais raisonner sur un cas ; balayer la plage.
* **Un test qui tombe en série accuse le banc d'essai, pas la cible.** Deux fois de suite, une salve
  d'échecs venait de mes tests (cadrage `x t600 g`, puis valeur `t600` elle-même), jamais du code
  émulé. Vérifier l'hypothèse du test avant de soupçonner l'implémentation.
* **Le maître d'un pseudo-terminal n'accepte pas `tcgetattr` sur macOS.** Linux le tolère, macOS
  répond `ENOTTY`. C'est l'esclave qui porte la discipline de ligne : c'est lui qu'il faut
  configurer, et cela marche sur les deux. Trouvé par la CI macOS, pas en local. Motif : une
  matrice trois OS dès le jalon J0 n'est pas un luxe ; elle a payé au premier commit natif.
* **Armer un watchdog au START, c'est le faire tomber pendant le décompte.** Le firmware n'émet
  aucun `R:` pendant les ~4 s de `CD:`. Le watchdog ne doit s'armer qu'à la première trame reçue
  *après* le START. Trouvé par le premier test d'intégration sur pseudo-terminal, qui n'a vu que
  deux trames `CD:` sur quatre — un test unitaire à port factice ne l'aurait pas montré.
* **Un compteur nommé « perdu » ne doit compter que ce qui est perdu.** Mon `push()` de ring buffer
  incrémentait `dropped()` à chaque tentative échouée, y compris quand l'appelant réessayait
  aussitôt. Affiché dans le panneau matériel, il aurait annoncé des milliers de pertes imaginaires.
  Séparé en `try_push()` (silencieux) et `push()` (comptabilise). Motif : un compteur exposé à
  l'utilisateur est une affirmation ; elle doit être vraie.
