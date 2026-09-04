## Jalon J3 — docs/05 lot 3, et le reste de l'interface operateur en marche
## normale.
##
## « Une course complete est menee de bout en bout au simulateur, sans toucher
## au clavier hors des boutons prevus, et le CSV produit est correct. »
##
## Le test respecte la lettre de l'exigence : il n'appelle AUCUNE methode du
## controleur ni du moteur. Il agit exclusivement sur les widgets — cases a
## cocher, listes deroulantes, champs, boutons — comme le ferait une main sur
## la souris. Si l'interface ne suffit pas a mener une course, le test echoue.
##
## Ce qui tourne MAL — lien perdu, disque plein, trames perdues, piste muette,
## fermeture en pleine course — vit dans `test_operateur_incidents.gd`.
extends "res://tests/support/base_operateur.gd"


func test_j3_une_course_complete_menee_uniquement_aux_boutons() -> void:
	assert_true(await _await_identified(), "le simulateur doit s'identifier")

	var roster_panel := _panel.roster_panel()
	var mode_panel := _panel.mode_panel()
	var race_panel := _panel.race_panel()
	var results_panel := _panel.results_panel()

	# --- roster : deux pistes, deux noms, deux dossards ---------------------
	_type_into(roster_panel.name_field(0), "Alice")
	_type_into(roster_panel.name_field(1), "Bob")
	roster_panel.active_check(2).button_pressed = false
	roster_panel.active_check(3).button_pressed = false
	assert_eq(_controller.roster.active_lanes(), [0, 1])
	assert_eq(roster_panel.warning_text(), "", "aucune alerte de configuration")

	# --- mode : distance, 100 m --------------------------------------------
	_select_option(mode_panel.mode_selector(), RaceConfig.Mode.DISTANCE)
	mode_panel.distance_field().value = 100.0
	assert_eq(_controller.settings.distance_m, 100.0)

	# --- le bouton START doit etre REELLEMENT actif -------------------------
	race_panel.refresh()
	assert_false(
		race_panel.start_button().disabled,
		"START desactive : %s" % _controller.start_blocked_reason()
	)

	# --- un clic, et rien d'autre ------------------------------------------
	race_panel.start_button().pressed.emit()

	var finished: Array[RaceResult] = []
	_controller.race_finished.connect(func(r: RaceResult) -> void: finished.append(r))
	for i: int in range(1200):
		await wait_physics_frames(1)
		if not finished.is_empty():
			break

	assert_false(finished.is_empty(), "la course doit se terminer seule")
	var result: RaceResult = finished[0]
	assert_eq(result.ranking.size(), 2, "deux riders classes")
	assert_false(result.interrupted, "fin normale, pas un plafond de securite")
	assert_eq(result.mode, "distance")
	# 100 m a ~45 km/h : autour de 8 s. Les deux riders du profil `egaux` sont
	# a moins d'un pour cent l'un de l'autre.
	assert_between(result.elapsed_ms, 7000, 10000)
	assert_gt(result.distance_m[result.winner()], 99.0)

	# --- l'interface a suivi ------------------------------------------------
	assert_string_contains(race_panel.notice_text(), "Terminé")
	assert_string_contains(results_panel.table_text(), "Alice")
	assert_string_contains(results_panel.table_text(), "Bob")
	assert_eq(results_panel.history_count(), 1, "la course entre dans l'historique du jour")
	assert_string_contains(results_panel.csv_path_label(), ".csv")

	# --- le CSV ------------------------------------------------------------
	var rows := _read_csv_rows()
	assert_gt(rows.size(), 3)
	assert_eq(rows[0].size(), 11, "onze colonnes, docs/02 §5")
	assert_eq(
		Array(rows[0]),
		Array(Recorder.CSV_HEADER.split(",")),
		"entete conforme"
	)

	var events: Array[String] = []
	var finish_rows: Array[PackedStringArray] = []
	for i: int in range(1, rows.size()):
		events.append(rows[i][1])
		if rows[i][1] == "RACE_FINISH":
			finish_rows.append(rows[i])

	assert_has(events, "RACE_START")
	assert_eq(events.count("RIDER_FINISH"), 2, "une ligne par franchissement")
	assert_eq(finish_rows.size(), 2, "une ligne de resultat par rider classe")

	# Le contenu, pas seulement la forme : dossards, rangs, distances.
	var winner_row := finish_rows[0]
	assert_eq(winner_row[2], "distance", "colonne mode")
	assert_eq(winner_row[9], "1", "le premier rang est ecrit")
	assert_gt(float(winner_row[5]), 99.0, "distance parcourue")
	assert_gt(float(winner_row[7]), 30.0, "vitesse moyenne plausible")
	assert_gt(float(winner_row[8]), float(winner_row[7]), "la pointe depasse la moyenne")


func test_j3_le_json_de_course_est_rejouable() -> void:
	# docs/06 §2 : chaque course devient un cas de test permanent.
	assert_true(await _await_identified())
	_panel.race_panel().start_button().pressed.emit()

	var finished: Array[RaceResult] = []
	_controller.race_finished.connect(func(r: RaceResult) -> void: finished.append(r))
	for i: int in range(2400):
		await wait_physics_frames(1)
		if not finished.is_empty():
			break
	assert_false(finished.is_empty())

	var loaded := Replay.load_file(_races.path_join("%s.json" % finished[0].uuid))
	assert_true(loaded.ok, loaded.error)
	var replayed := Replay.replay(loaded)
	assert_not_null(replayed)
	assert_eq(replayed.ranking, finished[0].ranking, "le rejeu donne le meme classement")


# =============================================================================
# Garde-fous de l'interface
# =============================================================================


func test_start_interdit_tant_que_le_lien_n_est_pas_identifie() -> void:
	# docs/01 §4 : IDENTIFIED est la SEULE condition d'autorisation du depart.
	var race_panel := _panel.race_panel()
	race_panel.refresh()
	assert_true(race_panel.start_button().disabled)
	assert_string_contains(race_panel.start_button().tooltip_text, "V:")


func test_start_est_interdit_sans_piste_active() -> void:
	assert_true(await _await_identified())
	var roster_panel := _panel.roster_panel()
	for lane: int in range(Protocol.MAX_RIDERS):
		roster_panel.active_check(lane).button_pressed = false
	_panel.race_panel().refresh()

	assert_true(_panel.race_panel().start_button().disabled)
	assert_string_contains(roster_panel.warning_text(), "Aucune piste active")
	# Le motif du refus doit etre LISIBLE : un bouton grise sans explication est
	# un appel au support en pleine soiree.
	assert_string_contains(_panel.race_panel().start_button().tooltip_text, "piste")


func test_la_poursuite_a_un_seul_rider_est_refusee() -> void:
	assert_true(await _await_identified())
	_select_option(_panel.mode_panel().mode_selector(), RaceConfig.Mode.PURSUIT)
	_panel.roster_panel().active_check(1).button_pressed = false
	_panel.race_panel().refresh()
	assert_true(_panel.race_panel().start_button().disabled)


func test_le_panneau_mode_ne_montre_que_les_reglages_du_mode_choisi() -> void:
	# Un ecran qui affiche trois reglages dont deux sans effet invite a se
	# tromper de champ.
	var mode_panel := _panel.mode_panel()
	_select_option(mode_panel.mode_selector(), RaceConfig.Mode.DISTANCE)
	assert_true(mode_panel.distance_field().visible)
	assert_false(mode_panel.gap_field().visible)

	_select_option(mode_panel.mode_selector(), RaceConfig.Mode.PURSUIT)
	assert_false(mode_panel.distance_field().visible)
	assert_true(mode_panel.gap_field().visible)
	# docs/02 §3 : les plafonds de securite sont des reglages de la poursuite.
	assert_true(mode_panel.time_cap_field().visible)
	assert_true(mode_panel.distance_cap_field().visible)
	mode_panel.time_cap_field().value = 120.0
	mode_panel.distance_cap_field().value = 2000.0
	assert_eq(_controller.settings.pursuit_time_cap_s, 120.0)
	assert_eq(_controller.settings.pursuit_distance_cap_m, 2000.0)
	assert_eq(_controller.current_config().pursuit_time_cap_s, 120.0, "la course suivante l'applique")

	_select_option(mode_panel.mode_selector(), RaceConfig.Mode.DISTANCE)
	assert_false(mode_panel.time_cap_field().visible, "sans effet hors poursuite : cache")


func test_le_panneau_materiel_explique_pourquoi_un_port_est_ignore() -> void:
	var hardware := _panel.hardware_panel()
	hardware.refresh_ports()
	assert_gt(hardware.port_list().item_count, 0)
	# En simulateur, le seul « port » est le simulateur lui-meme, et il est
	# annonce comme candidat.
	assert_string_contains(hardware.port_list().get_item_text(0), "SIMULATEUR")


func test_la_calibration_donne_un_retour_immediat_en_ticks() -> void:
	var hardware := _panel.hardware_panel()
	hardware.roller_field().value = 114.3
	assert_string_contains(hardware.ticks_hint(), "278 ticks")
	assert_string_contains(PanelHardware.CALIBRATION_HELP, "aimant")

	# Un autre rouleau change le nombre de ticks : la calibration a un effet
	# visible avant meme de lancer une course.
	hardware.roller_field().value = 200.0
	assert_false(hardware.ticks_hint().contains("278 ticks"))


func test_les_preferences_sont_ecrites_a_chaque_fin_de_course() -> void:
	# docs/02 §5 : pas seulement a la fermeture. Un plantage en soiree ne doit
	# pas perdre les noms des riders qui viennent de courir.
	var root := ProjectSettings.globalize_path(TEST_ROOT)
	var settings_path := root.path_join("settings-ecrit.json")
	var roster_path := root.path_join("roster-ecrit.json")
	for path: String in [settings_path, roster_path]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)

	var controller := AppController.new()
	controller.preferences_enabled = true
	controller.settings_path = settings_path
	controller.roster_path = roster_path
	controller.recorder_logs_dir = _logs
	controller.recorder_races_dir = _races
	add_child_autofree(controller)
	controller.set_simulation_speed(10.0)
	for i: int in range(120):
		await wait_physics_frames(1)
		if controller.link_state() == Protocol.State.IDENTIFIED:
			break
	controller.roster.rider(0).name = "Zoe"
	controller.settings.distance_m = 100.0
	assert_false(FileAccess.file_exists(roster_path), "rien d'ecrit avant la course")
	assert_true(controller.start_race())
	var finished: Array[RaceResult] = []
	controller.race_finished.connect(func(r: RaceResult) -> void: finished.append(r))
	for i: int in range(900):
		await wait_physics_frames(1)
		if not finished.is_empty():
			break
	assert_false(finished.is_empty())
	assert_true(FileAccess.file_exists(roster_path), "le roster est sur disque des la fin de course")
	assert_string_contains(FileAccess.get_file_as_string(roster_path), "Zoe")
	assert_string_contains(FileAccess.get_file_as_string(settings_path), "\"distance_m\": 100")
	for path: String in [settings_path, roster_path]:
		DirAccess.remove_absolute(path)


func test_le_test_capteurs_fait_vraiment_bouger_les_pistes() -> void:
	# docs/01 §5.7 : le firmware ne lit ses capteurs qu'en course. Le bouton
	# lance une course a blanc (x, t60, g) que le moteur n'arbitre pas, et
	# l'arrete par s. La premiere version attendait des R: au repos : elle
	# n'aurait jamais rien affiche sur le vrai boitier.
	assert_true(await _await_identified())
	var hardware := _panel.hardware_panel()
	hardware.sensor_button().button_pressed = true
	assert_true(_controller.sensor_test_active())
	# Le decompte firmware dure ~4 s ; le simulateur est a x10.
	var moved := false
	for i: int in range(300):
		await wait_physics_frames(1)
		if hardware.sensor_text(0).contains("ticks") and not hardware.sensor_text(0).contains(" 0 ticks"):
			moved = true
			break
	assert_true(moved, "la piste 1 s'anime : %s" % hardware.sensor_text(0))
	assert_eq(_controller.engine.state(), RaceEngine.State.IDLE, "le moteur n'arbitre rien")
	assert_eq(_controller.history().size(), 0, "rien n'est enregistre")

	hardware.sensor_button().button_pressed = false
	assert_false(_controller.sensor_test_active())
	await wait_physics_frames(5)
	assert_string_contains(hardware.sensor_text(0), "—", "affichage remis a zero")
	assert_eq(
		_controller.link_state(), Protocol.State.IDENTIFIED,
		"le lien est pret pour une vraie course"
	)
	assert_true(_controller.can_start_race(), "et START est possible")


func test_la_deuxieme_course_de_la_soiree_part_au_bouton_start_sans_rien_interrompre() -> void:
	# docs/02, FSM : FINISHED -> RESULTS -> NEW RACE -> IDLE. Le moteur restait
	# FINISHED pour toujours : START grise, et « Relancer » ABANDONNAIT la
	# course terminee — s au boitier, RACE_ABORTED au CSV, « COURSE
	# INTERROMPUE » sur l'ecran public — a chaque course sauf la premiere.
	assert_true(await _await_identified())
	var race_panel := _panel.race_panel()
	var aborted: Array[String] = []
	_controller.race_aborted.connect(func(note: String) -> void: aborted.append(note))
	_controller.settings.distance_m = 100.0

	race_panel.refresh()
	race_panel.start_button().pressed.emit()
	var finished: Array[RaceResult] = []
	_controller.race_finished.connect(func(r: RaceResult) -> void: finished.append(r))
	for i: int in range(900):
		await wait_physics_frames(1)
		if not finished.is_empty():
			break
	assert_eq(finished.size(), 1, "premiere course terminee")

	await wait_physics_frames(2)
	race_panel.refresh()
	assert_false(
		race_panel.start_button().disabled,
		"START est de nouveau possible : %s" % _controller.start_blocked_reason()
	)
	race_panel.start_button().pressed.emit()
	for i: int in range(900):
		await wait_physics_frames(1)
		if finished.size() >= 2:
			break
	assert_eq(finished.size(), 2, "deuxieme course terminee")
	assert_true(aborted.is_empty(), "rien n'a ete interrompu")

	# Et « Relancer » n'est meme plus PROPOSE apres une arrivee : il n'y a rien
	# a interrompre, il ne resterait que le START du bouton d'a cote. Emettre
	# `pressed` sur un bouton grise passerait outre — c'est l'etat du bouton
	# qu'on lit, comme l'operateur.
	await wait_physics_frames(2)
	race_panel.refresh()
	assert_true(race_panel.restart_button().disabled, "Relancer est grise apres une arrivee")
	assert_true(race_panel.stop_button().disabled, "STOP aussi")
	assert_string_contains(
		race_panel.restart_button().tooltip_text, "Rien à relancer", "et il dit pourquoi"
	)

	race_panel.start_button().pressed.emit()
	for i: int in range(900):
		await wait_physics_frames(1)
		if finished.size() >= 3:
			break
	assert_eq(finished.size(), 3, "troisieme course, lancee par START")
	assert_true(aborted.is_empty(), "aucun abandon dans toute la sequence")
	var events := _csv_events()
	assert_eq(events.count("RACE_START"), 3)
	assert_does_not_have(events, "RACE_ABORTED")


func test_la_politique_de_faux_depart_choisie_est_celle_qui_court() -> void:
	# Le selecteur n'etait exerce par aucun test alors que la politique a
	# maintenant des consequences visibles a l'ecran (docs/02 §4). Choisir
	# PENALITE doit aussi faire apparaitre le champ de handicap, qui ne sert
	# qu'a elle.
	var mode_panel := _panel.mode_panel()
	_select_option(mode_panel.policy_selector(), RaceConfig.FalseStartPolicy.PENALTY)
	assert_eq(_controller.settings.false_start_policy, RaceConfig.FalseStartPolicy.PENALTY)
	assert_eq(_controller.current_config().false_start_policy, RaceConfig.FalseStartPolicy.PENALTY)
	assert_true(mode_panel.penalty_field().visible, "le handicap se regle quand il s'applique")

	_select_option(mode_panel.policy_selector(), RaceConfig.FalseStartPolicy.IGNORE)
	assert_eq(_controller.settings.false_start_policy, RaceConfig.FalseStartPolicy.IGNORE)
	assert_false(mode_panel.penalty_field().visible, "et disparait quand il ne sert a rien")


func test_la_ligne_de_calibration_ne_parle_que_de_ce_qui_compte() -> void:
	# Le manuel promet « la circonference et le nombre de ticks pour 100 m et
	# pour la distance choisie ». En mode temps la distance ne decide de rien,
	# et l'annoncer la fait lire comme un objectif ; en poursuite, c'est
	# l'ecart qui compte.
	var hardware := _panel.hardware_panel()
	var mode_panel := _panel.mode_panel()

	_select_option(mode_panel.mode_selector(), RaceConfig.Mode.DISTANCE)
	mode_panel.distance_field().value = 500.0
	hardware.refresh()
	assert_string_contains(hardware.ticks_text(), "100 m =")
	assert_string_contains(hardware.ticks_text(), "500 m =")

	_select_option(mode_panel.mode_selector(), RaceConfig.Mode.TIME)
	hardware.refresh()
	assert_string_contains(hardware.ticks_text(), "100 m =", "le repere de calibration reste")
	assert_false(hardware.ticks_text().contains("500 m"), "la distance ne decide de rien ici")

	_select_option(mode_panel.mode_selector(), RaceConfig.Mode.PURSUIT)
	mode_panel.gap_field().value = 50.0
	hardware.refresh()
	assert_string_contains(hardware.ticks_text(), "écart 50 m =", "c'est l'écart qui compte")


func test_stop_ne_reste_pas_actif_apres_une_arrivee() -> void:
	# Depuis que FINISHED n'est plus « une course en cours », STOP restait
	# propose : un bouton qui invite au clic et ne fait rien. Il ne doit etre
	# actif que tant qu'il y a quelque chose a arreter.
	assert_true(await _await_identified())
	var race_panel := _panel.race_panel()
	race_panel.refresh()
	assert_true(race_panel.stop_button().disabled, "rien a arreter au repos")

	_controller.settings.distance_m = 100.0
	assert_true(_controller.start_race())
	assert_true(await _await_running(), "la course doit partir")
	race_panel.refresh()
	assert_false(race_panel.stop_button().disabled, "en course, STOP est possible")

	var finished: Array[RaceResult] = []
	_controller.race_finished.connect(func(r: RaceResult) -> void: finished.append(r))
	for i: int in range(900):
		await wait_physics_frames(1)
		if not finished.is_empty():
			break
	assert_false(finished.is_empty(), "la course se termine")
	race_panel.refresh()
	assert_true(race_panel.stop_button().disabled, "plus rien a arreter")
	assert_false(race_panel.start_button().disabled, "et la suivante peut partir")


func test_l_interface_construite_avant_l_entree_dans_l_arbre_fonctionne() -> void:
	# Regression : Godot ne declenche ni _enter_tree ni _ready de facon
	# synchrone quand on ajoute un noeud depuis SceneTree._initialize(). Un
	# outil en ligne de commande batissait donc l'interface contre un controleur
	# vide, et le panneau materiel affichait « aucun port » sans rien signaler.
	var controller := AppController.new()
	controller.preferences_enabled = false
	controller.recorder_logs_dir = _logs
	controller.recorder_races_dir = _races

	# Panneau construit AVANT toute entree dans l'arbre.
	var panel := OperatorPanel.new()
	panel.setup(controller)

	# `initialize()` a demarre le lien : le port est ouvert, mais rien n'a
	# encore ete recu, donc le depart reste interdit (docs/01 §4).
	assert_eq(controller.link_state(), Protocol.State.PORT_OPEN)
	assert_false(controller.can_start_race())
	panel.hardware_panel().refresh_ports()
	assert_gt(panel.hardware_panel().port_list().item_count, 0)
	assert_string_contains(
		panel.hardware_panel().port_list().get_item_text(0),
		"SIMULATEUR",
		"le simulateur doit s'annoncer meme avant l'entree dans l'arbre"
	)

	panel.free()
	controller.free()


# =============================================================================
# Le tableau operateur lit les memes donnees que le podium spectacle
# =============================================================================


func test_le_panneau_course_nomme_le_vainqueur_du_depart() -> void:
	# Troisieme lecteur du meme fil : le bandeau « Termine » lisait le roster
	# COURANT. Renommer les pistes pour la course suivante rebaptisait donc le
	# vainqueur de la precedente, encore affiche.
	var roster_panel := _panel.roster_panel()
	_type_into(roster_panel.name_field(0), "Carole")
	var result := RaceResult.new()
	result.mode = "distance"
	result.ranking = [0, 1]
	result.end_reason = RaceRule.EndReason.ALL_FINISHED
	result.finished_ms[0] = 8000
	result.rider_names = {0: "Alice", 1: "Bob"}
	_controller.race_finished.emit(result)

	assert_string_contains(_panel.race_panel().notice_text(), "Alice")
	assert_false(
		_panel.race_panel().notice_text().contains("Carole"),
		"le roster courant ne rebaptise pas le vainqueur"
	)


func test_le_chemin_du_json_de_la_course_affichee_est_donne() -> void:
	# DEPANNAGE : « c'est ce qu'il faut envoyer au developpeur en cas de
	# resultat suspect ». Le panneau ne donnait que le chemin du CSV, et son
	# bouton ouvrait le dossier des journaux : pour trouver le JSON, il fallait
	# deviner un dossier voisin et un nom de fichier en uuid.
	var result := RaceResult.new()
	result.mode = "distance"
	result.uuid = "20260903-011742-abcd"
	result.ranking = [0, 1]
	result.end_reason = RaceRule.EndReason.ALL_FINISHED
	result.rider_names = {0: "Alice", 1: "Bob"}

	var results := _panel.results_panel()
	results.show_result(result)
	assert_string_contains(results.files_text(), "CSV :")
	assert_string_contains(results.files_text(), "20260903-011742-abcd.json", "le fichier a envoyer")
	assert_string_contains(results.files_text(), _races, "dans le dossier des courses")


func test_le_tableau_ne_barre_pas_une_course_decidee_au_plafond() -> void:
	var config := RaceConfig.new()
	config.mode = RaceConfig.Mode.PURSUIT
	config.active_riders = [0, 1]
	var capped := RaceResult.new()
	capped.mode = "poursuite"
	capped.config = config
	capped.ranking = [0, 1]
	capped.interrupted = true
	capped.end_reason = RaceRule.EndReason.TIME_CAP
	capped.interruption_note = "plafond de sécurité atteint : plafond de durée"
	capped.rider_names = {0: "Alice", 1: "Bob"}

	_panel.results_panel().show_result(capped)
	var table := _panel.results_panel().table_text()
	assert_false(table.contains("INTERROMPUE"), "elle s'est decidee, elle n'a pas ete arretee")
	assert_string_contains(table, "plafond de durée", "et le motif se lit")

	capped.end_reason = RaceRule.EndReason.NONE
	capped.interruption_note = "arrêt opérateur"
	_panel.results_panel().show_result(capped)
	assert_string_contains(
		_panel.results_panel().table_text(), "INTERROMPUE : arrêt opérateur"
	)


func test_un_nom_long_ne_desaligne_pas_le_tableau_des_resultats() -> void:
	# Les colonnes du tableau operateur sont a largeur fixe : un nom plus long
	# que sa colonne poussait tout le reste de la ligne vers la droite, et le
	# tableau devenait illisible des qu'un seul coureur avait un nom long.
	assert_eq(
		_panel.roster_panel().name_field(0).max_length, Roster.MAX_DISPLAY_NAME,
		"la saisie s'arrete a la largeur affichable"
	)
	var result := RaceResult.new()
	result.mode = "distance"
	result.ranking = [0, 1]
	result.end_reason = RaceRule.EndReason.ALL_FINISHED
	result.finished_ms[0] = 8000
	result.finished_ms[1] = 9000
	result.rider_names = {0: "Zoe", 1: "Jean-Baptiste-Marie"}
	_panel.results_panel().show_result(result)

	var rows: Array[String] = []
	for line: String in _panel.results_panel().table_text().split("\n"):
		if line.begins_with("   1  ") or line.begins_with("   2  "):
			rows.append(line)
	assert_eq(rows.size(), 2, "deux lignes de classement")
	assert_eq(rows[0].length(), rows[1].length(), "colonnes alignees :\n%s\n%s" % [rows[0], rows[1]])


func test_le_tableau_montre_les_noms_du_depart_pas_le_roster_courant() -> void:
	# Alice et Bob ont couru ; on renomme les pistes pour la course suivante.
	# Cliquer la premiere course dans l'historique doit toujours dire Alice.
	var roster_panel := _panel.roster_panel()
	_type_into(roster_panel.name_field(0), "Carole")
	_type_into(roster_panel.name_field(1), "Dan")
	var result := RaceResult.new()
	result.mode = "distance"
	result.ranking = [1, 0]
	result.end_reason = RaceRule.EndReason.ALL_FINISHED
	result.rider_names = {0: "Alice", 1: "Bob"}
	_panel.results_panel().show_result(result)
	var table := _panel.results_panel().table_text()
	assert_string_contains(table, "Alice")
	assert_string_contains(table, "Bob")
	assert_false(table.contains("Carole"), "le roster courant ne reecrit pas l'histoire")


func test_l_historique_du_jour_survit_a_un_redemarrage() -> void:
	# Une course JSON deja sur disque, datee d'aujourd'hui : un controleur et
	# un panneau NEUFS — le logiciel vient d'etre relance — doivent la lister.
	var recorder := Recorder.new(_logs, _races)
	var config := RaceConfig.new()
	config.mode = RaceConfig.Mode.DISTANCE
	config.active_riders = [0, 1]
	config.distance_m = 100.0
	recorder.begin_race(config, {0: {"name": "Alice", "dossard": 7}})
	var result := RaceResult.new()
	result.mode = "distance"
	result.ranking = [1, 0]
	result.elapsed_ms = 8000
	result.end_reason = RaceRule.EndReason.ALL_FINISHED
	result.finished_ms[1] = 7900
	result.finished_ms[0] = 8000
	recorder.finish_race(result)

	var controller := AppController.new()
	controller.preferences_enabled = false
	controller.recorder_logs_dir = _logs
	controller.recorder_races_dir = _races
	add_child_autofree(controller)
	var panel := OperatorPanel.new()
	add_child_autofree(panel)
	panel.setup(controller)

	assert_eq(controller.history().size(), 1, "l'historique est relu au demarrage")
	assert_eq(panel.results_panel().history_count(), 1, "et le panneau le montre")
	panel.results_panel().select_history(0)
	assert_string_contains(panel.results_panel().table_text(), "tous arrivés")
	assert_string_contains(panel.results_panel().table_text(), "7.90 s")


func test_le_tableau_marque_l_instant_d_elimination_au_lieu_de_zero() -> void:
	# Un resultat de poursuite construit a la main : le survivant a un temps
	# d'arrivee, l'elimine n'en a pas mais a un instant d'elimination.
	var result := RaceResult.new()
	result.mode = "poursuite"
	result.config = RaceConfig.new()
	result.config.mode = RaceConfig.Mode.PURSUIT
	result.config.active_riders = [0, 1] as Array[int]
	result.ranking = [0, 1] as Array[int]
	result.finished_ms[0] = 15540
	result.distance_m[0] = 214.0
	result.avg_kph[0] = 49.6
	result.max_kph[0] = 58.8
	result.eliminated[1] = true
	result.eliminated_ms[1] = 14010
	result.distance_m[1] = 135.0
	result.avg_kph[1] = 34.7
	result.max_kph[1] = 41.1

	var panel := _panel.results_panel()
	panel._on_race_finished(result)
	var text := panel.table_text()

	assert_string_contains(text, "15.54 s", "le survivant a son temps d'arrivee")
	assert_string_contains(text, "14.01 s x", "l'elimine a son instant, marque")
	assert_false(text.contains("0.00 s"), "jamais 0,00 s pour un elimine")
	assert_string_contains(text, "x = éliminé", "la marque est expliquée")


func test_le_panneau_course_affiche_le_libelle_et_non_l_enum() -> void:
	# « Etat : IDLE » n'apprend rien a un operateur, et ces six mots
	# n'apparaissent nulle part dans le MANUEL : ils viennent du diagramme
	# d'etats de docs/02, qui est un document de conception.
	var race_panel := _panel.race_panel()
	assert_string_contains(race_panel.state_text(), RaceEngine.state_label(RaceEngine.State.IDLE))
	assert_false(race_panel.state_text().contains("IDLE"), "aucun nom de code a l'ecran")


func test_apres_une_arrivee_le_panneau_dit_que_le_resultat_attend_l_acquittement() -> void:
	# docs/02 §1 : `RUNNING ─▶ FINISHED ─▶ RESULTS`. RESULTS est « resultat
	# consultable, en attente d'acquittement » — un etat ou l'on SEJOURNE, le
	# temps que l'operateur regarde le classement. L'application le traversait
	# en une microseconde, au depart de la course SUIVANTE : le moteur restait
	# a FINISHED pendant toute la duree ou le podium etait a l'ecran, et l'etape
	# que le diagramme decrit n'existait nulle part.
	assert_true(await _await_identified())
	var race_panel := _panel.race_panel()
	_controller.settings.distance_m = 100.0
	assert_true(_controller.start_race())
	assert_true(await _await_running(), "la course doit partir")

	var finished: Array[RaceResult] = []
	_controller.race_finished.connect(func(r: RaceResult) -> void: finished.append(r))
	for i: int in range(900):
		await wait_physics_frames(1)
		if not finished.is_empty():
			break
	assert_false(finished.is_empty(), "la course se termine")

	race_panel.refresh()
	assert_string_contains(race_panel.state_text(), "acquitter")
	assert_false(race_panel.start_button().disabled, "la suivante peut partir")

	# Et le depart suivant acquitte : on repasse par IDLE avant d'armer.
	assert_true(_controller.start_race())
	assert_true(await _await_running(), "la seconde course part")


func test_l_interface_ne_colle_pas_aux_bords_de_la_fenetre() -> void:
	# Mesure sur une capture de la fenetre operateur : le premier pixel encre
	# etait en x = 0, le premier en y = 7. Titres et champs touchaient le bord,
	# ce qui fait « maquette » plutot qu'outil — et sur un ecran d'ordinateur
	# portable, une fenetre collee au bord se lit mal.
	# Ancres remises en haut a gauche : `_build` les pose en plein cadre, et
	# Godot refuse alors qu'on impose une taille.
	_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_panel.size = Vector2(1320, 900)
	await wait_physics_frames(2)
	var roster := _panel.roster_panel()
	assert_almost_eq(
		roster.global_position.x - _panel.global_position.x, float(OperatorPanel.MARGIN), 2.0,
		"la premiere colonne respire a gauche"
	)
	assert_almost_eq(
		roster.global_position.y - _panel.global_position.y, float(OperatorPanel.MARGIN), 2.0,
		"et en haut"
	)


func test_la_ligne_par_piste_dit_l_etat_de_chaque_coureur() -> void:
	# Le panneau Course tient une ligne par piste — distance, vitesse d'ecran,
	# et le SUFFIXE qui dit ce qui est arrive au coureur. Rien ne l'eprouvait :
	# l'accesseur existait sans aucun appelant.
	assert_true(await _await_identified())
	var race_panel := _panel.race_panel()
	_controller.roster.rider(0).name = "Lucie"
	_controller.roster.set_active(0, true)
	_controller.roster.set_active(1, true)
	race_panel.refresh()
	assert_string_contains(race_panel.lane_text(0), "P1", "la piste est nommee")
	assert_string_contains(race_panel.lane_text(0), "Lucie", "et le coureur aussi")

	_controller.settings.distance_m = 100.0
	assert_true(_controller.start_race())
	assert_true(await _await_running(), "la course doit partir")
	var finished: Array[RaceResult] = []
	_controller.race_finished.connect(func(r: RaceResult) -> void: finished.append(r))
	for i: int in range(900):
		await wait_physics_frames(1)
		if not finished.is_empty():
			break
	assert_false(finished.is_empty(), "la course se termine")
	assert_string_contains(
		race_panel.lane_text(0), "ARRIVÉ", "et la ligne dit que le coureur a franchi"
	)


func test_un_nom_tape_au_clavier_s_ecrit_dans_l_ordre() -> void:
	# Chaque frappe dans un nom emet `roster_changed`, que le panneau renvoie
	# en `refresh()`. Tant que `refresh()` reecrivait `LineEdit.text`, le
	# curseur repartait en tete apres CHAQUE lettre : « Alice » devenait
	# « ecilA », et ce nom retourne partait sur l'ecran public, au podium et
	# dans le CSV. Le defaut ne se voyait pas parce que le test posait le texte
	# d'un bloc — un geste qu'aucun operateur ne fait.
	var field := _panel.roster_panel().name_field(0)
	_type_into(field, "Alice")
	assert_eq(field.text, "Alice", "le nom s'ecrit dans l'ordre de la frappe")
	assert_eq(_controller.roster.rider(0).name, "Alice", "et le roster le retient tel quel")
	# Le curseur reste en fin de champ : l'operateur peut continuer a taper.
	assert_eq(field.caret_column, 5, "le curseur suit la frappe")

	# Une valeur venue d'AILLEURS, elle, doit bien s'imposer au champ.
	_controller.roster.rider(0).name = "Zoé"
	_panel.roster_panel().refresh()
	assert_eq(field.text, "Zoé", "un roster change hors du champ se voit quand meme")


func test_la_couleur_d_une_piste_se_choisit_et_se_remet_au_defaut() -> void:
	# L'ecran public est en face de velos reels poses sur des rouleaux, et
	# c'est le VELO qui a raison : un spectateur qui cherche « le rouge »
	# regarde la salle, pas la charte (docs/04 §2). La palette n'est donc plus
	# une contrainte, seulement un defaut — auquel un bouton ramene, ce qui est
	# le seul geste utile quand la salle change de velos.
	var roster_panel := _panel.roster_panel()
	assert_true(roster_panel.reset_button(0).disabled, "rien a remettre tant qu'on n'a rien change")

	roster_panel.color_picker(0).color_changed.emit(Color("#C81010"))
	assert_eq(_controller.roster.rider(0).color, "#C81010", "le velo rouge de la piste 1")
	roster_panel.refresh()
	assert_false(roster_panel.reset_button(0).disabled, "le bouton s'allume, la piste a change")

	roster_panel.reset_button(0).pressed.emit()
	assert_eq(_controller.roster.rider(0).color, Roster.DEFAULT_COLORS[0], "retour a la charte")
	assert_true(roster_panel.reset_button(0).disabled, "et le bouton se rendort")
	# Le selecteur suit la donnee, il ne vit pas sa vie de son cote.
	assert_true(
		roster_panel.color_picker(0).color.is_equal_approx(Color(Roster.DEFAULT_COLORS[0])),
		"le selecteur montre bien la couleur revenue"
	)


func test_deux_pistes_de_meme_couleur_sont_dites_a_l_operateur() -> void:
	# Signale, n'interdit pas. Si la salle aligne deux velos rouges,
	# l'operateur a raison contre la charte — le numero de piste et le nom
	# identifient toujours chacun (docs/03 §6). Mais un doublon involontaire
	# rend l'ecran ambigu, et cela se dit.
	var roster_panel := _panel.roster_panel()
	assert_eq(roster_panel.warning_text(), "", "rien a signaler au depart")

	roster_panel.color_picker(1).color_changed.emit(Color("#00D8F5"))
	roster_panel.refresh()
	assert_string_contains(roster_panel.warning_text(), "pistes 1 et 2")
	assert_string_contains(roster_panel.warning_text(), "se confondront")
	assert_eq(_controller.roster.rider(1).color, "#00D8F5", "la couleur est prise malgre tout")


func test_le_tableau_montre_les_dossards_du_depart_et_seulement_s_il_y_en_a() -> void:
	# L'operateur saisit un dossard, et ne le revoyait JAMAIS : il partait au
	# CSV, qu'on ouvre apres la soiree. Une faute de frappe restait donc
	# invisible jusqu'a ce que le fichier serve — c'est-a-dire trop tard.
	var results := _panel.results_panel()
	var plain := RaceResult.new()
	plain.mode = "distance"
	plain.ranking = [0, 1]
	plain.end_reason = RaceRule.EndReason.ALL_FINISHED
	plain.rider_names = {0: "Alice", 1: "Bob"}
	results.show_result(plain)
	assert_false(results.table_text().contains("doss."), "pas de colonne sans dossard")

	# LA COLONNE N'APPARAIT QUE SI ELLE SERT. La plupart des soirees s'en
	# passent, et une colonne vide en permanence n'est pas une information.
	var numbered := RaceResult.new()
	numbered.mode = "distance"
	numbered.ranking = [0, 1]
	numbered.end_reason = RaceRule.EndReason.ALL_FINISHED
	numbered.rider_names = {0: "Alice", 1: "Bob"}
	numbered.rider_dossards = {0: "42", 1: ""}
	results.show_result(numbered)
	assert_string_contains(results.table_text(), "doss.", "la colonne apparait")
	assert_string_contains(results.table_text(), "42", "et le numero avec")

	# LE DOSSARD DU DEPART, jamais celui du roster courant. Renumeroter les
	# pistes pour la manche suivante ne doit pas reetiqueter celle qui vient de
	# courir — la meme faute a ete commise deux fois sur les noms.
	_panel.roster_panel().name_field(0).text = ""
	_controller.roster.rider(0).dossard = "99"
	results.show_result(numbered)
	assert_string_contains(results.table_text(), "42", "toujours le numero du depart")
	assert_false(results.table_text().contains("99"), "et jamais celui d'apres")
