# 04 — Direction artistique et UX

## 1. Parti pris : vélodrome stylisé néon

Piste de vélodrome inclinée, éclairage néon, foule stylisée, effets de vitesse marqués.
Géométrie low-poly, lisibilité maximale, production réaliste pour une petite équipe.

**Ce n'est pas un choix par défaut, c'est un choix de lisibilité.** Le logiciel est projeté devant
un public à plusieurs mètres, souvent dans une salle mal éclairée. Un rendu photoréaliste serait
moins lisible qu'un rendu à fort contraste et silhouettes franches — en plus de coûter dix fois plus cher.

> **Leçon de la v2, à ne pas répéter.** La v2 contenait un jeu complet d'assets bitmap
> (`opensprintsLogo.png`, `dial_bg_*.png`, `cd_01..cd_go.png`, `finishFlag.png`, `WinnerModal.png`)
> **jamais référencés dans le code** : la direction visuelle a changé en cours de route et le travail
> a été perdu. En v3, **la direction artistique est figée par ce document avant la première ligne
> de code de rendu**, et tout asset non utilisé est supprimé du dépôt.

---

## 2. Palette

| Rôle | Couleur | Usage |
|---|---|---|
| Rider 1 | cyan `#00E5FF` | maillot, néon de piste, traînée, jauges |
| Rider 2 | magenta `#FF2E88` | idem |
| Rider 3 | ambre `#FFB300` | idem |
| Rider 4 | vert `#00E676` | idem |
| Fond | anthracite `#0B0E14` | |
| Piste | ardoise `#161B26` | |
| Accent / typo | blanc cassé `#F2F5FA` | |
| Alerte | rouge `#FF3B30` | faux départ, perte de lien, seuil de poursuite |

Chaque rider est identifié par **couleur + numéro de piste + nom**, jamais par la couleur seule
(daltonisme, projecteur qui délave les teintes).

## 3. Typographie

Une graisse condensée à fort caractère pour les chiffres géants (chrono, écart, vitesse) et une
grotesque neutre pour le reste. Chiffres **tabulaires obligatoires** : sans ça, le chrono et les
compteurs de vitesse « dansent » à chaque changement de chiffre, ce qui est très visible en projection.
Polices libres, embarquées dans le dépôt, licence vérifiée et notée dans `art/FONTS.md`.

## 4. Scène 3D

**Composition.** Vue 3/4 arrière légèrement surélevée, deux à quatre couloirs parallèles sur une
piste inclinée. Ligne d'arrivée matérialisée et visible à l'approche en mode distance.

**Caméra.** Un rig unique avec des comportements par mode :
* *distance / temps* — suit le leader, cadre l'ensemble du peloton, léger dutch angle à haute vitesse ;
* *poursuite* — cadre l'écart : elle recule et s'élève quand il se creuse, se resserre quand ça se recolle ;
* *photo-finish* — ralenti automatique et plan latéral sur la ligne quand l'écart à l'arrivée est
  inférieur à 1 m. C'est le moment qui fait crier une salle, il mérite un traitement dédié.
  L'écart est celui **des deux premiers encore en course** : un troisième loin derrière ne
  l'annule pas, et un coureur qui arrive seul — le seul de la course, ou le dernier après les
  autres — n'a pas de photo-finish.

**Riders.** Modèle unique de cycliste, cadence de pédalage indexée sur la vitesse réelle, inclinaison
en virage, maillot coloré par instance. Un seul modèle, quatre matériaux : le coût d'assets reste minimal.

**Effets de vitesse.** Ce sont eux qui portent la sensation, pas la géométrie :
* traînée lumineuse derrière chaque rider, longueur et intensité proportionnelles à la vitesse ;
* lignes de vitesse et flou radial en périphérie au-delà d'un seuil ;
* légère variation de FOV avec l'accélération ;
* bandes de néon au sol qui défilent, cadence indexée sur la vitesse.

**Environnement.** Tribunes low-poly, foule en *billboards* animés instanciés, réaction à
l'accélération et au franchissement de ligne. Volumétrique léger, bloom, vignettage.

**Budget de performance.** 60 fps stables en 1080p sur un GPU intégré Intel Iris Xe ou équivalent.
C'est la machine réelle d'un événement, pas une station de jeu. Toute fonctionnalité visuelle qui
fait passer sous 60 fps est coupée ou dégradée. Trois niveaux de qualité (`bas / moyen / élevé`),
détection automatique au premier lancement, réglage manuel possible.
La composition est pensée en 1080p, mais **la 3D ne se rend jamais plus fin que le projecteur** :
sur un 720p elle se rend en 720p — 2,25× moins de pixels — et l'habillage reste composé en 1080p.
Au-delà de 1080p, le rendu reste en 1080p, mis à l'échelle : c'est le budget, pas le projecteur, qui
fixe le plafond.

## 5. Habillage à l'écran (fenêtre spectacle)

* **Bandeau haut** — mode de course, objectif (`500 m` / `60 s` / `écart 50 m`), chrono en chiffres géants.
  Écran scindé : bandeau, chrono et titres réduits d'un peu moins de moitié, comme les cartes — à
  pleine taille ils mangeaient le haut de chaque volet.
* **Par rider** — nom, numéro de piste, vitesse instantanée en km/h, distance parcourue, cadence.
* **Poursuite** — l'écart occupe le centre de l'écran, avec la barre de tension entre `−G` et `+G`.
* **Décompte** — plein écran, `3 / 2 / 1 / GO`, synchronisé sur les trames `CD:` du firmware
  (jamais sur une horloge PC : les LED physiques et l'écran doivent être d'accord).
* **Arrivée** — ralenti, podium, temps, vitesse moyenne et vitesse de pointe par rider. Un rider
  arrivé ne s'arrête pas : il décélère vers une allure de croisière et continue de rouler sous la
  célébration et le podium — le sol défile. Une fois tout le monde arrivé, les suivants accélèrent
  pour revenir se placer derrière le premier, dans l'ordre d'arrivée, à quelques mètres — jamais
  devant lui — et la caméra retrouve tout le monde dans un seul cadre ; si l'écran était scindé au
  gong du mode temps, les volets se referment en les voyant se rapprocher.

## 6. Audio

* Nappe de fond dont l'intensité suit la vitesse du leader et, en poursuite, l'écart normalisé.
* Bips de décompte, klaxon de départ, cloche du dernier tour / des derniers 50 m.
* Réactions de foule sur les dépassements, les accélérations et le franchissement.
* Souffle de vent indexé sur la vitesse.
* **Coupure audio globale d'un bouton** : en événementiel, la sono est souvent gérée séparément
  et un logiciel qui sonne par-dessus la musique est un problème. **La coupure ET le volume sont
  persistés** : ils se règlent la veille, une fois, et sont réappliqués au lancement suivant.
