## Tests des reglages et du roster — docs/02 §5.
extends GutTest

const TEST_ROOT := "user://test_settings"

var _dir: String


func before_each() -> void:
	_dir = ProjectSettings.globalize_path(TEST_ROOT)
	_wipe()


func after_all() -> void:
	_wipe()


func _wipe() -> void:
	if DirAccess.dir_exists_absolute(_dir):
		for name: String in DirAccess.get_files_at(_dir):
			DirAccess.remove_absolute(_dir.path_join(name))


func _path(name: String) -> String:
	return _dir.path_join(name)


# =============================================================================
# Reglages
# =============================================================================

func test_un_aller_retour_disque_preserve_les_reglages() -> void:
	var settings := Settings.new()
	settings.preferred_port = "/dev/ttyACM0"
	settings.use_simulator = false
	settings.roller_mm = 120.5
	settings.mode = RaceConfig.Mode.PURSUIT
	settings.gap_m = 75.0
	settings.false_start_policy = RaceConfig.FalseStartPolicy.RESTART
	assert_true(settings.save(_path("settings.json")))

	var reloaded := Settings.new()
	assert_true(reloaded.load_from(_path("settings.json")))
	assert_eq(reloaded.preferred_port, "/dev/ttyACM0")
	assert_false(reloaded.use_simulator)
	assert_almost_eq(reloaded.roller_mm, 120.5, 0.001)
	assert_eq(reloaded.mode, RaceConfig.Mode.PURSUIT)
	assert_almost_eq(reloaded.gap_m, 75.0, 0.001)
	assert_eq(reloaded.false_start_policy, RaceConfig.FalseStartPolicy.RESTART)


func test_un_fichier_absent_laisse_les_valeurs_par_defaut() -> void:
	var settings := Settings.new()
	assert_false(settings.load_from(_path("jamais_ecrit.json")))
	assert_almost_eq(settings.roller_mm, Physics.DEFAULT_ROLLER_MM, 0.001)
	assert_eq(settings.mode, RaceConfig.Mode.DISTANCE)


func test_un_json_corrompu_ne_doit_jamais_empecher_le_demarrage() -> void:
	# Un fichier de reglages illisible la veille d'un evenement doit couter un
	# avertissement, pas la soiree.
	AppPaths.ensure_dir(_dir)
	var file := FileAccess.open(_path("settings.json"), FileAccess.WRITE)
	file.store_string("{ ceci n'est pas du JSON")
	file.close()

	var settings := Settings.new()
	assert_false(settings.load_from(_path("settings.json")))
	assert_eq(settings.mode, RaceConfig.Mode.DISTANCE, "valeurs par defaut conservees")
	# Le motif est RAPPORTE, pour que la couche applicative puisse l'afficher.
	assert_string_contains(JsonStore.last_error, "JSON invalide")


func test_une_valeur_hors_bornes_est_ramenee_dans_les_bornes() -> void:
	AppPaths.ensure_dir(_dir)
	var file := FileAccess.open(_path("settings.json"), FileAccess.WRITE)
	file.store_string('{"distance_m": 99999, "gap_m": -5, "duration_s": 1}')
	file.close()

	var settings := Settings.new()
	settings.load_from(_path("settings.json"))
	assert_eq(settings.distance_m, 5000.0, "borne haute de docs/02 §1")
	assert_eq(settings.gap_m, 10.0, "borne basse de docs/02 §3")
	assert_eq(settings.duration_s, 10.0, "borne basse de docs/02 §2")


func test_l_ecriture_est_atomique() -> void:
	# Une coupure pendant l'ecriture ne doit pas laisser un JSON tronque : on
	# verifie qu'aucun fichier temporaire ne subsiste apres coup.
	var settings := Settings.new()
	assert_true(settings.save(_path("settings.json")))
	assert_false(FileAccess.file_exists(_path("settings.json.tmp")))
	assert_true(FileAccess.file_exists(_path("settings.json")))


func test_les_reglages_produisent_une_configuration_de_course_valide() -> void:
	var settings := Settings.new()
	settings.mode = RaceConfig.Mode.PURSUIT
	settings.gap_m = 50.0
	var config := settings.to_race_config([0, 1])
	assert_true(config.is_valid(), ", ".join(config.validate()))
	assert_eq(config.mode, RaceConfig.Mode.PURSUIT)
	assert_eq(config.active_riders, [0, 1])


# =============================================================================
# Roster
# =============================================================================

func test_les_noms_des_riders_sont_persistes() -> void:
	# La v1 les perdait a chaque lancement — docs/02 §5.
	var roster := Roster.new()
	roster.rider(0).name = "Alice"
	roster.rider(0).dossard = "7"
	roster.rider(1).name = "Bob"
	roster.set_active(2, true)
	assert_true(roster.save(_path("roster.json")))

	var reloaded := Roster.new()
	assert_true(reloaded.load_from(_path("roster.json")))
	assert_eq(reloaded.rider(0).name, "Alice")
	assert_eq(reloaded.rider(0).dossard, "7")
	assert_eq(reloaded.rider(1).name, "Bob")
	assert_true(reloaded.rider(2).active)


func test_le_roster_par_defaut_a_deux_pistes_actives() -> void:
	# Configuration du boitier de l'utilisateur : deux capteurs cables.
	var roster := Roster.new()
	assert_eq(roster.active_lanes(), [0, 1])
	assert_eq(roster.riders.size(), Protocol.MAX_RIDERS)


func test_un_rider_sans_nom_reste_identifiable() -> void:
	# docs/03 §6 : aucune information ne doit reposer sur la seule couleur, et
	# aucune ligne ne doit rester vide a l'ecran spectacle.
	var roster := Roster.new()
	assert_eq(roster.rider(2).display_name(), "Piste 3")
	roster.rider(2).name = "Chloe"
	assert_eq(roster.rider(2).display_name(), "Chloe")


func test_chaque_piste_a_sa_couleur_de_la_palette() -> void:
	var roster := Roster.new()
	var seen: Array[String] = []
	for lane: int in range(Protocol.MAX_RIDERS):
		var color := roster.rider(lane).color
		assert_false(seen.has(color), "deux pistes ne peuvent pas partager une couleur")
		seen.append(color)
	assert_eq(roster.rider(0).color, "#00E5FF", "cyan, docs/04 §2")


func test_le_roster_alimente_le_csv_avec_noms_et_dossards() -> void:
	var roster := Roster.new()
	roster.rider(0).name = "Alice"
	roster.rider(0).dossard = "7"
	var map := roster.to_recorder_map()
	assert_eq(map.size(), 2, "seules les pistes actives")
	assert_eq((map[0] as Dictionary)["dossard"], "7")
	assert_eq((map[1] as Dictionary)["name"], "Piste 2")
