# Preuve du jalon J5 — habillage, poursuite, audio, deux fenêtres

> **Énoncé** (`docs/05` §Lot 5) : « Les trois modes tournent en configuration deux écrans, avec le
> son. » Preuve attendue : vidéo.

Date : 2026-09-02. Tout ce qui suit a été produit avec `--audio-driver Dummy` : **aucun son n'est
sorti de la machine** pendant la production de ces preuves — contrainte de l'utilisateur, qui
travaille en espace ouvert.

## 1. Les trois modes — vidéo

`tasks/preuves/j5-trois-modes.mp4` — 36 s, 1280×720, 30 i/s : trois séquences de 12 s
enchaînées, cartouche du mode incrusté en bas à droite.

| Séquence | Scénario | Ce qu'on y voit |
|---|---|---|
| distance | 4 coureurs, 130 m, profil `deux-groupes` | décompte plein écran, scission 2+2, cartes compactes, arrivée |
| temps | 4 coureurs, 12 s, profil `ecart-leger` | « reste N s », classement par distance |
| poursuite | 4 coureurs, écart 50 m, profil `eparpille` | écart géant au centre, barre par poursuivant, éliminations |

Reproductible : `tools/ss_race3d_demo.gd --video <dossier> --images 360 --mode-course <mode> …`
puis `ffmpeg` (commande dans l'historique du dépôt, commit de cette preuve).

## 2. Captures fixes, par élément de la spec (`docs/04` §5)

| Élément | Preuve |
|---|---|
| Décompte plein écran sur les trames `CD:` | `images/lot5-decompte.png` |
| Poursuite : écart au centre, barre signée −G…+G | `images/lot5-poursuite.png` |
| Photo-finish : plan latéral, ralenti | `images/lot5-photo-finish.png` |
| Podium — temps, moyenne, pointe | `images/lot5-podium.png` |
| Podium en mode temps — classé par distance | `images/lot5-podium-temps.png` |
| Podium en poursuite — instant d'élimination et distance | `images/lot5-podium-poursuite.png` |
| Cartes compactes en mode scindé | `images/lot5-cartes-compactes.png` |

## 3. Deux fenêtres

`images/lot5-deux-fenetres.png` : la fenêtre opérateur et la fenêtre spectacle sur une même course,
même chrono des deux côtés. Vérifié par `Window.is_embedded() == false` et un identifiant système
de fenêtre distinct — il a fallu `display/window/subwindows/embed_subwindows=false`, sans quoi Godot
dessine la seconde fenêtre À L'INTÉRIEUR de la première.

Sous Wayland, l'écran et le plein écran sont du ressort du compositeur ; vérifié sous Hyprland
0.56 avec la souris sur un autre écran que celui visé — recette dans `docs/DEPANNAGE.md`.

## 4. Le son — ce que cette preuve dit, et ce qu'elle ne dit pas

Le son est **synthétisé** (`audio/sound_forge.gd`) et piloté par les signaux du contrôleur
(`audio/race_audio.gd`) : nappe indexée sur la vitesse — sur l'écart en poursuite —, bips de
décompte, klaxon, cloche des 50 derniers mètres, clameurs, vent, et la coupure globale d'un bouton
(`docs/04` §6). Il démarre **muet par défaut**.

Ce qui est vérifié : 7 tests headless sur la synthèse (format, absence d'écrêtage, boucles sans
clic, déterminisme, coupure par défaut), et dans l'application réelle la présence du bus `Course`
et son état coupé. Ce qui n'est **pas** vérifié ici : l'écoute. Personne n'a entendu ces sons —
c'était la règle. Le jalon est franchi sur pièces ; l'écoute se fera à la recette, quand le son
pourra sortir.

## 5. Ce qui reste ouvert

**J1** — le boîtier réel n'a jamais été branché. Rien de ce qui précède ne vaut recette matériel.
