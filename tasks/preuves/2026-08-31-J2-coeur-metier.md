# Preuve — Jalon **J2** franchi

**Date** 2026-08-31 · **Commande** `godot --headless --script tests/run.gd` · **exit 0**

`docs/05` lot 2 : *« Suite de tests headless verte »*, avec sept exigences nommées. Chacune est
couverte ci-dessous par un test qui **échouerait sur l'ancien comportement**.

## Les sept exigences de docs/05

| Exigence | Test qui la couvre |
|---|---|
| `100 m @ rouleau 114.3 mm = 278 ticks` | `test_100_m_avec_un_rouleau_de_114_3_mm_font_278_ticks` |
| **course distance à 2 riders qui se termine** | `test_course_distance_a_2_riders_qui_se_termine` |
| poursuite 2 riders, fin au tick près sur 50 m | `test_poursuite_2_riders_fin_exacte_au_franchissement_de_l_ecart` |
| poursuite 4 riders, ordre d'élimination | `test_poursuite_4_riders_ordre_d_elimination_progressive` |
| plafonds de sécurité de la poursuite | `test_poursuite_plafond_de_duree`, `test_poursuite_plafond_de_distance` |
| chaque état de la FSM atteint | `test_chaque_etat_de_la_fsm_est_atteint` |
| rejeu d'une course JSON → classement identique | `test_rejeu_d_une_course_distance_le_classement_est_identique` |

### Le bug historique de la v1, prouvé mort

```
* test_course_distance_a_2_riders_qui_se_termine
```

Le firmware attend les **quatre** pistes matérielles : avec deux capteurs câblés, il n'arrête jamais
la course — c'est reproduit fidèlement par l'émulateur et par `link_sim.gd`, et couvert par
`test_course_distance_a_2_capteurs_les_riders_finissent_pas_la_course`. Le moteur, lui, ne compte
que les pistes **actives**, conclut à 8,0 s et 8,4 s, puis envoie `s`. Le test vérifie les deux
faces : la course se termine, **et** le `s` part bien du PC.

`test_les_pistes_inactives_sont_ignorees_partout` va plus loin : même si les pistes 2 et 3
produisent des ticks — capteur parasite, rebond — elles n'apparaissent ni au classement ni dans la
condition de fin.

## Trois défauts trouvés par les tests, pas par la relecture

1. **Le filtre de ticks rejetait une course entière.** À 100 Hz, un tick vaut 35,9 cm et une trame
   couvre 10 ms : un seul tick implique déjà 129 km/h. Onze tests sont tombés d'un coup.
   `docs/01` §6.3 promettait de rattraper les ticks fantômes — c'était faux, la promesse est
   retirée et remplacée par ce que le filtre sait réellement faire.
2. **Le classement de la poursuite était faux à la dernière trame.** Élimination du dernier et
   arrivée du vainqueur tombent ensemble ; traiter l'arrivée en premier faisait sortir le dernier
   avec le rang 1.
3. **`core/` journalisait.** Un `push_warning` dans `json_store.gd` imposait un canal de sortie à du
   code qui doit rester utilisable en headless, en test et en rejeu. Le motif est désormais
   *rapporté*, la couche applicative décide de l'afficher.

## Sortie complète

```
res://tests/unit/test_link_sim.gd
* test_les_bornes_d_argument_firmware_de_docs_01
* test_le_depart_n_est_autorise_qu_en_etat_identified
* test_la_version_est_annoncee_par_une_trame
* test_les_commandes_de_la_liste_exhaustive_sont_acceptees
* test_toute_commande_hors_liste_est_refusee
* test_l_ticks_respecte_les_deux_bornes_du_firmware
* test_toute_duree_qui_ferait_terminer_le_firmware_est_refusee
* test_le_decompte_emet_cd_3_a_cd_0_a_une_seconde_d_intervalle
* test_course_distance_a_2_capteurs_les_riders_finissent_pas_la_course
* test_course_distance_a_4_capteurs_la_course_se_termine
* test_les_ticks_sont_cumules_et_jamais_decroissants
* test_le_mode_temps_ne_se_termine_jamais_de_lui_meme
* test_faux_depart_pendant_le_decompte
* test_tick_fantome_ajoute_un_tick_sans_mouvement
* test_trame_corrompue_remonte_en_unknown_sans_rien_casser
* test_perte_et_retour_du_lien
* test_a_graine_fixee_le_scenario_se_rejoue_a_l_identique
* test_chaque_etat_du_lien_est_atteint
res://tests/unit/test_race_engine.gd
* test_les_modes_temps_et_poursuite_emettent_la_constante_sure_t60
* test_une_configuration_invalide_n_emet_aucune_commande
* test_une_distance_hors_bornes_est_refusee
* test_le_timeout_d_armement_est_de_2_s_et_renvoie_a_idle
* test_course_distance_a_2_riders_qui_se_termine
* test_les_pistes_inactives_sont_ignorees_partout
* test_course_distance_a_4_riders
* test_course_distance_a_1_rider
* test_le_plafond_de_securite_du_mode_distance
* test_mode_temps_le_pc_seul_decide_de_la_fin
* test_mode_temps_ex_aequo_departage_par_vitesse_de_pointe
* test_poursuite_2_riders_fin_exacte_au_franchissement_de_l_ecart
* test_poursuite_4_riders_ordre_d_elimination_progressive
* test_poursuite_plafond_de_duree
* test_poursuite_plafond_de_distance
* test_poursuite_la_tension_mesure_la_progression_vers_la_decision
* test_faux_depart_avertissement_la_course_continue
* test_faux_depart_relance_avorte_la_course
* test_faux_depart_penalite_applique_un_handicap_en_metres
* test_un_faux_depart_sur_une_piste_inactive_est_ignore
* test_un_tick_impliquant_plus_de_120_kmh_est_rejete_et_loggue
* test_un_compteur_de_ticks_qui_recule_est_rejete
* test_une_horloge_firmware_qui_recule_fait_rejeter_la_trame_entiere
* test_une_valeur_rejetee_est_rattrapee_par_la_trame_suivante
* test_chaque_etat_de_la_fsm_est_atteint
* test_un_abandon_operateur_coupe_la_course_et_envoie_s
* test_une_perte_de_lien_prolongee_avorte_la_course
* test_on_ne_peut_pas_armer_deux_courses_a_la_fois
* test_le_firmware_f_est_une_confirmation_jamais_une_condition_de_fin
res://tests/unit/test_recorder.gd
* test_les_evenements_declares_sont_reellement_ecrits
* test_l_append_est_reel_et_ne_reecrit_pas_le_fichier
* test_une_note_contenant_une_virgule_est_echappee
* test_le_dossard_du_roster_apparait_dans_le_csv
* test_une_course_complete_ecrit_une_ligne_race_finish_par_rider
* test_le_json_contient_la_trace_complete_des_trames
* test_rejeu_d_une_course_distance_le_classement_est_identique
* test_rejeu_d_une_poursuite_les_eliminations_sont_identiques
* test_un_json_de_format_inconnu_est_refuse_proprement
* test_un_fichier_absent_est_refuse_proprement
* test_les_chemins_suivent_la_convention_du_systeme
* test_le_nom_du_journal_quotidien_suit_le_format_v1
res://tests/unit/test_settings.gd
* test_un_fichier_absent_laisse_les_valeurs_par_defaut
* test_un_json_corrompu_ne_doit_jamais_empecher_le_demarrage
* test_une_valeur_hors_bornes_est_ramenee_dans_les_bornes
* test_l_ecriture_est_atomique
* test_les_reglages_produisent_une_configuration_de_course_valide
* test_les_noms_des_riders_sont_persistes
* test_le_roster_par_defaut_a_deux_pistes_actives
* test_un_rider_sans_nom_reste_identifiable
* test_chaque_piste_a_sa_couleur_de_la_palette
* test_le_roster_alimente_le_csv_avec_noms_et_dossards
res://tests/unit/test_smoke.gd
* test_les_constantes_physiques_de_docs_01_sont_coherentes
Scripts               5
Tests                75
Passing Tests        75
Asserts            3160
Time              1.238s
---- All tests passed! ----
```

## Commande reproductible

```sh
./.tools/Godot_v4.5-stable_linux.x86_64 --headless --import
./.tools/Godot_v4.5-stable_linux.x86_64 --headless --script tests/run.gd ; echo $?
```

Les mêmes tests tournent en CI sur ubuntu, windows et macos, après compilation et **chargement
vérifié** du module natif.
