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
* **Un filtre calibre sur une fenetre trop courte rejette le signal.** A 100 Hz, un tick de rouleau
  vaut 35,9 cm et une trame couvre 10 ms : un seul tick implique 129 km/h. Le controle de vitesse
  par trame etait donc structurellement incapable de distinguer un cycliste d'un rebond, et
  rejetait la totalite d'une course normale. `docs/01` §6.3 promettait ce qu'aucun filtre ne peut
  tenir ; la promesse a ete retiree plutot que maquillee. Motif : verifier qu'un seuil est
  atteignable AVEC la resolution reelle du capteur avant de l'ecrire dans une spec.
* **Deux evenements sur la meme trame, deux compteurs qui se marchent dessus.** A la fin d'une
  poursuite, l'elimination du dernier et l'arrivee du vainqueur arrivent ensemble. Un unique
  compteur de rang faisait sortir le dernier premier. Motif : quand deux flux d'evenements
  alimentent une meme numerotation, les separer explicitement plutot qu'ordonner au hasard.
* **`core/` ne journalise pas.** Un `push_warning` dans un module de `core/` impose un canal de
  sortie a du code qui doit rester utilisable en headless, en test et en rejeu — et fait echouer
  la suite GUT, qui compte les avertissements moteur. Le module rapporte, la couche applicative
  affiche. Meme raison pour `JSON.parse_string`, qui ecrit dans le journal du moteur : preferer
  `JSON.new().parse()` sur un cas d'erreur deja gere.
* **Godot ne déclenche `_ready` ni `_enter_tree` de façon synchrone depuis `SceneTree._initialize()`.**
  Un outil en ligne de commande bâtissait donc l'interface contre un contrôleur vide, et le panneau
  matériel affichait « aucun port détecté » sans rien signaler. Corrigé par une initialisation
  explicite et idempotente que la vue déclenche elle-même, plutôt qu'en insérant un `await` au bon
  endroit. Motif : quand un ordre d'appel est fragile, supprimer la dépendance à l'ordre, pas
  l'ajuster.
* **Une métrique affichée est une affirmation.** La « vitesse de pointe » était calculée sur la
  vitesse instantanée : un cycliste à 45 km/h ressortait à 117 km/h dans le CSV. Même cause que la
  tolérance du filtre de ticks — la quantification à 35,9 cm sur une fenêtre de 10 ms — vue d'un
  autre côté. Motif : toute grandeur dérivée d'un capteur doit être vérifiée contre une valeur
  attendue connue, pas seulement contre elle-même.

## Lot 4 — retours sur le rendu 3D (2026-08-31)

* **Un matériau émissif n'a pas d'ombrage : toute forme pleine devient un aplat.** Les cyclistes
  sortaient en « grosses patates » parce que le maillot était fortement émissif. Le vélo, lui, se
  lisait — parce qu'il est fait de traits fins, où la silhouette suffit. Correction : le corps est
  **éclairé** (deux lumières directionnelles, ambiante réduite) avec un simple liseré coloré ;
  l'émission est réservée aux jantes et aux lignes de piste. Motif : l'émission sert à *désigner*,
  la lumière sert à *donner du volume*. Les confondre aplatit tout.
* **`TorusMesh` a son axe sur Y : le tourner autour de Y ne fait rien.** Mes roues étaient couchées
  à plat sur la piste, ce qui explique à lui seul que rien ne ressemblait à un vélo. Il faut
  basculer autour de Z. Motif : vérifier l'orientation par défaut d'une primitive avant d'écrire
  une rotation « évidente » — et surtout, REGARDER le résultat.
* **Regarder le rendu fait partie du travail.** J'ai mesuré des fps et écrit des shaders pendant
  plusieurs étapes sans jamais ouvrir une capture. L'utilisateur, lui, a regardé, et a vu en trois
  secondes ce que je n'avais pas vu. `xvfb-run` permet de capturer sans ouvrir de fenêtre sur son
  bureau : il n'y a aucune excuse.
* **Une scène sans habillage n'est pas un affichage de course.** « On ne sait pas quelle distance il
  reste ni où on en est. » L'information — objectif, distance parcourue, distance restante,
  progression — est aussi indispensable que la piste elle-même, et elle était renvoyée au lot 5.
* **Une traînée plaquée au sol est invisible.** Vue à la hauteur de caméra de `docs/04` §4, elle se
  réduit à un trait. Un aileron vertical se lit. Motif : penser un effet dans le repère de la
  CAMÉRA, pas dans celui du monde.
* **`Engine.get_frames_per_second()` est lissé sur une seconde.** Calculer un centile dessus revient
  à faire des statistiques sur des valeurs répétées : j'ai failli rapporter un « 1 % bas » qui ne
  mesurait rien. Le fps se déduit du delta de chaque image.
* **Ne jamais laisser un script de correctifs échouer en silence.** Deux fois, un appel mal formé a
  fait que les shaders étaient écrits mais pas le code qui les utilise — et j'ai mesuré des fps sur
  une scène amputée de son post-traitement sans m'en apercevoir. Les patchs vérifient désormais leur
  ancrage ET leur nombre d'arguments.

## Lot 4 — écran scindé et fluidité (2026-09-01)

* **`gdlint` n'est pas un analyseur syntaxique Godot.** Il a validé `split_screen.gd` alors que le
  fichier contenait deux fonctions `resize` et refusait de se charger — écran gris au lancement.
  Toute modification de script passe désormais par
  `godot --headless --check-only --script <fichier>` avant d'être considérée comme écrite.
  Motif : un formateur vérifie la forme, pas la cohérence du programme.
* **Vérifier qu'une fonction n'existe pas avant de l'ajouter.** `resize` était déjà là — écrite par
  moi, plus tôt — mais n'était appelée par personne. Le vrai défaut n'était pas son absence mais son
  inutilisation.
* **Ancrer le monde sur le leader borne l'écart affichable.** La piste ne s'étendait qu'à un quart
  de segment derrière l'ancre : à 112 m d'écart les poursuivants pédalaient au-dessus du vide.
  L'ancre est passée au MILIEU du peloton, ce qui divise par deux l'étendue nécessaire et supprime
  le cas limite. Corollaire : tout le décor périodique doit alors s'étendre des DEUX côtés.
* **Une caméra qui vise un sujet ne le cadre pas pour autant.** Sa position en x restait déduite de
  la largeur de piste ; seule sa visée suivait le couloir. Un leader à droite se retrouvait donc au
  centre de l'image. C'est l'utilisateur qui a posé le bon diagnostic. Motif : distinguer *où est la
  caméra* de *ce qu'elle regarde*.
* **Convertir une position d'écran en angle exige le champ COURANT.** J'avais figé le demi-champ
  horizontal dans une constante alors que le champ s'ouvre avec la vitesse : le décadrage se
  trompait d'autant plus que la course allait vite. La conversion appartient à la caméra.
* **Scinder trop tard revient à ne pas scinder.** Le seuil était à 14 m quand la caméra ne sait
  cadrer que 13 m d'étalement : au moment de la coupe, le retardataire venait de sortir du champ.
  Un seuil de déclenchement doit précéder la limite qu'il protège, pas la suivre.
* **Le bruit d'un signal quantifié ne doit jamais piloter un effet de fond.** Les caméras des volets
  se calaient sans amortissement, si bien que la dérivée de la vitesse — mesurée en ticks — passait
  directement dans le champ et le roulis. D'où le scintillement. Champ et roulis s'amortissent
  désormais plus lentement que la position : ils ont le droit d'être en retard, pas de trembler.
* **Supprimer le bruit supprime aussi la sensation de vitesse ; il faut la remettre autrement.**
  Une fois le tremblement parti, l'allure s'est fadeuse. La réponse n'est pas de rendre le bruit
  mais d'ajouter une vibration DÉTERMINISTE — somme de sinusoïdes à fréquences premières entre
  elles, indexée sur la vitesse lissée. Une oscillation régulière se lit comme une caméra tenue ;
  un bruit se lit comme un défaut.
* **Lisser une valeur au rythme de sa source ne suffit pas.** La vitesse affichée était déjà moyennée
  sur une seconde côté moteur, et le dixième battait encore parce que le libellé était réécrit à
  chaque trame du boîtier. Le lissage d'affichage appartient à l'affichage, cadencé par l'écran.
* **Allouer en pleine action, c'est hoqueter au pire moment.** Les vues des volets étaient créées à
  leur ouverture : une cible de rendu 1080p et une compilation de shader exactement quand le peloton
  casse. Elles sont désormais réservées ET rendues une fois au montage.
* **Une lame qui naît au milieu doit sortir de sa voisine.** Quand un groupe de trois casse en 2+1,
  la cassure s'insère à GAUCHE des lames déjà ouvertes et tous les volets glissent d'un cran. Faire
  entrer la nouvelle lame depuis le bord droit laissait un coureur invisible le temps de la
  traversée. Elle démarre à la place de sa voisine, et les deux s'écartent — la lame se dédouble,
  ce qui raconte exactement ce que fait la course.
* **Mesurer la secousse en unités par seconde carrée ne veut rien dire à 170 fps.** La normalisation
  par `dt²` amplifie des écarts imperceptibles. Ce qui se voit, c'est la différence seconde PAR
  IMAGE, en unités brutes.
