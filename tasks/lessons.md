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
