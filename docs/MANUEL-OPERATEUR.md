# Manuel opérateur — SilverSprint v3

Court, volontairement. Tout ce qui concerne une panne est dans **`DEPANNAGE.md`** ; ce manuel
décrit le déroulé normal d'une soirée.

## 1. Avant la salle (la veille)

1. Lancer le logiciel une première fois sur la machine qui servira : il crée ses fichiers de
   réglages et son dossier de résultats (le chemin du CSV s'affiche dans le panneau **Résultats**).
2. Panneau **Fenêtre spectacle** : ouvrir la fenêtre, choisir l'écran du projecteur, cocher
   **Plein écran**. Le réglage est mémorisé.
   *Sous Wayland (Hyprland, Sway…), l'écran et le plein écran se règlent côté compositeur — le
   panneau le dit, la recette est dans `DEPANNAGE.md`.*
3. Panneau **Fenêtre spectacle**, section **Son** : le logiciel démarre **muet**. Activer le son
   seulement si la sono de la salle passe par cette machine, et régler le volume. Les deux sont
   mémorisés : le lancement suivant les retrouve.
4. Section **Qualité** du même panneau : le niveau est détecté au premier lancement. Le forcer si
   l'image saccade sur la machine du projecteur — le choix est mémorisé et ne sera plus remis en
   cause automatiquement.
5. Faire une course complète au **simulateur** (interrupteur dans le panneau **Matériel**) pour
   vérifier l'écran du public, le décompte, le podium.

## 2. Branchement du boîtier

1. Brancher l'Arduino en USB **avant** de lancer le logiciel, ou cliquer **Rafraîchir les ports**.
2. Panneau **Matériel** : le port apparaît avec le motif de sa retenue ou de son rejet. Basculer
   l'interrupteur **Simulateur** sur arrêt.
3. Attendre `Lien : IDENTIFIED` et la ligne **Firmware : SS_v0.1.7**. Tant que ce n'est pas le cas,
   le bouton START reste grisé, et son infobulle dit pourquoi.
4. **Test capteurs** : le boîtier ne lit ses capteurs qu'en course — le bouton en lance une, à
   blanc, que le logiciel n'arbitre pas. Attendre **~4 s** (son décompte), puis faire tourner chaque
   rouleau à la main. Chaque piste doit s'animer dans l'ordre attendu. Ré-appuyer pour arrêter. Une piste qui reste à zéro, ou qui bouge quand on tourne le rouleau d'à côté,
   c'est un câblage à reprendre **avant** la première course — pas pendant.
5. Débrancher puis rebrancher l'USB une fois : le bandeau **LIEN PERDU** doit apparaître en moins
   d'une seconde, puis disparaître à la reconnexion.

## 3. Calibration

* **Diamètre du rouleau (mm)** — mesurer la distance de l'aimant au centre du rouleau, puis
  doubler. Un tick = un tour de rouleau = une circonférence. Aucun rapport de transmission n'entre
  ici : le panneau affiche en direct la circonférence et le nombre de ticks pour 100 m, plus le
  repère qui compte dans le mode choisi — la distance de course en distance, l'écart décisif en
  poursuite, rien de plus en temps.
* **Développement (m / tour de manivelle)** — ne sert **qu'à** afficher la cadence sur l'écran
  public. Le capteur ne connaît pas le braquet ; 7 m est un développement de piste courant.
  Ni les distances, ni les temps, ni le classement n'en dépendent.

## 4. Une course

1. **Riders** : cocher les pistes actives, saisir noms et dossards. Les noms sont mémorisés. Le
   champ s'arrête à dix-huit caractères, la largeur que l'écran public peut montrer ; un nom plus
   long y serait de toute façon coupé.
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
5. **STOP** interrompt une course en cours ; **Relancer** l'interrompt et réarme la même
   configuration. Après une arrivée, il n'y a rien à interrompre : START comme Relancer lancent
   simplement la suivante, le podium reste à l'écran public jusqu'au décompte.
6. À l'arrivée : célébration, puis podium sur l'écran public. Le panneau **Résultats** montre le
   même classement, et la course entre dans **Courses du jour**. Le CSV est écrit au fil de l'eau.
   Cette liste survit à un redémarrage : elle est relue depuis les fichiers de course au lancement.
   Chaque ligne donne l'heure d'arrivée **en heure locale** (`21:47`), le mode et le vainqueur ;
   les fichiers, eux, sont horodatés en UTC.

Sous les boutons, le panneau **Course** tient un court journal : les cinq derniers messages, le plus
récent en tête, effacé au départ de la course suivante. C'est là qu'apparaissent les alertes — piste
muette, pointe suspecte, trames perdues, faux départ, lien perdu. Aucune ne peut plus être effacée
par la suivante.

## 5. Si ça coince

`DEPANNAGE.md`, dans cet ordre : START grisé → boîtier non détecté → ticks sur la mauvaise
piste → lien perdu → pas de son → mauvais écran. Et la dernière fiche, « Rien ne fonctionne et
le public attend » : le simulateur permet de faire courir les gens quand même.

## 6. Après

Fermer la fenêtre opérateur arrête proprement une course encore en cours : le boîtier reçoit son
ordre d'arrêt, la course est marquée **INTERROMPUE** et sa trace est écrite comme les autres. Sans
cela le boîtier resterait en course, LED allumées, et refuserait de repartir droit au lancement
suivant.


Le dossier des résultats contient un **CSV** (une ligne par événement, toutes courses de la
journée) et un **JSON par course** avec la trace complète des trames, rejouable. **Ouvrir le
dossier du CSV** dans le panneau Résultats y mène directement.
