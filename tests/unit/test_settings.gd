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


## Valeur distincte de `current`, et qui reste dans les bornes de `from_dict` :
## les defauts sont tous au milieu de leur plage, un facteur 1,5 sur un flottant
## et un increment sur un entier y tiennent. Un futur reglage aux bornes plus
## serrees fera echouer ce test en le nommant — c'est le but.
func _mutate(current: Variant, type: int) -> Variant:
	match type:
		TYPE_BOOL:
			return not bool(current)
		TYPE_INT:
			return int(current) + 1
		TYPE_FLOAT:
			return float(current) * 1.5
		TYPE_STRING:
			return "%s-modifie" % str(current)
	return current


func test_tous_les_reglages_declares_font_l_aller_retour() -> void:
	# LE TEST S'ENTRETIENT SEUL. La version nommant les champs un a un n'en
	# couvrait que six sur dix-sept : un reglage ajoute puis oublie dans
	# `to_dict` ne serait jamais persiste, et aucun test ne l'aurait dit.
	# Celui-ci enumere les champs DECLARES et echouera sur le prochain oubli.
	var settings := Settings.new()
	var expected := {}
	for property: Dictionary in settings.get_property_list():
		if not (int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var name := str(property["name"])
		var value: Variant = _mutate(settings.get(name), int(property["type"]))
		settings.set(name, value)
		expected[name] = value

	assert_gt(expected.size(), 10, "la reflexion doit voir les reglages, pas une liste vide")
	assert_true(settings.save(_path("tous.json")))

	var reloaded := Settings.new()
	assert_true(reloaded.load_from(_path("tous.json")))
	for name: String in expected:
		var want: Variant = expected[name]
		var got: Variant = reloaded.get(name)
		if want is float:
			assert_almost_eq(float(got), float(want), 0.001, "reglage %s" % name)
		else:
			assert_eq(got, want, "reglage %s : absent de to_dict ou de from_dict ?" % name)


func test_le_fichier_de_reglages_se_lit_sans_connaitre_les_enumerations() -> void:
	# `"mode": 2` ne dit rien a qui ouvre le fichier — et `DEPANNAGE` donne son
	# chemin a l'operateur. La trace d'une course ecrit deja « poursuite » en
	# toutes lettres ; les reglages faisaient autrement.
	var settings := Settings.new()
	settings.mode = RaceConfig.Mode.PURSUIT
	settings.false_start_policy = RaceConfig.FalseStartPolicy.PENALTY
	assert_true(settings.save(_path("lisible.json")))

	var written := FileAccess.get_file_as_string(_path("lisible.json"))
	assert_string_contains(written, '"mode": "poursuite"')
	assert_string_contains(written, '"false_start_policy": "penalite"')

	var reloaded := Settings.new()
	assert_true(reloaded.load_from(_path("lisible.json")))
	assert_eq(reloaded.mode, RaceConfig.Mode.PURSUIT)
	assert_eq(reloaded.false_start_policy, RaceConfig.FalseStartPolicy.PENALTY)


func test_un_ancien_fichier_de_reglages_en_chiffres_se_relit_encore() -> void:
	# Les fichiers deja ecrits par les versions precedentes portent des
	# entiers : les refuser reviendrait a perdre les reglages d'un operateur a
	# la mise a jour, ce que docs/02 §5 interdit en substance.
	var file := FileAccess.open(_path("ancien.json"), FileAccess.WRITE)
	file.store_string('{"version": 1, "mode": 2, "false_start_policy": 3, "gap_m": 75.0}')
	file.close()

	var settings := Settings.new()
	assert_true(settings.load_from(_path("ancien.json")))
	assert_eq(settings.mode, RaceConfig.Mode.PURSUIT, "2 valait poursuite")
	assert_eq(settings.false_start_policy, RaceConfig.FalseStartPolicy.PENALTY, "3 valait penalite")
	assert_almost_eq(settings.gap_m, 75.0, 0.001, "et le reste suit")


func test_couper_les_preferences_isole_aussi_les_courses_enregistrees() -> void:
	# `preferences_enabled = false` protegeait les reglages et le roster, mais
	# le recorder continuait de viser les dossiers de l'operateur : les demos
	# lui ont ainsi depose 63 courses dans « Courses du jour », et deux
	# fichiers de test l'auraient fait aussi. Un seul sens pour ce drapeau :
	# ce controleur ne touche a AUCUNE donnee de l'utilisateur.
	var controller := AppController.new()
	controller.preferences_enabled = false
	add_child_autofree(controller)

	assert_ne(controller.recorder_logs_dir, AppPaths.logs_dir(), "pas le journal de l'operateur")
	assert_ne(controller.recorder_races_dir, AppPaths.races_dir(), "ni ses courses")
	assert_false(controller.recorder_logs_dir.is_empty(), "mais un dossier bien defini")

	# Un dossier explicite reste prioritaire : les outils et les tests visent ou
	# ils veulent.
	var chosen := AppController.new()
	chosen.preferences_enabled = false
	chosen.recorder_logs_dir = "/tmp/ss-test/logs"
	add_child_autofree(chosen)
	assert_eq(chosen.recorder_logs_dir, "/tmp/ss-test/logs")


func test_le_plein_ecran_du_spectacle_est_un_reglage_a_part_entiere() -> void:
	# `main.gd` passait `not single_window_mode` comme argument « plein ecran » :
	# vouloir la fenetre spectacle IMPLIQUAIT le plein ecran. L'operateur qui
	# la voulait en fenetre — pour la surveiller a cote de son panneau — la
	# retrouvait plein ecran a chaque lancement, alors que le commentaire du
	# code promettait « rouverte telle qu'elle a ete laissee ».
	var settings := Settings.new()
	assert_true(settings.spectacle_fullscreen, "par defaut oui : la cible est un projecteur")

	settings.single_window_mode = false
	settings.spectacle_fullscreen = false
	assert_true(settings.save(_path("spectacle.json")))

	var reloaded := Settings.new()
	assert_true(reloaded.load_from(_path("spectacle.json")))
	assert_false(reloaded.single_window_mode, "la fenetre est voulue")
	assert_false(reloaded.spectacle_fullscreen, "et elle est voulue EN FENETRE")


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


func test_tous_les_champs_d_un_rider_font_l_aller_retour() -> void:
	# Meme garde-fou que pour les reglages, sur l'autre fichier persiste : un
	# champ ajoute a `Rider` et oublie dans `to_dict` serait perdu en silence.
	var roster := Roster.new()
	var rider := roster.rider(1)
	var expected := {}
	for property: Dictionary in rider.get_property_list():
		if not (int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var name := str(property["name"])
		# La piste identifie le rider dans le fichier : la muter le deplacerait
		# au lieu de le modifier.
		if name == "lane":
			expected[name] = rider.lane
			continue
		# La couleur est ECRITE mais jamais RELUE : elle vient de la palette
		# figee, et un fichier ne doit pas pouvoir donner la meme couleur a
		# deux pistes. Exclusion voulue, pas un oubli — c'est ce test qui l'a
		# exigee en tombant.
		if name == "color":
			expected[name] = rider.color
			continue
		var value: Variant = _mutate(rider.get(name), int(property["type"]))
		rider.set(name, value)
		expected[name] = value

	assert_gt(expected.size(), 3, "la reflexion doit voir les champs d'un rider")
	assert_true(roster.save(_path("roster-complet.json")))

	var reloaded := Roster.new()
	assert_true(reloaded.load_from(_path("roster-complet.json")))
	for name: String in expected:
		assert_eq(
			reloaded.rider(1).get(name), expected[name],
			"champ %s : absent de Rider.to_dict ou de from_dict ?" % name
		)


func test_le_roster_par_defaut_a_deux_pistes_actives() -> void:
	# Configuration du boitier de l'utilisateur : deux capteurs cables.
	var roster := Roster.new()
	assert_eq(roster.active_lanes(), [0, 1])
	assert_eq(roster.riders.size(), Protocol.MAX_RIDERS)


func test_le_nom_qu_un_ecran_affiche_vient_du_depart_et_tient_dans_sa_colonne() -> void:
	# Deux corrections faites a des tours differents — le nom du DEPART porte
	# par le resultat, et sa troncature a la largeur affichable — etaient
	# recopiees ensemble dans quatre ecrans. Un cinquieme en aurait oublie une.
	var result := RaceResult.new()
	result.rider_names = {0: "Jean-Baptiste de la Tour du Pin", 1: "Bob"}

	var shown := result.display_name(0)
	assert_eq(shown.length(), Roster.MAX_DISPLAY_NAME, "borne a la largeur affichable")
	assert_true(shown.begins_with("Jean-Baptiste"))
	assert_eq(result.rider_name(0), "Jean-Baptiste de la Tour du Pin", "la donnee reste entiere")
	assert_eq(result.display_name(1), "Bob", "un nom court n'est pas touche")
	assert_eq(result.display_name(3), "Piste 4", "et une piste sans nom reste identifiable")


func test_un_nom_trop_long_est_tronque_pour_l_affichage() -> void:
	# La carte de l'ecran public donne 414 px au nom, soit une vingtaine de
	# caracteres : au-dela il passait par-dessus le compteur de vitesse et
	# debordait sur la scene. Le nom STOCKE, lui, n'est pas touche.
	var roster := Roster.new()
	roster.rider(0).name = "Jean-Baptiste de la Tour du Pin"
	var shown := roster.rider(0).display_name()
	assert_eq(shown.length(), Roster.MAX_DISPLAY_NAME, "borne a la largeur de la carte")
	assert_true(shown.ends_with("…"), "et l'on voit que c'est coupe : %s" % shown)
	assert_true(shown.begins_with("Jean-Baptiste"))
	assert_eq(roster.rider(0).name, "Jean-Baptiste de la Tour du Pin", "la donnee est intacte")

	roster.rider(1).name = "Bob"
	assert_eq(roster.rider(1).display_name(), "Bob", "un nom court n'est pas touche")


func test_un_rider_sans_nom_reste_identifiable() -> void:
	# docs/03 §6 : aucune information ne doit reposer sur la seule couleur, et
	# aucune ligne ne doit rester vide a l'ecran spectacle.
	var roster := Roster.new()
	assert_eq(roster.rider(2).display_name(), "Piste 3")
	roster.rider(2).name = "Chloe"
	assert_eq(roster.rider(2).display_name(), "Chloe")


func test_une_couleur_choisie_se_relit_mais_seulement_si_c_en_est_une() -> void:
	# La couleur ne se relisait PAS du fichier tant que la palette etait figee.
	# Elle se regle desormais — l'ecran public doit correspondre aux velos poses
	# sur les rouleaux (docs/04 §2) — donc elle se retrouve au lancement
	# suivant, comme les noms.
	#
	# Mais validee. Un fichier edite a la main peut porter n'importe quoi, et
	# une teinte illisible ne se decouvrirait qu'en soiree : la piste retrouve
	# alors son defaut, qui est toujours lisible.
	var file := FileAccess.open(_path("couleurs.json"), FileAccess.WRITE)
	file.store_string('{"riders": [' +
		'{"lane": 0, "name": "Alice", "active": true, "color": "#FF2E88"},' +
		'{"lane": 1, "name": "Bob", "active": true, "color": "pas-une-couleur"}]}')
	file.close()

	var roster := Roster.new()
	assert_true(roster.load_from(_path("couleurs.json")))
	assert_eq(roster.rider(0).name, "Alice", "le reste du fichier est bien relu")
	assert_eq(roster.rider(0).color, "#FF2E88", "la couleur choisie se retrouve")
	assert_eq(roster.rider(1).color, Roster.DEFAULT_COLORS[1], "l'invalide rend au defaut")


func test_la_couleur_se_choisit_se_valide_et_se_remet_au_defaut() -> void:
	var roster := Roster.new()
	assert_eq(roster.rider(0).color, "#00E5FF", "cyan par defaut, docs/04 §2")
	assert_true(roster.set_color(0, "#C81010"), "le velo rouge de la salle")
	assert_eq(roster.rider(0).color, "#C81010")
	# Point d'entree unique, validation unique : rien d'autre n'entre.
	assert_false(roster.set_color(0, "bleu marine"), "ce n'est pas une couleur")
	assert_eq(roster.rider(0).color, "#C81010", "et rien n'a bouge")
	roster.reset_color(0)
	assert_eq(roster.rider(0).color, Roster.DEFAULT_COLORS[0], "le bouton rend la charte")


func test_deux_pistes_de_meme_couleur_sont_signalees_pas_interdites() -> void:
	# docs/04 §2. Si la salle aligne deux velos rouges, l'operateur a raison
	# contre la charte — le numero de piste et le nom identifient toujours
	# chacun. Mais un doublon involontaire rend l'ecran ambigu, et cela se dit.
	var roster := Roster.new()
	var seen: Array[String] = []
	for lane: int in range(Protocol.MAX_RIDERS):
		assert_false(seen.has(roster.rider(lane).color), "la palette n'a pas de doublon")
		seen.append(roster.rider(lane).color)
	assert_eq(roster.clashing_lanes(), [] as Array[int], "et rien n'est signale au depart")

	roster.set_color(1, "#00D8F5")  # presque le cyan de la piste 1
	assert_eq(roster.clashing_lanes(), [0, 1] as Array[int], "les deux pistes sont nommees")
	assert_eq(roster.rider(1).color, "#00D8F5", "mais la couleur est bien prise")

	# Une piste INACTIVE ne gene personne : elle n'est pas a l'ecran.
	roster.set_active(1, false)
	assert_eq(roster.clashing_lanes(), [] as Array[int], "plus de conflit hors course")


func test_le_roster_alimente_le_csv_avec_noms_et_dossards() -> void:
	var roster := Roster.new()
	roster.rider(0).name = "Alice"
	roster.rider(0).dossard = "7"
	var map := roster.to_recorder_map()
	assert_eq(map.size(), 2, "seules les pistes actives")
	assert_eq((map[0] as Dictionary)["dossard"], "7")
	assert_eq((map[1] as Dictionary)["name"], "Piste 2")


# =============================================================================
# Developpement — la donnee que le capteur ne peut PAS fournir (docs/01 §6)
# =============================================================================


func test_le_developpement_fait_l_aller_retour_et_reste_borne() -> void:
	var settings := Settings.new()
	settings.development_m = 6.4
	var revived := Settings.new()
	revived.from_dict(settings.to_dict())
	assert_almost_eq(revived.development_m, 6.4, 0.001, "persiste tel quel")

	# Un developpement aberrant vient d'un fichier corrompu ou edite a la main :
	# on le ramene dans les bornes plutot que d'afficher une cadence absurde.
	var wild := Settings.new()
	wild.from_dict({"development_m": 900.0})
	assert_lt(wild.development_m, 21.0, "borne haute appliquee")
	wild.from_dict({"development_m": -3.0})
	assert_gt(wild.development_m, 0.0, "borne basse appliquee")


func test_le_developpement_ne_touche_a_aucun_calcul_de_course() -> void:
	# Garde-fou explicite : la cadence est un affichage. Si un jour quelqu'un
	# fait dependre une distance du developpement, ce test doit tomber.
	var settings := Settings.new()
	settings.development_m = 3.0
	var short_gear := settings.to_race_config([0, 1] as Array[int])
	settings.development_m = 12.0
	var long_gear := settings.to_race_config([0, 1] as Array[int])
	assert_eq(short_gear.distance_m, long_gear.distance_m, "distance inchangee")
	assert_eq(short_gear.roller_mm, long_gear.roller_mm, "rouleau inchange")
	assert_eq(
		short_gear.arming_commands(), long_gear.arming_commands(),
		"les commandes firmware ne dependent pas du developpement"
	)


func test_la_fenetre_de_lissage_reglee_atteint_vraiment_la_mesure() -> void:
	# `docs/01` §7 : « Retenir 20 echantillons (~200 ms) […] Parametre expose en
	# reglage avance. » Il l'etait a moitie : ecrit dans le fichier de reglages,
	# borne a la relecture, et lu par PERSONNE. `SpeedSmoother` prenait toujours
	# la constante. Un operateur qui l'aurait change n'aurait rien vu bouger.
	var settings := Settings.new()
	settings.speed_samples = 4
	var config := settings.to_race_config([0, 1] as Array[int])
	assert_eq(config.speed_samples, 4, "le reglage arrive dans la configuration")

	# Une fenetre courte suit une ACCELERATION bien plus vite qu'une longue.
	# La moyenne divise par le nombre d'echantillons DEJA vus : tant que la
	# fenetre n'est pas pleine, les deux donnent la meme valeur. Il faut donc
	# remplir, puis changer d'allure.
	var slow_config := settings.to_race_config([0, 1] as Array[int])
	slow_config.speed_samples = 40
	var quick_state := RaceState.new(config)
	var slow_state := RaceState.new(slow_config)
	var physics := Physics.new(config.roller_mm)
	var metres := 0.0
	var ms := 0
	# Quarante trames a allure lente : les deux fenetres sont pleines.
	for step: int in range(40):
		metres += 0.05
		ms += 10
		var ticks := physics.metres_to_ticks(metres)
		quick_state.apply_sample([ticks, 0, 0, 0], ms)
		slow_state.apply_sample([ticks, 0, 0, 0], ms)
	# Puis quatre trames a allure double.
	for step: int in range(4):
		metres += 0.20
		ms += 10
		var ticks := physics.metres_to_ticks(metres)
		quick_state.apply_sample([ticks, 0, 0, 0], ms)
		slow_state.apply_sample([ticks, 0, 0, 0], ms)
	assert_gt(
		quick_state.speed_kph[0], slow_state.speed_kph[0],
		"quatre echantillons suivent l'acceleration, quarante la lissent"
	)


func test_aucun_reglage_persiste_n_est_lettre_morte() -> void:
	# LE DEFAUT DE CLASSE. Un champ ecrit dans `settings.json` que rien ne lit
	# est une promesse faite a l'operateur et jamais tenue : il peut l'editer et
	# ne verra rien changer. Chaque champ doit avoir un lecteur ailleurs.
	var sources := ""
	for dir: String in ["res://core", "res://scenes", "res://hardware", "res://audio"]:
		sources += _read_scripts(dir)

	var orphans: Array[String] = []
	for entry: Dictionary in Settings.new().get_property_list():
		if int(entry["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		var name := str(entry["name"])
		if not sources.contains(".%s" % name):
			orphans.append(name)
	assert_eq(orphans, [] as Array[String], "des reglages persistes que rien ne lit")


## Concatene les scripts d'un dossier, sans `settings.gd` lui-meme : c'est
## AILLEURS qu'un reglage doit etre lu.
func _read_scripts(path: String) -> String:
	var out := ""
	var dir := DirAccess.open(path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		var full := path.path_join(name)
		if dir.current_is_dir():
			out += _read_scripts(full)
		elif name.get_extension() == "gd" and name != "settings.gd":
			var file := FileAccess.open(full, FileAccess.READ)
			if file != null:
				out += file.get_as_text()
		name = dir.get_next()
	dir.list_dir_end()
	return out


func test_reecrire_un_fichier_ne_le_fait_jamais_disparaitre() -> void:
	# L'ecriture atomique supprimait la destination AVANT de renommer. Entre les
	# deux, plus aucun fichier n'existait a ce chemin — et c'est le seul instant
	# ou une coupure fait des degats. `DEPANNAGE` decrit d'ailleurs cette perte
	# comme un cas connu : « disque coupe pendant l'ecriture ».
	#
	# Renommer par-dessus un fichier existant est atomique sur les systemes
	# POSIX et remplace la destination : la suppression ne servait a rien, et
	# elle ouvrait la fenetre que l'ecriture atomique existe pour fermer.
	var path := _path("atomique.json")
	assert_true(JsonStore.write(path, {"tour": 1}), "premiere ecriture")
	for tour: int in range(2, 6):
		assert_true(JsonStore.write(path, {"tour": tour}), "reecriture %d" % tour)
		assert_true(FileAccess.file_exists(path), "le fichier existe apres la reecriture %d" % tour)
		assert_eq(int(JsonStore.read(path).get("tour", 0)), tour, "et porte la valeur %d" % tour)
	# Aucun temporaire ne traine : un `.tmp` oublie serait relu un jour comme
	# une sauvegarde valable.
	assert_false(FileAccess.file_exists(path + ".tmp"), "pas de temporaire abandonne")


func test_une_ecriture_qui_echoue_laisse_l_ancien_fichier_intact() -> void:
	# C'est toute la promesse de l'ecriture atomique, et elle se verifie sur un
	# echec REEL : un dossier occupe le nom du fichier temporaire, donc rien ne
	# peut s'y ecrire. L'ancien contenu doit survivre entier.
	# Ce test ne prouve PAS la fermeture de la fenetre de coupure : elle n'est
	# observable qu'entre deux appels systeme, au moment precis ou le courant
	# tombe, et aucun test ne peut s'y placer. Il garde le contrat — un echec ne
	# detruit rien — qui est ce que l'operateur constate, et il attraperait la
	# regression evidente : supprimer la destination avant meme d'avoir ecrit le
	# temporaire.
	var path := _path("intact.json")
	assert_true(JsonStore.write(path, {"garde": "ancien"}), "le fichier de depart")
	DirAccess.make_dir_recursive_absolute(path + ".tmp")

	assert_false(JsonStore.write(path, {"garde": "nouveau"}), "l'ecriture echoue")
	assert_false(JsonStore.last_error.is_empty(), "et elle dit pourquoi")
	assert_eq(
		str(JsonStore.read(path).get("garde", "")), "ancien",
		"l'ancien contenu est intact — c'est toute la promesse"
	)
	DirAccess.remove_absolute(path + ".tmp")
