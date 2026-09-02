# Traces de référence

Deux courses réelles, enregistrées **avant** plusieurs changements du moteur : elles ne portent ni
`eliminated_ms` ni `hardware_finishes`, ajoutés depuis. Ne pas les régénérer — c'est précisément leur
ancienneté qui a de la valeur.

`tests/unit/test_traces_de_reference.gd` les rejoue à chaque exécution de la suite : le format doit
rester lisible, et le moteur d'aujourd'hui doit redonner le classement d'hier sur les mêmes trames.
Un test généré ne peut prouver ni l'un ni l'autre, puisqu'il produit sa trace avec le code du jour.

Elles se rejouent aussi à la main :

```sh
godot --headless --script tools/ss_replay.gd -- --dossier tests/fixtures --detail
```
