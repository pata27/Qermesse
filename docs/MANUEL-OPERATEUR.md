# Manuel opérateur — SilverSprint v3

Court, volontairement. Tout ce qui concerne une panne est dans **`DEPANNAGE.md`** ; ce manuel
décrit le déroulé normal d'une soirée.

## 1. Avant la salle (la veille)

1. Lancer le logiciel une première fois sur la machine qui servira : il crée ses fichiers de
   réglages et son dossier de résultats (le chemin du CSV s'affiche dans le panneau **Résultats**,
   **avant même la première course** : c'est le journal où ira la prochaine).
2. Panneau **Fenêtre spectacle** : ouvrir la fenêtre, choisir l'écran du projecteur, cocher
   **Plein écran**. Le réglage est mémorisé.
   *Sous Wayland (Hyprland, Sway…), l'écran et le plein écran se règlent côté compositeur — le
   panneau le dit, la recette est dans `DEPANNAGE.md`.*
3. Panneau **Fenêtre spectacle**, section **Son** : le logiciel démarre **muet**. Activer le son
   seulement si la sono de la salle passe par cette machine. Le curseur **Volume** se règle
   **même son coupé** — c'est un réglage, pas une sortie : on le pose la veille dans une salle
   vide, sans rien faire entendre, et il s'applique le jour venu. Les deux sont mémorisés : le
   lancement suivant les retrouve.
4. Section **Qualité** du même panneau : le niveau est détecté au premier lancement. Le forcer si
   l'image saccade sur la machine du projecteur — le choix est mémorisé et ne sera plus remis en
   cause automatiquement.
5. Faire une course complète au **simulateur** (interrupteur dans le panneau **Matériel**) pour
   vérifier l'écran du public, le décompte, le podium.

## 2. Branchement du boîtier

1. Brancher l'Arduino en USB **avant** de lancer le logiciel, ou cliquer **Rafraîchir les ports**.
2. Panneau **Matériel** : le port apparaît avec le motif de sa retenue ou de son rejet. Basculer
   l'interrupteur **Simulateur** sur arrêt. Cet interrupteur est **grisé pendant une course** : le
   boîtier ne se change pas sous des gens qui pédalent — STOP d'abord.
3. Attendre `Lien : IDENTIFIED` et la ligne **Firmware : SS_v0.1.7**. Tant que ce n'est pas le cas,
   le bouton START reste grisé, et son infobulle dit pourquoi.
4. **Test capteurs** : le boîtier ne lit ses capteurs qu'en course — le bouton en lance une, à
   blanc, que le logiciel n'arbitre pas. Attendre **~4 s** (son décompte), puis faire tourner chaque
   rouleau à la main. Chaque piste doit s'animer dans l'ordre attendu. Ré-appuyer pour arrêter. Une piste qui reste à zéro, ou qui bouge quand on tourne le rouleau d'à côté,
   c'est un câblage à reprendre **avant** la première course — pas pendant.
   Le bouton dit toujours la vérité : il se **relâche de lui-même** si un START met fin au test ou
   si le lien tombe, et il est **grisé pendant une course** — le boîtier ne fait pas deux choses à
   la fois.
5. Débrancher puis rebrancher l'USB une fois. **Hors course**, ce n'est pas le bandeau rouge
   qu'on attend — il ne viendra pas : la ligne du panneau **Matériel** passe à
   `Lien : DISCONNECTED` en moins d'une seconde, le firmware redevient *inconnu* et START se
   grise. Au rebranchement, tout revient seul, sans rien cliquer. Le bandeau `LIEN PERDU`, lui,
   est un signal **de course** : il se vérifie une course lancée, `RECETTE.md` §6.

## 3. Calibration

* **Diamètre du rouleau (mm)** — mesurer la distance de l'aimant au centre du rouleau, puis
  doubler. Un tick = un tour de rouleau = une circonférence. Aucun rapport de transmission n'entre
  ici : le panneau affiche en direct la circonférence et le nombre de ticks pour 100 m, plus le
  repère qui compte dans le mode choisi — la distance de course en distance, l'écart décisif en
  poursuite, rien de plus en temps.
* **Développement (m/tour de manivelle)** — ne sert **qu'à** afficher la cadence sur l'écran
  public. Le capteur ne connaît pas le braquet ; 7 m est un développement de piste courant.
  Ni les distances, ni les temps, ni le classement n'en dépendent.

## 4. Une course

1. **Riders** : cocher les pistes actives, saisir noms et dossards. Les noms sont mémorisés. Le
   champ s'arrête à dix-huit caractères, la largeur que l'écran public peut montrer ; un nom plus
   long y serait de toute façon coupé.
   La **couleur** de chaque piste se règle à côté, et **l'écran public suit immédiatement** —
   maillot, jantes, traînée et néon de piste : on la choisit en regardant le vélo posé sur les
   rouleaux, jusqu'à ce que les deux correspondent. **Défaut** ramène à la couleur de charte, et
   ce bouton est grisé tant que la piste n'a pas été changée. Les couleurs sont mémorisées comme
   les noms. Si deux pistes actives finissent trop proches, le panneau le dit — il ne l'interdit
   pas : deux vélos rouges dans la salle, c'est vous qui avez raison, et le numéro de piste
   continue d'identifier chacun.
2. **Mode de course** :
   * **Distance** — premier à parcourir la distance ; tout le monde va au bout.
   * **Temps** — plus grande distance dans le temps imparti ; le classement est la distance.
   * **Poursuite** — le dernier est éliminé dès que son retard sur le premier atteint l'écart ;
     le survivant gagne. À l'écran, la barre se remplit vers celui qui mène, une barre par
     poursuivant.
     Deux **plafonds** bornent la poursuite — durée (défaut 300 s) et distance (défaut 5000 m) :
     atteint, celui qui mène gagne. L'écran public affiche « décision dans … » sous la barre.
3. **Faux départ** : choisir la politique. Ce que le public voit en dépend — *ignorer* ne montre
   rien et ne sonne pas (la ligne part quand même au journal), *avertir* affiche le bandeau rouge,
   *pénaliser* annonce la piste et son handicap, *relancer* arrête la course en affichant le motif.
4. **START**. Le décompte `3 · 2 · 1 · PARTEZ` est piloté par le boîtier : les LED et l'écran
   sont d'accord. Ne pas compter à haute voix sur une autre cadence.
   Pendant la course, **on peut préparer la suivante** — noms, pistes, mode, distance, pénalité :
   l'écran public continue de raconter la course en cours, avec sa configuration à elle, quoi qu'on
   change dans le panneau, et les lignes de pistes du panneau **Course** restent celles qui
   courent — décocher une piste ne la fait pas disparaître tant qu'elle pédale. Le nouveau réglage
   ne prend effet qu'au prochain START.
5. **STOP** interrompt une course en cours ; **Relancer** l'interrompt et réarme la même
   configuration — c'est le geste du faux départ qu'on refait tout de suite. Les deux ne sont
   proposés que tant qu'il y a quelque chose à interrompre : **après une arrivée, ils sont
   grisés**, et c'est START qui lance la suivante. Le podium reste à l'écran public jusqu'au
   décompte.
   *Attention : Relancer sur une course lancée écrit une ligne **INTERROMPUE** dans Courses du
   jour, avec sa trace — c'est un abandon suivi d'un départ. Relancer avant le `PARTEZ`, non :
   une course interrompue à l'armement ou au décompte n'a rien à raconter.*
6. À l'arrivée : célébration, puis podium sur l'écran public. Le panneau **Résultats** montre le
   même classement, et la course entre dans **Courses du jour**. Le CSV est écrit au fil de l'eau.
   **La dernière manche est en tête**, comme le journal des messages juste au-dessus : sur une
   soirée chargée, c'est presque toujours celle qu'on veut relire.
   Cette liste survit à un redémarrage : elle est relue depuis les fichiers de course au lancement.
   Le tableau est en chasse fixe : rangs, distances, temps et vitesses forment des colonnes, quels
   que soient les noms.
   Chaque ligne donne l'heure d'arrivée **en heure locale** (`21:47`), le mode et le vainqueur ;
   les fichiers, eux, sont horodatés en UTC.

Au-dessus, une ligne par piste en course — numéro, nom, distance, vitesse, puis `ARRIVÉ` ou
`ÉLIMINÉ` — en chasse fixe : les chiffres s'alignent en colonnes, quelle que soit la longueur des
noms, et l'œil compare deux pistes sans lire.

Sous les boutons, une ligne dit **où en est la course**, en toutes lettres :

| Ligne | Ce que ça veut dire |
|---|---|
| au repos — prêt à lancer | rien en cours ; START est disponible |
| armement — le boîtier doit répondre | les commandes sont parties, on attend le premier `CD:` |
| décompte | 3 · 2 · 1, piloté par le boîtier |
| course en cours | les coureurs roulent, l'arbitrage tourne |
| arrivée — classement figé | le PC a tranché, plus rien ne peut changer le résultat |
| résultat affiché — à acquitter | le podium est à l'écran public jusqu'au prochain départ |

Si quelque chose s'est mal passé **au lancement** — roster illisible, réglages perdus, course du
jour introuvable —, le panneau **Course** l'affiche en orange au-dessus du journal, et **cela y
reste**. Ce n'est pas l'alerte d'une course : c'est vrai tant que le fichier n'est pas réparé, et
ça ne s'efface donc pas au départ de la suivante.

Sous les boutons, le panneau **Course** tient un court journal : les cinq derniers messages, le plus
récent en tête, effacé au départ de la course suivante. C'est là qu'apparaissent les alertes — piste
muette, pointe suspecte, trames perdues, faux départ, lien perdu. Aucune ne peut plus être effacée
par la suivante.

## 4 bis. Entre deux manches — le mode démo

Panneau **Fenêtre spectacle** → **Mode démo (vitrine)**. Des coureurs synthétiques enchaînent des
manches tout seuls sur l'écran public : les trois modes, deux à quatre pistes, l'écran qui se
scinde, la caméra qui tourne autour du peloton. C'est ce qu'affiche une borne d'arcade quand
personne ne joue, et c'est fait pour la même raison — un projecteur figé pendant l'apéritif, et la
file se dissout.

Ce sont de **vraies courses**, arbitrées par le même moteur et **à vitesse réelle** : ce qu'on
montre est le produit, pas une animation à part. Une manche de 250 m dure donc une vingtaine de
secondes — c'est le temps qu'il faut à quelqu'un pour s'arrêter et regarder.

* **Rien n'est enregistré.** Ces courses n'entrent ni dans **Courses du jour**, ni dans le journal
  CSV, ni dans le dossier des courses. Elles n'ont pas eu lieu. À l'arrêt, le tableau **Résultats**
  revient à la dernière vraie course et le journal du panneau **Course** est vidé de ses lignes de
  démonstration : ce qu'il vous restait à lire est ce qui s'est passé pour de vrai.
* **Arrêter la vitrine en pleine manche n'est pas un incident** : l'écran public revient au repos,
  sans bandeau `COURSE INTERROMPUE` — ce bandeau est réservé aux vrais abandons, arrêt opérateur ou
  lien perdu, où le public doit savoir pourquoi la course s'arrête.
* **Les coureurs s'appellent Démo 1 à Démo 4**, sans dossard : ce sont des synthétiques, et l'écran
  ne doit pas couronner « Alice » pendant qu'Alice est au bar. Vos noms et dossards reviennent à
  l'arrêt, avec le reste.
* **Vos réglages sont rendus à l'arrêt** — mode, distance, durée, écart, pistes actives, profil du
  simulateur, et le choix simulateur/matériel. Lancez la vitrine pendant l'apéritif, arrêtez-la
  quand les coureurs arrivent, tout est comme vous l'aviez laissé.
* Tant que la vitrine tourne, **START, Relancer et Test capteurs sont grisés** — l'infobulle le
  dit. L'arrêter d'abord. Sans cela, une vraie course lancée entre deux manches partait
  enregistreur muet, comme une démonstration, et n'entrait pas dans **Courses du jour**.
* Le bouton est **grisé pendant une course** : on n'interrompt pas des gens qui pédalent. Il l'est
  aussi tant que la fenêtre spectacle est fermée — il n'y aurait rien à montrer. Et **fermer la
  fenêtre spectacle pendant la vitrine l'arrête**, pour la même raison ; vos réglages sont rendus
  comme après un arrêt au bouton.
* La vitrine bascule sur le **simulateur** le temps de tourner, même si le boîtier est branché : un
  vrai boîtier attendrait des ticks que personne ne produit.

## 5. Si ça coince

`DEPANNAGE.md`, dans cet ordre : START grisé → boîtier non détecté → ticks sur la mauvaise
piste → lien perdu → pas de son → mauvais écran. Et la dernière fiche, « Rien ne fonctionne et
le public attend » : le simulateur permet de faire courir les gens quand même.

## 6. Après

Fermer la fenêtre opérateur arrête proprement une course encore en cours : le boîtier reçoit son
ordre d'arrêt, la course est marquée **INTERROMPUE** et sa trace est écrite comme les autres. Un
**test capteurs** encore en cours reçoit le même ordre — c'est une course à blanc côté boîtier.
Sans cela le boîtier resterait en course, LED allumées, et refuserait de repartir droit au
lancement suivant.


Le dossier des résultats contient un **CSV** (une ligne par événement, toutes courses de la
journée) et un **JSON par course** avec la trace complète des trames, rejouable. Le panneau
Résultats affiche les deux chemins — celui du journal et celui de la course sélectionnée — et
**Ouvrir le dossier des résultats** y mène directement.

Une soirée qui passe minuit reste **une seule journée** : la bascule se fait à 5 h du matin. La
course de 00 h 20 va donc dans le fichier de la veille, avec le reste de sa soirée, et
**Courses du jour** ne se vide pas au douzième coup — même si le logiciel redémarre à 1 h.
