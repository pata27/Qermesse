## Traces de reference — docs/06 §2.
##
## Deux courses REELLES enregistrees avant plusieurs changements du moteur.
## Elles ne portent ni `eliminated_ms` ni `hardware_finishes`, ajoutes depuis :
## les rejouer prouve deux choses qu'aucun test genere ne peut prouver, puisque
## celui-ci produit sa trace avec le code du jour —
##
##   1. le format d'hier se relit encore ;
##   2. le moteur d'aujourd'hui redonne le classement d'hier sur les memes
##      trames. Une divergence serait une derive silencieuse de l'arbitrage.
##
## Ne pas regenerer ces fichiers : c'est leur anciennete qui a de la valeur.
extends GutTest

const FIXTURES := "res://tests/fixtures"


func _rejouer(name: String) -> Array:
	var loaded := Replay.load_file("%s/%s" % [FIXTURES, name])
	assert_true(loaded.ok, "%s : %s" % [name, loaded.error])
	if not loaded.ok:
		return []
	var replayed := Replay.replay(loaded)
	assert_not_null(replayed, "%s : le rejeu doit produire un resultat" % name)
	return [loaded, replayed]


func test_une_course_en_distance_redonne_le_meme_classement() -> void:
	var pair := _rejouer("course-distance-4-coureurs.json")
	if pair.is_empty():
		return
	var loaded: Replay.Loaded = pair[0]
	var replayed: RaceResult = pair[1]

	assert_eq(replayed.ranking, Array(loaded.recorded_ranking), "meme classement qu'a l'epoque")
	assert_eq(replayed.ranking, [1, 3, 0, 2], "et c'est bien celui-la")
	assert_eq(replayed.elapsed_ms, loaded.recorded_elapsed_ms, "au meme instant")
	assert_eq(int(replayed.end_reason), loaded.recorded_end_reason)
	for rider: int in replayed.ranking:
		assert_gt(replayed.finished_ms[rider], 0, "piste %d a franchi la ligne" % (rider + 1))


func test_une_poursuite_redonne_les_memes_eliminations() -> void:
	var pair := _rejouer("course-poursuite-3-eliminations.json")
	if pair.is_empty():
		return
	var loaded: Replay.Loaded = pair[0]
	var replayed: RaceResult = pair[1]

	assert_eq(replayed.ranking, Array(loaded.recorded_ranking), "meme classement qu'a l'epoque")
	assert_eq(replayed.ranking, [1, 2, 0, 3], "le survivant, puis les elimines a l'envers")
	assert_eq(int(replayed.end_reason), RaceRule.EndReason.LAST_ONE_STANDING)
	var eliminated := 0
	for rider: int in range(Protocol.MAX_RIDERS):
		if replayed.eliminated[rider]:
			eliminated += 1
	assert_eq(eliminated, 3, "trois elimines, un survivant")
	# Le champ n'existait pas dans cette trace : il est RECALCULE par le rejeu,
	# ce qui est tout l'interet — le rejeu ne relit pas, il rejoue.
	for rider: int in range(Protocol.MAX_RIDERS):
		if replayed.eliminated[rider]:
			assert_gt(replayed.eliminated_ms[rider], 0, "instant d'elimination recalcule")


func test_une_trace_ancienne_ne_voit_pas_ses_chiffres_compares() -> void:
	# Le rejeu ne comparait QUE le classement. Il recalcule pourtant distances,
	# temps, moyennes et pointes — il les imprimait avec `--detail` et ne les
	# confrontait a rien : une derive qui fausserait toutes les distances sans
	# changer l'ORDRE d'arrivee passait inapercue, sur l'outil meme que
	# `docs/06` appelle le filet de securite le plus rentable du projet.
	#
	# Ces deux traces-ci ne peuvent pas subir cette comparaison, et c'est
	# normal : elles precedent l'instant d'elimination, si bien que leurs
	# moyennes d'elimines sont calculees sur toute la course. Aucun moteur
	# d'aujourd'hui ne les redonnera. Leur anciennete est leur valeur.
	for name: String in [
		"course-distance-4-coureurs.json", "course-poursuite-3-eliminations.json"
	]:
		var pair := _rejouer(name)
		if pair.is_empty():
			continue
		var loaded: Replay.Loaded = pair[0]
		assert_false(loaded.recorded_complete, "%s : trace anterieure a eliminated_ms" % name)
		assert_eq(
			Replay.figure_gaps(loaded, pair[1]), [] as Array[String],
			"%s : ses chiffres ne sont pas mis en cause" % name
		)


func test_une_trace_d_aujourd_hui_voit_tous_ses_chiffres_compares() -> void:
	# Le versant qui compte : sur une course enregistree par le logiciel
	# d'aujourd'hui, les chiffres doivent concorder AU CHIFFRE PRES. C'est
	# exactement le cas de `DEPANNAGE`, qui fait envoyer ce fichier au
	# developpeur devant un resultat suspect — et un outil de diagnostic qui ne
	# regarde que l'ordre d'arrivee ne diagnostique pas grand-chose.
	var dir := ProjectSettings.globalize_path("user://test_rejeu")
	DirAccess.make_dir_recursive_absolute(dir)
	var recorder := Recorder.new(dir.path_join("logs"), dir.path_join("races"))
	var config := RaceConfig.new()
	config.mode = RaceConfig.Mode.DISTANCE
	config.distance_m = 100.0
	config.active_riders = [0, 1]

	var engine := RaceEngine.new()
	var produced: Array[RaceResult] = []
	engine.race_finished.connect(func(r: RaceResult) -> void: produced.append(r))
	recorder.begin_race(config, {})
	engine.arm(config, 0)
	for value: int in [3, 2, 1, 0]:
		engine.on_countdown(value)
	var physics := Physics.new(config.roller_mm)
	var elapsed := 0
	while produced.is_empty() and elapsed < 40000:
		elapsed += 50
		var ticks := PackedInt32Array([
			physics.metres_to_ticks(float(elapsed) * 0.0125),
			physics.metres_to_ticks(float(elapsed) * 0.0118),
			0, 0,
		])
		recorder.record_sample(ticks, elapsed)
		engine.on_progress(ticks, elapsed)
	assert_false(produced.is_empty(), "la course va au bout")
	var path := recorder.finish_race(produced[0])
	assert_false(path.is_empty(), "la trace est ecrite")

	var loaded := Replay.load_file(path)
	assert_true(loaded.ok, loaded.error)
	assert_true(loaded.recorded_complete, "une trace d'aujourd'hui porte eliminated_ms")
	var replayed := Replay.replay(loaded)
	assert_not_null(replayed, "elle se rejoue")
	assert_eq(
		Replay.figure_gaps(loaded, replayed), [] as Array[String],
		"et tous ses chiffres concordent"
	)

	# ET LA COMPARAISON MORD. Un seul chiffre fausse suffit a la faire parler —
	# sans quoi le « aucun ecart » ci-dessus ne prouverait que son silence.
	loaded.recorded_distance_m[replayed.ranking[0]] += 5.0
	var gaps := Replay.figure_gaps(loaded, replayed)
	assert_eq(gaps.size(), 1, "une distance faussee est signalee")
	assert_string_contains(gaps[0], "distance", "et elle est nommee")
	DirAccess.remove_absolute(path)
