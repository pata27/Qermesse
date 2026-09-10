# Qermesse — Brief de développement

> **À lire en premier, intégralement, avant toute action.**
> Ce dossier `docs/` est la source de vérité du projet. Les documents `01` et `02` sont **normatifs** :
> on ne s'en écarte pas sans mettre à jour le document d'abord.

## Ce qu'on fait

Refonte complète du logiciel de course de rouleaux **SilverSprint** (goldsprints).
Le matériel et le firmware Arduino existants sont **conservés à l'identique**. Tout le logiciel PC
est réécrit : nouvelle stack, vue 3D immersive, trois modes de jeu, qualité professionnelle,
multiplateforme natif Windows / Linux / macOS.

## Décisions déjà prises — ne pas rouvrir

| Sujet | Décision |
|---|---|
| Moteur | **Godot 4.5**, GDScript, avec un module **GDExtension C++** pour le port série |
| Firmware Arduino | **conservé tel quel**, non modifié |
| Direction artistique | **vélodrome stylisé néon/arcade**, low-poly, haute lisibilité |
| Riders | **1 à 4**, configurables individuellement |
| Écrans | **fenêtre opérateur + fenêtre spectacle** plein écran |
| Simulateur | **intégré et obligatoire**, dès le lot 1 |
| Modes | distance, temps, **poursuite** (nouveau) |

## Les deux découvertes qui structurent tout le projet

L'analyse du code v1 (`/home/antoine/Code/SilverSprint`) a mis au jour deux faits qui changent
l'architecture. Ils sont détaillés dans `01` §5.

1. **Le firmware ne sait pas combien de riders sont actifs.** En mode distance, il attend que les
   4 pistes aient franchi la ligne pour terminer la course. Avec 2 riders, **la course ne se termine
   jamais** — c'est le bug d'usage majeur du logiciel existant.
2. **Le firmware ne connaîtra jamais le mode poursuite**, puisqu'on ne le modifie pas.

→ **Conséquence : le PC devient autoritaire.** L'Arduino est traité comme un simple capteur qui
fournit un flux de ticks cumulés horodatés à 100 Hz, cadence le décompte et pilote les LED.
**Tout l'arbitrage de course est calculé sur le PC**, qui envoie `s` quand *lui* décide que c'est fini.
Un développeur qui ignore ce point reproduira mécaniquement les bugs de la v1.

## L'erreur à ne pas répéter

Le prototype v2 (`/home/antoine/Code/SilverSprint-v2`) a consacré sa dernière session à embellir
l'affichage — vélo animé, halos, traînées — alors que la chaîne de données qu'il visualisait
**n'avait jamais été validée contre un Arduino réel**. Il s'arrête littéralement sur un commit
« mode mock, no Arduino needed ». Le parseur, pur et sans risque, avait 7 tests ; le threading série,
le vrai risque d'un dispositif de course en direct, en avait zéro.

D'où la règle numéro un du projet : **la donnée avant le pixel**. Aucun travail de rendu 3D avant
que le lien série soit validé sur le matériel réel (jalon J1) et que le cœur métier soit vert (J2).

## Ordre de lecture

| Doc | Contenu | Statut |
|---|---|---|
| `01-PROTOCOLE-HARDWARE.md` | contrat série, trames, handshake, limites firmware | **normatif** |
| `02-MODES-DE-JEU.md` | FSM, règles des 3 modes, faux départ, persistance | **normatif** |
| `03-ARCHITECTURE.md` | stack, arborescence, flux de données, GDExtension, simulateur | directeur |
| `04-DIRECTION-ARTISTIQUE.md` | palette, scène 3D, caméra, habillage, audio, budget perf | directeur |
| `05-PLAN-EXECUTION.md` | 7 lots, jalons vérifiables, charge, dépendances | directeur |
| `06-QUALITE-RISQUES.md` | règles de dev, tests, CI, risques, décisions en attente | directeur |

## Méthode de travail attendue

* Avancer **lot par lot** dans l'ordre de `05`. Cocher `tasks/todo.md` au fil de l'eau.
* **Ne jamais cocher un jalon sans preuve** : sortie de test, capture d'écran, ou vidéo.
* En cas de correction reçue, écrire la leçon dans `tasks/lessons.md` et la relire en début de session.
* Si une spec est fausse ou incomplète, **corriger le document d'abord**, coder ensuite.
* Si quelque chose part de travers, s'arrêter et re-planifier plutôt que de forcer.

## Points ouverts

Cinq décisions restent à confirmer avec l'utilisateur — elles sont listées dans `06` §5.
Aucune ne bloque le démarrage : **les lots 0 à 2 peuvent commencer immédiatement.**
