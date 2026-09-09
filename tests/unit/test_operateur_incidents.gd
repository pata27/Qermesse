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
	await wait_physics_frames(10)

	_controller.simulate_link_loss()
	await wait_physics_frames(2)
	assert_eq(_controller.link_state(), Protocol.State.LINK_LOST)
	assert_has(notices, "LIEN PERDU", "bandeau d'alerte")
	assert_eq(_controller.engine.state(), RaceEngine.State.RUNNING, "gel, pas abandon")

	await wait_seconds(0.5)
	_controller.simulate_link_return()
	for i: int in range(600):
		await wait_physics_frames(1)
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
	await wait_physics_frames(10)

	_controller.simulate_link_loss()
	await wait_seconds(2.5)
	assert_eq(_controller.engine.state(), RaceEngine.State.RUNNING, "encore dans le delai de grace")
	await wait_seconds(0.8)
	assert_eq(_controller.engine.state(), RaceEngine.State.IDLE, "au-dela de 3 s : abandon")
	assert_eq(aborted.size(), 1)
	assert_string_contains(aborted[0], "grâce")
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
	await wait_physics_frames(10)
	assert_eq(_controller.rejected_ticks(), 0)

	for i: int in range(12):
		_controller.simulate_phantom_tick(1)
	await wait_physics_frames(5)
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
	# LIGNE PERSISTANTE, pas le journal : un probleme de demarrage decrit l'etat
	# de la session, pas un evenement de course, et il survit a l'ardoise propre
	# du premier armement.
	assert_string_contains(panel.race_panel().startup_text(), "REGLAGES")
	assert_string_contains(panel.race_panel().startup_text(), "JSON invalide")
	DirAccess.remove_absolute(settings_path)


func test_un_fichier_de_reglages_lisible_mais_faux_est_dit_au_lancement() -> void:
	# `"gap_m": "abc"` donnait un ecart de 10 m en silence — `float("abc")`
	# vaut 0, ramene a la borne basse — et la poursuite eliminait au premier
	# tour de rouleau. Le fichier se lit, donc `JsonStore` n'a rien a dire ;
	# c'est le chargement qui doit compter ce qu'il a corrige, et le dire sur
	# la ligne orange, celle qui survit au premier depart.
	var settings_path := ProjectSettings.globalize_path(TEST_ROOT).path_join("settings-faux.json")
	AppPaths.ensure_dir(ProjectSettings.globalize_path(TEST_ROOT))
	var file := FileAccess.open(settings_path, FileAccess.WRITE)
	file.store_string('{"mode": 2, "gap_m": "abc", "distance_m": 10000}')
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

	assert_eq(controller.settings.mode, RaceConfig.Mode.PURSUIT, "ce qui est juste est pris")
	assert_eq(controller.settings.gap_m, Settings.new().gap_m, "« abc » : l'ecart par defaut")
	assert_eq(controller.startup_problems().size(), 1)
	var line := panel.race_panel().startup_text()
	assert_string_contains(line, "REGLAGES : 2 valeur(s) corrigée(s) dans settings.json")
	assert_string_contains(line, "gap_m : « abc » n'est pas un nombre")
	assert_string_contains(line, "distance_m : 10000 hors bornes")
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
		await wait_physics_frames(1)
		if controller.link_state() == Protocol.State.IDENTIFIED:
			break
	controller.settings.distance_m = 100.0
	assert_true(controller.start_race())
	var finished: Array[RaceResult] = []
	controller.race_finished.connect(func(r: RaceResult) -> void: finished.append(r))
	for i: int in range(900):
		await wait_physics_frames(1)
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
		await wait_physics_frames(1)
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
	await wait_physics_frames(10)
	assert_eq(notices.size(), before, "on ne repete pas a chaque image")
	_controller.stop_race()


func test_une_pointe_suspecte_remonte_a_l_operateur() -> void:
	var notices: Array[String] = []
	_controller.notice.connect(func(text: String) -> void: notices.append(text))
	_controller.engine.speed_implausible.emit(1, 104.0)
	assert_eq(notices.size(), 1)
	assert_string_contains(notices[0], "PISTE 2")
	assert_string_contains(notices[0], "104 km/h")
	assert_string_contains(notices[0], "conservée", "on ne jette pas la mesure")


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
		await wait_physics_frames(1)
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
	await wait_physics_frames(20)

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
	await wait_physics_frames(20)
	_controller.stop_race()
	await wait_physics_frames(2)

	var files := DirAccess.get_files_at(_races)
	assert_eq(files.size(), 1, "la course interrompue laisse sa trace")
	var loaded := Replay.load_file(_races.path_join(files[0]))
	assert_true(loaded.ok, loaded.error)
	assert_gt(loaded.samples.size(), 5, "avec les trames deja recues")

	var relu := Recorder.new(_logs, _races).load_day()[0]
	assert_true(relu.interrupted, "et elle se declare interrompue")
	assert_string_contains(relu.interruption_note, "opérateur", "en disant pourquoi")


func test_l_historique_n_invente_pas_de_vainqueur_a_une_course_arretee() -> void:
	assert_true(await _await_identified())
	_controller.settings.distance_m = 500.0
	assert_true(_controller.start_race())
	assert_true(await _await_running())
	await wait_physics_frames(20)
	_controller.stop_race()
	await wait_physics_frames(2)

	var results := _panel.results_panel()
	assert_eq(results.history_count(), 1, "elle entre dans les courses du jour")
	assert_string_contains(results.history_text(0), "INTERROMPUE")
	assert_false(results.history_text(0).contains("vainqueur"), "personne n'a gagne")


func test_stop_interrompt_la_course_et_le_csv_le_dit() -> void:
	assert_true(await _await_identified())
	var race_panel := _panel.race_panel()
	race_panel.refresh()
	race_panel.start_button().pressed.emit()
	await wait_physics_frames(30)

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
	await wait_physics_frames(5)
	toggle.button_pressed = true

	assert_true(await _await_identified(), "le lien simulateur repart")
	assert_true(_controller.is_simulated())
	assert_true(_controller.can_start_race(), "et START redevient possible")


## Attend qu'une ligne d'evenement apparaisse dans le CSV, et la rend.
func _await_csv_line(event: String, frames: int = 900) -> PackedStringArray:
	for i: int in range(frames):
		await wait_physics_frames(1)
		for row: PackedStringArray in _read_csv_rows():
			if row.size() > 1 and row[1] == event:
				return row
	return PackedStringArray()


func test_un_faux_depart_est_ecrit_au_csv_et_la_course_part_quand_meme() -> void:
	# docs/02 §5 liste huit evenements de CSV. `FALSE_START` etait le seul
	# qu'aucun test n'atteignait : la couture d'injection manquait, et
	# `docs/RECETTE.md` §7 le faisait cocher a la main, boitier branche.
	#
	# docs/02 §4, AVERTISSEMENT — le defaut : « bandeau + son, la course
	# continue ». Une ligne au journal, et le depart a lieu.
	assert_true(await _await_identified())
	_controller.settings.distance_m = 100.0
	_controller.settings.false_start_policy = RaceConfig.FalseStartPolicy.WARN
	assert_true(_controller.start_race())
	# PENDANT LE DECOMPTE, pas avant : le firmware ne signale un faux depart
	# qu'entre `CD:3` et `CD:0`. Injecte trop tot, il ne se passait rien.
	for i: int in range(300):
		await wait_physics_frames(1)
		if _controller.engine.state() == RaceEngine.State.COUNTDOWN:
			break
	assert_eq(_controller.engine.state(), RaceEngine.State.COUNTDOWN, "le decompte tourne")
	_controller.simulate_false_start(1)

	var line := await _await_csv_line("FALSE_START", 300)
	assert_gt(line.size(), 3, "la ligne FALSE_START est ecrite")
	if line.size() > 3:
		assert_eq(line[3], "1", "et porte la piste fautive, en colonne rider")
	assert_string_contains(_panel.race_panel().notice_text(), "FAUX DÉPART")
	assert_true(await _await_running(), "avec AVERTISSEMENT, la course part quand meme")


func test_une_elimination_est_ecrite_au_csv_avec_son_rang() -> void:
	# `RIDER_ELIMINATED` etait l'autre evenement jamais verifie. C'est pourtant
	# celui qui porte le classement d'une poursuite : sans lui, le CSV d'une
	# soiree de poursuites ne dirait pas qui est sorti, ni quand.
	assert_true(await _await_identified())
	_controller.settings.mode = RaceConfig.Mode.PURSUIT
	_controller.settings.gap_m = 10.0
	assert_true(_controller.set_simulator_profile("domination"), "profil de domination")
	assert_true(_controller.start_race())
	assert_true(await _await_running(), "la course doit partir")

	var line := await _await_csv_line("RIDER_ELIMINATED")
	assert_gt(line.size(), 10, "la ligne RIDER_ELIMINATED est ecrite")
	if line.size() > 10:
		assert_false(line[3].is_empty(), "elle porte la piste")
		assert_false(line[9].is_empty(), "et son rang")
		assert_string_contains(line[10], "écart", "la note dit de combien")


func test_une_trame_illisible_se_dit_a_l_operateur_sans_arreter_la_course() -> void:
	# docs/06 §2 liste la trame corrompue parmi les pannes a eprouver, et
	# `docs/01` §4 exige qu'aucune trame ne soit avalee en silence. Le
	# simulateur savait en produire une ; rien ne pouvait la demander depuis
	# l'application, et le chemin qui la remonte a l'operateur n'etait teste
	# nulle part.
	assert_true(await _await_identified())
	_controller.settings.distance_m = 100.0
	assert_true(_controller.start_race())
	assert_true(await _await_running(), "la course doit partir")

	var notices: Array[String] = []
	_controller.notice.connect(func(text: String) -> void: notices.append(text))
	_controller.simulate_corrupt_frame()
	await wait_physics_frames(10)

	var said := false
	for text: String in notices:
		if text.contains("trame anormale"):
			said = true
	assert_true(said, "l'operateur est prevenu")
	assert_eq(_controller.engine.state(), RaceEngine.State.RUNNING, "et la course continue")


func test_chaque_panne_du_simulateur_est_atteignable_depuis_l_application() -> void:
	# LE DEFAUT DE CLASSE, tenu par la machine. Deux injections sur six ne
	# traversaient pas la facade `Link` : le faux depart et la trame corrompue.
	# Elles existaient dans `link_sim`, personne ne pouvait les demander, et
	# c'est pour cela qu'aucun test ne les couvrait. Une panne qu'on ne peut pas
	# provoquer est une panne qu'on ne saura pas diagnostiquer le soir venu.
	var sim: Node = (load("res://hardware/link_sim.gd") as GDScript).new()
	var injections: Array[String] = []
	for entry: Dictionary in sim.get_method_list():
		var name := str(entry["name"])
		if name.begins_with("inject_"):
			injections.append(name)
	sim.free()
	assert_gt(injections.size(), 3, "le simulateur sait provoquer des pannes")

	var link := Link.new()
	var controller := AppController.new()
	for injection: String in injections:
		assert_true(
			link.has_method(injection),
			"`Link` doit relayer `%s`, sinon l'application ne peut pas la demander" % injection
		)
		var seam := injection.replace("inject_", "simulate_")
		assert_true(
			controller.has_method(seam),
			"`AppController` doit exposer `%s`" % seam
		)
	link.free()
	controller.free()


func test_le_boitier_qui_comprend_une_autre_longueur_le_dit_a_l_operateur() -> void:
	# `docs/01` §2 : le firmware accuse reception de `l<ticks>` par `L:<ticks>`.
	# C'est sa SEULE facon de dire ce qu'il a compris — et personne ne le lisait.
	# `docs/06` §4 liste pourtant « le firmware reel diverge de ss_basic.ino »
	# parmi les risques forts. Un boitier reflashe qui borne ou tronque la
	# longueur allumerait ses LED d'arrivee au mauvais endroit, devant le public,
	# sans que rien ne l'annonce.
	assert_true(await _await_identified())
	var notices: Array[String] = []
	_controller.notice.connect(func(text: String) -> void: notices.append(text))

	# Le boitier accuse une longueur qui n'est pas celle demandee.
	_controller.settings.distance_m = 500.0
	assert_true(_controller.start_race())
	await wait_physics_frames(3)
	_controller.simulate_length_ack(999)
	await wait_physics_frames(3)

	var said := false
	for text: String in notices:
		if text.to_lower().contains("longueur"):
			said = true
	assert_true(said, "l'ecart entre la longueur demandee et l'accusee se dit")


func test_un_accuse_de_longueur_conforme_ne_dit_rien() -> void:
	# Le cas nominal doit rester silencieux : une alerte qui se declenche a
	# chaque course cesse d'etre lue.
	assert_true(await _await_identified())
	var notices: Array[String] = []
	_controller.notice.connect(func(text: String) -> void: notices.append(text))
	_controller.settings.distance_m = 100.0
	assert_true(_controller.start_race())
	assert_true(await _await_running(), "la course part")
	for text: String in notices:
		assert_false(text.to_lower().contains("longueur"), "rien a signaler : %s" % text)


func test_aucune_trame_ne_tombe_dans_le_silence() -> void:
	# LE DEFAUT DE CLASSE. Le `match` du controleur traitait six des onze sortes
	# de trames ; les cinq autres tombaient dans son silence, sans qu'aucune
	# ligne ne dise si c'etait un choix. L'accuse de longueur y dormait, et avec
	# lui la seule chose que le boitier dise de ce qu'il a compris.
	#
	# Chaque sorte doit etre NOMMEE — traitee ou explicitement ignoree, avec sa
	# raison a cote. Une trame qu'on ignore volontairement et une trame qu'on a
	# oubliee se ressemblent trop pour qu'on laisse le silence trancher.
	var file := FileAccess.open("res://scenes/app_controller.gd", FileAccess.READ)
	assert_not_null(file, "le controleur est lisible")
	var source := file.get_as_text()
	var dispatch := source.substr(source.find("func _on_frame"))

	var missing: Array[String] = []
	for name: String in Protocol.Frame.keys():
		if not dispatch.contains("Protocol.Frame.%s" % name):
			missing.append(name)
	assert_eq(missing, [] as Array[String], "des sortes de trames que le controleur ne nomme pas")


func test_les_trames_kiosque_sont_comptees_et_dites_au_panneau_materiel() -> void:
	# docs/06 §4 : « parsees et loggees, comportement active seulement si
	# observe ». `ss_monitor` les journalisait ; l'application les jetait — or
	# c'est en soiree qu'un tel boitier se revelerait, et le monitor ne tourne
	# pas ce soir-la.
	assert_true(await _await_identified())
	assert_eq(_controller.kiosk_frames(), 0, "un boitier ordinaire n'en emet aucune")
	_panel.hardware_panel().refresh()
	assert_false(
		_panel.hardware_panel().stats_text().contains("kiosque"),
		"et le panneau n'en parle pas"
	)

	_controller._on_frame(Protocol.Frame.KIOSK_START, {})
	_controller._on_frame(Protocol.Frame.KIOSK_STOP, {})
	assert_eq(_controller.kiosk_frames(), 2, "comptees")
	_panel.hardware_panel().refresh()
	assert_string_contains(_panel.hardware_panel().stats_text(), "kiosque")


func test_la_trace_est_le_flux_recu_trame_pour_trame() -> void:
	# `docs/02` §5 : le JSON porte « la trace COMPLETE des trames R: ». Elle
	# portait en fait `state.ticks` — c'est-a-dire les valeurs APRES le filtre et
	# APRES le gel d'un rider arrive. Un tick rejete, ou la valeur que le boitier
	# a reellement envoyee apres une arrivee, n'y figurait pas : le fichier que
	# `DEPANNAGE` fait envoyer au developpeur avait deja perdu ce qu'on lui
	# demande de diagnostiquer.
	#
	# Le contrat se verifie sans mise en scene : ce que la trace contient doit
	# etre, trame pour trame, ce que le lien a livre.
	assert_true(await _await_identified())
	var received: Array = []
	_controller.get_node("Link").frame_received.connect(
		func(kind: int, payload: Dictionary) -> void:
			if kind == Protocol.Frame.PROGRESS:
				var ticks: Array = payload.get("ticks", [])
				received.append([
					int(ticks[0]), int(ticks[1]), int(ticks[2]), int(ticks[3]),
					int(payload.get("elapsed_ms", 0)),
				])
	)
	_controller.settings.distance_m = 100.0
	assert_true(_controller.start_race())
	assert_true(await _await_running(), "la course doit partir")
	var finished: Array[RaceResult] = []
	_controller.race_finished.connect(func(r: RaceResult) -> void: finished.append(r))
	for i: int in range(2500):
		await wait_physics_frames(1)
		if not finished.is_empty():
			break
	assert_false(finished.is_empty(), "la course se termine")

	var loaded := Replay.load_file(_controller.recorder.json_path(finished[0].uuid))
	assert_true(loaded.ok, "le fichier se relit")
	assert_gt(loaded.samples.size(), 100, "la trace n'est pas vide")

	# Chaque trame enregistree doit exister telle quelle dans le flux recu. Une
	# valeur filtree ou gelee n'y serait pas.
	var stream: Dictionary = {}
	for row: Variant in received:
		stream[str(row)] = true
	var altered := 0
	for sample: Variant in loaded.samples:
		var row: Array = sample
		var key := str([int(row[0]), int(row[1]), int(row[2]), int(row[3]), int(row[4])])
		if not stream.has(key):
			altered += 1
	assert_eq(altered, 0, "aucune trame de la trace n'a ete retouchee avant d'etre ecrite")

	# Et elle se rejoue toujours au meme classement.
	assert_eq(
		Replay.replay(loaded).ranking, finished[0].ranking,
		"le rejeu de la trace brute redonne le meme classement"
	)


func test_une_piste_qui_se_tait_en_pleine_course_est_signalee() -> void:
	# `DEPANNAGE` : « La course ne se termine jamais ». La garde existante ne
	# voyait que les pistes muettes DEPUIS LE DEPART — une case cochee sans
	# personne dessus. Or un capteur lache bien plus volontiers pendant
	# l'effort : cable arrache par la secousse, aimant parti, coureur a
	# l'arret. Cette piste-la avait produit des ticks, donc rien ne la
	# signalait, et en distance la course l'attendait jusqu'au plafond de dix
	# minutes, devant le public, sans un mot.
	#
	# Le profil `abandon` du simulateur fait exactement cela : la piste 2 cesse
	# de produire des ticks a la vingtieme seconde de course.
	assert_true(await _await_identified())
	assert_true(_controller.set_simulator_profile("abandon"), "profil abandon")
	var notices: Array[String] = []
	_controller.notice.connect(func(text: String) -> void: notices.append(text))
	# Assez longue pour que la piste 1 ne franchisse pas avant l'alerte.
	_controller.settings.distance_m = 800.0
	assert_true(_controller.start_race())
	assert_true(await _await_running(), "la course doit partir")

	var alert := ""
	for i: int in range(2000):
		await wait_physics_frames(1)
		for text: String in notices:
			if text.contains("plus un seul tick"):
				alert = text
				break
		if not alert.is_empty():
			break
	assert_string_contains(alert, "PISTE 2", "la piste nommee est celle qui s'est tue")
	assert_string_contains(alert, "capteur perdu en route", "et le motif possible est dit")
	# Une seule fois : une alerte repetee a chaque trame noierait le journal.
	var count := 0
	for text: String in notices:
		if text.contains("plus un seul tick"):
			count += 1
	assert_eq(count, 1, "signalee une seule fois")
	# La piste QUI ROULE n'est jamais accusee.
	for text: String in notices:
		assert_false(
			text.contains("PISTE 1 : plus un seul tick"), "la piste 1 roule, on ne l'accuse pas"
		)
	_controller.engine.abort("fin du test")


func test_relancer_en_pleine_course_abandonne_puis_repart() -> void:
	# Le versant inverse du grisage : « Relancer » est propose EXACTEMENT tant
	# qu'il y a quelque chose a interrompre. En course il est actif, et il fait
	# ce que son nom dit — un abandon suivi d'un depart, donc une ligne
	# INTERROMPUE dans Courses du jour, avec sa trace. C'est le geste du faux
	# depart qu'on refait tout de suite, et `MANUEL-OPERATEUR` §4.5 previent
	# desormais de ce qu'il laisse au journal.
	assert_true(await _await_identified())
	var race_panel := _panel.race_panel()
	var aborted: Array[String] = []
	_controller.race_aborted.connect(func(note: String) -> void: aborted.append(note))
	var finished: Array[RaceResult] = []
	_controller.race_finished.connect(func(r: RaceResult) -> void: finished.append(r))

	_controller.settings.distance_m = 100.0
	assert_true(_controller.start_race())
	assert_true(await _await_running(), "la course doit partir")
	await wait_physics_frames(10)

	race_panel.refresh()
	assert_false(race_panel.restart_button().disabled, "Relancer est actif en course")
	assert_string_contains(race_panel.restart_button().tooltip_text, "réarmer")

	race_panel.restart_button().pressed.emit()
	assert_eq(aborted.size(), 1, "la course en cours est bien abandonnee")
	assert_true(await _await_running(), "et une nouvelle repart aussitot")
	for i: int in range(900):
		await wait_physics_frames(1)
		if not finished.is_empty():
			break
	assert_false(finished.is_empty(), "la seconde va au bout")

	var events := _csv_events()
	assert_has(events, "RACE_ABORTED", "l'abandon laisse sa trace")
	assert_eq(events.count("RACE_START"), 2, "deux departs")
	assert_has(events, "RACE_FINISH")


func test_une_piste_vide_est_signalee_meme_sur_une_course_courte() -> void:
	# LE SEUIL ABSOLU ARRIVAIT TROP TARD. L'alerte tombait a dix secondes de
	# course, et 100 m durent huit secondes a 45 km/h : elle venait donc APRES
	# l'instant ou la course aurait du se terminer. Elle finissait par venir —
	# le chrono continue de courir, puisque le PC attend justement la piste
	# manquante — mais huit secondes trop tard. Mesure : 10,0 s avant, 2,1 s
	# apres.
	#
	# En distance le PC attend TOUTES les pistes actives : une piste cochee sans
	# personne dessus fait attendre jusqu'au plafond de dix minutes, devant le
	# public. Chaque seconde gagnee sur le diagnostic est une seconde de moins.
	#
	# Meme piege que la cloche de fin, meme correction : un repere absolu se
	# plafonne a une fraction de l'epreuve.
	assert_true(await _await_identified())
	var config := RaceConfig.new()
	config.mode = RaceConfig.Mode.DISTANCE
	config.distance_m = 100.0
	config.active_riders = [0, 1]
	var notices: Array[String] = []
	_controller.notice.connect(func(text: String) -> void: notices.append(text))
	_controller.race_state_changed.emit(RaceEngine.State.IDLE, RaceEngine.State.ARMING)
	_controller.race_state_changed.emit(RaceEngine.State.COUNTDOWN, RaceEngine.State.RUNNING)

	# La piste 1 roule, la piste 2 est cochee mais vide. Au quart de la course —
	# 25 m — le doute n'est plus permis.
	var state := RaceState.new(config)
	var physics := Physics.new(config.roller_mm)
	for metres: float in [5.0, 15.0, 26.0]:
		state.apply_sample([physics.metres_to_ticks(metres), 0, 0, 0], int(metres * 80.0))
		_controller.engine.progress_updated.emit(state)

	var said := ""
	for text: String in notices:
		if text.contains("aucun tick depuis le départ"):
			said = text
	assert_false(said.is_empty(), "la piste vide est signalee avant la fin d'une course courte")
	assert_string_contains(said, "PISTE 2", "et c'est bien la piste vide qui est nommee")
	# C'EST LE MOMENT QUI COMPTE, pas le fait. Le dernier echantillon est a
	# 2,1 s de course : l'alerte est donc tombee bien avant le seuil absolu, et
	# avant les huit secondes que dure cette course. C'est tout le gain.
	assert_lt(2080, AppController.SILENT_LANE_MS, "l'alerte precede le seuil absolu")
	# La piste qui ROULE n'est jamais accusee.
	for text: String in notices:
		assert_false(text.contains("PISTE 1 : aucun tick"), "la piste 1 roule")
	_controller.engine.abort("fin du test")


func test_une_course_en_temps_courte_signale_aussi_sa_piste_vide() -> void:
	# La duree MINIMALE acceptee est de dix secondes : le seuil absolu tombait
	# alors exactement au gong. Une annonce qui arrive avec le resultat ne sert
	# a rien.
	assert_true(await _await_identified())
	var config := RaceConfig.new()
	config.mode = RaceConfig.Mode.TIME
	config.duration_s = 12.0
	config.active_riders = [0, 1]
	var notices: Array[String] = []
	_controller.notice.connect(func(text: String) -> void: notices.append(text))
	_controller.race_state_changed.emit(RaceEngine.State.IDLE, RaceEngine.State.ARMING)
	_controller.race_state_changed.emit(RaceEngine.State.COUNTDOWN, RaceEngine.State.RUNNING)

	var state := RaceState.new(config)
	var physics := Physics.new(config.roller_mm)
	# Au quart des douze secondes, soit trois secondes.
	state.apply_sample([physics.metres_to_ticks(20.0), 0, 0, 0], 3200)
	_controller.engine.progress_updated.emit(state)

	var said := false
	for text: String in notices:
		if text.contains("aucun tick depuis le départ"):
			said = true
	assert_true(said, "signalee au quart du temps, pas au gong")
	_controller.engine.abort("fin du test")


func test_un_probleme_de_demarrage_survit_au_premier_depart() -> void:
	# Les problemes de demarrage — roster illisible, reglages perdus, courses du
	# jour introuvables — etaient pousses dans le journal du panneau Course, qui
	# se vide a CHAQUE armement. Un operateur qui lance sa premiere course dans
	# la minute perdait donc la seule notification lui disant que ses noms de
	# coureurs n'avaient pas ete relus : il decouvrait « Piste 1, Piste 2 » sur
	# l'ecran public, ou dans le CSV le lendemain.
	#
	# Ce n'est pas l'alerte d'une course, c'est une CONDITION de la session,
	# vraie tant que le fichier n'est pas repare. Elle a donc sa place a elle,
	# que l'ardoise propre n'efface pas.
	var dir := ProjectSettings.globalize_path("user://test_demarrage")
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join("roster.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{ ceci n'est pas du JSON")
	file.close()

	var controller := AppController.new()
	controller.settings_path = dir.path_join("reglages.json")
	controller.roster_path = path
	controller.recorder_logs_dir = dir.path_join("logs")
	controller.recorder_races_dir = dir.path_join("races")
	add_child_autofree(controller)
	# `_ready` n'est pas synchrone selon d'ou l'on ajoute le noeud : le
	# controleur expose `initialize` exactement pour cela.
	controller.initialize()
	var panel := PanelRace.new()
	add_child_autofree(panel)
	panel.setup(controller)

	assert_string_contains(panel.startup_text(), "ROSTER", "le probleme est dit au lancement")
	# L'operateur lance sa premiere course.
	controller.race_state_changed.emit(RaceEngine.State.IDLE, RaceEngine.State.ARMING)
	await wait_physics_frames(1)
	assert_string_contains(
		panel.startup_text(), "ROSTER", "et il est TOUJOURS la apres le premier depart"
	)
	# Le journal des alertes, lui, s'efface bien : c'est sa raison d'etre.
	assert_eq(panel.notice_text(), "", "l'ardoise des alertes reste propre")
	DirAccess.remove_absolute(path)


func test_la_piste_muette_est_annoncee_avec_ce_que_la_course_en_fera_selon_le_mode() -> void:
	# « La course attend cette piste » n'etait vrai qu'en distance. En temps le
	# gong tombe quand meme — un operateur qui lisait « attend » pouvait
	# arreter une course qui allait finir seule — et en poursuite le muet est
	# elimine a l'ecart. La phrase dicte le geste : elle doit etre vraie dans
	# le mode joue.
	var notices: Array[String] = []
	_controller.notice.connect(func(text: String) -> void: notices.append(text))

	# TEMPS, 20 s : le quart tombe a 5 s.
	_controller.settings.mode = RaceConfig.Mode.TIME
	_controller.settings.duration_s = 20.0
	var config := _controller.current_config()
	_controller.race_state_changed.emit(RaceEngine.State.COUNTDOWN, RaceEngine.State.RUNNING)
	var state := RaceState.new(config)
	var physics := Physics.new(config.roller_mm)
	state.apply_sample([physics.metres_to_ticks(30.0), 0, 0, 0], 6000)
	_controller.engine.progress_updated.emit(state)
	var said := _last_containing(notices, "aucun tick depuis le départ")
	assert_string_contains(said, "PISTE 2")
	assert_string_contains(said, "finira au gong", "en temps, la course finit seule")
	assert_false(said.contains("attend cette piste"), "et n'attend personne")
	_controller.engine.abort("fin du test")


func test_en_poursuite_la_piste_muette_est_annoncee_eliminee_a_l_ecart() -> void:
	# Meme regle, autre mode — et un autre test, parce que la liste des pistes
	# deja signalees ne se vide qu'au START : la piste 2 du test precedent y
	# serait encore.
	var notices: Array[String] = []
	_controller.notice.connect(func(text: String) -> void: notices.append(text))
	_controller.settings.mode = RaceConfig.Mode.PURSUIT
	var config := _controller.current_config()
	_controller.race_state_changed.emit(RaceEngine.State.COUNTDOWN, RaceEngine.State.RUNNING)
	var state := RaceState.new(config)
	var physics := Physics.new(config.roller_mm)
	# Dix secondes : la poursuite n'a pas de quart, sa fin depend d'un ecart.
	state.apply_sample([physics.metres_to_ticks(60.0), 0, 0, 0], 10500)
	_controller.engine.progress_updated.emit(state)
	var said := _last_containing(notices, "aucun tick depuis le départ")
	assert_string_contains(said, "PISTE 2")
	assert_string_contains(said, "sera éliminée", "en poursuite, l'ecart decide")
	assert_false(said.contains("attend cette piste"))
	_controller.engine.abort("fin du test")


func _last_containing(texts: Array[String], needle: String) -> String:
	var found := ""
	for text: String in texts:
		if text.contains(needle):
			found = text
	return found


func test_fermer_le_logiciel_pendant_un_test_capteurs_arrete_le_boitier() -> void:
	# Manuel §6 : a la fermeture, le boitier recoit son ordre d'arret. Le test
	# capteurs est une course a blanc cote boitier, moteur au repos : `shutdown`
	# ne regardait que le moteur, et le boitier restait en course, LED
	# allumees. Preuve sans ecouter le port : les trames R: detournees vers
	# `sensor_activity` cessent quand le simulateur a recu `s`.
	assert_true(await _await_identified())
	_controller.begin_sensor_test()
	assert_true(_controller.sensor_test_active())
	# UN TABLEAU, PAS UN ENTIER : une lambda GDScript capture les entiers par
	# valeur, et `frames += 1` n'incrementait qu'une copie.
	var frames: Array[int] = []
	_controller.sensor_activity.connect(func(_t: PackedInt32Array) -> void: frames.append(1))
	# Le decompte du simulateur, puis des trames.
	for i: int in range(600):
		await wait_physics_frames(1)
		if not frames.is_empty():
			break
	assert_gt(frames.size(), 0, "la course a blanc envoie des trames")

	_controller.shutdown()
	assert_false(_controller.sensor_test_active(), "le test est termine")
	var after_shutdown := frames.size()
	await wait_physics_frames(30)
	assert_eq(frames.size(), after_shutdown, "plus une trame : le boitier a recu `s`")
