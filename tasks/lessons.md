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

## Lot 4 — mesure de performance et repère de la scène (2026-09-01)

* **Une mesure de performance prise pendant qu'autre chose tourne ne mesure rien.** J'ai lancé un
  banc en tâche de fond tout en faisant tourner d'autres instances de Godot, et j'en ai tiré des
  chiffres que j'ai présentés comme des faits : « les lignes de vitesse coûtent 15 ms ». Repris
  proprement, en alternant les configurations sur plusieurs tours, l'écart entre configurations
  (19,3 à 22,7 ms) s'est révélé PLUS PETIT que l'écart entre deux relevés d'une même configuration
  (17,0 à 32,7 ms). L'effet était du bruit. Règle : une seule chose tourne pendant une mesure, les
  configurations sont alternées, et on ne conclut pas tant que la dispersion intra-configuration
  n'est pas plus petite que l'écart cherché.
* **Deux relevés contradictoires ne se départagent pas au jugé.** `glow=0` seul donnait 16,3 ms et
  `glow=0,msaa=0` en donnait 5,3, alors que `msaa=0` seul ne changeait rien. C'est arithmétiquement
  impossible : c'était le signal qu'il fallait tout reprendre, pas choisir le chiffre qui arrangeait.
* **Réduire les appels de rendu n'accélère que si l'on est limité par eux.** Diviser par deux le
  nombre d'appels (495 → 225, en supprimant 96 projeteurs d'ombre sur 104) n'a rien changé au temps
  par image. À 76 triangles par appel, cette scène est limitée par le REMPLISSAGE. Le correctif reste
  bon — il supprime un coût réel sans toucher à l'image — mais il ne visait pas le bon goulot.
* **Faire pivoter une caméra pour décadrer, c'est regarder le sujet de biais.** Une projection
  décentrée (`Camera3D` en mode frustum) place le sujet où on veut à l'écran en le montrant DE FACE,
  et permet en prime de ne rendre que la tranche d'écran utile. C'est ce que fait un vrai écran
  scindé.
* **Vérifier le sens du repère plutôt que de le supposer.** La caméra regarde vers les Z croissants ;
  en repère droitier son axe « droite » est donc −X, et toute la piste était dessinée EN MIROIR
  depuis le premier jour — piste 1 à droite, piste 4 à gauche. Personne ne l'avait vu parce que rien
  dans l'image ne trahit un miroir tant qu'on ne connaît pas l'ordre attendu. C'est l'utilisateur qui
  l'a relevé.
* **Ordonner les volets par couloir était une fausse bonne idée.** L'utilisateur avait raison de
  signaler l'inversion, mais la corriger en rangeant les volets par couloir aggravait le cas où un
  paquet MÊLE des couloirs — aucun rangement ne préserve alors la place de tout le monde. L'ordre du
  classement, lui, est toujours le même. Motif : quand aucune règle ne satisfait tous les cas,
  choisir celle qui ne surprend jamais plutôt que celle qui est parfaite sur un exemple.
* **Ne pas confondre ce qu'une vue REND et ce qu'elle MONTRE.** Depuis que chaque volet déborde de sa
  bande pour couvrir l'inclinaison de la lame, sa largeur rendue (61 %) n'est plus sa part visible
  (33 %). Avoir passé la première au calcul de recul faisait cadrer trop serré et sortait du volet
  les coureurs les plus excentrés.
* **Terminer un câblage avant de lancer autre chose.** J'ai remplacé le décadrage par rotation dans
  la caméra sans finir de brancher son remplaçant, et l'utilisateur s'est retrouvé avec un cadrage
  cassé et plus aucun volet. Un changement d'interface se termine dans la même passe.
* **Un décor qui défile par modulo n'accepte que des objets PÉRIODIQUES.** Poteaux, poutres et
  marquages sont espacés de dix mètres exactement : décaler leur nœud de `-fposmod(ancre, 10)` les
  fait défiler sans que rien ne se voie, puisque le motif revient sur lui-même. Les spectateurs, eux,
  sont répartis au hasard : à chaque tour de modulo, la tribune entière se téléportait de dix
  mètres. Ils rebouclent désormais un par un dans leur shader, à l'extrémité du tronçon, hors de vue.
  Motif : le recyclage par modulo est une propriété du MOTIF, pas du nœud qui le porte.

## Lot 4 — fin de course (2026-09-01)

* **LA DERNIÈRE TRAME `R:` N'ARRIVE JAMAIS.** `ss_basic.ino` (`checkDistanceBased`, l. 285-307) met
  `raceStarted = false` dans la passe même où le dernier tick fait franchir la ligne, et l'émission
  périodique des `R:` est conditionnée par `raceStarted`. La valeur qui atteint la cible n'est donc
  jamais transmise. Le PC restait bloqué un tick en dessous et **la course ne se terminait pas** —
  « reste 1 m » indéfiniment. La règle « les trames `R:` portent un cumul absolu, donc en perdre une
  est sans conséquence » est vraie de toutes les trames SAUF la dernière. C'est l'émulateur, fidèle,
  qui a permis de le trouver avant la première course réelle. Trois tests de non-régression écrits.
* **Ne pas confondre « l'émulateur a un bug » et « l'émulateur reproduit un bug ».** Le réflexe était
  de corriger `link_sim`. La lecture du firmware réel a montré qu'il fait exactement pareil : le
  correctif appartenait au PC.
* **Un état figé volontairement doit être animé à l'affichage.** `RaceState.apply_sample` gèle un
  coureur arrivé pour ne pas fausser son résultat — c'est juste. Mais à l'écran, il s'arrêtait NET
  sur la ligne, à pleine vitesse. La roue libre est un effet d'affichage, et elle ne remonte jamais
  vers le moteur.
* **Un effet d'affichage ne doit pas nourrir une décision.** La roue libre creusait des écarts entre
  coureurs déjà arrivés — le premier ayant roulé plusieurs secondes de plus — et ces écarts
  rouvraient une scission en pleine célébration. Le regroupement se fait sur la donnée, pas sur
  l'habillage.
* **Une ancre qui suit un ensemble variable doit être amortie.** L'ancre du monde se pose au milieu
  de ceux qui courent encore ; dès qu'un coureur franchit la ligne il sort de ce calcul et le milieu
  recule de plusieurs mètres EN UNE IMAGE — tout le décor sautait au passage de la ligne.
* **Une rotation d'enfant s'ajoute à celle du parent.** Les bras sont enfants du buste : une valeur
  pensée comme absolue les envoyait à 200°, repliés en arrière. Seul le complément doit être appliqué.
* **Un système de particules compile ses shaders au PREMIER tir.** Déclenchée au franchissement, la
  gerbe de confettis provoquait un à-coup exactement au moment le plus chargé. Elle est désormais
  tirée une fois au montage, quarante mètres sous la piste.
* **Il n'existe pas de bonne distance pour un plan latéral sur cette piste.** La main courante est à
  4,9 m de l'axe et le groupe occupe déjà ±2,4 m : 6,5 m filmait à travers le rail, 1,8 m collait la
  caméra au premier coureur. Le plan d'arrivée est passé en trois quarts arrière surélevé.
* **Une hystérésis indexée sur un rang suppose que le rang désigne la même chose.** Les cassures se
  renumérotent dès qu'un coureur quitte le champ de course : comparer la cassure `i` à son état
  précédent gardait la scission ouverte sur un peloton pourtant regroupé.

## Lot 5 — deuxième fenêtre (2026-09-01)

* **Godot embarque les fenêtres filles PAR DÉFAUT.** Un nœud `Window` ajouté à l'arbre est dessiné
  À L'INTÉRIEUR de la fenêtre principale, comme un panneau flottant. La fenêtre spectacle était donc
  prisonnière de la fenêtre opérateur, et le second écran inatteignable — ce qui est toute sa raison
  d'être. Il faut `display/window/subwindows/embed_subwindows=false`. Vérifié par `is_embedded()`,
  pas à l'œil.
* **`own_world_3d` n'est pas facultatif pour une seconde fenêtre 3D.** Sans lui, elle partage le
  monde de la fenêtre opérateur, qui se met alors à afficher le vélodrome derrière ses panneaux.
* **Un halo qui mélange deux couches n'est pas une composition.** La lame de séparation écrivait
  `mix(vue, couleur_de_lame, halo)` avec une opacité de `halo` : à GAUCHE de la lame, où le volet ne
  doit rien afficher, elle peignait quand même deux tiers de l'image de l'autre volet. Les lignes de
  piste semblaient déborder d'un volet sur l'autre. La bonne formule EMPILE les couches —
  `lame·g + vue·other·(1−g) + fond·(1−g)(1−other)` — au lieu de les moyenner.
* **Ne pas appeler `get_tree()` dans un `_build`.** L'interface opérateur est construite avant
  d'entrer dans l'arbre ; `get_tree()` y journalise une erreur, qu'un test existant transforme en
  échec. La racine se passe en argument, elle ne se cherche pas.
* **Une fenêtre d'outil doit avoir la taille de son contenu.** Sans taille explicite ni drapeaux
  d'expansion, l'interface se tassait en haut à gauche d'un immense fond vide.

## Lot 5 — habillage et audio (2026-09-01)

* **`set_anchors_preset` ne suffit pas : il faut `set_anchors_and_offsets_preset`.** Le premier pose
  les ancres et LAISSE les marges d'origine. Un `Control` neuf ayant une taille nulle, le panneau
  opérateur gardait 109 pixels de large dans une fenêtre de 1261, et l'interface se réduisait à ses
  titres. C'est ce que signalait depuis le début l'avertissement « non-equal opposite anchors » de
  Godot, que j'avais laissé passer comme du bruit.
* **L'ordre de dessin d'un `CanvasLayer` suit l'ordre des enfants.** Le décompte plein écran,
  construit au montage, passait sous les cartes des coureurs, recréées à chaque armement. Un
  plein-écran appartient à sa propre couche : la question ne se pose alors plus jamais.
* **Un ralenti ne se fait pas avec `Engine.time_scale` quand deux fenêtres partagent le processus.**
  Il aurait engourdi l'interface opérateur sur l'autre écran. Le ralenti n'agit que sur le temps de
  la scène 3D.
* **Une barre signée dit deux fois plus qu'une barre positive.** De 0 à G, on ne lit que la taille de
  l'écart ; de −G à +G, on lit aussi de quel côté il penche — qui est la question du mode poursuite.
* **Afficher une grandeur qu'on ne mesure pas exige de déclarer d'où elle vient.** La cadence dépend
  du braquet, que le capteur ignore : elle est déduite d'un développement DÉCLARÉ par l'opérateur, et
  deux tests verrouillent le fait qu'aucun calcul de course n'en dépend.
* **Synthétiser le son plutôt que l'embarquer.** Aucun fichier audio, donc rien à télécharger, rien
  qui manque à l'export, et une synthèse qui se teste en headless sans carte son. Deux pièges :
  une boucle doit contenir un nombre ENTIER de périodes de chacun de ses partiels sous peine de
  claquer à chaque tour, et le bruit — qui n'a pas de période — se raccorde par fondu croisé.

## Boucle d'amélioration (2026-09-02)

* **Une case cochée sur une preuve absente vaut une case non cochée.** `tasks/preuves/j4-course.mp4`
  était cité par J4 et n'existait pas : la vidéo avait été rendue puis jamais encodée. Vérifier
  l'existence des fichiers cités fait partie de la vérification, pas de la relecture.
* **Un test de conformité doit comparer des scénarios ÉGAUX.** Le premier passage accusait
  `link_sim` d'émettre deux `V:` — c'est le test qui lui envoyait un `v` de trop : `ss_emu` sur
  `--stdio` est un firmware nu, `link_sim` intègre la poignée de main du pilote. J'avais conclu
  « bug du simulateur » avant d'avoir relu le firmware, qui ne dit jamais sa version de lui-même :
  la source de vérité se lit AVANT d'accuser une implémentation.
* **Une case restée décochée n'est pas toujours du travail restant.** Les quatre pannes exigées par
  `docs/03` §5 existaient avec leurs tests ; seule la case manquait. L'inventaire doit vérifier le
  code, pas se fier au suivi.
* **Une barre « tête moins queue » redescend quand la queue change.** À quatre coureurs, l'élimination
  du dernier refermait l'écart et faisait rebaisser la barre du premier, qui n'avait pas ralenti ;
  et les deuxième et troisième n'apparaissaient nulle part. La référence doit être le LEADER : une
  barre par poursuivant, longueur = retard sur lui. Une élimination retire une barre sans déplacer
  les autres. Vu par l'utilisateur, pas par moi.
* **Un affichage qui redit ce qu'un autre montre déjà ne fait que cacher la scène.** Les cartes en
  poursuite répétaient les couleurs de la barre. Coupées : l'écart, sujet du mode, a l'écran pour lui.
* **Vérifier un mode jusqu'au podium fait remonter des bugs de DONNÉES.** Le moteur ne mémorisait pas
  l'instant d'élimination ; la moyenne d'un éliminé se calculait sur toute la course alors que sa
  distance est figée — toujours trop basse. Le commentaire du code disait pourtant l'intention
  juste. Un test verrouille désormais que la moyenne s'arrête à l'élimination.
* **Ce que l'écran affirme, le CSV doit le porter aussi.** `temps_ms` valait 0 pour un éliminé.
* **Une correction faite dans une branche d'un `match` doit être cherchée dans les autres.** La
  caméra du mode peloton avait été corrigée pour se placer par rapport à son SUJET et non au centre
  de piste ; la branche poursuite, trois lignes plus bas, gardait l'ancien code. Dès que l'écran se
  scindait, le leader seul dans son volet — décalé de 2,4 m dans le couloir 1 — sortait du cadre et
  le volet de gauche était vide. Repéré sur capture, confirmé par l'utilisateur, reproduit avant
  d'être corrigé.

## Placement des fenêtres sous Wayland (2026-09-02)

* **Un essai qui réussit là où le pointeur était déjà ne prouve rien.** Trois « vérifications » de
  suite ont conclu que la règle Hyprland fonctionnait, alors qu'aucune règle n'était lue : la fenêtre
  s'ouvrait simplement sur l'écran du pointeur, qui était le bon. Un test de placement se fait avec
  la souris AILLEURS, lue avant le lancement. C'est l'utilisateur qui a vu que « ça dépend de là où
  est la souris », pas moi.
* **Poser un témoin avant d'accuser une syntaxe.** J'ai essayé quatre syntaxes de règle avant de
  vérifier si le fichier était seulement LU : un `border_size` témoin, sans effet, a tout tranché en
  une commande. Hyprland 0.56 avait ici un `configProvider: lua` — `hyprland.conf` était ignoré en
  silence, `hyprctl reload` disait `ok` et `configerrors` restait vide.
* **Sous Wayland, l'application ne choisit ni l'écran ni le plein écran.** Une requête plein écran
  X11 emporte la géométrie de l'écran que Godot croit être le sien — hérité de la fenêtre
  principale, donc de la souris au lancement — et le compositeur l'honore de préférence à sa règle.
  La carte des écrans vue par Godot à travers XWayland est en outre fausse quand un écran est pivoté.
  On s'abstient, on désactive les réglages dans le panneau, et la règle du compositeur fait les deux.
* **`pkill -f` avec un motif présent dans sa propre ligne de commande se tue lui-même.** Deux
  vérifications perdues. Arrêter par PID.
* **Ce que le scratchpad contient disparaît entre deux sessions.** Deux fois un script de lancement
  a manqué et l'application « n'avait pas de fenêtre ». Vérifier l'existence du script avant de
  conclure.

## Boucle d'amélioration, suite (2026-09-02)

* **Une insertion « au prochain motif » n'a pas de cible : elle a un hasard.** Pour ajouter un appel
  à la fin de `rebuild_cards`, j'ai cherché « le prochain `func` » — le texte a atterri à la fin de
  `_tick_podium`, où il ne s'exécutait qu'après un podium. Les cartes restaient à l'origine jusqu'à
  la première scission, et la suite de tests, qui ne teste pas les positions, est restée verte. Un
  patch s'ancre sur un texte UNIQUE du bon endroit, et un changement de disposition se vérifie à
  CHAQUE phase — le décompte a révélé ce que la course ne montrait pas.
* **Sous zsh, `set -- $variable` ne segmente pas.** Deux courses ont tourné avec des paramètres vides
  sans que rien ne le signale ; les images existaient, les journaux étaient propres. Écrire les
  boucles avec des arguments explicites, et vérifier que les noms de fichiers produits sont ceux
  attendus.
* **En mode scindé, l'habillage doit s'effacer.** Le volet du leader — le plus important — tenait
  tout entier sous la colonne de cartes. Une vérification « jusqu'au podium » sur 1 et 3 coureurs
  n'a rien trouvé côté données, mais a montré ça côté lisibilité.
* **Un renvoi vers une section qu'on n'a pas écrite se lit comme une preuve.** Trois commits citaient
  « `docs/01` §5.4 » pour la dernière trame `R:` jamais émise ; la section ne contenait pas ce que je
  lui faisais dire, et affirmait même le contraire (« `F:` jamais une condition »). Le document
  normatif se corrige AVANT le code — c'est la règle — et un renvoi se vérifie en ouvrant la section.
* **Godot n'est pas dans le PATH : `./.tools/Godot_v4.5-stable_linux.x86_64`.** Six minutes à
  chercher un binaire « disparu » alors qu'il n'a jamais été ailleurs. Une commande qui a marché dans
  une session précédente a marché avec un chemin ; le retrouver dans le journal avant de fouiller le
  disque.
* **« Du jour » veut dire persistant.** L'historique des courses du jour n'existait qu'en mémoire :
  un redémarrage en soirée le vidait alors que les JSON étaient sur disque. Quand un libellé nomme
  une portée (le jour, la session, l'événement), vérifier que la donnée survit vraiment à cette
  portée — et penser au fuseau : `started_at` est en UTC, le CSV est nommé en heure locale.
* **Une capture PNG par image fausse toute mesure de lissage.** Sauver chaque image ralentit la boucle,
  les deltas gonflent, et un filtre réglé pour 60 i/s paraît sauter. Valider un filtre d'affichage
  hors ligne, sur le signal exact décrit par l'utilisateur (ici : un tick de 0,3 m qui alterne à
  40 Hz entre deux coureurs), avant de conclure sur des captures.
* **Toute valeur brute à 100 Hz affichée telle quelle finit par stroboscoper.** Vitesse hier, écart
  aujourd'hui : même cause (quantum de tick), même recette (cible + lissage continu + hystérésis
  sur le chiffre). Chercher les autres étiquettes qui lisent `state` directement.
* **`git checkout -- fichier` jette TOUT le travail non commité du fichier.** Utilisé pour annuler un
  `sed` de preuve rouge, il a emporté la fonctionnalité entière avec. Pour défaire une mutation
  temporaire : la refaire à l'envers (`sed` inverse, `git stash push -- fichier` puis `pop`), jamais
  `checkout` tant qu'il reste du travail non commité dans le fichier.
* **Un scan « relis tout » qui marche à 60 fichiers est une bombe à retardement.** `load_day`
  parsait chaque JSON du dossier — 7,6 Mo après deux jours de développement, et le dossier ne
  s'élague jamais. Quand une donnée s'accumule sans borne, filtrer sur ce qui est gratuit (le nom)
  avant ce qui coûte (le parseur), et laisser un compteur observable pour le prouver.
* **Un test dont l'assertion tolère le bug vaut moins que pas de test.** « L'affichage n'anticipe
  pas de plus d'un tick » tolérait `vitesse × 1 s + un tick`, soit 12,9 m — écrit pour passer sur
  un `minf(x, x + borne)` qui ne bornait rien. Relire la borne d'un test contre la phrase de son
  nom : si le nombre ne correspond pas au mot, l'un des deux ment.
* **Un outil de preuve qui peut pendre n'est pas un outil de preuve.** Le démo 3D a tourné à vide
  deux minutes sur une scène qui ne se chargeait pas, jusqu'au `timeout` externe, sans un mot.
  Tout outil qui attend un événement porte un délai maximal de temps mur et un code de sortie
  distinct par cause d'échec — et on prouve les deux en les déclenchant.
* **Un test qui finit par `assert_not_null(_result)` n'a rien testé.** « Ex æquo départagé par la
  pointe » n'affirmait rien sur le classement, ses vitesses ne faisaient pas un ex æquo, et son
  second appel à `_run_race` repartait de zéro — chaque trame rejetée par le filtre, en silence.
  Trois défauts invisibles derrière un test vert. Un test se relit comme une phrase : sujet, verbe,
  nombre attendu.
* **Un accesseur « pour les tests » qu'aucun test n'appelle cache une fonctionnalité jamais exercée.**
  `sensor_button()` existait, personne ne l'appelait, et le bouton ne pouvait pas marcher sur le vrai
  boîtier — le firmware ne lit ses capteurs qu'en course. Le balayage du code mort a trouvé un
  bloqueur J1 sans matériel. Chaque accesseur de widget doit avoir son test, ou disparaître.
* **Un rendu qui produit ses images peut hurler des erreurs de script à chaque image.** Un `[]`
  littéral passé à un `Array[int]` échouait 60 fois par seconde après chaque arrivée, depuis des
  jours, invisible parce que mes greps ne cherchaient que « capture : ». Toute exécution d'un outil
  se termine par `grep -c "SCRIPT ERROR"` — et le chiffre attendu est zéro.
* **Commit après la suite complète, pas après le test ciblé — et la suite deux fois.** Un test qui
  laissait un dossier derrière lui passait seul et tombait au passage suivant ; je l'ai commité
  entre les deux. Un test qui écrit sur disque nettoie avant ET après, et la preuve d'idempotence
  est de lancer la suite deux fois de suite.
* **L'à-coup à l'ouverture d'une lame n'est pas le préchauffage — piste déjà creusée, ne pas la
  reprendre.** Trois à-coups reproductibles (25–35 ms) à l'ouverture des deux premières lames, jamais
  à la troisième. Écarté par la mesure : ce n'est pas l'allègement par volets (identique avec
  `_relieve_for_panes` neutralisé), ni une réallocation de cible (`_slice_width` ne dépend que de
  l'index). Chauffer les volets sur plusieurs images avec une caméra visée sur le peloton ne change
  rien non plus, et coûte du débit — essai annulé. Signature : ces images ne dessinent que 185
  primitives quand une image normale à quatre volets en dessine 414 en 8 ms. C'est un gel côté
  pilote, pas du travail. À reprendre avec un vrai profileur GPU, pas à l'intuition.
* **Un test qui nomme les champs un à un est toujours en retard d'un champ.** L'aller-retour des
  réglages en vérifiait six sur dix-sept : les onze autres, dont tous ceux ajoutés depuis, auraient
  pu disparaître de `to_dict` sans qu'un test bronche. Quand la garantie porte sur « tous les
  champs », énumérer par réflexion et comparer, pas énumérer à la main.
* **Une borne en caractères ne garantit aucune largeur.** Dix-huit lettres larges font 623 px là où
  la carte en offre 414 : mon estimation « une vingtaine de caractères » était fausse d'un facteur
  1,5, et le test écrit avec les vraies métriques de police l'a dit tout de suite. Ce qui doit tenir
  dans une place se borne en PIXELS ; la borne en caractères ne vaut que pour des colonnes de texte.
* **Réparer la source ne suffit pas : il faut chercher tous les lecteurs.** « Le résultat porte les
  noms du départ » a été corrigé trois fois, à trois tours différents — tableau opérateur, puis
  podium et bandeau spectacle, puis bandeau du panneau course — parce que chaque fois je m'étais
  arrêté au consommateur que j'avais sous les yeux. Après une correction de ce genre, faire le
  `grep` de l'ancienne source d'information sur tout le dépôt AVANT de refermer.
* **Le linter de la CI se lance en local, pas au push.** Soixante commits s'étaient accumulés avec
  treize violations de `gdlint` — la CI aurait été rouge dès la première tentative, et le diagnostic
  aurait porté sur du code écrit deux semaines plus tôt. Un tour de boucle qui touche du GDScript
  finit par `gdlint core hardware scenes tests tools audio`, au même titre que la suite de tests.
* **Un outil de preuve ne doit jamais écrire dans les données de l'utilisateur.** Les démos font de
  vraies courses, donc de vrais enregistrements : elles ont déposé 63 courses dans la liste
  « Courses du jour » de l'opérateur en une journée, et la CI en ajoutait à chaque exécution. Les
  réglages étaient protégés (`preferences_enabled = false`), pas le dossier des courses — la moitié
  d'un cloisonnement n'en est pas un. Vérifier ce qu'un outil écrit, pas seulement ce qu'il lit.
* **Un défaut lu dans le code n'est pas un défaut tant qu'on ne l'a pas provoqué.** J'ai cru qu'un
  `return` privait le repli sur simulateur de son `start()`, et j'ai « corrigé ». En provoquant
  vraiment le cas — bibliothèque native écartée — le lien restait IDENTIFIED : `Link._swap` garde le
  simulateur déjà en place, et mon correctif aurait relancé un lien vivant, qui serait repassé par
  PORT_OPEN à l'écran. Reproduire avant de corriger, même quand la lecture semble sans appel.
* **Un drapeau d'isolation doit isoler TOUT, sinon il rassure à tort.** `preferences_enabled = false`
  protégeait les réglages et le roster mais laissait le recorder viser les dossiers de l'opérateur :
  les démos y ont déposé 63 courses, et j'ai reproduit l'oubli dans deux fichiers de test. Corrigé une
  fois à l'appelant (les démos), il fallait le corriger à la source. Quand un drapeau porte une
  promesse, la tenir entièrement — ou la renommer pour ce qu'elle couvre vraiment.
* **Extraire un widget dans son propre fichier peut casser sa mise en page sans casser un test.**
  Le podium sorti de `race_hud.gd` gardait tous ses chiffres — les tests lisent son TEXTE — mais son
  voile passait à une taille nulle et le classement se tassait en haut à gauche : j'avais ajouté le
  nœud à l'arbre avant de le configurer, l'inverse de l'ordre d'origine. Toute extraction d'un
  élément visible se termine par une capture, pas seulement par une suite verte.
* **Un concept qui se calcule à cinq endroits finit par diverger aux cinq.** « Cette course a-t-elle
  été arrêtée, ou seulement décidée autrement ? » était réécrit à la main dans le podium, deux
  bandeaux, un tableau et le CSV — et n'était juste que dans un seul. Corrigé écran par écran trois
  fois avant que je pense à le NOMMER dans `RaceResult`. Quand une même question se repose ailleurs,
  lui donner un nom au lieu de recopier sa réponse.
* **Un tri sans départage attend une coïncidence pour devenir un bug.** Quatre tris comparaient sans
  cas d'égalité ; trois étaient inoffensifs, le quatrième téléportait le vainqueur 59 m en arrière —
  mais seulement en mode temps, où tous finissent au même instant, et seulement si l'ordre des
  couloirs différait de l'ordre d'arrivée. Mes captures utilisaient des profils où les deux
  coïncidaient. Chercher les tris sans `if égalité` vaut mieux qu'attendre la coïncidence.
* **Un outil de preuve qui accepte une valeur qu'il ne comprend pas fabrique une preuve fausse.**
  Quatre replis silencieux dans les démos : option inconnue ignorée, profil inconnu remplacé par
  `egaux`, qualité inconnue par `moyen`, mode inconnu par `distance`. Une faute de frappe suffisait
  à mesurer autre chose que ce que la commande annonçait — sans un mot, et sans moyen de le savoir
  après coup. Dans un outil qui produit des preuves, tout repli implicite est un mensonge en attente.

## Le document normatif peut avoir raison contre le code

`docs/07` §5 exigeait douze profils d'émulateur ; `ss_emu` n'en offrait que cinq. Les sept
manquants, ajoutés au lot 5 côté `link_sim.gd`, n'existaient donc que dans le simulateur qui
court-circuite la couche série : `ss_emu --profile eparpille` échouait, et ces scénarios
n'étaient **jamais** joués sur un vrai pseudo-terminal. Le test C++ verrouillait même le retard
avec `CHECK(profiles().size() == 5)`.

**Leçon** : la règle « corriger le document avant le code » suppose que l'écart vienne du
document. Il faut lire les deux dans les deux sens. Ici le document était juste et complet ; le
travail était de rattraper le code, puis d'ouvrir le garde-fou qui pétrifiait l'écart.

**Comment le retrouver** : quand deux implémentations doivent s'accorder, comparer leurs listes
plutôt que leurs comportements. `--list-profiles` contre les clés de `PROFILES` : douze contre
cinq se voit en une seconde, alors qu'aucun test ne s'en plaignait.

## Une définition juste peut trahir l'intention qu'elle sert

`docs/02` §5 exigeait qu'un redémarrage en pleine soirée ne vide pas l'historique, puis définissait
« le jour » comme le jour du calendrier. Les deux phrases se contredisaient sans que rien ne le
signale : une soirée de goldsprints passe minuit, donc un redémarrage à 00 h 30 vidait précisément
l'historique que la phrase précédente protégeait. Le CSV se scindait au même instant.

**Leçon** : quand une spec énonce une intention puis la définition qui doit la servir, vérifier que
la définition tient sur les cas du terrain, pas seulement sur le cas nominal. Ici l'intention était
« la soirée » et la définition disait « le calendrier » ; il a fallu nommer la journée
d'exploitation, qui bascule à 5 h.

**Comment le retrouver** : lire les horaires réels de l'usage. Un goldsprint court de 20 h à 1 h.
Toute frontière temporelle placée à minuit tombe donc au milieu de l'événement.

## Une capture montre ce qu'aucun test ne demandait

L'écran scindé fonctionnait, les cartes étaient compactées, les tests passaient. En regardant une
capture à quatre volets, l'évidence : les quatre cartes étaient empilées dans le premier volet.
Aucun test ne pouvait le dire — ils lisent du texte, pas des positions, et la spec ne parlait que
de la TAILLE des cartes en écran scindé, jamais de leur place.

**Leçon** : produire l'image et la regarder reste la seule façon de trouver ce que personne n'a
pensé à spécifier. Un rendu se relit avec les yeux ; le test vient après, pour le tenir.

**Et le premier correctif se regarde aussi** : posées dans leur volet, les cartes tenaient — sauf
la dernière, coupée par le bord de l'écran. La lame est inclinée, donc le dernier volet est plus
étroit en haut qu'en bas, là où vivent les cartes. La géométrie qui décide de la place doit être
celle qui est réellement dessinée, à la hauteur concernée — pas la position de repos de la lame.

## Le réglage coupable n'était pas celui que je soupçonnais

Le brouillard volumétrique laitait tout le vélodrome. Premier réflexe : diviser la densité par
trois. Le fond redevenait sombre — et la brume disparaissait complètement, effet payé pour rien.
La mesure a tranché : à albédo sombre, faire varier la densité de 0,004 à 0,012 déplace la
luminance du fond de 31 à 31,9. C'est l'ALBÉDO, blanche par défaut, qui renvoyait les projecteurs
de salle dans tout le volume. Seule l'émission était réglée, ce qui ne pouvait rien y faire.

**Leçon** : devant un rendu fautif, ne pas tourner le premier bouton venu jusqu'à ce que le
symptôme parte. Balayer chaque paramètre séparément et lire les chiffres : le bouton qui fait
disparaître le symptôme n'est pas forcément celui qui cause le problème, et on peut le tourner
jusqu'à supprimer l'effet entier.

**Et une propriété de l'image se garde dans l'image.** Aucun test unitaire ne pouvait voir ce
défaut. `ss_race3d_demo` mesure désormais la luminance du fond sur la capture et sort en erreur
au-delà du plafond que `docs/04` §4 chiffre. Vérifié dans les deux sens : 35,7 conforme avec le
correctif, 62,0 et code 4 en remettant l'albédo blanche.

## Un nom d'enum n'est pas un mot de l'interface

Le panneau Course affichait « Etat : IDLE ». Ces six mots — IDLE, ARMING, COUNTDOWN, RUNNING,
FINISHED, RESULTS — viennent du diagramme d'états de `docs/02` §1, qui est un document de
CONCEPTION. Ils n'apparaissent nulle part dans le manuel de l'opérateur : celui qui tient la souris
un soir de course n'avait aucune clé pour les lire. Deux messages d'erreur les recrachaient aussi.

**Leçon** : ce qui traverse la frontière du code vers l'écran doit être traduit une fois, dans une
fonction qui porte ce rôle. `state_name()` reste, pour les journaux et les outils de diagnostic qui
parlent la langue du diagramme ; `state_label()` est ce que lit l'opérateur, et la table du MANUEL
est la même.

**Comment le retrouver** : capturer l'interface et la LIRE comme un utilisateur qui n'a pas écrit
le code. Un mot en majuscules anglaises au milieu d'un panneau français se voit en une seconde,
alors qu'il ne fait échouer aucun test.

## `OptionButton.add_item(texte, -1)` ne range pas -1

Godot interprète un identifiant `-1` comme « prends l'index de l'entrée ». L'entrée
« automatique », posée en tête avec l'id `-1` — la valeur même du réglage —, recevait donc l'id 0,
c'est-à-dire « écran 1 » et « qualité basse ». Le sélecteur d'écran vivait avec ce défaut :
choisir « automatique » écrivait `show_window_screen = 0`. Le mode que le code recommande, parce
qu'il survit à un rebranchement, était inatteignable à la souris — et rien ne le signalait, puisque
l'entrée s'affichait bien et se sélectionnait bien.

**Leçon** : une valeur sentinelle du domaine métier n'est pas forcément une valeur licite pour le
widget qui la porte. Vérifier ce que l'API stocke réellement, par un essai de six lignes, plutôt
que de supposer qu'elle range ce qu'on lui donne.

**Comment il a été trouvé** : en implémentant la même entrée « automatique » pour la qualité. Mon
test échouait sur l'id ; en cherchant pourquoi, le sélecteur d'écran, en place depuis longtemps,
s'est révélé porteur du même défaut. Corriger un endroit oblige à regarder ses voisins.

## Une règle non outillée n'est pas une règle

`docs/06` §1 pose sept règles non négociables. La cinquième — « pas d'asset orphelin » — était la
seule qu'aucune machine ne vérifiait, et c'était la seule violée : `speed_lines.gdshader.uid`
traînait dans le dépôt depuis que ses lignes de vitesse ont été fondues dans `overlay.gdshader`.
Le `.gdshader` n'a même jamais été commité ; seul son `.uid` l'a été. Godot crée ces fichiers à
l'import et ne les efface jamais.

**Leçon** : devant une liste de règles, chercher d'abord celles que rien ne contrôle. Ce sont
celles-là qui ont dérivé. Une règle tenue à la main est tenue jusqu'au jour où on regarde ailleurs.

**Et une garde se prouve dans les deux sens.** J'ai fabriqué un `.uid` fantôme et un shader que
personne ne nomme : les deux tests échouent sur eux, puis repassent au vert une fois supprimés.
Un garde-fou qu'on n'a vu que vert ne prouve rien.

## Un état traversé n'est pas un état atteint

`docs/06` §1 règle 4 : « tout état de la FSM est atteint par au moins un test ». RESULTS l'était,
formellement — un test appelait `show_results()` puis `acknowledge_results()` l'un derrière
l'autre. L'application faisait exactement pareil, au départ de la course SUIVANTE : la FSM entrait
et sortait de RESULTS dans le même appel. Pendant toute la durée où le podium était à l'écran, le
moteur restait à FINISHED, et l'étape que le diagramme de `docs/02` §1 décrit — « résultat
consultable, en attente d'acquittement » — n'existait à aucun instant observable.

**Leçon** : pour un état où l'on est censé SÉJOURNER, la bonne assertion n'est pas « la transition
a eu lieu » mais « après tel événement, l'état COURANT est celui-là ». La première est satisfaite
par un passage instantané ; seule la seconde dit que l'état existe.

**Comment il a été trouvé** : en cherchant, parmi les sept règles non négociables, celles que rien
ne contrôle. La règle 4 était tenue pour le lien série (`test_link_sim.gd`) mais pas pour la FSM de
course — celle qui arbitre les classements.

## Un test qui n'a jamais été rouge ne prouve rien

J'ai écrit le test de marge APRÈS avoir posé le `MarginContainer` : il est passé du premier coup,
ce qui ne dit rien — il aurait pu mesurer la mauvaise chose et passer quand même. J'ai donc remis
la marge à zéro le temps d'un lancement : le test échoue en annonçant `0.0 attendu 20.0`, puis
repasse au vert une fois la constante rétablie.

**Leçon** : quand l'ordre s'inverse par accident et que le code arrive avant le test, ne pas se
contenter du vert. Neutraliser le correctif une fois suffit à savoir si le test regarde bien ce
qu'on croit. C'est la même vérification dans les deux sens que pour les garde-fous d'assets.

## L'orthographe de l'écran public est une question de rendu

L'écran spectacle mélangeait « éliminé » et « tous arrives », « ARRIVÉE » et « FAUX DEPART ». Rien
ne l'avait décidé : les chaînes suivaient l'époque du fichier qui les portait — `core/`, écrit tôt,
sans accents ; `scenes/race3d/`, écrit tard, avec. Le podium affichait les deux orthographes à
trois lignes d'écart.

**Leçon** : une incohérence de texte n'est pas un détail quand le texte fait soixante points sur un
mur devant un public. Elle se traite comme un défaut de rendu, avec la même règle écrite dans le
document de direction artistique et la même preuve par capture.

**Portée assumée** : le sweep s'arrête à l'écran spectacle et à ce qui l'alimente. La fenêtre
opérateur garde ses « Materiel » et « Resultats » — même dérive, autre surface, vue par une seule
personne, et un sweep plus large mérite son propre passage.

## Le reste du sweep, fait plutôt que promis

Le passage précédent s'était arrêté à l'écran spectacle en annonçant la fenêtre opérateur pour
plus tard. Celui-ci la termine : panneaux, messages d'erreur du moteur et du contrôleur, motifs de
validation, erreurs de fichiers, notes du CSV, et jusqu'à la chaîne C++ qui explique pourquoi un
port n'est pas retenu — `String::utf8` était déjà là, il n'y manquait que les accents.

**Leçon** : un sweep annoncé en deux temps doit avoir son second temps, sinon il laisse le projet
dans un état pire que les deux extrêmes — à moitié corrigé, sans règle lisible. La frontière, elle,
se décide et s'écrit : écran accentué, terminal ASCII, et un mot laissé tel quel parce qu'il doit
rester identique dans trois endroits.

## Un témoin de test peut mentir, et il faut le prouver aussi

En complétant `cue_counts`, j'ai remis les compteurs à zéro à l'entrée EN COURSE. La première
mesure a donc annoncé qu'aucun bip de décompte ni klaxon de départ n'avait sonné — alors que les
deux sonnaient très bien. Le décompte précède la course : je remettais le témoin à zéro juste après
qu'il eut noté ce qu'on voulait voir.

**Leçon** : un instrument neuf se calibre contre un cas connu avant de servir de preuve. Ici le cas
connu était « le décompte sonne » ; un témoin qui le nie accuse l'instrument, pas le produit.

**Et un dossier absent de la liste du linter est un dossier sans garde.** `audio/` ne figurait ni
dans le rituel ni dans la CI depuis sa création : une erreur d'ordre de définitions y dormait. Le
critère est simple — tout dossier de code du projet est dans la ligne `gdlint` ; seul `addons/`,
tiers et vendorisé, en est dehors.

## `$?` après un pipe ne mesure pas ce qu'on croit

En éprouvant les codes de sortie de `ss_replay`, j'ai lu `code=0` sur trois cas d'échec et j'ai
cru tenir un défaut grave : un outil qui imprime « DIVERGENT » et sort à zéro. C'était mon `$?`
qui rapportait l'état de `grep`, en bout de pipe, et non celui de Godot. Remesuré sans pipe, les
codes étaient corrects — 1 sur divergence, 2 sans rien à lire, 0 sur conformité.

**Leçon** : un code de sortie se mesure sur la commande elle-même, jamais derrière un `|`. Et
avant d'annoncer un défaut grave dans du code éprouvé, refaire la mesure autrement — c'est
l'instrument qui est le plus souvent en cause.

**Ce que l'épisode a quand même donné** : l'outil était sain, mais rien ne le gardait. La suite
exerçait `core/replay.gd`, pas la ligne de commande que `DEPANNAGE` promet à l'opérateur. Un test
en sous-processus et une étape de CI la tiennent désormais, verdicts et codes compris.

## Un événement que rien n'atteint révèle un chaînon manquant, pas un test manquant

`docs/02` §5 liste huit événements de CSV. Six étaient vérifiés, deux ne l'étaient par rien. En
cherchant à écrire le test de `FALSE_START`, la cause est apparue : la couture n'existait pas dans
`AppController`, et la façade `Link` ne relayait pas non plus `inject_false_start`, pourtant
présente dans `link_sim`. Le faux départ était donc **injouable depuis l'application** — d'où
l'absence de test, et d'où la case à cocher à la main dans `docs/RECETTE.md`.

**Leçon** : quand un comportement documenté n'a aucun test, se demander d'abord s'il est
seulement atteignable. L'absence de test est parfois le symptôme, pas la maladie.

**Corollaire sur la recette** : une case cochée à la main l'est parce que la machine ne peut pas
la tenir — ou parce que personne n'a essayé. Il faut savoir lequel des deux, et l'écrire à côté de
la case. Ici le test couvre le simulateur ; ce qu'il ne prouve pas, c'est que le vrai boîtier
émette `FS:`, et c'est ce qui reste à cocher.

## Corriger un cas, puis empêcher la classe

Le faux départ n'était pas jouable depuis l'application : la façade `Link` ne le relayait pas. Le
réflexe correct n'était pas de relayer ce cas-là et de passer à autre chose, mais de demander
combien d'autres lui ressemblaient. Réponse : `inject_corrupt_frame`, dans le même angle mort — la
trame corrompue est pourtant listée dans `docs/06` §2 parmi les pannes à éprouver.

**Leçon** : après avoir corrigé un chaînon manquant, énumérer mécaniquement les chaînons de même
forme. Ici trois listes — les `inject_*` du simulateur, les relais de la façade, les coutures
`simulate_*` du contrôleur — se comparent en dix lignes de réflexion, et le test qui les compare
vaut mieux que les deux correctifs qu'il rend inutiles à refaire.

**Et il se prouve en rouge** : en retirant le relais, le test annonce « `Link` doit relayer
`inject_corrupt_frame` » ; remis, il repasse au vert.

## Un réglage déclaré que rien ne lit est une promesse non tenue

`RenderQuality.PROFILES` portait un `msaa` par niveau — 0, 1, 2, qui sont exactement les valeurs de
`Viewport.MSAA_DISABLED / 2X / 4X`. Le tableau l'annonçait, `docs/04` §4 annonçait trois niveaux de
qualité, l'aide de la surcharge de diagnostic citait `msaa=0` en exemple — et aucune ligne ne
lisait la clé. Le niveau « bas », fait pour une machine faible, gardait l'anticrénelage, y compris
sur les trois viewports supplémentaires de l'écran scindé, là où le coût est.

**Leçon** : un dictionnaire de configuration se lit dans les deux sens. Chaque clé déclarée doit
avoir un lecteur, et c'est vérifiable par la machine — le test compare les clés du profil aux
`option("…")` présents dans les sources de la scène.

**Et il faut mesurer ce qu'on rétablit** : la première mesure comparait « bas » à « élevé », qui
diffèrent aussi par la foule, la brume et le halo — elle ne prouvait rien sur l'anticrénelage. La
surcharge `SS_QOPT=msaa=…`, prévue par le code pour isoler un effet à la fois, donne la vraie
comparaison : 1367 bords durs contre 1298, à niveau égal par ailleurs.

## Le même défaut de classe, deux étages plus bas

Après `msaa`, déclaré dans les profils de qualité et lu par personne, `speed_samples` : écrit dans
`settings.json`, borné à la relecture, et sans aucun lecteur. `docs/01` §7 le réclamait pourtant —
« paramètre exposé en réglage avancé ». Un opérateur pouvait l'éditer et ne rien voir changer.

**Leçon** : quand un défaut de classe apparaît une fois, il est rentable de le chercher à tous les
étages où la même forme existe. Ici trois dictionnaires de configuration — profils de qualité,
réglages persistés, et demain d'autres — se vérifient de la même façon : chaque clé déclarée doit
avoir un lecteur ailleurs, et une dizaine de lignes de test le tiennent.

**Et vérifier la prémisse du test avant d'accuser le code** : ma première version comparait quatre
échantillons à vingt sur quatre trames seulement. Les deux donnaient la même valeur, et c'était
juste — la moyenne divise par le nombre d'échantillons DÉJÀ vus, donc tant que la fenêtre n'est pas
pleine, sa taille ne change rien. Il fallait remplir, puis accélérer.

## Ce que le boîtier répond mérite d'être lu

Le firmware n'accuse réception que d'une seule commande : `l<ticks>`, par `L:<ticks>`. C'est la
seule chose qu'il dise de ce qu'il a compris — et l'accusé était reçu, parsé, puis jeté. Le
contrôleur traitait six trames sur onze ; celle-ci tombait dans le silence du `match`.

**Leçon** : dans un dialogue avec du matériel, chaque réponse est une preuve gratuite. En ignorer
une, c'est refuser de savoir. Et l'argument « le PC arbite de toute façon » se retourne : c'est
justement parce que le classement reste juste que l'écart doit être DIT — sinon les LED du boîtier
contrediront l'écran, et c'est le logiciel qu'on accusera.

**Encore un test faux avant un code faux** : le message dit « LONGUEUR », mon test cherchait
« longueur », et `String.contains` respecte la casse. Le mécanisme marchait déjà quand je le croyais
cassé — vérifié par une sonde de vingt lignes avant de toucher au code.

## Le silence d'un `match` ne distingue pas l'oubli du choix

Le contrôleur traitait six des onze sortes de trames. Les cinq autres tombaient dans le silence de
son `match`, sans qu'une ligne dise si c'était délibéré. L'accusé de longueur y dormait — un oubli.
`V:` et `M:` y dorment aussi — deux choix, l'une consommée par la couche lien, l'autre jamais
émise par la v3. Rien ne permettait de les distinguer.

**Leçon** : dans un aiguillage sur une énumération, nommer TOUS les cas, y compris ceux qu'on
ignore, avec la raison à côté. Le coût est de trois lignes ; le bénéfice est qu'un cas ajouté plus
tard ne peut plus disparaître sans bruit. Un test le tient : chaque valeur de l'énumération doit
apparaître dans la source de l'aiguillage.

**Compter plutôt que commenter** : les trames kiosque sont comptées et affichées au panneau
Matériel dès qu'il y en a, pas annoncées une par une. Une notice par trame noierait le journal si
le shield en émet en continu — et sur un boîtier ordinaire, une ligne « kiosque : 0 » serait du
bruit permanent.

## La limite de lignes se paie au moment où on la franchit

Remplir les cartes dès le décompte a fait passer `race_hud.gd` de 992 à 1008 lignes — huit de trop.
La tentation était de tasser mon propre ajout ; le fichier serait revenu cogner la limite au
correctif suivant. J'ai extrait `RaceTension` : tout ce qui ne s'affiche qu'en poursuite — le gros
chiffre d'écart, la barre signée, la jauge « décision dans » — soit 164 lignes, et le HUD retombe à
811 avec de la marge.

**Leçon** : quand un fichier franchit la limite, la découpe se fait sur un axe qui a du sens — ici
un MODE de course — et pas sur ce qui vient d'être ajouté. Le linter dit qu'il faut couper ; il ne
dit pas où.

**Et une extraction de `Control` se vérifie à l'image.** Les tests lisent du texte, pas des
positions : ils sont restés verts la fois où le podium extrait s'était empilé en haut à gauche,
faute d'avoir été dimensionné avant d'entrer dans l'arbre. Capture de poursuite à quatre coureurs
faite, barre signée et bornes en place.

## Ce qui est expliqué à l'opérateur doit l'être au public, pas l'inverse

Le tableau de résultats de l'opérateur légende sa marque depuis toujours : « x = éliminé à cet
instant ». Le podium projeté portait la même croix, nue. L'asymétrie était à l'envers de ce qu'elle
devrait être — l'écran public est vu par cent personnes qui n'ont pas le manuel, celui de
l'opérateur par une qui l'a.

**Leçon** : quand deux surfaces montrent la même donnée, comparer ce que chacune EXPLIQUE, pas
seulement ce que chacune affiche. Et la légende n'apparaît que si la marque est là : une légende
permanente serait du bruit sur une arrivée ordinaire, ce qu'un second test tient.

**Le piège d'accent, dans l'autre sens** : mon assertion cherchait « elimin » sans accent, sur un
écran que j'ai moi-même accentué il y a trois tours. La légende était bien présente ; c'est le test
qui la manquait. Une chaîne cherchée doit être copiée depuis la source, pas retapée.

## Un test peut se désarmer lui-même en citant ce qu'il cherche

La garde des constantes mortes compte les occurrences d'un nom dans tout le code. Sa propre
documentation citait `TARGET_FPS` et `REFRESH_S` en exemple — et ces deux noms suffisaient à les
faire passer pour lues. Le test passait au vert sur les défauts qu'il décrivait.

**Leçon** : un test qui compte des occurrences doit exclure les commentaires, et se relire en se
demandant si ses propres mots entrent dans son décompte. Corrigé en retirant les commentaires du
corpus avant de compter — ce qui est de toute façon la bonne définition : nommer une constante dans
une phrase ne la rend pas lue.

**Et une constante morte se traite au cas par cas, pas en lot** : sur cinq, deux méritaient d'être
branchées — `REFRESH_S` économise quatre-vingt kilo-octets de sortie, `TARGET_FPS` fait dire au
rapport de perf la cible qu'il juge — et trois n'avaient plus de raison d'être. Un sweep mécanique
les aurait toutes supprimées, en perdant deux intentions justes.

## Une fonction morte est parfois un test manquant

Douze accesseurs n'avaient aucun appelant. Le réflexe — les supprimer tous — aurait été faux pour
trois d'entre eux : `lane_text` donne la ligne par piste du panneau Course, `measured_m` permet de
comparer l'affichage à la mesure dans l'interpolateur, `gap_text` expose l'hystérésis du chiffre
d'écart. Trois comportements réels que rien n'éprouvait, et dont l'accesseur était précisément la
prise qui manquait pour les éprouver.

**Leçon** : devant une fonction sans appelant, demander d'abord ce qu'elle donne accès à. Si c'est
un comportement non testé, écrire le test plutôt que supprimer la prise. Les neuf autres faisaient
double emploi avec un accesseur voisin — celles-là partent.

**Et le test faux, encore une fois, avant le code faux** : j'ai d'abord écrit que « une variation
sous le pas ne réécrit rien ». C'est faux : l'hystérésis compare au dernier chiffre IMPRIMÉ, pas à
la dernière variation, si bien que de petites variations accumulées finissent par franchir le pas.
Le contrat réel est « à écart stable, plus une seule réécriture » — et c'est celui-là qui empêche
le scintillement.

## Une règle appliquée à l'affichage seulement n'est pas appliquée

`docs/02` §4 : « PÉNALITÉ — le rider fautif démarre avec un handicap de P mètres. » Le handicap
décalait sa position affichée, le décalait dans la scène 3D, et faisait annoncer au bandeau
« PISTE 2 PÉNALISÉE — DÉPART 10 m EN ARRIÈRE ». Mais la condition d'arrivée du mode distance
comparait des ticks BRUTS : le fautif franchissait la ligne au même compteur que les autres. Trois
manifestations visibles, aucune conséquence. Mesuré avant : 11 ms d'écart au lieu de 825.

**Leçon** : quand une règle a un effet visuel évident, il est facile de croire qu'elle est
implémentée — l'image la montre. Vérifier qu'elle touche aussi la DÉCISION, et pas seulement le
rendu. La question à se poser : « qu'est-ce que cela change au classement ? »

**Comment elle a été trouvée** : trois sondes visuelles de suite n'avaient rien donné — trois
coureurs, deuxième course, célébration, tout correct. J'ai arrêté de parcourir et j'ai choisi une
règle précise à éprouver de bout en bout, en mesurant son effet chiffré plutôt qu'en regardant si
« ça a l'air bon ».

## Un correctif juste ouvre parfois le cas dégénéré qu'il cachait

En rendant la pénalité de faux départ réellement coûteuse, j'ai éprouvé la même règle en poursuite.
Résultat : une pénalité de 10 m avec un écart décisif de 10 m élimine le fautif à la première
trame. Course finie en onze millisecondes, vainqueur à 0,0 m et 0,0 km/h — et surtout, une moyenne
de **−3272 km/h** pour le pénalisé, chiffre qui partait au podium public et au CSV.

**Leçon** : après avoir donné du mordant à une règle, chercher la combinaison où ce mordant devient
absurde. Ici deux défauts distincts sont sortis du même essai — une configuration injouable qu'il
faut refuser à l'armement, et un calcul de moyenne qui prenait une POSITION pour une distance
parcourue.

**Et le second valait mieux que le premier** : la moyenne négative n'a rien à voir avec la
poursuite. Un rider pénalisé en mode distance, éliminé ou arrêté avant d'avoir remonté son
handicap, aurait produit le même chiffre. Le cas dégénéré n'était que le révélateur.

## Un seuil absolu doit être confronté aux bornes de la configuration

La cloche annonce la fin imminente aux cinquante derniers mètres. La distance MINIMALE qu'accepte
la configuration est cinquante mètres : sur une telle course, la cloche sonnait sur la ligne de
départ. Même piège en mode temps — dix secondes d'annonce sur une durée minimale de dix secondes.
Le seuil était juste sur le cas nominal, absurde à la borne, et je l'avais écrit moi-même deux
tours plus tôt sans regarder les bornes que `validate()` autorise.

**Leçon** : tout seuil exprimé en unités absolues — mètres, secondes — doit être lu à côté des
bornes que la configuration accepte. La question tient en une phrase : « et si l'épreuve valait
exactement le seuil ? ». Le correctif est du même ordre : plafonner au dernier quart, ce qui
préserve les cinquante mètres sur une course de cinq cents et les ramène à douze sur une de
cinquante.

**Mesuré plutôt que raisonné** : cloche à 76 % du parcours sur 50 m et sur 100 m, à 90 % sur 500 m.
C'est ce tableau qui dit que le plafond fait ce qu'on veut, pas la relecture du code.

## Un guide de dépannage se lit dans les deux sens

Vérifier que chaque message promis par `DEPANNAGE.md` existe dans le code n'a rien donné : ils
existent tous. Le sens inverse, lui, a donné onze trous — des alertes que le logiciel affiche et
que le guide ne mentionne nulle part, dont « PISTE 2 : aucun tick depuis le départ », précisément
celle qu'on cherche quand un coureur ne démarre pas.

**Leçon** : la fidélité d'une documentation ne se mesure pas à ce qu'elle promet, mais à ce qu'elle
COUVRE. Un opérateur ne lit pas le guide en entier : il y cherche le message qu'il a sous les yeux.
Un message absent le laisse sans recours au pire moment.

**Tenu par la machine** : un test extrait les `notice.emit` du contrôleur et exige que chaque début
de message figure dans le guide. Il a aussi rattrapé un « boitier » sans accent que le balayage
d'accents avait manqué — le guide écrivait « boîtier », le code non, et la comparaison littérale l'a
vu.

## Un réglage n'est pas une sortie

Le curseur de volume était grisé tant que le son était coupé — et il l'est par défaut. `docs/04` §6
demande pourtant que la coupure ET le volume « se règlent la veille, une fois ». Pour préparer le
volume dans une salle vide, il fallait donc activer le son et faire du bruit : l'inverse exact du
besoin, et l'inverse exact de la consigne sous laquelle tout ce travail se fait.

**Leçon** : griser un contrôle parce que son effet n'est pas audible confond le RÉGLAGE et la
SORTIE. Un volume se pose à froid et s'applique quand on ouvre le son ; c'est d'ailleurs ce que
faisait déjà la couche audio, seule l'interface l'interdisait.

**Trouvé par la même méthode que le tour précédent, dans l'autre sens** : en comparant les
commandes du panneau au manuel, une seule manquait — « Volume ». En allant voir pourquoi elle
n'était pas décrite, le défaut d'usage est apparu derrière l'omission.

## Le fichier qui survit à la soirée doit se lire seul

L'écran public disait « photo-finish », le tableau de l'opérateur l'expliquait — et le CSV écrivait
deux temps identiques avec les rangs 1 et 2, sans un mot. Relu six mois plus tard, rien n'y
distinguait un ex aequo d'une coïncidence d'arrondi. Or c'est le seul des trois qui survit à la
soirée.

**Leçon** : quand une information est portée par trois surfaces, se demander laquelle est encore
là dans six mois. C'est celle-là qui doit être la plus explicite, pas la plus économe.

**Trouvé par accident, en vérifiant autre chose** : je mesurais le taux de remplissage des colonnes
du CSV — le `dossard` était vide, mais seulement parce que la démo n'en pose pas. En le vérifiant
avec un vrai dossard, la sortie a montré deux coureurs à 5016 ms exactement. C'est cette ligne-là,
pas ma question de départ, qui portait le défaut.

**Et le test s'est trompé avant le code** : la note contient une virgule, donc le champ est entouré
de guillemets. Mon découpage naïf sur les virgules la coupait en deux. Corrigé en lisant avec un
vrai parseur CSV — ce qui prouve du même coup que l'échappement fonctionne.

## Chercher un scénario spectaculaire quand un test simple suffit

J'ai voulu prouver que la trace enregistrée n'était pas brute en injectant une rafale de ticks
fantômes. Une heure de sondes pour rien : à la cadence du simulateur, l'injection ne déclenche
aucun rejet, et j'ai en chemin accusé le moteur de ne pas terminer une course — c'était un piège de
lambda GDScript, `done = true` écrivant dans une copie capturée par valeur.

Le contrat, lui, se vérifie sans mise en scène : **ce que la trace contient doit être, trame pour
trame, ce que le lien a livré**. Ce test-là est court, il ne dépend d'aucun timing, et il a montré
que deux trames par course étaient retouchées avant d'être écrites.

**Leçon** : quand une propriété se formule comme une égalité entre deux flux, la comparer
directement plutôt que de fabriquer l'anomalie qui la révélerait. La mise en scène coûte cher et
introduit ses propres défauts.

**Et un flag capturé par une lambda est une copie** : pour observer un signal depuis un test ou une
sonde, muter un tableau, jamais réaffecter un booléen local.

## Le document peut être en retard sur une décision déjà prise et expliquée

`docs/04` §2 donnait la piste pour une ardoise sombre. Le rendu emploie un bois clair depuis
longtemps, avec sa raison écrite juste à côté du code : une piste sombre sur fond anthracite
disparaît, et le vélodrome n'existe plus. La décision était prise, motivée, appliquée — et le
tableau de la palette ne l'avait jamais suivie.

**Leçon** : ce n'est pas toujours le code qui dérive. Une décision prise en cours de route et
justifiée dans un commentaire doit remonter dans le document, sinon le prochain qui lit la palette
« corrigera » le rendu vers une valeur abandonnée.

**Tenu par la machine** : un test compare les codes hexadécimaux du tableau aux couleurs employées
dans `core`, `scenes`, `audio` et `art`. Il a d'abord attrapé l'ancien code que j'avais cité dans
l'explication — utile rappel qu'une valeur abandonnée n'a pas à rester écrite, même en note
historique. Mesuré à l'écran : piste à 83 de luminance contre 29 pour le fond, le contraste que la
règle réclame.

## Le plan du dépôt est la première chose qu'on lit — et personne ne le relit

L'arbre de `docs/03` §2 omettait `tools/` en entier : vingt-six fichiers, dont les cinq outils de
preuve, dont trois que la CI lance à chaque poussée. Il dessinait en revanche `scenes/shared/`,
`tests/replay/` et quatre sous-dossiers de `art/` qui n'ont jamais reçu un fichier. Un plan faux
oriente moins bien que pas de plan : on cherche ce qui n'existe pas, on ignore ce qui existe.

**Leçon** : un arbre de fichiers dans un document se périme silencieusement, parce que rien ne
casse quand il ment. Il se vérifie comme le reste — chaque dossier dessiné doit exister ET contenir
quelque chose, chaque dossier de code doit y figurer.

**Le test s'est trompé deux fois avant d'être juste** : d'abord il reconstruisait mal les chemins
d'un arbre ASCII et accusait `rules/`, `operator/`, `race3d/` ; puis il exigeait des fichiers
DIRECTEMENT dans le dossier et accusait `art/`, qui n'a que des sous-dossiers. Une garde qui
accuse à tort se désarme d'elle-même, parce qu'on finit par la croire fausse.

## Un commentaire qui décrit une capacité ne la donne pas

`tools/ss_emu/CMakeLists.txt` s'ouvrait sur « se construit aussi bien seul que depuis la racine »,
et le README documentait la commande. Elle échouait : sans `cmake_minimum_required` ni `project()`,
CMake refuse de configurer un dossier pris comme racine. Le drapeau `SS_EMU_STANDALONE` existait
même déjà — l'intention était écrite deux fois, implémentée zéro.

Deuxième couche du même défaut : une fois la configuration réparée, `ctest` répondait « No tests
were found ». `add_test` n'a d'effet que si `enable_testing()` a été appelé au niveau racine, ce
que faisait le CMakeLists parent et personne d'autre.

**Leçon** : une capacité annoncée dans un commentaire ou un README se vérifie en la lançant. Ici
deux commandes de dix secondes suffisaient, et le chemin d'entrée du projet était cassé depuis
sa création.

**Mis sous garde** : la CI construit désormais l'émulateur seul et lance ses tests, exactement
comme le README le dit. Un chemin documenté que rien ne garde finit toujours par ne plus marcher.

## Le même défaut dans trois outils : ce n'est plus un défaut, c'est une habitude

`ss_monitor` repeignait sa ligne d'état à chaque image, `ss_probe.py` à chaque tour de boucle,
50 Hz — 57,6 Ko pour une sonde de vingt secondes. Deux outils écrits à des moments différents, dans
deux langages, avec la même faute : afficher une ligne vivante sans la limiter.

**Leçon** : quand un défaut réapparaît dans un troisième endroit, ce n'est plus une inattention, et
le corriger au cas par cas ne suffira pas. Le nommer — ici « une ligne d'état se repeint à 10 Hz,
jamais à la cadence de la boucle » — et vérifier les autres outils du même genre AVANT qu'ils ne
tombent dedans.

**Le vrai résultat de ce tour n'est pas le correctif** : c'est d'avoir lancé la répétition J1
complète, jamais exercée. L'émulateur sur un vrai pseudo-terminal, la sonde Python indépendante,
puis le moniteur Godot à travers le module natif. Les deux témoins, écrits séparément et dans deux
langages, annoncent les arrivées aux mêmes millisecondes : 7596 et 9897. C'est la preuve que la
chaîne série tient de bout en bout, sans matériel branché.

## La ligne la plus importante de la matrice était la seule sans automatisation

`docs/06` §2 décrit huit niveaux de test. Celui qui porte la mention « LA PARTIE RISQUEE » —
`ss_emu` sur pseudo-terminal, ouverture de port, handshake, threading, watchdog — était le seul
qu'aucun test n'exécutait. `test_conformite_emulateur.gd` pilote l'émulateur par `--stdio` pour
tourner partout, ce qui court-circuite précisément la couche que cette ligne désigne.

**Leçon** : une matrice de tests se relit en se demandant, pour chaque ligne, quel fichier
l'exécute. Celle qu'on a écrite avec le plus d'insistance n'est pas forcément celle qu'on a
outillée — l'insistance dans le document peut même compenser inconsciemment l'absence d'outil.

**Et le test avait tort avant le code** : ma première version tuait l'émulateur AU REPOS et
s'étonnait que le lien reste IDENTIFIED. Le watchdog n'est armé que pendant une course : hors
course, un port silencieux est normal, le boîtier n'émet des `R:` qu'en course. Le lien avait
raison. La version juste arme une vraie course, attend que les trames coulent, puis débranche.

## Ma propre garde accusait un rendu irréprochable

Le contrôle de luminance que j'avais ajouté était calé sur une seule mesure : une course de 250 m,
où la bande observée ne voit guère que le ciel — 35,9. Sur 100 m, la caméra cadre plus près, la
bande attrape les gradins éclairés, et la MÊME scène saine monte à 48, puis 55. La garde annonçait
« TROP CLAIR » sur un rendu parfait.

Déplacer la bande ne sauve rien : plus haut, les mêmes scènes donnent 46 à 65 contre 81 pour le
défaut recherché. C'est le cadrage qui domine, pas la brume.

**Leçon** : une grandeur absolue mesurée sur une image n'est comparable qu'à cadrage identique. Un
seuil photométrique doit donc nommer la scène sur laquelle il a été calibré, et se taire ailleurs —
imprimer la mesure sans conclure. Une garde qui accuse à tort finit ignorée, et alors elle ne
protège plus de rien.

**Vérifié dans les trois sens** : sur la scène de référence elle conclut et passe ; hors calibrage
elle imprime sans conclure ; et avec l'albédo blanche remise, elle attrape toujours son défaut à 62
contre 45.

## « Jamais vert par absence » l'était pourtant

Cinq tests se sautent quand leur décor manque — émulateur pas construit, module natif pas compilé,
Windows sans pseudo-terminal. Leurs commentaires promettaient tous « sauté explicitement, jamais
vert par absence ». Ils appelaient `pass_test()`, qui les compte comme RÉUSSIS. La suite annonçait
269 verts sur une machine où la couche série n'avait pas été touchée.

**Leçon** : l'intention écrite dans un commentaire ne remplace pas le mécanisme. GUT distingue
`pending` de `pass_test` et affiche une ligne `Risky/Pending` : c'était disponible, personne ne
s'en servait. Vérifié en cachant le binaire — « Passing 266, Risky/Pending 3 » au lieu de 269
verts, et le code de sortie reste 0, ce qui est juste : sous Windows le saut est légitime.

**Corollaire pour la recette** : la ligne `Risky/Pending` entre dans les vérifications d'avant
événement, et elle doit valoir zéro. Un test sauté n'est pas un test vert — c'est une couche qui
n'a pas été éprouvée, et le plus souvent la plus risquée.

## Huit cent vingt-neuf avertissements par exécution

`wait_frames` est un alias déprécié de `wait_physics_frames` : chaque appel imprimait sa ligne
d'avertissement, 829 par exécution de la suite. J'ai passé la nuit à filtrer autour pour lire les
échecs. C'est exactement le défaut déjà corrigé sur `ss_monitor` et `ss_probe` — une sortie trop
bavarde enterre le diagnostic — mais dans la suite de tests, là où je le voyais tous les jours sans
le traiter.

**Leçon** : le bruit qu'on contourne machinalement est celui qu'on ne voit plus. Quand on
s'aperçoit qu'on grep systématiquement autour d'une sortie, c'est la sortie qu'il faut corriger,
pas le grep.

**Le renommage était sans risque** : l'alias déprécié appelle littéralement la fonction qui le
remplace. Vérifié malgré tout par deux exécutions complètes, et une garde empêche le retour.

**Un chiffre à connaître** : la suite passe de 41 à 63 secondes selon que l'émulateur est construit
ou non. Ces vingt-deux secondes sont le prix des deux tests sur pseudo-terminal — la couche la plus
risquée. C'est cher et c'est justifié ; il fallait le mesurer pour pouvoir le dire.

## Une formule qui « oscille » n'oscille pas forcément autour de zéro

Le roulis du coureur valait `sin(angle) * 0.5 + 0.5`, multiplié par l'inclinaison maximale. La
formule a l'air d'un balancement — elle est périodique, elle suit le pédalier — mais son image est
[0, 1] : le vélo penchait d'un seul côté puis revenait droit, comme un métronome bloqué. Le
`* 0.5 + 0.5` est l'idiome pour ramener un sinus dans [0, 1] ; il n'avait rien à faire là.

**Leçon** : quand une formule périodique pilote un mouvement symétrique, vérifier son SIGNE, pas
seulement sa périodicité. Le test le dit en une ligne — le minimum doit être négatif, le maximum
positif, et les deux symétriques.

**Et le document parlait d'autre chose** : « inclinaison en virage », alors que des rouleaux n'ont
pas de virage. Le code visait le bon geste — le balancement du sprinteur en danseuse — et le
document était resté sur un modèle mental de vélodrome. Deuxième fois cette nuit que la direction
artistique est en retard sur une décision de rendu déjà prise.

## Le témoin croisé n'était surveillé par personne

`ss_probe.py` est la sonde indépendante du jalon J1 : aucun code commun avec l'émulateur ni avec le
module natif, c'est ce qui lui permet d'arbitrer entre deux implémentations. La CI ne la touchait
pas — pas même un `py_compile`. Elle pouvait cesser de fonctionner sans que rien ne le dise,
jusqu'au jour où l'on en aurait eu besoin pour trancher.

Elle sortait par ailleurs à zéro quand la course qu'elle arme ne produit aucune arrivée — boîtier
muet, mauvais port, firmware différent : exactement les symptômes qu'on vient chercher. Elle
annonçait donc « OK » sur le chemin cassé qu'elle est censée détecter.

**Leçon** : un témoin doit être surveillé comme le reste, et il doit échouer sur ce qu'il est
chargé de voir. La règle vaut trois fois cette nuit — `ss_replay`, `ss_race3d_demo --mesure`, et
maintenant `ss_probe.py`.

**Séquence CI rejouée en entier localement** avant tout cela, puisque je l'avais modifiée trois
fois sans jamais la lancer : lint, C++ racine, émulateur seul, import, suite GUT, module chargé,
rejeu des traces, course complète. Onze étapes, toutes vertes.

## Le moment le plus important n'était capturé par aucune preuve

Le jeu de captures couvre neuf instants — décompte, départ, lancée, pleine course, premier,
arrivée, célébration, regroupement, podium. Aucun ne montrait le **signal de départ** : `depart`
est pris trois secondes après, quand le chrono a déjà remplacé le mot. Le « PARTEZ ! » plein écran,
celui que les coureurs attendent et que les LED du boîtier doivent accompagner, n'avait jamais été
vu en image.

**Leçon** : un jeu de preuves se relit en se demandant ce qu'il ne montre PAS. Les instants
manquants sont souvent les plus brefs — et la brièveté n'a rien à voir avec l'importance. Vérifié
au passage que le mot n'est pas rogné : 72 px de marge à gauche, 61 à droite.

**Troisième dérive de `docs/04` cette nuit** : le document annonçait `3 / 2 / 1 / GO`, l'écran dit
`PARTEZ !`. Après la couleur de la piste et le roulis en danseuse. J'ai regardé s'il valait la
peine d'outiller cette classe : non — la section cite aussi `500 m` et `CD:`, des exemples de
format, et une garde qui les confondrait avec des littéraux d'écran accuserait à tort. Renoncer à
une garde est parfois la bonne décision, à condition de dire pourquoi.
