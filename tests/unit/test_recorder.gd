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
	_recorder.record_abort("arret operateur")

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

func test_le_json_contient_la_trace_complete_des_trames() -> void:
	var result := _run_recorded_race(_config(), [45.0, 43.0])
	var path := _races.path_join("%s.json" % result.uuid)
	assert_true(FileAccess.file_exists(path), "le JSON de course doit exister")

	var loaded := Replay.load_file(path)
	assert_true(loaded.ok, loaded.error)
	# 100 m a 45 km/h = 8 s a 100 Hz : environ 800 trames.
	assert_gt(loaded.samples.size(), 700)
	assert_eq((loaded.samples[0] as Array).size(), 5, "[t0,t1,t2,t3,elapsed_ms]")


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
