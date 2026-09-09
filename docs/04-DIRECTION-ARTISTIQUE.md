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
| Piste | bois clair `#6B5138` | **Nettement plus clair qu'il n'y paraît à l'écrit.** La première rédaction annonçait une ardoise sombre : sur fond anthracite, la piste disparaissait et le vélodrome n'existait plus. Une piste éclairée par des projecteurs de salle est CLAIRE, et c'est ce contraste avec le fond qui la fait exister |
| Accent / typo | blanc cassé `#F2F5FA` | |
| Alerte | rouge `#FF3B30` | faux départ, perte de lien, seuil de poursuite |

Chaque rider est identifié par **couleur + numéro de piste + nom**, jamais par la couleur seule
(daltonisme, projecteur qui délave les teintes).

### La palette de pistes est un DÉFAUT, pas une contrainte

Ces quatre teintes sont celles qu'on obtient sans rien régler, et elles restent le bon choix quand
rien ne s'y oppose : quatre couleurs franches, distinctes même sur un projecteur pâle.

Mais l'écran public est en face de vélos réels, posés sur des rouleaux, et **c'est le vélo qui a
raison**. Un spectateur qui cherche « le rouge » regarde la salle, pas la charte. L'opérateur peut
donc choisir la couleur de chaque piste, et la **remettre au défaut** d'un bouton — ce qui est le
seul geste utile quand la salle change de vélos entre deux soirées.

Deux conséquences en découlent.

* **La couleur choisie est persistée**, comme les noms. Elle ne se relit du fichier que si elle est
  valide ; sinon la piste retrouve son défaut, plutôt que de charger un écran public avec une
  teinte illisible venue d'un fichier édité à la main.
* **Deux pistes de même couleur sont signalées, pas interdites.** Si la salle aligne deux vélos
  rouges, l'opérateur a raison contre la charte, et le logiciel n'a pas à réécrire la réalité — le
  numéro de piste et le nom continuent d'identifier chacun (voir plus haut). Mais il le dit, parce
  qu'un doublon involontaire rend l'écran ambigu.

## 3. Typographie

Une graisse condensée à fort caractère pour les chiffres géants (chrono, écart, vitesse) et une
grotesque neutre pour le reste. Chiffres **tabulaires obligatoires** : sans ça, le chrono et les
compteurs de vitesse « dansent » à chaque changement de chiffre, ce qui est très visible en projection.
Polices libres, embarquées dans le dépôt, licence vérifiée et notée dans `art/FONTS.md`.

**Le français projeté est accentué.** Tout ce qui s'affiche sur l'écran spectacle est écrit
correctement : `FAUX DÉPART`, `PISTE 3 ÉLIMINÉE`, `décision dans 1:30`, `tous arrivés`. Rien ne
l'imposait, et les chaînes ont dérivé selon l'époque du fichier qui les portait — le podium
affichait « éliminé » à trois lignes de « tous arrives ». En capitales de soixante points sur un
mur, devant un public, une lettre manquante est la faute la plus visible qui soit. Les majuscules
accentuées comprises : `É`, `À`, `È`.

La règle vaut aussi pour **la fenêtre opérateur**, ses messages d'erreur et le CSV — même dérive,
même correction. Deux exceptions, et elles sont motivées : les outils en ligne de commande
(`ss_monitor`, `ss_emu`, `ss_replay`) écrivent dans un terminal et restent en ASCII, et le mot
`ignore` de la liste des ports garde son orthographe parce qu'il doit être **identique** dans
`docs/RECETTE.md`, dans `ss_monitor` et à l'écran.

## 4. Scène 3D

**Composition.** Vue 3/4 arrière légèrement surélevée, deux à quatre couloirs parallèles sur une
piste inclinée. Ligne d'arrivée matérialisée et visible à l'approche en mode distance.

### Les ombres des coureurs

Un coureur est fait de vingt-six pièces. Les faire toutes projeter donne une ombre qui **ressemble
à un cycliste** — on y lit le buste, les bras, la roue qui tourne — mais une lumière directionnelle
les redessine une fois par cascade.

* **Profils bas et moyen** : un volume approché projette seul, les pièces se taisent. Sous les néons
  d'un vélodrome l'ombre est une tache douce, et personne n'y lit un rayon de roue. Le profil moyen
  est celui que la détection choisit sur un GPU intégré : c'est donc le cas courant.
* **Profil élevé** : la vraie silhouette. C'est un choix délibéré de l'opérateur, sur une machine
  qu'il sait capable.
* **Dès que l'écran se scinde**, on retombe sur le volume approché quel que soit le profil : chaque
  volet redessine la scène, et c'est précisément là que le coût se multiplie.

Le volume approché reste en permanence en `SHADOWS_ONLY` : c'est ce qui le tient **hors de l'image**.
Couper son ombre autrement — en lui retirant le droit de projeter — le laisse se dessiner, et une
boîte d'un mètre apparaît debout sur le vélo. C'est arrivé, et aucune assertion sur les ombres ne
pouvait le voir.

**Caméra.** Un rig unique avec des comportements par mode :
* *distance / temps* — suit le leader, cadre l'ensemble du peloton, léger dutch angle à haute vitesse ;
* *poursuite* — cadre l'écart : elle recule et s'élève quand il se creuse, se resserre quand ça se recolle ;
* *photo-finish* — ralenti automatique et plan latéral sur la ligne quand l'écart à l'arrivée est
  inférieur à 1 m. C'est le moment qui fait crier une salle, il mérite un traitement dédié.
  L'écart est celui **des deux premiers encore en course** : un troisième loin derrière ne
  l'annule pas, et un coureur qui arrive seul — le seul de la course, ou le dernier après les
  autres — n'a pas de photo-finish.

**Riders.** Modèle unique de cycliste, cadence de pédalage indexée sur la vitesse réelle, **roulis
en danseuse** — le vélo bascule d'un côté puis de l'autre, une fois par demi-tour de pédalier, et
d'autant plus vite qu'on va vite —, maillot coloré par instance. La première rédaction disait
« inclinaison en virage » : des rouleaux n'ont pas de virage, et c'est le balancement du sprinteur
que le public reconnaît. Un seul modèle, quatre matériaux : le coût d'assets reste minimal.

**Effets de vitesse.** Ce sont eux qui portent la sensation, pas la géométrie :
* traînée lumineuse derrière chaque rider, longueur et intensité proportionnelles à la vitesse ;
* lignes de vitesse et flou radial en périphérie au-delà d'un seuil ;
* légère variation de FOV avec l'accélération ;
* bandes de néon au sol qui défilent, cadence indexée sur la vitesse.

**Environnement.** Tribunes low-poly, foule en *billboards* animés instanciés, réaction à
l'accélération et au franchissement de ligne. Volumétrique léger, bloom, vignettage.

**« Léger » se mesure**, mais **à cadrage identique**. La luminance moyenne du haut de l'image,
gradins compris, reste sous **45 sur 255** sur la course de référence — deux coureurs, 250 m, profil
`egaux` — où elle vaut 33 sans brume. Le chiffre n'est comparable que là : sur une course plus
courte la caméra cadre plus près, la bande observée attrape les gradins éclairés, et la même scène
saine monte à 48. C'est le cadrage qui domine, pas la brume. Hors de cette configuration,
`ss_race3d_demo` imprime la mesure sans rendre de verdict. Au-delà, la salle vire au lait gris, les gradins lointains disparaissent et les néons
perdent le contraste qui les fait exister (`§1`) ; le niveau de qualité le plus coûteux donne alors
l'image la moins conforme. Le levier n'est pas la densité mais **l'albédo** de la brume : blanche,
elle renvoie les projecteurs de salle dans tout le volume.

**Budget de performance.** 60 fps stables en 1080p sur un GPU intégré Intel Iris Xe ou équivalent.
`ss_race3d_demo --mesure` le **fait échouer** quand il n'est pas tenu — code 5, et le rapport dit
de combien. Un chiffre imprimé sans conséquence n'est qu'une observation ; la CI n'ayant pas de
GPU, c'est le seul endroit où cette exigence peut mordre.
C'est la machine réelle d'un événement, pas une station de jeu. Toute fonctionnalité visuelle qui
fait passer sous 60 fps est coupée ou dégradée. Trois niveaux de qualité (`bas / moyen / élevé`),
détection automatique au premier lancement, réglage manuel possible. **Un niveau choisi à la main
est persisté et désarme la dégradation automatique** : sinon il serait défait dès la première
seconde sous le budget, et la machine du projecteur retrouverait un niveau trop lourd à chaque
soirée.

L'**anticrénelage** fait partie des leviers du niveau, au même titre que la foule ou le
volumétrique : coupé en `bas`, 2× en `moyen`, 4× en `élevé`, et les vues de l'écran scindé le
suivent. Un trait de néon d'un pixel ne supporte aucun rééchantillonnage — mais sur une machine qui
ne tient pas les 60 fps, une image qui fourmille vaut mieux qu'une image qui saccade.

**L'automatique est un choix, pas seulement un état de départ.** Le sélecteur l'offre comme
première entrée, au même titre que l'écran, et il indique le niveau réellement détecté
(`automatique (moyen)`) — et, si la scène s'est allégée d'elle-même en cours de soirée, le niveau
réellement **appliqué** (`automatique (bas — abaissé)`), l'opérateur en étant prévenu dans le
journal du panneau Course : une décision prise sans lui doit lui être dite, sinon il cherche
pourquoi l'image a changé. Sans ce retour en arrière, un opérateur qui essaie « élevé » un soir perd
définitivement la dégradation qui protège les 60 fps, et ne peut la rétablir qu'en éditant un
fichier JSON. Le sélecteur reste utilisable **fenêtre spectacle fermée** : c'est un réglage
persisté, que l'ouverture suivante applique — on le règle la veille, sans projecteur branché.

Attention au piège de l'`OptionButton` : `add_item(texte, -1)` ne mémorise pas `-1`, Godot y met
l'index de l'entrée. Les entrées « automatique » des deux sélecteurs portent donc un identifiant
propre, traduit en `-1` au moment d'écrire le réglage.

La composition est pensée en 1080p, mais **la 3D ne se rend jamais plus fin que le projecteur** :
sur un 720p elle se rend en 720p — 2,25× moins de pixels — et l'habillage reste composé en 1080p.
Au-delà de 1080p, le rendu reste en 1080p, mis à l'échelle : c'est le budget, pas le projecteur, qui
fixe le plafond.

## 5. Habillage à l'écran (fenêtre spectacle)

* **Bandeau haut** — mode de course, objectif (`500 m` / `60 s` / `écart 50 m`), chrono en chiffres géants.
  Écran scindé : bandeau, chrono et titres réduits d'un peu moins de moitié, comme les cartes — à
  pleine taille ils mangeaient le haut de chaque volet.
* **Par rider** — nom, numéro de piste, vitesse instantanée en km/h, distance parcourue, cadence.
  Les cartes sont **complètes dès le décompte**, à zéro et objectif annoncé (`0.0 km/h`, `0 m
  parcourus — reste 250 m`) : remplies seulement à la première trame `R:`, elles montraient un nom
  et deux lignes vides pendant les trois secondes où tout le monde regarde, ce qui se lit comme un
  affichage cassé.
  Écran scindé : **la carte se pose dans le volet qui montre son coureur**, et non toutes en
  colonne à gauche — sinon le spectateur qui regarde le quatrième volet cherche la vitesse de son
  coureur à l'autre bout de l'écran. Les coureurs d'un même paquet empilent leurs cartes dans leur
  volet commun. La lame étant inclinée, un volet est plus étroit en haut qu'en bas : une carte trop
  large pour le sien est réduite jusqu'à y tenir.
* **Poursuite** — l'écart occupe le centre de l'écran, avec la barre de tension entre `−G` et `+G`.
* **Décompte** — plein écran, `3 / 2 / 1 / PARTEZ !`, synchronisé sur les trames `CD:` du firmware
  (jamais sur une horloge PC : les LED physiques et l'écran doivent être d'accord).
* **Arrivée** — ralenti, podium, temps, vitesse moyenne et vitesse de pointe par rider. **Toute
  marque portée par une ligne est légendée sous le tableau** — la croix d'un éliminé, par exemple —
  et seulement quand elle est présente : l'écran public est vu par cent personnes qui n'ont pas le
  manuel, là où le tableau de l'opérateur est vu par une qui l'a. Un rider
  arrivé ne s'arrête pas : il décélère vers une allure de croisière et continue de rouler sous la
  célébration et le podium — le sol défile. Une fois tout le monde arrivé, les suivants accélèrent
  pour revenir se placer derrière le premier, dans l'ordre d'arrivée, à quelques mètres — jamais
  devant lui — et la caméra retrouve tout le monde dans un seul cadre ; si l'écran était scindé au
  gong du mode temps, les volets se referment en les voyant se rapprocher.

## 6. Audio

### Le lit sonore — ce qu'on entend quand il ne se passe rien

Une course dure vingt secondes et il ne s'y passe presque aucun ÉVÉNEMENT. Ce qui tient la
bande-son, c'est donc le fond, pas les cues. Il en faut trois, qui suivent tous l'intensité de la
course :

* **Le grondement des rouleaux** — le son propre du goldsprint, et le seul que le public entend
  vraiment dans la salle. Bruit filtré autour de 320 Hz avec une seconde résonance vers 780,
  modulé lentement pour le roulement ; sa hauteur et son niveau suivent la vitesse.
* **La rumeur de la salle** — une foule qui attend n'est pas silencieuse. Continue, elle enfle
  avec la course, et laisse la place aux clameurs ponctuelles.
* **La nappe grave** — la tension musicale. Elle porte des partiels **au-dessus de 200 Hz**, pas
  seulement à 55 : voir la règle des haut-parleurs plus bas.
* **Le souffle de vent**, indexé sur la vitesse, en appoint — il ne porte plus la scène à lui seul.

**RÈGLE DES HAUT-PARLEURS. Tout son continu porte la majorité de son énergie au-dessus de
200 Hz.** La première nappe empilait 55, 82,5, 110 et 165 Hz : mesurée, elle plaçait 90 % de son
énergie sous 200 Hz, c'est-à-dire sous ce qu'un haut-parleur d'ordinateur portable ou une petite
enceinte peut restituer. Elle était donc inaudible sur les machines qui font tourner ce logiciel,
et il ne restait que le vent — « il ne se passe rien ». Un son qu'on ne peut pas entendre n'est pas
un son discret, c'est un son absent. La suite de tests le vérifie sur chaque flux continu.

### Les événements

* Nappe de fond dont l'intensité suit la vitesse du leader et, en poursuite, l'écart normalisé.
* Bips de décompte, klaxon de départ, **cloche de la fin imminente** — une volée, jamais deux.
  C'est une **cloche de vélodrome** : sur piste, la fin se dit à la cloche, en volée de plusieurs
  frappes, et non d'un coup unique qu'on prendrait pour un bip. Le battant s'entend.
  Un goldsprint n'a pas de tour et une course en temps n'a pas de mètres : la cloche sonne aux
  **50 derniers mètres** en mode distance et aux **10 dernières secondes** en mode temps, **sans
  jamais dépasser le dernier quart de l'épreuve**. Ce plafond n'est pas une précaution théorique :
  la distance minimale acceptée est de 50 m et la durée minimale de 10 s, si bien que la cloche
  sonnait sur la ligne de départ d'une course courte. Une annonce de fin qui tombe au départ ne dit
  plus rien. En poursuite elle se tait — la fin y arrive quand l'écart se referme, ce que rien ne
  permet d'annoncer à l'avance.
* Réactions de foule sur les dépassements, les accélérations et le franchissement.
* **Souffle de dépassement** sur le changement d'ordre : la clameur dit que la salle a réagi, le
  souffle dit ce qui s'est passé sur la piste. Deux informations, deux sons.
* **Glas d'élimination** en poursuite — grave, lent, sans appel. Une élimination est le contraire
  d'une clameur : c'est quelqu'un qui sort.
* **Le lit s'efface sous les annonces.** Cloche, klaxon et glas font plonger rouleaux, rumeur et
  nappe le temps de passer, puis tout remonte. Sans cela l'annonce se noie dans le fond qu'elle
  est censée interrompre.
* **Lien perdu : le lit s'efface et reste effacé.** La course est figée à l'écran, bandeau
  `LIEN PERDU` ; des rouleaux qui sifflent et une nappe qui monte sous un écran immobile passent
  pour un plantage. Rouleaux, vent, rumeur et couches retombent à leur plancher et n'y remontent
  qu'avec les trames, quand le lien revient. Seul le pouls reste : la course n'est pas finie.
  **L'image suit la même règle** : sans trames, jambes, foule et effets de vitesse retombent à
  l'arrêt — des vélos immobiles aux jambes qui tournent à 45 km/h ne se lisent pas comme une
  course figée, mais comme un bug. Seul le bandeau vit, jusqu'aux trames suivantes.
* Souffle de vent indexé sur la vitesse.
### Synthèse d'abord, enregistrements là où elle échoue

Tout est **synthétisé** par défaut : rien à télécharger, rien à perdre à l'export, et surtout tout
ce qui doit suivre la course — hauteur des rouleaux, montée de la nappe, couches de musique en
phase — ne peut pas être un échantillon figé.

**Trois exceptions, et elles sont motivées** : la cloche et les deux réactions de foule viennent
d'enregistrements réels. Une foule est faite de centaines de voix corrélées, une cloche est une
géométrie de bronze ; approchées en code elles s'entendaient comme « du bruit blanc » et « plein de
bips ». Ce n'est pas un défaut d'implémentation qu'un tour de plus aurait corrigé, c'est la limite
de l'exercice.

Les fichiers sont **versionnés dans le dépôt** (122 Ko en Vorbis mono) : rien n'est téléchargé pour
construire, la règle de reproductibilité portait sur le build et elle tient. **Aucune clause de
partage à l'identique n'est acceptée** — CC0, domaine public ou CC-BY seulement : une clause SA
suivrait le fichier dans toute distribution, et cela ne se décide pas au détour d'un choix de
bruitage. Sources, auteurs et modifications sont dans `audio/CREDITS.md`.

**Un échantillon manquant ne fait pas taire le logiciel** : la synthèse reste en place derrière
chacun et prend le relais. Un fichier absent est un son moins beau, jamais une soirée sans son.

**Ce qui a sonné se constate, il ne s'écoute pas.** Chaque son déclenché est noté (`last_cue`,
`cue_counts`) : c'est la seule façon de prouver la bande-son dans une suite qui tourne sans carte
son, et la seule façon honnête de la valider quand la consigne interdit d'en juger à l'oreille.

* **Coupure audio globale d'un bouton** : en événementiel, la sono est souvent gérée séparément
  et un logiciel qui sonne par-dessus la musique est un problème. **La coupure ET le volume sont
  persistés** : ils se règlent la veille, une fois, et sont réappliqués au lancement suivant. Le
  volume se règle **son coupé** : c'est un réglage, pas une sortie. Le griser tant que le son est
  muet — et il l'est par défaut — obligeait à faire du bruit pour préparer une salle vide.
