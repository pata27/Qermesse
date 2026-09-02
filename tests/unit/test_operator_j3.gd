## Jalon J3 — docs/05 lot 3.
##
## « Une course complete est menee de bout en bout au simulateur, sans toucher
## au clavier hors des boutons prevus, et le CSV produit est correct. »
##
## Le test respecte la lettre de l'exigence : il n'appelle AUCUNE methode du
## controleur ni du moteur. Il agit exclusivement sur les widgets — cases a
## cocher, listes deroulantes, champs, boutons — comme le ferait une main sur
## la souris. Si l'interface ne suffit pas a mener une course, le test echoue.
extends GutTest

const TEST_ROOT := "user://test_j3"

var _controller: AppController
var _panel: OperatorPanel
var _logs: String
var _races: String


func before_each() -> void:
	_logs = ProjectSettings.globalize_path(TEST_ROOT).path_join("logs")
	_races = ProjectSettings.globalize_path(TEST_ROOT).path_join("races")
	_wipe()

	_controller = AppController.new()
	# Coutures de test : ni les reglages de l'utilisateur, ni ses donnees.
	_controller.preferences_enabled = false
	_controller.recorder_logs_dir = _logs
	_controller.recorder_races_dir = _races
	add_child_autofree(_controller)

	_panel = OperatorPanel.new()
	add_child_autofree(_panel)
	_panel.setup(_controller)
	# Le temps du simulateur est accelere : une course de 13 s se deroule en
	# 1,5 s. Rien d'autre n'est modifie.
	_controller.set_simulation_speed(10.0)


func after_all() -> void:
	_wipe()


func _wipe() -> void:
	for dir: String in [_logs, _races]:
		if DirAccess.dir_exists_absolute(dir):
			for name: String in DirAccess.get_files_at(dir):
				DirAccess.remove_absolute(dir.path_join(name))


func _await_identified() -> bool:
	for i: int in range(120):
		await wait_frames(1)
		if _controller.link_state() == Protocol.State.IDENTIFIED:
			return true
	return false


## Saisit un texte comme le ferait un operateur : la valeur ET le signal.
func _type_into(field: LineEdit, text: String) -> void:
	field.text = text
	field.text_changed.emit(text)


func _select_option(button: OptionButton, id: int) -> void:
	var index := button.get_item_index(id)
	button.select(index)
	button.item_selected.emit(index)


func _read_csv_rows() -> Array[PackedStringArray]:
	var path := _controller.recorder.csv_path()
	var rows: Array[PackedStringArray] = []
	if path.is_empty() or not FileAccess.file_exists(path):
		return rows
	var file := FileAccess.open(path, FileAccess.READ)
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() > 1:
			rows.append(row)
	file.close()
	return rows


# =============================================================================
# J3 — la course complete
# =============================================================================

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
		await wait_frames(1)
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
	assert_string_contains(race_panel.notice_text(), "Termine")
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
		await wait_frames(1)
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


func test_stop_interrompt_la_course_et_le_csv_le_dit() -> void:
	assert_true(await _await_identified())
	var race_panel := _panel.race_panel()
	race_panel.refresh()
	race_panel.start_button().pressed.emit()
	await wait_frames(30)

	race_panel.stop_button().pressed.emit()
	assert_eq(_controller.engine.state(), RaceEngine.State.IDLE)

	var events: Array[String] = []
	for row: PackedStringArray in _read_csv_rows():
		events.append(row[1])
	assert_has(events, "RACE_ABORTED")


# =============================================================================
# Lien perdu pendant la course — docs/01 §6.2
# =============================================================================


func _await_running() -> bool:
	for i: int in range(300):
		await wait_frames(1)
		if _controller.engine.state() == RaceEngine.State.RUNNING:
			return true
	return false


func _csv_events() -> Array[String]:
	var events: Array[String] = []
	for row: PackedStringArray in _read_csv_rows():
		events.append(row[1])
	return events


func test_lien_perdu_puis_revenu_sous_trois_secondes_la_course_reprend() -> void:
	assert_true(await _await_identified())
	var notices: Array[String] = []
	_controller.notice.connect(func(text: String) -> void: notices.append(text))
	var finished: Array[RaceResult] = []
	_controller.race_finished.connect(func(r: RaceResult) -> void: finished.append(r))
	_controller.settings.distance_m = 100.0
	assert_true(_controller.start_race())
	assert_true(await _await_running(), "la course doit partir")
	await wait_frames(10)

	_controller.simulate_link_loss()
	await wait_frames(2)
	assert_eq(_controller.link_state(), Protocol.State.LINK_LOST)
	assert_has(notices, "LIEN PERDU", "bandeau d'alerte")
	assert_eq(_controller.engine.state(), RaceEngine.State.RUNNING, "gel, pas abandon")

	await wait_seconds(0.5)
	_controller.simulate_link_return()
	for i: int in range(600):
		await wait_frames(1)
		if not finished.is_empty():
			break
	assert_false(finished.is_empty(), "la course reprend et se termine")
	assert_false(finished[0].interrupted, "fin normale : rien n'est perdu, elapsedMs est absolu")
	var events := _csv_events()
	assert_has(events, "LINK_LOST")
	assert_has(events, "RACE_FINISH")
	assert_does_not_have(events, "RACE_ABORTED")


func test_lien_perdu_au_dela_de_trois_secondes_la_course_est_abandonnee() -> void:
	assert_true(await _await_identified())
	var aborted: Array[String] = []
	_controller.race_aborted.connect(func(note: String) -> void: aborted.append(note))
	_controller.settings.distance_m = 100.0
	assert_true(_controller.start_race())
	assert_true(await _await_running(), "la course doit partir")
	await wait_frames(10)

	_controller.simulate_link_loss()
	await wait_seconds(2.5)
	assert_eq(_controller.engine.state(), RaceEngine.State.RUNNING, "encore dans le delai de grace")
	await wait_seconds(0.8)
	assert_eq(_controller.engine.state(), RaceEngine.State.IDLE, "au-dela de 3 s : abandon")
	assert_eq(aborted.size(), 1)
	assert_string_contains(aborted[0], "grace")
	var events := _csv_events()
	assert_has(events, "LINK_LOST")
	assert_eq(events[events.size() - 1], "RACE_ABORTED", "la derniere ligne du CSV")


func test_un_tick_fantome_est_loggue_et_compte_au_panneau_materiel() -> void:
	# docs/01 §6.3 et docs/06 : « tout rejet loggue et visible dans le panneau
	# materiel ». Un seul tick fantome passe la tolerance — c'est voulu — ;
	# une rafale de rebonds, non.
	assert_true(await _await_identified())
	_controller.settings.distance_m = 100.0
	assert_true(_controller.start_race())
	assert_true(await _await_running(), "la course doit partir")
	await wait_frames(10)
	assert_eq(_controller.rejected_ticks(), 0)

	for i: int in range(12):
		_controller.simulate_phantom_tick(1)
	await wait_frames(5)
	assert_gt(_controller.rejected_ticks(), 0, "la rafale est rejetee")
	assert_string_contains(_controller.last_rejection(), "piste 2")
	assert_has(_csv_events(), "TICK_REJECTED", "loggue")
	_panel.hardware_panel().refresh()
	assert_string_contains(_panel.hardware_panel().stats_text(), "rejet")
	assert_string_contains(_panel.hardware_panel().stats_text(), "piste 2")


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
	assert_string_contains(panel.results_panel().table_text(), "tous arrives")
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
	assert_string_contains(text, "x = elimine", "la marque est expliquee")
