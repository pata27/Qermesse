## La configuration d'une course dans sa trace JSON — docs/02 §5.
##
## `test_recorder` laisse `config` a l'enregistreur et se contente de « relue ».
## C'est la que deux champs manquaient : la penalite de faux depart et la
## fenetre de lissage. Le rejeu les prenait par defaut — une course a 25 m de
## penalite se rejouait a 10 m, et l'outil accusait d'ecart une trace saine.
extends GutTest

const TEST_ROOT := "user://test_trace_config"

## Une valeur loin du defaut pour chaque champ qui n'est pas un simple nombre,
## valide pour `RaceConfig.validate()`.
const MUTATIONS := {
	"mode": RaceConfig.Mode.TIME,
	"active_riders": [0, 2, 3],
	"false_start_policy": RaceConfig.FalseStartPolicy.PENALTY,
}

var _logs: String
var _races: String


func before_each() -> void:
	_logs = ProjectSettings.globalize_path(TEST_ROOT).path_join("logs")
	_races = ProjectSettings.globalize_path(TEST_ROOT).path_join("races")
	_wipe()


func after_all() -> void:
	_wipe()


func _wipe() -> void:
	for dir: String in [_logs, _races]:
		if DirAccess.dir_exists_absolute(dir):
			for name: String in DirAccess.get_files_at(dir):
				DirAccess.remove_absolute(dir.path_join(name))


func test_chaque_champ_de_la_configuration_survit_au_json_de_course() -> void:
	# Enumere les champs DECLARES de RaceConfig, tous mutes loin de leur
	# defaut, et exige chacun de l'autre cote du JSON. Le test s'entretient
	# seul : un champ ajoute a RaceConfig et oublie dans `_write_json` ou dans
	# `Replay.config_from_dict` echouera ici.
	var config := RaceConfig.new()
	var expected := {}
	for property: Dictionary in config.get_property_list():
		if not (int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var name := str(property["name"])
		var before: Variant = config.get(name)
		var after: Variant = _mutate(name, before)
		assert_ne(after, before, "champ %s : type non gere par le test, a completer" % name)
		config.set(name, after)
		expected[name] = config.get(name)
	assert_gt(expected.size(), 10, "la reflexion doit voir les champs de la configuration")
	assert_true(config.is_valid(), "la configuration mutee doit rester armable")

	var recorder := Recorder.new(_logs, _races)
	var result := RaceResult.new()
	result.mode = config.mode_name()
	recorder.begin_race(config, {})
	assert_false(recorder.finish_race(result).is_empty(), "le JSON doit s'ecrire")

	var day := Recorder.new(_logs, _races).load_day()
	assert_eq(day.size(), 1, "la course est relue")
	var relu: RaceConfig = day[0].config
	for name: String in expected:
		assert_eq(relu.get(name), expected[name], "champ %s : perdu par le JSON de course" % name)


func _mutate(name: String, before: Variant) -> Variant:
	if MUTATIONS.has(name):
		return MUTATIONS[name]
	if before is float:
		return float(before) + 7.0
	if before is int:
		return int(before) + 3
	return before


func test_le_chemin_du_journal_est_connu_avant_la_premiere_course() -> void:
	# Le manuel fait reperer le chemin du CSV LA VEILLE, dans une salle vide.
	# `csv_path()` restait vide jusqu'a la premiere ligne ecrite : le panneau
	# affichait « CSV : » sans rien derriere.
	var recorder := Recorder.new(_logs, _races)
	var expected := _logs.path_join(AppPaths.daily_log_name())
	assert_eq(recorder.csv_path(), expected, "hors course : le journal du jour, ou ira la prochaine")

	# Une course ouverte impose SON journal — celui du jour de son depart —,
	# meme si ce n'est pas celui d'aujourd'hui.
	var veille := {"year": 1999, "month": 12, "day": 31, "hour": 4, "minute": 59, "second": 0}
	recorder.begin_race(RaceConfig.new(), {}, veille)
	assert_ne(recorder.csv_path(), expected, "en course : le journal de la course")
	assert_true(recorder.csv_path().ends_with(AppPaths.daily_log_name(veille)))
