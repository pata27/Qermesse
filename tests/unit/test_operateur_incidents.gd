## Ce qui tourne mal a l'interface operateur.
##
## Separe de `test_operator_j3.gd`, qui decrit la marche normale : ici on coupe
## le lien, on remplit le disque, on perd des trames, on coche une piste vide,
## on ferme le logiciel en pleine course. Chacun de ces cas doit se voir a
## l'ecran et laisser une trace exploitable — c'est ce que `DEPANNAGE.md`
## promet a l'operateur.
extends "res://tests/support/base_operateur.gd"


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


# =============================================================================
# Ce qui tourne mal se dit a l'operateur — jamais en silence
# =============================================================================


func test_des_reglages_corrompus_demarrent_par_defaut_et_le_disent() -> void:
	var settings_path := ProjectSettings.globalize_path(TEST_ROOT).path_join("settings-casse.json")
	var file := FileAccess.open(settings_path, FileAccess.WRITE)
	file.store_string("{ \"mode\": 2, \"distance_m\": ")  # coupe en pleine ecriture
	file.close()

	var controller := AppController.new()
	controller.preferences_enabled = true
	controller.settings_path = settings_path
	controller.roster_path = ProjectSettings.globalize_path(TEST_ROOT).path_join("roster-absent.json")
	controller.recorder_logs_dir = _logs
	controller.recorder_races_dir = _races
	add_child_autofree(controller)
	var panel := OperatorPanel.new()
	add_child_autofree(panel)
	panel.setup(controller)

	assert_eq(controller.settings.mode, RaceConfig.Mode.DISTANCE, "valeurs par defaut")
	assert_eq(controller.startup_problems().size(), 1, "le roster absent n'est pas un probleme")
	assert_string_contains(panel.race_panel().notice_text(), "REGLAGES")
	assert_string_contains(panel.race_panel().notice_text(), "JSON invalide")
	DirAccess.remove_absolute(settings_path)


func test_un_journal_impossible_a_ecrire_est_signale_en_fin_de_course() -> void:
	# Un FICHIER a la place du dossier des journaux : le disque plein en
	# miniature. Le classement doit s'afficher, et l'operateur doit savoir
	# qu'il n'est pas sur disque.
	var blocked := ProjectSettings.globalize_path(TEST_ROOT).path_join("logs-bloque")
	var file := FileAccess.open(blocked, FileAccess.WRITE)
	file.store_string("pas un dossier")
	file.close()

	var controller := AppController.new()
	controller.preferences_enabled = false
	controller.recorder_logs_dir = blocked
	controller.recorder_races_dir = _races
	add_child_autofree(controller)
	var notices: Array[String] = []
	controller.notice.connect(func(text: String) -> void: notices.append(text))
	controller.set_simulation_speed(10.0)
	for i: int in range(120):
		await wait_frames(1)
		if controller.link_state() == Protocol.State.IDENTIFIED:
			break
	controller.settings.distance_m = 100.0
	assert_true(controller.start_race())
	var finished: Array[RaceResult] = []
	controller.race_finished.connect(func(r: RaceResult) -> void: finished.append(r))
	for i: int in range(900):
		await wait_frames(1)
		if not finished.is_empty():
			break
	assert_false(finished.is_empty(), "la course se termine et se classe")
	var said := false
	for text: String in notices:
		if text.begins_with("ENREGISTREMENT"):
			said = true
	assert_true(said, "l'operateur sait que rien n'est ecrit")
	DirAccess.remove_absolute(blocked)


func test_une_alerte_n_est_pas_effacee_par_le_message_suivant() -> void:
	# Le bandeau n'affichait QUE le dernier message. Depuis que le logiciel
	# signale les pistes muettes, les pointes suspectes et les trames perdues,
	# l'alerte qui compte disparaissait derriere le bavardage suivant — et
	# c'est la plus grave qui a le plus de chances d'etre recouverte.
	var race_panel := _panel.race_panel()
	_controller.notice.emit("TRAMES PERDUES : la machine ne suit plus le flux du boitier.")
	for i: int in range(3):
		_controller.notice.emit("tick rejete : piste 2, %d" % i)

	assert_string_contains(race_panel.notice_text(), "TRAMES PERDUES", "l'alerte tient")
	assert_string_contains(race_panel.notice_text(), "tick rejete : piste 2, 2", "le dernier aussi")

	# Le journal reste court : c'est un bandeau, pas une console.
	assert_lt(race_panel.notice_text().split("\n").size(), 8)

	# Une nouvelle course repart d'une ardoise propre.
	_controller.race_state_changed.emit(RaceEngine.State.IDLE, RaceEngine.State.ARMING)
	assert_false(race_panel.notice_text().contains("TRAMES PERDUES"))


func test_des_trames_perdues_sont_signalees_pendant_la_course() -> void:
	# DEPANNAGE : « `perdues` non nulle : la machine n'arrive plus a suivre le
	# flux. C'est LE SEUL CAS qui fausse reellement une mesure. » Le compteur
	# vivait dans une ligne de statistiques que personne ne lit pendant une
	# soiree — le defaut le plus grave etait le plus discret.
	assert_true(await _await_identified())
	var notices: Array[String] = []
	_controller.notice.connect(func(text: String) -> void: notices.append(text))
	_controller.settings.distance_m = 500.0
	assert_true(_controller.start_race())
	assert_true(await _await_running(), "la course doit partir")

	_controller.simulate_dropped_frames(3)
	var warned := ""
	for i: int in range(120):
		await wait_frames(1)
		for text: String in notices:
			if text.begins_with("TRAMES PERDUES"):
				warned = text
		if not warned.is_empty():
			break
	assert_false(warned.is_empty(), "la perte est signalee : %s" % str(notices))
	assert_string_contains(warned, "fausse")

	# Une seule alerte par course : le compteur ne redescend jamais.
	var before := notices.size()
	_controller.simulate_dropped_frames(2)
	await wait_frames(10)
	assert_eq(notices.size(), before, "on ne repete pas a chaque image")
	_controller.stop_race()


func test_une_pointe_suspecte_remonte_a_l_operateur() -> void:
	var notices: Array[String] = []
	_controller.notice.connect(func(text: String) -> void: notices.append(text))
	_controller.engine.speed_implausible.emit(1, 104.0)
	assert_eq(notices.size(), 1)
	assert_string_contains(notices[0], "PISTE 2")
	assert_string_contains(notices[0], "104 km/h")
	assert_string_contains(notices[0], "conservee", "on ne jette pas la mesure")


func test_une_piste_cochee_qui_ne_bouge_pas_est_signalee() -> void:
	# DEPANNAGE, « la course ne se termine jamais » : la fiche demande a
	# l'operateur de verifier lui-meme qu'aucune piste cochee n'est vide. C'est
	# le bug de la v1 sous une autre forme — en distance, le PC attend TOUTES
	# les pistes actives, et une piste sans coureur les fait attendre jusqu'au
	# plafond de dix minutes, public compris. Le logiciel peut le voir.
	assert_true(await _await_identified())
	# Trois pistes cochees, mais un boitier a deux capteurs cables.
	_controller.roster.set_active(2, true)
	_controller.set_simulator_riders(2)
	_controller.settings.distance_m = 500.0

	var notices: Array[String] = []
	_controller.notice.connect(func(text: String) -> void: notices.append(text))
	assert_true(_controller.start_race())
	assert_true(await _await_running(), "la course doit partir")

	var warned := ""
	for i: int in range(900):
		await wait_frames(1)
		for text: String in notices:
			if text.begins_with("PISTE 3"):
				warned = text
		if not warned.is_empty():
			break
	assert_false(warned.is_empty(), "la piste muette est signalee : %s" % str(notices))
	assert_string_contains(warned, "aucun tick")
	_controller.stop_race()


func test_fermer_le_logiciel_pendant_une_course_arrete_le_boitier() -> void:
	# A la fermeture, seuls les reglages etaient sauves. Le `s` ne partait pas :
	# le firmware restait en course, LED allumees, et la sequence d'armement du
	# lancement suivant tombait sur une course deja lancee (docs/01 §5.4). La
	# trace de la course en cours etait perdue avec.
	assert_true(await _await_identified())
	_controller.settings.distance_m = 500.0
	assert_true(_controller.start_race())
	assert_true(await _await_running(), "la course doit partir")
	await wait_frames(20)

	var commands: Array[String] = []
	_controller.engine.command_requested.connect(func(c: String) -> void: commands.append(c))
	_controller.shutdown()

	assert_has(commands, "s", "le boitier est arrete")
	assert_eq(_controller.engine.state(), RaceEngine.State.IDLE)
	assert_eq(DirAccess.get_files_at(_races).size(), 1, "et la trace est ecrite")
	assert_has(_csv_events(), "RACE_ABORTED")


func test_fermer_le_logiciel_hors_course_n_ecrit_rien() -> void:
	assert_true(await _await_identified())
	var before := DirAccess.get_files_at(_races).size()
	_controller.shutdown()
	assert_eq(DirAccess.get_files_at(_races).size(), before, "rien a arreter, rien a ecrire")


func test_une_course_interrompue_garde_sa_trace_rejouable() -> void:
	# DEPANNAGE : « le JSON d'une course est ce qu'il faut envoyer au
	# developpeur, la course peut etre rejouee a l'identique ». Une course
	# ARRETEE — lien perdu, arret operateur — n'en ecrivait aucun : ses trames
	# etaient jetees. C'est pourtant l'incident qu'on veut rejouer.
	assert_true(await _await_identified())
	_controller.settings.distance_m = 500.0
	assert_true(_controller.start_race())
	assert_true(await _await_running(), "la course doit partir")
	await wait_frames(20)
	_controller.stop_race()
	await wait_frames(2)

	var files := DirAccess.get_files_at(_races)
	assert_eq(files.size(), 1, "la course interrompue laisse sa trace")
	var loaded := Replay.load_file(_races.path_join(files[0]))
	assert_true(loaded.ok, loaded.error)
	assert_gt(loaded.samples.size(), 5, "avec les trames deja recues")

	var relu := Recorder.new(_logs, _races).load_day()[0]
	assert_true(relu.interrupted, "et elle se declare interrompue")
	assert_string_contains(relu.interruption_note, "operateur", "en disant pourquoi")


func test_l_historique_n_invente_pas_de_vainqueur_a_une_course_arretee() -> void:
	assert_true(await _await_identified())
	_controller.settings.distance_m = 500.0
	assert_true(_controller.start_race())
	assert_true(await _await_running())
	await wait_frames(20)
	_controller.stop_race()
	await wait_frames(2)

	var results := _panel.results_panel()
	assert_eq(results.history_count(), 1, "elle entre dans les courses du jour")
	assert_string_contains(results.history_text(0), "INTERROMPUE")
	assert_false(results.history_text(0).contains("vainqueur"), "personne n'a gagne")


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


func test_basculer_materiel_puis_simulateur_ramene_un_lien_vivant() -> void:
	# docs/05 lot 3 : la bascule se fait « en un clic », et la recette fait ce
	# geste le jour du boitier. S'il laisse un lien mort, la soiree s'arrete la.
	assert_true(await _await_identified())
	var toggle := _panel.hardware_panel().backend_toggle()

	toggle.button_pressed = false
	await wait_frames(5)
	toggle.button_pressed = true

	assert_true(await _await_identified(), "le lien simulateur repart")
	assert_true(_controller.is_simulated())
	assert_true(_controller.can_start_race(), "et START redevient possible")
