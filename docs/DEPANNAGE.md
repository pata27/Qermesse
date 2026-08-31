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
- **Des ticks rejetés apparaissent en cours de course** : un capteur rebondit ou un aimant est mal
  fixé. Le filtre écarte les valeurs impossibles, mais **il ne peut pas rattraper un tick fantôme
  isolé** — resserrer la fixation avant la course suivante.
- **`perdues` non nulle** : la machine n'arrive plus à suivre le flux. Fermer les autres
  applications ; c'est le seul cas qui fausse réellement une mesure.

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

---

## Les vitesses affichées sont absurdes

- **Vitesse trois fois trop grande ou trop petite** : le diamètre du rouleau est faux. Le mesurer :
  distance de l'aimant au centre du rouleau, **×2**. La ligne de calibration donne immédiatement le
  nombre de ticks pour 100 m ; à 114,3 mm ce doit être **278**.
- **Une pointe au-dessus de 90 km/h** n'est pas une performance : c'est un capteur qui rebondit ou un
  aimant qui passe deux fois par tour.

---

## Le CSV est introuvable

Le chemin complet est affiché **en clair** sous l'écran de résultats, et le bouton
*Ouvrir le dossier du CSV* y mène.

| Système | Emplacement |
|---|---|
| Linux | `~/.local/share/silversprint/logs/` |
| macOS | `~/Library/Application Support/SilverSprint/logs/` |
| Windows | `%APPDATA%\SilverSprint\logs\` |

Un fichier par jour, nommé `AAAA_MM_JJ_SilverSprintRaceLog.csv`. Les courses s'y **ajoutent** : il
n'est jamais réécrit, et le fichier de la veille n'est jamais touché.

Le dossier `races/` voisin contient un JSON par course, avec la trace complète des mesures. C'est ce
qu'il faut envoyer au développeur en cas de résultat suspect : la course peut être rejouée à
l'identique.

---

## Le vidéoprojecteur n'est pas détecté

*(La fenêtre spectacle arrive au lot 5 — cette section sera complétée à ce moment-là.)*

En attendant : le mode mono-fenêtre est le comportement par défaut, l'opérateur et l'affichage
partagent le même écran.

---

## Rien ne fonctionne et le public attend

1. Panneau matériel → **Simulateur**.
2. Lancer la course. Elle se déroulera de bout en bout, avec des cyclistes synthétiques.
3. Diagnostiquer après.

Le simulateur produit exactement les mêmes trames que le boîtier, bugs du firmware compris. Ce n'est
pas un mode dégradé bricolé : c'est le même logiciel, avec une autre source de données.
