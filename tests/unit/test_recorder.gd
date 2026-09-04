## Tests de la persistance et du rejeu — docs/02 §5 et docs/06 §2.
##
## Tout est ecrit dans un dossier temporaire : un test qui ecrirait dans les
## donnees de l'utilisateur serait un test qu'on n'ose plus lancer.
extends GutTest

const TEST_ROOT := "user://test_recorder"

var _logs: String
var _races: String
var _recorder: Recorder


func before_each() -> void:
	_logs = ProjectSettings.globalize_path(TEST_ROOT).path_join("logs")
	_races = ProjectSettings.globalize_path(TEST_ROOT).path_join("races")
	_wipe()
	_recorder = Recorder.new(_logs, _races)


func after_all() -> void:
	_wipe()


func _wipe() -> void:
	for dir: String in [_logs, _races]:
		if DirAccess.dir_exists_absolute(dir):
			for name: String in DirAccess.get_files_at(dir):
				DirAccess.remove_absolute(dir.path_join(name))


func _config() -> RaceConfig:
	var config := RaceConfig.new()
	config.mode = RaceConfig.Mode.DISTANCE
	config.active_riders = [0, 1]
	config.distance_m = 100.0
	return config


## Deroule une course complete et rend le resultat, en enregistrant tout.
func _run_recorded_race(config: RaceConfig, speeds: Array) -> RaceResult:
	var engine := RaceEngine.new()
	var produced: Array[RaceResult] = []
	engine.race_finished.connect(func(r: RaceResult) -> void: produced.append(r))
	engine.rider_finished.connect(func(rider: int, ms: int, rank: int) -> void:
		_recorder.record_rider_finished(rider, ms, rank))
	engine.rider_eliminated.connect(func(rider: int, rank: int, gap: float) -> void:
		_recorder.record_rider_eliminated(rider, rank, gap))

	_recorder.begin_race(config, {0: {"name": "Alice", "dossard": 7},
		1: {"name": "Bob", "dossard": 12}})
	engine.arm(config, 0)
	for value: int in [3, 2, 1, 0]:
		engine.on_countdown(value)

	var physics := Physics.new(config.roller_mm)
	var distances := [0.0, 0.0, 0.0, 0.0]
	var ms := 0
	while ms < 120000 and engine.state() == RaceEngine.State.RUNNING:
		ms += 10
		var ticks: Array = []
		for rider: int in range(Protocol.MAX_RIDERS):
			var kph: float = speeds[rider] if rider < speeds.size() else 0.0
			distances[rider] += kph * Physics.KPH_TO_MM_PER_MS * 10.0
			ticks.append(int(floor(distances[rider] / physics.circumference_mm)))
		engine.on_progress(ticks, ms)
		var accepted := engine.race_state().ticks
		_recorder.record_sample(accepted, ms)

	if not produced.is_empty():
		_recorder.finish_race(produced[0])
		return produced[0]
	return null


func _read_csv_lines() -> PackedStringArray:
	var path := _recorder.csv_path()
	if path.is_empty() or not FileAccess.file_exists(path):
		return PackedStringArray()
	var file := FileAccess.open(path, FileAccess.READ)
	var text := file.get_as_text()
	file.close()
	return text.strip_edges().split("\n")


# =============================================================================
# CSV
# =============================================================================

func test_le_csv_porte_l_entete_de_docs_02() -> void:
	_recorder.begin_race(_config())
	var lines := _read_csv_lines()
	assert_gt(lines.size(), 1)
	assert_eq(lines[0], Recorder.CSV_HEADER)
	assert_eq(lines[0].split(",").size(), 11, "onze colonnes")


func test_l_horodatage_du_csv_se_lit_a_l_heure_de_la_salle() -> void:
	# Le fichier est nomme par le jour LOCAL, sa colonne d'horodatage etait en
	# UTC : l'operateur qui ouvre le CSV le lendemain lisait deux heures
	# d'ecart, et une course de fin de soiree portait la date de la veille.
	_recorder.begin_race(_config())
	var stamp := _read_csv_lines()[1].split(",")[0]

	# L'horodatage porte le jour du fichier — SAUF entre minuit et 5 h, ou la
	# journee d'exploitation est celle de la veille (docs/02 §5). Une course de
	# 00 h 40 est ecrite « 2030-06-16T00:40 » dans le CSV du 15 : c'est voulu,
	# et c'est ce que l'operateur attend d'une soiree qui passe minuit.
	var day := AppPaths.daily_log_name().substr(0, 10).replace("_", "-")
	var evening := AppPaths.operating_day(Time.get_datetime_dict_from_system())
	var today := "%04d-%02d-%02d" % [evening["year"], evening["month"], evening["day"]]
	assert_eq(day, today, "le fichier porte la journee d'exploitation")
	var stamp_day := stamp.substr(0, 10)
	if int(Time.get_datetime_dict_from_system()["hour"]) >= AppPaths.DAY_ROLLOVER_HOUR:
		assert_eq(stamp_day, day, "en journee, horodatage et fichier portent la meme date")
	else:
		assert_ne(stamp_day, day, "apres minuit, le CSV est celui de la veille")

	# Et il porte son decalage : un horodatage sans fuseau ne veut rien dire.
	var bias := int(Time.get_time_zone_from_system()["bias"])
	var offset := "%s%02d:%02d" % ["+" if bias >= 0 else "-", absi(bias) / 60, absi(bias) % 60]
	assert_true(stamp.ends_with(offset), "%s doit finir par %s" % [stamp, offset])


func test_les_evenements_declares_sont_reellement_ecrits() -> void:
	# docs/02 §5 : la v1 declarait cinq types d'evenements et n'en ecrivait
	# qu'un seul. Chacun doit apparaitre.
	var config := _config()
	config.mode = RaceConfig.Mode.PURSUIT
	config.gap_m = 30.0
	_recorder.begin_race(config)
	_recorder.record_false_start(0)
	_recorder.record_rider_finished(0, 8000, 1)
	_recorder.record_rider_eliminated(1, 2, 30.4)
	_recorder.record_link_lost("500 ms sans trame")
	_recorder.record_tick_rejected(1, "piste 2 : 14 ticks en 10 ms, 1811 km/h")
	_recorder.record_abort("arrêt opérateur")

	var text := "\n".join(Array(_read_csv_lines()))
	for event: String in Recorder.EVENTS:
		if event == "RACE_FINISH":
			continue  # ecrit par finish_race, couvert plus bas
		assert_string_contains(text, event)


func test_l_append_est_reel_et_ne_reecrit_pas_le_fichier() -> void:
	# La v1 rechargeait tout le fichier et le reecrivait a chaque ligne. On
	# verifie qu'une ligne ajoutee a la main SURVIT a l'ecriture suivante :
	# une reecriture complete l'effacerait.
	_recorder.begin_race(_config())
	var path := _recorder.csv_path()
	var before := _read_csv_lines().size()

	var file := FileAccess.open(path, FileAccess.READ_WRITE)
	file.seek_end()
	file.store_line("MARQUEUR_EXTERNE,,,,,,,,,,")
	file.close()

	_recorder.record_false_start(1)
	var lines := _read_csv_lines()
	assert_eq(lines.size(), before + 2)
	assert_string_contains("\n".join(Array(lines)), "MARQUEUR_EXTERNE")


func test_une_note_contenant_une_virgule_est_echappee() -> void:
	# Sans echappement, la colonne suivante se decale et le CSV devient faux
	# sans prevenir. On relit avec un vrai lecteur CSV plutot qu'en decoupant
	# sur la virgule : c'est ce que fera le tableur de l'operateur.
	_recorder.begin_race(_config())
	_recorder.record_link_lost("coupure, puis reprise")

	var file := FileAccess.open(_recorder.csv_path(), FileAccess.READ)
	var rows: Array[PackedStringArray] = []
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() > 1:
			rows.append(row)
	file.close()

	assert_gt(rows.size(), 1)
	var last := rows[rows.size() - 1]
	assert_eq(last.size(), 11, "les onze colonnes restent alignees")
	assert_eq(last[1], "LINK_LOST")
	assert_eq(last[10], "coupure, puis reprise", "la virgule survit dans la note")


func test_le_dossard_du_roster_apparait_dans_le_csv() -> void:
	_recorder.begin_race(_config(), {0: {"name": "Alice", "dossard": 7}})
	_recorder.record_rider_finished(0, 8000, 1)
	var lines := _read_csv_lines()
	var last := lines[lines.size() - 1]
	assert_eq(last.split(",")[4], "7")


func test_la_note_d_une_ligne_race_finish_decrit_le_rider_pas_la_course() -> void:
	# Vu dans un vrai journal de poursuite : un coureur elimine a 14 s portait
	# la note « dernier en course », qui est le motif de fin de LA COURSE. Dans
	# un tableur, chaque ligne se lit seule — et celle-la disait faux de lui.
	var config := _config()
	config.mode = RaceConfig.Mode.PURSUIT
	config.active_riders = [0, 1]
	_recorder.begin_race(config)

	var result := RaceResult.new()
	result.mode = "poursuite"
	result.config = config
	result.ranking = [0, 1]
	result.end_reason = RaceRule.EndReason.LAST_ONE_STANDING
	result.finished_ms[0] = 38302
	result.eliminated[1] = true
	result.eliminated_ms[1] = 14014
	_recorder.finish_race(result)

	var notes := {}
	for line: String in _read_csv_lines():
		var row := line.split(",")
		if row[1] == "RACE_FINISH":
			notes[int(row[3])] = row[10]
	assert_eq(notes[0], "dernier en course", "le survivant porte le motif de fin")
	assert_string_contains(str(notes[1]), "éliminé", "l'éliminé dit ce qui LUI est arrivé")


func test_une_course_complete_ecrit_une_ligne_race_finish_par_rider() -> void:
	var result := _run_recorded_race(_config(), [45.0, 43.0])
	assert_not_null(result)
	var finishes := 0
	for line: String in _read_csv_lines():
		if line.contains("RACE_FINISH"):
			finishes += 1
	assert_eq(finishes, 2)


# =============================================================================
# JSON et rejeu — docs/06 §2
# =============================================================================

func test_les_problemes_d_ecriture_sont_ceux_de_la_course_en_cours() -> void:
	# Un journal impossible a ecrire pour une course, puis le disque revient :
	# la course suivante ne doit pas etre accusee a tort.
	var blocked := ProjectSettings.globalize_path(TEST_ROOT).path_join("logs-bloque")
	# Le passage precedent laisse un DOSSIER de ce nom : l'enlever d'abord,
	# sinon ouvrir un fichier a sa place rend null.
	_remove_dir(blocked)
	var file := FileAccess.open(blocked, FileAccess.WRITE)
	assert_not_null(file, "le fichier-bouchon doit pouvoir s'ecrire")
	file.store_string("pas un dossier")
	file.close()
	var recorder := Recorder.new(blocked, _races)
	recorder.begin_race(_config())
	assert_false(recorder.problems().is_empty(), "l'echec est constate")

	# Le disque revient : on change de dossier de journaux, comme l'operateur.
	DirAccess.remove_absolute(blocked)
	DirAccess.make_dir_recursive_absolute(blocked)
	recorder.begin_race(_config())
	assert_true(recorder.problems().is_empty(), "plus rien a reprocher a la course suivante")
	_remove_dir(blocked)


## Supprime un dossier et son contenu (un niveau) — `remove_absolute` refuse
## un dossier non vide.
func _remove_dir(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for name: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(name))
	DirAccess.remove_absolute(path)


func test_les_survivants_d_un_plafond_de_poursuite_ont_un_temps_couru() -> void:
	# docs/02 §5 : temps_ms n'est jamais 0 pour un rider classe. Deux riders
	# de niveau egal, plafond de duree a 6 s : personne n'est arrive, personne
	# n'est elimine — ils ont couru 6 s.
	var config := _config()
	config.mode = RaceConfig.Mode.PURSUIT
	config.gap_m = 500.0
	config.pursuit_time_cap_s = 6.0
	var result := _run_recorded_race(config, [45.0, 44.5])
	assert_true(result.interrupted, "plafond : course interrompue")
	assert_between(result.raced_ms(0), 6000, 6100)
	assert_between(result.raced_ms(1), 6000, 6100)
	var finishes: Array[String] = []
	for line: String in _read_csv_lines():
		if line.contains("RACE_FINISH"):
			finishes.append(line.split(",")[6])
	assert_eq(finishes.size(), 2)
	for value: String in finishes:
		assert_between(int(value), 6000, 6100, "temps_ms = l'instant du plafond")


func test_le_json_contient_la_trace_complete_des_trames() -> void:
	var result := _run_recorded_race(_config(), [45.0, 43.0])
	var path := _races.path_join("%s.json" % result.uuid)
	assert_true(FileAccess.file_exists(path), "le JSON de course doit exister")

	var loaded := Replay.load_file(path)
	assert_true(loaded.ok, loaded.error)
	# 100 m a 45 km/h = 8 s a 100 Hz : environ 800 trames.
	assert_gt(loaded.samples.size(), 700)
	assert_eq((loaded.samples[0] as Array).size(), 5, "[t0,t1,t2,t3,elapsed_ms]")


## Valeur distincte de `current`, ou `current` si le type n'est pas gere — le
## test echoue alors en nommant le champ, ce qui est le comportement voulu :
## un champ d'un type nouveau doit forcer une decision, pas passer en silence.
func _mutate_result(name: String, current: Variant) -> Variant:
	# Les tableaux TYPES ne se construisent pas generiquement : une `Array`
	# nue refusee a l'affectation. Ces trois-la sont donc nommes.
	if name == "ranking":
		var ranking: Array[int] = [3, 1, 0, 2]
		return ranking
	if name == "eliminated" or name == "false_started":
		var flags: Array[bool] = [true, false, true, false]
		return flags
	# Un seul point de sortie : le `match` choisit, il ne rend pas.
	var mutated: Variant = current
	match typeof(current):
		TYPE_BOOL:
			mutated = not bool(current)
		TYPE_INT:
			mutated = int(current) + 7
		TYPE_FLOAT:
			mutated = float(current) + 3.5
		TYPE_STRING:
			mutated = "%s-modifie" % str(current)
		TYPE_PACKED_INT32_ARRAY:
			var ints := PackedInt32Array()
			for i: int in range((current as PackedInt32Array).size()):
				ints.append(1000 + i)
			mutated = ints
		TYPE_PACKED_FLOAT32_ARRAY:
			var floats := PackedFloat32Array()
			for i: int in range((current as PackedFloat32Array).size()):
				floats.append(11.5 + float(i))
			mutated = floats
	return mutated


func test_toutes_les_donnees_d_un_resultat_survivent_au_json() -> void:
	# Le JSON de course est ce que relit « Courses du jour » et ce qu'on envoie
	# au developpeur devant un resultat suspect. Un champ ajoute a RaceResult
	# et oublie dans `_write_json` ou dans `from_json` fausserait l'historique
	# en silence. Ce test enumere les champs DECLARES : il s'entretient seul.
	#
	# Les valeurs sont FABRIQUEES, pas issues d'une course : un champ dont la
	# valeur reelle vaut son defaut — `interruption_note` d'une course qui
	# s'est bien terminee — passerait sans rien prouver.
	var result := RaceResult.new()
	# Champs que le recorder possede : il les ecrase a l'enregistrement.
	var owned := [
		"uuid", "started_at_iso", "finished_at_iso", "rider_names", "rider_dossards", "config",
	]
	var expected := {}
	for property: Dictionary in result.get_property_list():
		if not (int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var name := str(property["name"])
		if owned.has(name):
			continue
		var before: Variant = result.get(name)
		var after: Variant = _mutate_result(name, before)
		assert_ne(after, before, "champ %s : type non gere par le test, a completer" % name)
		result.set(name, after)
		expected[name] = after

	assert_gt(expected.size(), 8, "la reflexion doit voir les champs du resultat")
	_recorder.begin_race(_config(), {0: {"name": "Alice", "dossard": 7}})
	assert_false(_recorder.finish_race(result).is_empty(), "le JSON doit s'ecrire")

	var relu := Recorder.new(_logs, _races).load_day()[0]
	for name: String in expected:
		assert_eq(relu.get(name), expected[name], "champ %s : perdu par le JSON" % name)
	# Ce que le recorder possede fait l'aller-retour aussi.
	assert_eq(relu.uuid, result.uuid)
	assert_eq(relu.started_at_iso, result.started_at_iso)
	assert_eq(relu.finished_at_iso, result.finished_at_iso)
	assert_eq(relu.rider_name(0), "Alice", "les noms du depart viennent du roster")
	assert_not_null(relu.config, "la configuration est relue")


func test_rejeu_d_une_course_distance_le_classement_est_identique() -> void:
	var original := _run_recorded_race(_config(), [45.0, 43.0])
	var loaded := Replay.load_file(_races.path_join("%s.json" % original.uuid))
	assert_true(loaded.ok, loaded.error)

	var replayed := Replay.replay(loaded)
	assert_not_null(replayed, "le rejeu doit produire un resultat")
	assert_eq(replayed.ranking, original.ranking, "meme classement")
	assert_eq(replayed.ranking, Array(loaded.recorded_ranking))
	assert_eq(replayed.elapsed_ms, original.elapsed_ms, "meme instant de fin")
	assert_eq(replayed.finished_ms[0], original.finished_ms[0])
	assert_eq(replayed.finished_ms[1], original.finished_ms[1])


func test_rejeu_d_une_poursuite_les_eliminations_sont_identiques() -> void:
	var config := _config()
	config.mode = RaceConfig.Mode.PURSUIT
	config.active_riders = [0, 1, 2, 3]
	config.gap_m = 30.0
	var original := _run_recorded_race(config, [55.0, 50.0, 45.0, 40.0])
	assert_not_null(original)

	var loaded := Replay.load_file(_races.path_join("%s.json" % original.uuid))
	var replayed := Replay.replay(loaded)
	assert_not_null(replayed)
	assert_eq(replayed.ranking, original.ranking)
	assert_eq(replayed.eliminated, original.eliminated)


func test_rejeu_d_une_course_interrompue_rend_le_classement_partiel() -> void:
	# Une course arretee laisse desormais sa trace ; encore faut-il pouvoir en
	# tirer quelque chose. Le moteur n'y atteint jamais sa condition de fin, et
	# le rejeu rendait `null` : le fichier le plus utile apres un incident
	# etait le seul qu'on ne pouvait pas rejouer.
	var config := _config()
	config.distance_m = 500.0
	var engine := RaceEngine.new()
	_recorder.begin_race(config, {0: {"name": "Alice"}, 1: {"name": "Bob"}})
	engine.arm(config, 0)
	for value: int in [3, 2, 1, 0]:
		engine.on_countdown(value)

	var physics := Physics.new(config.roller_mm)
	var distances := [0.0, 0.0, 0.0, 0.0]
	var ms := 0
	while ms < 5000:
		ms += 10
		var ticks: Array = []
		for rider: int in range(Protocol.MAX_RIDERS):
			var kph: float = [45.0, 40.0][rider] if rider < 2 else 0.0
			distances[rider] += kph * Physics.KPH_TO_MM_PER_MS * 10.0
			ticks.append(int(floor(distances[rider] / physics.circumference_mm)))
		engine.on_progress(ticks, ms)
		_recorder.record_sample(engine.race_state().ticks, ms)

	engine.abort("arrêt opérateur")
	var original := engine.result()
	assert_not_null(original, "l'abandon produit un resultat partiel")
	assert_false(_recorder.finish_race(original).is_empty())

	var loaded := Replay.load_file(_races.path_join("%s.json" % original.uuid))
	assert_true(loaded.ok, loaded.error)
	var replayed := Replay.replay(loaded)
	assert_not_null(replayed, "une course interrompue se rejoue aussi")
	assert_true(replayed.interrupted, "et se declare interrompue")
	assert_string_contains(replayed.interruption_note, "opérateur")
	assert_eq(replayed.ranking, original.ranking, "meme classement partiel")
	assert_almost_eq(replayed.distance_m[0], original.distance_m[0], 0.01)
	assert_almost_eq(replayed.distance_m[1], original.distance_m[1], 0.01)


func test_un_json_de_format_inconnu_est_refuse_proprement() -> void:
	AppPaths.ensure_dir(_races)
	var path := _races.path_join("bidon.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string('{"format": "autre-chose/9"}')
	file.close()
	var loaded := Replay.load_file(path)
	assert_false(loaded.ok)
	assert_string_contains(loaded.error, "format inconnu")


func test_un_fichier_absent_est_refuse_proprement() -> void:
	var loaded := Replay.load_file(_races.path_join("nexiste_pas.json"))
	assert_false(loaded.ok)
	assert_string_contains(loaded.error, "introuvable")


# =============================================================================
# Chemins par systeme — docs/02 §5
# =============================================================================

func test_les_chemins_suivent_la_convention_du_systeme() -> void:
	var config_dir := AppPaths.config_dir()
	assert_false(config_dir.is_empty())
	assert_string_contains(config_dir.to_lower(), "silversprint")
	assert_string_contains(AppPaths.settings_path(), "settings.json")
	assert_string_contains(AppPaths.logs_dir(), "logs")
	assert_string_contains(AppPaths.races_dir(), "races")


func test_le_nom_du_journal_quotidien_suit_le_format_v1() -> void:
	var name := AppPaths.daily_log_name({"year": 2026, "month": 8, "day": 31})
	assert_eq(name, "2026_08_31_SilverSprintRaceLog.csv")


# =============================================================================
# Rejeu d'une trace REELLE — la derniere trame R: manque (docs/01 §5.6)
# =============================================================================


func test_rejeu_d_une_trace_reelle_ou_la_derniere_trame_manque() -> void:
	# Le firmware cesse d'emettre dans la passe ou le dernier tick fait franchir
	# la ligne : la derniere R: recue porte un tick de moins que la cible, puis
	# arrive <idx>F:. La course vecue s'est terminee grace a cette trame ; le
	# rejeu, qui ne rejouait que les R:, restait un tick sous la cible.
	var config := _config()
	var engine := RaceEngine.new()
	var produced: Array[RaceResult] = []
	engine.race_finished.connect(func(r: RaceResult) -> void: produced.append(r))
	engine.rider_finished.connect(func(rider: int, ms: int, rank: int) -> void:
		_recorder.record_rider_finished(rider, ms, rank))

	_recorder.begin_race(config, {0: {"name": "Alice"}, 1: {"name": "Bob"}})
	engine.arm(config, 0)
	for value: int in [3, 2, 1, 0]:
		engine.on_countdown(value)

	var physics := Physics.new(config.roller_mm)
	var target := physics.metres_to_ticks(config.distance_m)
	var distances := [0.0, 0.0]
	var speeds := [45.0, 43.0]
	var ms := 0
	var last_ms := 0
	while ms < 120000:
		ms += 10
		var ticks: Array = [0, 0, 0, 0]
		for rider: int in range(2):
			distances[rider] += speeds[rider] * Physics.KPH_TO_MM_PER_MS * 10.0
			ticks[rider] = int(floor(distances[rider] / physics.circumference_mm))
		# Le tick qui fait franchir la ligne au DERNIER n'est jamais transmis.
		if ticks[1] >= target:
			break
		engine.on_progress(ticks, ms)
		_recorder.record_sample(engine.race_state().ticks, ms)
		last_ms = ms

	assert_eq(engine.race_state().ticks[1], target - 1, "la derniere R: est un tick sous la cible")
	assert_eq(engine.state(), RaceEngine.State.RUNNING, "sans F:, la course attend")

	# Le boitier annonce l'arrivee : observation enregistree PUIS soumise.
	_recorder.record_hardware_finish(1, last_ms + 2)
	engine.on_rider_finish(1, last_ms + 2)
	assert_eq(produced.size(), 1, "la course vecue se termine sur la trame F:")
	var original := produced[0]
	_recorder.finish_race(original)

	var loaded := Replay.load_file(_races.path_join("%s.json" % original.uuid))
	assert_true(loaded.ok, loaded.error)
	assert_eq(loaded.hardware_finishes.size(), 1, "la trace porte la trame F:")
	var replayed := Replay.replay(loaded)
	assert_not_null(replayed, "le rejeu se termine")
	assert_eq(replayed.ranking, original.ranking, "meme classement")
	assert_gt(replayed.finished_ms[1], 0, "Bob est arrive au rejeu aussi")
	assert_eq(replayed.finished_ms[1], original.finished_ms[1], "au meme instant")


# =============================================================================
# Historique du jour — docs/02 §5
# =============================================================================

## Ecrit un JSON de course minimal date d'un autre jour : il ne doit pas
## entrer dans l'historique d'aujourd'hui.
func _write_foreign_day_race(uuid: String, started_at: String) -> void:
	# Nomme comme `_make_uuid` : l'horodatage UTC du depart, puis le label.
	var stamp := "00000000-000000"
	if started_at.length() >= 19:
		stamp = "%s-%s" % [
			started_at.substr(0, 10).replace("-", ""), started_at.substr(11, 8).replace(":", "")
		]
	var file := FileAccess.open(_races.path_join("%s-%s.json" % [stamp, uuid]), FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"format": "silversprint-race/1",
		"uuid": uuid,
		"started_at": started_at,
		"finished_at": started_at,
		"config": {"mode": "distance", "active_riders": [0, 1]},
		"result": {"ranking": [1, 0], "elapsed_ms": 9000, "end_reason": 1},
	}))
	file.close()


func test_l_historique_du_jour_est_relu_depuis_les_json() -> void:
	var first := _run_recorded_race(_config(), [45.0, 43.0])
	var second := _run_recorded_race(_config(), [40.0, 44.0])
	_write_foreign_day_race("veille", "2000-01-01T22:30:00")
	_write_foreign_day_race("brouillon", "pas-une-date")
	assert_eq(DirAccess.get_files_at(_races).size(), 4, "quatre fichiers sur disque")

	# Un recorder NEUF, comme apres un redemarrage du logiciel.
	var reloaded := Recorder.new(_logs, _races).load_day()
	assert_eq(reloaded.size(), 2, "seules les courses du jour")
	# Les deux courses sont parties dans la meme seconde : l'ordre de depart
	# est teste plus bas, sur des dates distinctes.
	var uuids := [reloaded[0].uuid, reloaded[1].uuid]
	uuids.sort()
	var expected := [first.uuid, second.uuid]
	expected.sort()
	assert_eq(uuids, expected, "les deux courses du jour, rien d'autre")

	var relu: RaceResult = reloaded[0] if reloaded[0].uuid == second.uuid else reloaded[1]
	assert_eq(relu.ranking, second.ranking, "meme classement")
	assert_eq(relu.winner(), 1, "Bob a gagne la seconde")
	assert_eq(relu.mode, "distance")
	assert_eq(relu.elapsed_ms, second.elapsed_ms)
	assert_eq(relu.end_reason, RaceRule.EndReason.ALL_FINISHED)
	assert_eq(relu.finished_ms[0], second.finished_ms[0])
	assert_eq(relu.finished_ms[1], second.finished_ms[1])
	assert_almost_eq(relu.distance_m[1], second.distance_m[1], 0.01)
	assert_almost_eq(relu.avg_kph[1], second.avg_kph[1], 0.01)
	assert_almost_eq(relu.max_kph[1], second.max_kph[1], 0.01)
	assert_false(relu.interrupted)
	assert_eq(relu.finished_at_iso, second.finished_at_iso)
	assert_not_null(relu.config, "la configuration est relue aussi")
	assert_eq(relu.config.active_riders, [0, 1])


func test_le_fichier_garde_le_nom_entier_pas_celui_qui_tient_a_l_ecran() -> void:
	# Defaut introduit par la troncature des noms longs : `to_recorder_map`
	# passait par `display_name()`, si bien que le nom ECRIT AU DISQUE etait
	# ampute et portait des points de suspension. Les fichiers doivent garder
	# ce que l'operateur a saisi ; c'est l'affichage qui borne, pas la donnee.
	var roster := Roster.new()
	roster.set_active(0, true)
	roster.rider(0).name = "Jean-Baptiste de la Tour du Pin"
	roster.set_active(1, true)

	_recorder.begin_race(_config(), roster.to_recorder_map())
	var result := RaceResult.new()
	result.mode = "distance"
	result.ranking = [0, 1]
	result.end_reason = RaceRule.EndReason.ALL_FINISHED
	result.finished_ms[0] = 8000
	result.finished_ms[1] = 9000
	_recorder.finish_race(result)

	assert_eq(result.rider_name(0), "Jean-Baptiste de la Tour du Pin", "le nom entier est ecrit")
	assert_eq(result.display_name(0).length(), Roster.MAX_DISPLAY_NAME, "l'ecran, lui, borne")
	# Une piste sans nom reste identifiable a la relecture, sans que le fichier
	# invente un nom que personne n'a saisi.
	assert_eq(result.rider_name(1), "Piste 2")

	var relu := Recorder.new(_logs, _races).load_day()[0]
	assert_eq(relu.rider_name(0), "Jean-Baptiste de la Tour du Pin", "et il survit au disque")


func test_le_resultat_porte_les_noms_du_depart_et_les_relit() -> void:
	var result := _run_recorded_race(_config(), [45.0, 43.0])
	assert_eq(result.rider_name(0), "Alice", "le nom du depart, porte par le resultat")
	assert_eq(result.rider_name(1), "Bob")
	assert_eq(result.rider_name(2), "Piste 3", "une piste sans nom reste identifiable")

	var relu := Recorder.new(_logs, _races).load_day()[0]
	assert_eq(relu.rider_name(0), "Alice", "relu depuis le JSON")
	assert_eq(relu.rider_name(1), "Bob")


func test_le_resultat_porte_les_dossards_du_depart_et_les_relit() -> void:
	# MEME REGLE QUE LES NOMS, et pour la meme raison : l'operateur les saisit
	# avant la course et peut les changer entre deux manches. Sans capture, le
	# tableau reetiquetterait une course passee avec les numeros de la suivante
	# — une erreur deja commise deux fois sur les noms.
	#
	# Le JSON portait DEJA le dossard : le fichier enregistre le roster entier,
	# on ne le relisait simplement pas. Les courses deja ecrites retrouvent donc
	# leurs numeros sans changement de format.
	var result := _run_recorded_race(_config(), [45.0, 43.0])
	assert_eq(result.rider_dossard(0), "7", "le dossard du depart, porte par le resultat")
	assert_eq(result.rider_dossard(1), "12")
	assert_eq(result.rider_dossard(2), "", "une piste sans dossard n'en invente pas")

	var relu := Recorder.new(_logs, _races).load_day()[0]
	assert_eq(relu.rider_dossard(0), "7", "relu depuis le JSON")
	assert_eq(relu.rider_dossard(1), "12")
	# ECRIT EN NOMBRE DANS CE FICHIER — le montage de test le fait, et un
	# fichier edite a la main le peut aussi. JSON n'a qu'un type numerique :
	# tout revient en flottant, et un dossard « 7.0 » sur un tableau de
	# resultats se lit comme une erreur du logiciel.
	assert_false(relu.rider_dossard(0).contains("."), "jamais de dossard a virgule")


func test_seuls_les_fichiers_du_jour_sont_ouverts() -> void:
	# Le dossier `races/` grossit de plusieurs Mo par soiree et ne s'elague
	# jamais : parser chaque fichier au lancement finirait par couter des
	# secondes. Le nom horodate suffit a ecarter les autres jours sans ouvrir.
	_run_recorded_race(_config(), [45.0, 43.0])
	for day: int in [1, 2, 3]:
		_write_foreign_day_race("ancien", "2020-01-%02dT12:00:00" % day)
	var recorder := Recorder.new(_logs, _races)
	assert_eq(recorder.load_day().size(), 1)
	assert_eq(recorder.last_scan_opened(), 1, "un seul fichier ouvert sur quatre")


func test_l_heure_d_arrivee_se_lit_en_heure_locale() -> void:
	# Les fichiers sont en UTC ; l'operateur lit l'heure de la salle. Sur une
	# machine reglee sur UTC+2, « 19:47 UTC » se lit « 21:47 ».
	var result := RaceResult.new()
	result.finished_at_iso = "2026-09-02T19:47:05"
	var bias_min := int(Time.get_time_zone_from_system()["bias"])
	var expected_min := (19 * 60 + 47 + bias_min) % (24 * 60)
	if expected_min < 0:
		expected_min += 24 * 60
	assert_eq(result.finished_at_local(), "%02d:%02d" % [expected_min / 60, expected_min % 60])
	assert_eq(RaceResult.new().finished_at_local(), "", "pas d'heure, pas de texte")


func test_le_jour_est_la_journee_d_exploitation_celle_du_csv() -> void:
	# Une course partie a 23 h 30 en heure locale d'un fuseau UTC+2 est ecrite
	# « 21:30 UTC » : elle est de la journee locale. Une autre a 00 h 01 le
	# LENDEMAIN l'est aussi — meme soiree, apres minuit (docs/02 §5). Celle de
	# 00 h 30 le 15, en revanche, appartient a la soiree du 14 : c'est la
	# journee d'exploitation qui tranche, pas le calendrier. On construit tout
	# a partir d'un « maintenant » fictif, le 15 juin, avec le fuseau machine.
	var bias_s := int(Time.get_time_zone_from_system()["bias"]) * 60
	var local_midnight := Time.get_unix_time_from_datetime_dict(
		{"year": 2030, "month": 6, "day": 15, "hour": 0, "minute": 0, "second": 0}
	)
	var utc_of := func(local_unix: int) -> String:
		return Time.get_datetime_string_from_unix_time(local_unix - bias_s)
	_write_foreign_day_race("nuit", utc_of.call(local_midnight + 30 * 60))
	_write_foreign_day_race("soir", utc_of.call(local_midnight + 23 * 3600 + 30 * 60))
	_write_foreign_day_race("lendemain", utc_of.call(local_midnight + 24 * 3600 + 60))
	_write_foreign_day_race("veille", utc_of.call(local_midnight - 60))

	var day := Recorder.new(_logs, _races).load_day(
		{"year": 2030, "month": 6, "day": 15, "hour": 20, "minute": 0, "second": 0}
	)
	var uuids: Array[String] = []
	for result: RaceResult in day:
		uuids.append(result.uuid)
	assert_eq(uuids, ["soir", "lendemain"], "la soiree du 15 juin, minuit franchi, dans l'ordre")


func test_une_soiree_qui_passe_minuit_reste_une_seule_journee() -> void:
	# LE CAS DU TERRAIN. Un goldsprint tourne de 20 h a 1 h du matin. Si le
	# logiciel redemarre a 00 h 30 — plantage, machine changee —, `docs/02` §5
	# exige que l'historique ne soit PAS vide. Decoupe au calendrier, il l'etait :
	# les courses de 20 h a 23 h 59 portaient la veille.
	var bias_s := int(Time.get_time_zone_from_system()["bias"]) * 60
	var local_midnight := Time.get_unix_time_from_datetime_dict(
		{"year": 2030, "month": 6, "day": 16, "hour": 0, "minute": 0, "second": 0}
	)
	var utc_of := func(local_unix: int) -> String:
		return Time.get_datetime_string_from_unix_time(local_unix - bias_s)
	_write_foreign_day_race("avant-minuit", utc_of.call(local_midnight - 4 * 3600))
	_write_foreign_day_race("apres-minuit", utc_of.call(local_midnight + 20 * 60))
	# La veille au soir : une AUTRE soiree, qui ne doit pas remonter.
	_write_foreign_day_race("veille", utc_of.call(local_midnight - 28 * 3600))

	# Il est 00 h 30 le 16 juin ; l'operateur relance le logiciel.
	var day := Recorder.new(_logs, _races).load_day(
		{"year": 2030, "month": 6, "day": 16, "hour": 0, "minute": 30, "second": 0}
	)
	var uuids: Array[String] = []
	for result: RaceResult in day:
		uuids.append(result.uuid)
	assert_eq(uuids, ["avant-minuit", "apres-minuit"], "toute la soiree, des deux cotes de minuit")


func test_le_csv_dapres_minuit_porte_la_date_de_la_soiree() -> void:
	# Meme decoupe pour le nom du fichier : sinon la soiree se scinderait en
	# deux CSV, et l'operateur en exporterait la moitie.
	assert_eq(
		AppPaths.daily_log_name({"year": 2030, "month": 6, "day": 16, "hour": 0, "minute": 10}),
		"2030_06_15_SilverSprintRaceLog.csv",
		"00 h 10 appartient a la soiree de la veille"
	)
	assert_eq(
		AppPaths.daily_log_name({"year": 2030, "month": 6, "day": 16, "hour": 23, "minute": 50}),
		"2030_06_16_SilverSprintRaceLog.csv",
		"23 h 50 est du jour meme"
	)
	assert_eq(
		AppPaths.daily_log_name({"year": 2030, "month": 6, "day": 16, "hour": 5, "minute": 0}),
		"2030_06_16_SilverSprintRaceLog.csv",
		"5 h pile ouvre la journee"
	)
	assert_eq(
		AppPaths.daily_log_name({"year": 2030, "month": 6, "day": 1, "hour": 4, "minute": 59}),
		"2030_05_31_SilverSprintRaceLog.csv",
		"la bascule traverse aussi les changements de mois"
	)


func test_le_csv_dit_qu_un_photo_finish_n_a_pas_pu_etre_departage() -> void:
	# Sur cinquante metres, un tick vaut 36 cm et les trames tombent a 100 Hz :
	# deux coureurs franchissent souvent DANS LA MEME TRAME. L'ecran dit alors
	# « photo-finish » et le tableau operateur l'explique — le CSV, lui, ecrivait
	# deux temps identiques avec les rangs 1 et 2, sans un mot. Relu six mois
	# plus tard, rien ne distinguait un ex aequo d'une coincidence d'arrondi.
	var config := _config()
	var result := RaceResult.new()
	result.mode = "distance"
	result.ranking = [0, 1] as Array[int]
	result.finished_ms = [5016, 5016, 0, 0] as Array[int]
	result.distance_m = [50.0, 50.0, 0.0, 0.0] as Array[float]
	result.end_reason = RaceRule.EndReason.ALL_FINISHED

	_recorder.begin_race(config)
	_recorder.finish_race(result)
	# LU AVEC UN VRAI PARSEUR CSV : la note porte une virgule, donc le champ est
	# entoure de guillemets. Un decoupage naif sur les virgules la coupait en
	# deux — et c'est precisement ce que fait un tableur, correctement.
	var notes: Array[String] = []
	var file := FileAccess.open(_recorder.csv_path(), FileAccess.READ)
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() > 10 and row[1] == "RACE_FINISH":
			notes.append(row[10])
	file.close()
	assert_eq(notes.size(), 2, "une ligne par coureur")
	for note: String in notes:
		assert_string_contains(note, "photo-finish", "l'ex aequo est dit : %s" % note)
		assert_string_contains(note, "tous arrivés", "sans perdre le motif de fin")


func test_un_penalise_n_emporte_jamais_de_distance_negative() -> void:
	# LA MOITIE DU DEFAUT AVAIT ETE REPAREE. La position d'un penalise est
	# negative tant qu'il n'a pas remonte son handicap ; la moyenne calculee
	# dessus donnait `-3272 km/h`, ce qui a ete corrige. La DISTANCE, elle,
	# etait restee brute — et c'est elle qui part au podium public, au tableau
	# de l'operateur, au CSV et au JSON.
	#
	# Le cas se produit des qu'une course s'arrete avant que le penalise ait
	# rattrape la ligne : abandon, elimination en poursuite, ou gong d'une
	# course en temps courte.
	var config := _config()
	config.mode = RaceConfig.Mode.TIME
	config.duration_s = 20.0
	config.false_start_policy = RaceConfig.FalseStartPolicy.PENALTY
	config.false_start_penalty_m = 10.0

	var state := RaceState.new(config)
	state.handicap_m[1] = -config.false_start_penalty_m
	var physics := Physics.new(config.roller_mm)
	# La piste 2 n'a roule que quatre metres : elle est encore six metres
	# DERRIERE la ligne quand la course s'arrete.
	state.apply_sample(
		[physics.metres_to_ticks(60.0), physics.metres_to_ticks(4.0), 0, 0], 8000
	)
	assert_lt(state.distance_m[1], 0.0, "sa position est bien negative dans l'etat")

	var result := RaceResult.from_state(state, RuleTime.new(), RaceRule.EndReason.TIME_ELAPSED)
	assert_gte(result.distance_m[1], 0.0, "mais le resultat ne l'emporte pas")
	assert_gte(result.avg_kph[1], 0.0, "pas plus que la moyenne")
	# Le classement, lui, est calcule sur l'etat AVANT : le borner ne change
	# l'ordre de personne.
	assert_eq(result.ranking[0], 0, "la piste qui mene reste premiere")

	# Et rien de negatif n'atteint le disque, ni le CSV ni le JSON.
	_recorder.begin_race(config, {0: {"name": "Alice"}, 1: {"name": "Bob"}})
	_recorder.finish_race(result)
	var text := "\n".join(Array(_read_csv_lines()))
	assert_false(text.contains(",-"), "aucun nombre negatif dans le journal")
	var relu := Recorder.new(_logs, _races).load_day()[0]
	assert_gte(relu.distance_m[1], 0.0, "ni au rechargement du JSON")


func test_aucun_champ_du_csv_ne_peut_decaler_les_colonnes() -> void:
	# L'echappement ne portait que sur la note, parce que c'est la qu'on
	# attendait une virgule. Mais le DOSSARD est un champ de texte libre saisi
	# par l'operateur : « 7,5 » suffisait a produire une ligne de DOUZE colonnes
	# dans un fichier qui en annonce onze. Tout ce qui suit se decalait — la
	# distance devenait un morceau du dossard, le temps devenait la distance —
	# et rien ne le signalait.
	#
	# C'est le fichier meme que `DEPANNAGE` fait envoyer au developpeur devant
	# un resultat suspect : un decalage silencieux y est le pire des defauts,
	# puisqu'il rend menteur l'outil du diagnostic.
	var config := _config()
	# Une virgule, un guillemet et un point-virgule : les trois pieges usuels.
	_recorder.begin_race(config, {
		0: {"name": "Alice", "dossard": "7,5"},
		1: {"name": "Bob \"le rapide\"", "dossard": "9;2"},
	})
	_recorder.record_rider_finished(0, 20000, 1)
	_recorder.record_tick_rejected(1, "valeur folle, ecartee")

	var file := FileAccess.open(_recorder.csv_path(), FileAccess.READ)
	assert_not_null(file, "le journal existe")
	var header := file.get_csv_line()
	assert_eq(header.size(), 11, "l'en-tete annonce onze colonnes")
	var rows := 0
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() <= 1:
			continue
		rows += 1
		assert_eq(
			row.size(), header.size(),
			"ligne « %s » : autant de colonnes que l'en-tete" % row[1]
		)
	assert_gte(rows, 3, "les trois lignes ont bien ete ecrites")


func test_un_dossard_a_virgule_se_relit_intact() -> void:
	# Echapper ne suffit pas : il faut que la valeur REVIENNE telle quelle.
	var config := _config()
	_recorder.begin_race(config, {0: {"name": "Alice", "dossard": "7,5"}})
	_recorder.record_rider_finished(0, 20000, 1)
	var file := FileAccess.open(_recorder.csv_path(), FileAccess.READ)
	file.get_csv_line()
	var found := ""
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() > 4 and row[1] == "RIDER_FINISH":
			found = row[4]
	assert_eq(found, "7,5", "le dossard sort du fichier comme il y est entre")
