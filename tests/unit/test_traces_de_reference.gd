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
