## Roue libre et regroupement apres la ligne — docs/04 §5.
##
## Ce comportement n'etait verifie que par des captures : il vivait dans
## `race_scene.gd` et demandait une scene 3D complete pour tourner. Sorti dans
## `RaceCoast`, il ne fait plus que des mathematiques sur des positions.
extends GutTest

const LANES := [0, 1, 2]


func _state(finished: Array, eliminated: Array, speeds: Array) -> RaceState:
	var config := RaceConfig.new()
	config.mode = RaceConfig.Mode.DISTANCE
	config.active_riders = [0, 1, 2]
	var state := RaceState.new(config)
	for lane: int in LANES:
		state.finished_ms[lane] = int(finished[lane])
		state.eliminated[lane] = bool(eliminated[lane])
		state.display_speed_kph[lane] = float(speeds[lane])
	return state


## Fait tourner `seconds` secondes a 60 images par seconde et rend les
## positions AFFICHEES a la fin.
##
## `base` porte les positions MESUREES, reconstruites a chaque image comme le
## fait la scene : un arrive ne bouge plus cote moteur, sa mesure est donc
## constante. Repasser la sortie precedente compterait l'avance deux fois —
## c'est le contrat de `advance`, et l'avoir enfreint ici l'a mis au jour.
func _run(coast: RaceCoast, state: RaceState, base: Dictionary, seconds: float) -> Dictionary:
	var shown := base.duplicate()
	for i: int in range(int(seconds * 60.0)):
		shown = base.duplicate()
		coast.advance(1.0 / 60.0, state, shown, LANES)
	return shown


func test_un_arrive_ne_s_arrete_pas_mais_ralentit() -> void:
	# « Ils ne ralentissent pas a la fin, ils s'arretent, on ne voit plus les
	# lignes du sol defiler. » Un arrive garde une allure de croisiere.
	var coast := RaceCoast.new()
	var state := _state([8000, 0, 0], [false, false, false], [45.0, 45.0, 45.0])
	var base := {0: 500.0, 1: 480.0, 2: 470.0}
	var positions := _run(coast, state, base, 4.0)

	var travelled: float = positions[0] - 500.0
	assert_gt(travelled, 20.0, "il a continue de rouler")
	assert_almost_eq(positions[1], 480.0, 0.001, "ceux qui courent ne sont pas touches")
	assert_almost_eq(positions[2], 470.0, 0.001)


func test_un_elimine_s_arrete() -> void:
	# Il est sorti de la course : rien ne justifie qu'il continue de rouler.
	var coast := RaceCoast.new()
	var state := _state([0, 0, 0], [false, false, true], [45.0, 45.0, 30.0])
	var base := {0: 500.0, 1: 480.0, 2: 300.0}
	var positions := _run(coast, state, base, 6.0)
	assert_lt(positions[2] - 300.0, 25.0, "il decelere jusqu'a l'arret, il ne croisiere pas")
	var after: float = _run(coast, state, base, 4.0)[2]
	assert_almost_eq(_run(coast, state, base, 2.0)[2], after, 0.001, "et il ne bouge plus du tout")


func test_tout_le_monde_arrive_les_suivants_se_regroupent_sans_depasser() -> void:
	# Demande en cours de route : « tu peux les faire accelerer pour resserrer
	# le premier ? Sans jamais le rattraper, juste les mettre beaucoup plus
	# proches dans l'ordre d'arrivee, pour regrouper la cam. »
	var coast := RaceCoast.new()
	var state := _state([8000, 9000, 10000], [false, false, false], [45.0, 42.0, 40.0])
	var base := {0: 500.0, 1: 460.0, 2: 420.0}
	var spread_before: float = base[0] - base[2]
	var positions := _run(coast, state, base, 5.0)

	var spread_after: float = positions[0] - positions[2]
	assert_lt(spread_after, spread_before * 0.5, "le peloton s'est nettement resserre")
	assert_lt(spread_after, 12.0, "assez pour tenir dans un seul cadre")

	# L'ORDRE D'ARRIVEE EST UNE CONTRAINTE : personne ne repasse devant.
	assert_gt(positions[0], positions[1], "le premier reste devant le deuxieme")
	assert_gt(positions[1], positions[2], "et le deuxieme devant le troisieme")
	assert_gt(
		positions[0] - positions[1], RaceCoast.REGROUP_MIN_SPACING_M - 0.01,
		"sans lui coller dans la roue"
	)


func test_le_regroupement_n_a_pas_lieu_tant_qu_un_coureur_court() -> void:
	# Resserrer pendant qu'un retardataire est encore en course ferait mentir
	# l'image : les ecarts affiches doivent rester ceux de la course.
	var coast := RaceCoast.new()
	var state := _state([8000, 9000, 0], [false, false, false], [45.0, 42.0, 40.0])
	var base := {0: 500.0, 1: 460.0, 2: 300.0}
	var positions := _run(coast, state, base, 3.0)
	assert_gt(positions[0] - positions[1], 25.0, "les deux arrives roulent chacun pour soi")


func test_en_mode_temps_personne_n_est_repousse_en_arriere() -> void:
	# Au gong, tous les coureurs finissent au MEME instant : la chaine du
	# regroupement, ordonnee par instant d'arrivee, se retrouvait arbitraire.
	# Chacun etant contraint de rester derriere le precedent, un coureur
	# genuinement devant pouvait etre repousse de plusieurs dizaines de metres
	# — un saut en arriere en pleine celebration.
	var coast := RaceCoast.new()
	var state := _state([20000, 20000, 20000], [false, false, false], [42.0, 48.0, 45.0])
	# La piste 1 mene, la piste 0 est derniere : l'ordre des couloirs et celui
	# de la course ne coincident pas.
	var base := {0: 200.0, 1: 260.0, 2: 230.0}
	var positions := _run(coast, state, base, 0.2)

	for lane: int in LANES:
		assert_gt(
			positions[lane], base[lane] - 0.01,
			"la piste %d ne doit pas reculer (%.1f -> %.1f)" % [lane + 1, base[lane], positions[lane]]
		)

	# Et le regroupement respecte l'ordre REEL, pas celui des couloirs.
	positions = _run(coast, state, base, 5.0)
	assert_gt(positions[1], positions[2], "le meneur reste devant")
	assert_gt(positions[2], positions[0], "et le deuxieme devant le dernier")


func test_une_nouvelle_course_repart_de_zero() -> void:
	# Jamais remise, la roue libre ajoutait d'un coup au passage de la ligne
	# les metres accumules a la course precedente.
	var coast := RaceCoast.new()
	var state := _state([8000, 0, 0], [false, false, false], [45.0, 45.0, 45.0])
	var base := {0: 500.0, 1: 480.0, 2: 470.0}
	assert_gt(_run(coast, state, base, 3.0)[0], 510.0)

	coast.reset()
	var fresh := {0: 10.0, 1: 9.0, 2: 8.0}
	coast.advance(1.0 / 60.0, state, fresh, LANES)
	assert_lt(fresh[0] - 10.0, 1.0, "pas de saut herite de la course precedente")
