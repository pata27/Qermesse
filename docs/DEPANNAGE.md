# Dépannage

> Écrit pour l'opérateur, pas pour le développeur. Chaque section donne le symptôme tel qu'il se voit
> à l'écran, la cause la plus fréquente, et quoi faire — dans cet ordre.
>
> **Règle d'or le soir d'un événement : basculer sur le simulateur.** Le bouton *Simulateur* du
> panneau matériel fait tourner une course complète sans aucun boîtier. On garde le public, on
> diagnostique après.

---

## Le bouton START est grisé

Ce n'est jamais arbitraire : **survoler le bouton affiche le motif**. Trois causes possibles.

| Infobulle | Cause | Quoi faire |
|---|---|---|
| `lien DISCONNECTED` ou `PORT_OPEN` | Le boîtier n'a pas répondu `V:` | Voir *Le boîtier n'est pas détecté* |
| `une course est déjà en cours` | La course précédente n'a pas été clôturée | Appuyer sur STOP |
| `aucune piste active` | Le roster est vide | Cocher au moins une piste |

> Un port ouvert **n'est pas** une preuve qu'on parle au bon appareil. Le logiciel refuse de démarrer
> tant que le boîtier n'a pas répondu — c'est délibéré : la v1 acceptait n'importe quel périphérique
> série et pouvait piloter une souris Bluetooth.

---

## Le boîtier n'est pas détecté

Le panneau matériel liste tous les ports série, avec **le motif de leur retenue ou de leur rejet**.
Un port marqué `•` sera essayé ; les autres sont ignorés, et la raison est écrite en face.

1. **Le boîtier n'apparaît pas du tout.** C'est un problème système, pas logiciel.
   - Vérifier le câble USB — un câble « de charge » sans fil de données est le grand classique.
   - Linux : `lsusb` doit montrer l'Arduino. Sinon, essayer un autre port USB.
   - **Droits d'accès, Linux :** si `ls -l /dev/ttyACM0` montre le groupe `dialout` et que vous n'en
     faites pas partie, le port est invisible pour le logiciel.
     ```sh
     sudo usermod -aG dialout $USER   # puis se déconnecter et se reconnecter
     ```
   - Windows : le gestionnaire de périphériques doit montrer un port COM. Sinon, installer le pilote
     CH340 (clones) ou FTDI.

2. **Le boîtier apparaît mais est marqué `ignore`.** Son VID/PID n'est pas dans la liste connue.
   Ce n'est pas grave : **cliquer dessus dans la liste** le force. Le choix est mémorisé.
   Signaler l'identifiant au développeur pour qu'il l'ajoute.

3. **Le boîtier est candidat mais le lien reste `PORT_OPEN`.** Le port s'ouvre, rien n'en sort.
   - Un autre logiciel tient le port : moniteur série de l'IDE Arduino, `screen`, `minicom`. Le fermer.
   - Le boîtier a été reflashé avec un firmware qui ne répond pas `V:`.
   - Débrancher, attendre cinq secondes, rebrancher.

---

## Les ticks arrivent sur la mauvaise piste

**Symptôme :** on tourne le rouleau 1 et c'est la piste 2 qui avance.

Ce n'est pas un bug logiciel : c'est le câblage des capteurs sur le boîtier.

1. Panneau matériel → **Test capteurs**.
2. Tourner **un seul rouleau à la fois**, lentement.
3. Noter la correspondance réelle.

Deux issues : intervertir les fiches sur le boîtier, ou intervertir les noms des riders dans le
roster. La seconde marche pour la soirée ; la première est la vraie réparation.

**À faire avant chaque événement**, pas quand le problème se manifeste devant le public.

---

## Une piste reste à zéro alors que le rouleau tourne

- Le capteur de cette piste n'est pas câblé. Voir *Test capteurs* : si aucune activité, c'est
  mécanique ou électrique, pas logiciel.
- L'aimant est trop loin du capteur. Il doit passer à quelques millimètres.
- L'aimant s'est détaché — cela arrive plus souvent qu'on ne croit.

---

## Le compteur de trames rejetées grimpe

Le panneau matériel affiche `Trames …, inconnues …, perdues …`.

- **`inconnues` monte** : le boîtier envoie des trames que le logiciel ne reconnaît pas. Le plus
  probable est un firmware différent. Relever la version affichée.
- **`LONGUEUR : le boîtier a compris N ticks, M demandés` apparaît** — le firmware n'a pas retenu
  la distance envoyée. Le classement reste juste : c'est le PC qui arbitre. Ce qui sera faux, ce
  sont les **LED d'arrivée du boîtier**, qui s'allumeront à la mauvaise distance. Cause probable :
  un boîtier reflashé, ou une variante de firmware. Relever la version affichée dans le panneau
  Matériel et l'envoyer au développeur avec le JSON de la course.
- **`Ticks rejetés : N (dernier : piste 2 …)` apparaît** — la ligne reste toute la soirée, avec le
  dernier motif, et chaque rejet est écrit au CSV (`TICK_REJECTED`) : un capteur rebondit ou un
  aimant est mal fixé. Le filtre écarte les valeurs impossibles, mais **il ne peut pas rattraper un tick fantôme
  isolé** — resserrer la fixation avant la course suivante.
- **`perdues` non nulle** : la machine n'arrive plus à suivre le flux. Fermer les autres
  applications ; c'est le seul cas qui fausse réellement une mesure. Le logiciel le dit sans
  attendre qu'on lise ce compteur : `TRAMES PERDUES : la machine ne suit plus le flux du boîtier.`
  apparaît dans le panneau **Course** dès la première perte, une fois par course. La course qui la
  subit est à refaire.

---

## Le bandeau « LIEN PERDU » apparaît en pleine course

Le logiciel a cessé de recevoir des données pendant plus d'une demi-seconde. L'affichage se fige sur
la dernière valeur connue — il ne revient pas à zéro.

- **Si le lien revient dans les trois secondes, la course reprend toute seule.** Rien à faire. Aucune
  donnée n'est perdue : le boîtier envoie des compteurs cumulés, pas des incréments.
- **Au-delà, la course est marquée `INTERROMPUE`** dans le résultat et dans le CSV. Elle reste
  exploitable, mais elle est signalée comme telle. Relancer.

Causes, par fréquence : câble USB qui bouge, prise mal enfoncée, alimentation instable, veille de la
machine. **Désactiver la mise en veille avant l'événement.**

---

## La course ne se termine jamais

Si vous voyez ce symptôme avec **cette** version, c'est un bug — signalez-le.

Le contexte mérite d'être connu : c'était le défaut majeur de l'ancien logiciel. Le boîtier attend
que les **quatre** pistes matérielles aient franchi la ligne, ce qui n'arrive jamais avec deux
capteurs câblés. En v3, c'est le PC qui arbitre et ne compte que les pistes déclarées actives —
vérifier d'ailleurs que le roster ne contient pas une piste cochée sans cycliste dessus.

**Le logiciel le dit lui-même**, et il distingue deux cas — le motif n'est pas le même.

*La piste n'a jamais rien produit.* Toute piste cochée restée muette est signalée dans le panneau
**Course** : `PISTE 3 : aucun tick depuis le départ — coureur absent ou capteur débranché ? La
course attend cette piste.` Personne sur la piste, ou un câble jamais branché.

Le signal tombe au premier de ces deux repères : **dix secondes de course**, ou **le quart de
l'épreuve** — le quart de la distance en mode distance, du temps en mode temps. Les dix secondes
seules arrivaient trop tard : une course de 100 m dure huit secondes à 45 km/h, et l'alerte tombait
donc **après** l'instant où la course aurait dû se terminer. Sur 50 m, plus du double. Mesuré : sur
100 m avec une piste vide, l'alerte passe de 10,0 s à 2,1 s — huit secondes gagnées, pendant
lesquelles le public regarde une course qui visiblement aurait dû finir.

*La piste s'est tue en route.* Cinq secondes sans un seul tick alors qu'elle roulait :
`PISTE 2 : plus un seul tick depuis 5 s alors qu'elle roulait — coureur arrêté ou capteur perdu en
route ? La course attend cette piste.` Le câblage n'est pas en cause, il a fonctionné : c'est
arrivé **pendant** la course — câble arraché par la secousse, aimant parti, ou simplement un
coureur à l'arrêt. Un tick vaut un tour de rouleau, 36 cm : cinq secondes de silence, c'est
l'arrêt, pas une allure lente.

Dans les deux cas, c'est le moment d'arrêter et de repartir, plutôt que d'attendre le plafond de
dix minutes devant le public. Rien n'est signalé pour une piste déjà arrivée ou éliminée : son
silence est normal.

---

## Les vitesses affichées sont absurdes

- **Vitesse trois fois trop grande ou trop petite** : le diamètre du rouleau est faux. Le mesurer :
  distance de l'aimant au centre du rouleau, **×2**. La ligne de calibration donne immédiatement le
  nombre de ticks pour 100 m ; à 114,3 mm ce doit être **278**.
- **Une pointe au-dessus de 90 km/h** n'est pas une performance : c'est un capteur qui rebondit ou un
  aimant qui passe deux fois par tour. Le logiciel le signale de lui-même, en course, dans le
  panneau **Course** : `PISTE 2 : pointe à 104 km/h — capteur qui rebondit ou aimant qui passe deux
  fois par tour ? La mesure est conservée.` Elle est **conservée**, pas rejetée : elle est
  peut-être vraie, et un logiciel qui efface une performance est pire qu'un logiciel qui pose une
  question. Le filtre, lui, rejette au-delà de 120 km/h (`01` §6.3) — c'est un autre seuil, pour
  l'impossible et non pour l'invraisemblable.

---

## Le CSV est introuvable

Les chemins complets sont affichés **en clair** sous l'écran de résultats — celui du journal du jour
et celui du **fichier de la course sélectionnée**, qui est celui à envoyer au développeur. Le bouton
*Ouvrir le dossier des résultats* mène au dossier qui contient les deux.

Les **outils de démonstration** (`tools/ss_operator_demo.gd`, `tools/ss_race3d_demo.gd`) font de
vraies courses et enregistrent donc de vrais fichiers. Ils écrivent dans un dossier séparé —
`<données Godot>/SilverSprint v3/demo/` — et **jamais** dans celui de l'opérateur, sauf si on le leur
demande avec `--donnees <dossier>`. Une course apparue dans « Courses du jour » sans que personne
n'ait couru vient d'un outil lancé avant ce cloisonnement.

| Système | Emplacement |
|---|---|
| Linux | `~/.local/share/silversprint/logs/` |
| macOS | `~/Library/Application Support/SilverSprint/logs/` |
| Windows | `%APPDATA%\SilverSprint\logs\` |

Un fichier par journée d'exploitation, nommé `AAAA_MM_JJ_SilverSprintRaceLog.csv`. Cette journée
va de 5 h à 5 h : une course de 00 h 10 est écrite dans le fichier de la **veille**, avec le reste
de sa soirée. **Une course appartient au jour de son départ**, toute entière : celle qui part à
04 h 59 et arrive à 05 h 01 est dans le fichier de la veille du début à la fin, comme son JSON.
Les courses s'y **ajoutent** : il n'est jamais réécrit, et le fichier de la veille n'est jamais
touché.

Le dossier `races/` voisin contient un JSON par course, avec la trace complète des mesures. C'est ce
qu'il faut envoyer au développeur en cas de résultat suspect : la course peut être rejouée à
l'identique. **Une course arrêtée en a un aussi** — c'est même le fichier le plus utile après un
incident, puisqu'il contient les trames reçues jusqu'à la coupure.

Le rejeu se fait avec `tools/ss_replay.gd` : il repousse les trames dans un moteur neuf, recalcule
tout et compare au classement enregistré. Une divergence est un bug du logiciel, pas de la course.

```sh
godot --headless --script tools/ss_replay.gd -- --dossier <dossier races>
```

**Si l'écriture échoue** — disque plein, dossier interdit —, le panneau **Course** l'affiche en fin
de course : `ENREGISTREMENT : …`. Le logiciel ne s'arrête pas pour autant ; le classement reste à
l'écran, mais il n'est **pas** sur disque. Libérer de la place ou changer de dossier, puis relancer.

---

## Les noms des riders et les réglages ont disparu au lancement

Le fichier `settings.json` ou `roster.json` est illisible — édité à la main, disque coupé pendant
l'écriture. Le logiciel démarre quand même, **avec les valeurs par défaut**, et le dit dans le
panneau **Course** au lancement : `REGLAGES : JSON invalide ligne N …`. Le fichier fautif est
remplacé à la prochaine sauvegarde ; le message donne son chemin.

Un fichier **lisible mais faux** — une distance de 10 000 m, un écart écrit `"abc"`, une durée
`true` — ne bloque pas non plus : la valeur hors bornes est **ramenée dans les bornes**, la valeur
qui n'est pas un nombre est **remplacée par la valeur par défaut**, et la ligne orange du panneau
**Course** dit lesquelles : `REGLAGES : N valeur(s) corrigée(s) dans settings.json — …`. Sans
cela, un écart `"abc"` devenait 10 m en silence, et la poursuite éliminait au premier tour de
rouleau.

---

## Il n'y a pas de son

**C'est voulu : le logiciel démarre muet.** En événementiel la sono est presque toujours gérée
séparément, et un logiciel qui se met à sonner par-dessus la musique de la salle dès la première
course est un problème, pas une fonctionnalité (`docs/04` §6). Le son ne s'allume que d'un geste
de l'opérateur, une fois vérifié où il sort.

* Panneau opérateur, section **Son** : le bouton affiche l'état — `SON COUPÉ` en rouge, `SON ACTIF`
  en vert. Un clic bascule. Le curseur **Volume** n'agit que si le son est actif.
* L'état est mémorisé : si le son a été activé la veille, il l'est encore au lancement.
* Tout le son du logiciel passe par un bus audio dédié, `Course` : le couper ne touche pas au
  volume de la machine, et le volume de la machine ne le rallume pas. Vérifier les deux.
* Aucun fichier audio n'est nécessaire — les sons sont synthétisés au lancement. Un export qui
  « n'a pas de son » n'a donc pas perdu de fichier : c'est le bouton.

Ce que le son joue quand il est actif : bips de décompte, klaxon de départ, nappe de fond qui suit
la vitesse (l'écart, en poursuite), cloche de la fin imminente — cinquante derniers mètres en
distance, dix dernières secondes en temps, jamais plus du dernier quart —, clameurs sur dépassement
et franchissement, souffle de vent.

## Le vidéoprojecteur n'est pas détecté

Panneau **Fenêtre spectacle**. Sa dernière ligne indique combien d'écrans le système annonce —
`2 écrans détectés.` Le logiciel ne détecte rien lui-même : il liste ce que le système lui donne.

**S'il n'annonce qu'un écran**, il le dit en toutes lettres — *« Un seul écran détecté : la fenêtre
spectacle s'ouvrira en fenêtré par-dessus. Branchez le projecteur puis rouvrez-la pour l'y
envoyer. »* Le problème est alors en amont du logiciel :

1. Brancher le projecteur **avant** de lancer le logiciel, et le mettre sous tension.
2. Vérifier côté système que le second écran est bien actif — et en mode **étendu**, pas en
   duplication. En duplication, il n'y a qu'un écran pour le système, et la liste le reflète.
3. Rouvrir le panneau : la liste est reconstruite à chaque affichage.

**S'il annonce deux écrans mais que la fenêtre s'ouvre au mauvais endroit**, choisir l'écran dans la
liste — `automatique` prend le second s'il existe. Sous Wayland, c'est le compositeur qui tranche :
voir la fiche dédiée plus bas.

**Si rien n'y fait, le spectacle passe quand même.** Fermer la fenêtre spectacle et **dupliquer
l'écran au niveau du système** : le public voit alors le panneau opérateur, ce qui n'est pas beau
mais reste lisible — chronos, distances, vitesses y sont. La course, elle, est indifférente à
l'affichage : fermer la fenêtre spectacle n'arrête rien.

---

## Rien ne fonctionne et le public attend

1. Panneau matériel → **Simulateur**.
2. Lancer la course. Elle se déroulera de bout en bout, avec des cyclistes synthétiques.
3. Diagnostiquer après.

Le simulateur produit exactement les mêmes trames que le boîtier, bugs du firmware compris. Ce n'est
pas un mode dégradé bricolé : c'est le même logiciel, avec une autre source de données.

## La fenêtre spectacle ne s'ouvre pas sur le bon écran (Wayland : Hyprland, Sway…)

Sous Wayland, **c'est le compositeur qui décide de l'écran et du plein écran**, pas
l'application. Les réglages « Écran » et « Plein écran » du panneau opérateur sont désactivés dans
ce cas, et le panneau le dit. Une requête plein écran faite par l'application emporterait la
géométrie de l'écran où se trouvait la **souris au lancement**, et le compositeur la suivrait :
la fenêtre s'ouvrirait donc « là où était le pointeur ». C'est le compositeur qui doit faire les
deux, par une règle sur le **titre** des fenêtres, qui est stable :

* fenêtre spectacle : `SilverSprint — spectacle`
* fenêtre opérateur : `SilverSprint v3 — operateur` (suffixée de ` (DEBUG)` hors export)

### Hyprland 0.55 et suivants — configuration Lua

Depuis 0.55 la configuration `hyprland.conf` (hyprlang) est dépréciée, et à partir de 0.57 la
configuration est en **Lua**. Le signe qui ne trompe pas : `hyprctl systeminfo` affiche
`configProvider: lua`. Dans ce cas **tout ce qu'on écrit dans `hyprland.conf` est ignoré en
silence** — `hyprctl reload` répond `ok`, `hyprctl configerrors` reste vide, et rien ne change.

Dans un fichier `~/.config/hypr/silversprint.lua`, chargé par `require("silversprint")` depuis
`hyprland.lua` :

```lua
hl.window_rule({
    name = "silversprint-spectacle",
    match = { title = "^(SilverSprint).*spectacle.*" },
    monitor = "eDP-1",       -- nom donné par `hyprctl monitors`
    fullscreen = true,
})
hl.window_rule({
    name = "silversprint-operateur",
    match = { title = "^(SilverSprint).*operateur.*" },
    monitor = "DP-10",
})
```

Pour essayer une règle **sans toucher au fichier**, `hyprctl eval '<le même appel Lua>'` la pose
à chaud jusqu'au prochain rechargement.

### Hyprland avant 0.55 — configuration hyprlang

```
windowrulev2 = monitor <NOM_ECRAN>, title:^(SilverSprint).*spectacle.*
windowrulev2 = fullscreen, title:^(SilverSprint).*spectacle.*
```

### Vérifier, ne pas supposer

`hyprctl clients -j` donne, pour chaque fenêtre, `monitor` et `fullscreen`. Faire l'essai avec la
souris sur **un autre écran** que celui visé : une fenêtre qui s'ouvre au bon endroit alors que le
pointeur y était déjà ne prouve rien — c'est le placement par défaut. Les deux fenêtres tournent en
XWayland (le projet ne force pas le pilote Wayland de Godot) ; les règles s'appliquent de la même
façon.

---

## Tous les messages du panneau Course

Le journal du panneau **Course** garde les cinq derniers messages, le plus récent en tête. Voici
chacun de ceux que le logiciel peut y écrire, ce qu'il veut dire, et ce qu'il faut faire — les
alertes d'abord, les faits de course ensuite. Les
symptômes qui demandent une explication longue ont leur section plus haut ; celle-ci est la table
d'entrée quand on lit un message et qu'on ne sait pas par où commencer.

| Message | Ce qu'il veut dire | Quoi faire |
|---|---|---|
| `départ impossible : …` | La configuration ou le lien interdit de lancer. Le motif suit. | Lire le motif : piste active, lien identifié, bornes de l'épreuve. |
| `armement refusé : …` | Le moteur a refusé d'armer — configuration invalide, ou course déjà en cours. | Le motif suit. Après une arrivée, START relance simplement la suivante. |
| `commande refusée par le lien : …` | Une commande série n'est pas partie. Bornes du firmware, ou lien coupé. | Vérifier l'état du lien dans **Matériel**. Si le lien est bon, la commande était hors bornes : c'est un bug, garder le CSV. |
| `LIEN PERDU` | Le boîtier ne répond plus. Une course en cours a trois secondes de grâce. | Voir « Le bandeau LIEN PERDU apparaît en pleine course ». |
| `trame anormale : …` | Le boîtier a envoyé une ligne que le protocole ne connaît pas. Elle est loggée, jamais avalée. | Une ligne isolée est sans conséquence. Répétée, c'est un firmware différent : relever la version dans **Matériel**. |
| `LONGUEUR : le boîtier a compris N ticks, M demandés` | Le firmware n'a pas retenu la distance envoyée. | Voir la section dédiée plus haut. |
| `TRAMES PERDUES : la machine ne suit plus le flux du boîtier.` | Le PC n'a pas lu la ligne assez vite. **Le seul cas qui fausse une mesure.** | Fermer les autres applications. Si cela persiste, baisser la qualité de rendu. |
| `tick rejeté : …` | Un tick incohérent a été écarté par le filtre. | Voir « Le compteur de trames rejetées grimpe ». |
| `PISTE N : aucun tick depuis le départ — coureur absent ou capteur débranché ?` | Une piste **cochée** n'a produit aucun tick au bout de dix secondes, ou du quart de l'épreuve — le premier des deux. En mode distance, la course ne peut pas se terminer sans elle. | Décocher la piste et relancer, ou rebrancher le capteur. Voir « Une piste reste à zéro ». |
| `PISTE N : pointe à X km/h — capteur qui rebondit ou aimant qui passe deux fois par tour ?` | Une pointe humainement invraisemblable. La mesure est **conservée**, pas corrigée. | Voir « Les vitesses affichées sont absurdes ». |
| `ENREGISTREMENT : …` | Le classement est à l'écran mais n'a pas pu être écrit sur le disque. | Le plus urgent de la soirée : photographier l'écran de résultats, puis voir « Le CSV est introuvable ». |
| `SAUVEGARDE DES REGLAGES : …` / `SAUVEGARDE DU ROSTER : …` | Les réglages ou les noms n'ont pas pu être écrits. La course, elle, est enregistrée. | Vérifier l'espace disque et les droits sur le dossier de configuration. Les noms seront à ressaisir au prochain lancement. |
| `COURSES DU JOUR : N fichier(s) de course illisible(s), la liste est incomplète` | Au lancement, un ou plusieurs fichiers de course du jour n'ont pas pu être relus — disque coupé pendant l'écriture, fichier tronqué. La liste **Courses du jour** est donc plus courte que le nombre de manches réellement courues. | Le message donne les noms. Le **journal CSV du jour garde ses lignes** : classements, temps et vitesses y sont. Seul le rejeu de ces courses-là est perdu. |
| `REGLAGES : …` / `ROSTER : …` au lancement | Un fichier de configuration est illisible ; les valeurs par défaut ont été prises. | Voir « Les noms des riders et les réglages ont disparu au lancement ». |
| `REGLAGES : N valeur(s) corrigée(s) dans settings.json — …` | Le fichier de réglages se lit, mais une ou plusieurs valeurs sont hors bornes ou ne sont pas des nombres — édité à la main. Chacune est ramenée dans ses bornes ou remplacée par la valeur par défaut ; le message les nomme, avec la valeur lue et la valeur gardée. | Vérifier les réglages dans les panneaux **Mode** et **Matériel** avant la première course. La prochaine sauvegarde réécrit le fichier propre. |
| `Module natif absent : retour au simulateur.` | Le GDExtension n'est pas compilé : aucun port série n'est accessible. | `cd addons/serial_link && scons target=template_debug`. Voir « Le boîtier n'est pas détecté ». |
| `test capteurs : impossible pendant une course` | Le test capteurs est une course à blanc ; il ne peut pas tourner par-dessus une vraie. | Attendre l'arrivée, ou STOP. |
| `test capteurs : interrompu, lien perdu` | Le boîtier a été débranché pendant un test capteurs. La course à blanc côté boîtier n'existe plus ; le bouton se relâche. | Rebrancher, attendre `IDENTIFIED`, relancer le test si besoin. |
| `test capteurs : après le décompte du boîtier, tournez chaque rouleau, une piste à la fois` | Ce n'est pas une erreur : c'est la marche à suivre. Le firmware ne lit ses capteurs qu'en course. | Faire tourner un rouleau à la fois et lire quelle piste bouge. |
| `test capteurs : commande refusée par le lien : …` | La course à blanc n'a pas pu être armée. | Même cause que `commande refusée par le lien`. |
| `mode démo : impossible pendant une course` | La vitrine refuse de démarrer : des gens pédalent. | Attendre l'arrivée, ou STOP. Voir le manuel, « Entre deux manches ». |

Les quatre suivants ne sont pas des alertes : ce sont les faits de course, écrits au même endroit
pour que le journal se lise comme le récit de la manche. Aucun ne demande d'action.

| Message | Ce qu'il veut dire |
|---|---|
| `FAUX DÉPART piste N` | Le boîtier a vu la piste `N` bouger pendant le décompte. Ce que le public en voit dépend de la politique choisie — voir `docs/02` §4. |
| `Piste N éliminée (rang R, écart X m)` | Poursuite : la piste `N` a atteint l'écart décisif et sort, à la place `R`. |
| `Terminé — vainqueur piste N (nom)` | La course est arrivée. Le nom est celui **du départ**, pas celui que le roster porte maintenant. |
| `Terminé — vainqueur piste N (nom)  [INTERROMPUE]` | La course a été arrêtée. Le motif, lui, est sur l'écran public ; un plafond de sécurité a bien un vainqueur et ne porte pas cette mention (`docs/02` §3). |
