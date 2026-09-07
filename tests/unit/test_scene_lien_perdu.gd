## La scène 3D pendant un lien perdu — docs/04 §6, « l'image suit la même règle ».
##
## Sans trames, la vitesse de chaque coureur restait celle de la dernière :
## jambes à 45 km/h sur des vélos immobiles, foule qui s'agite, sous un écran
## qui dit LIEN PERDU. Ça ne se lit pas comme une course figée, mais comme un
## bug. Rien n'est jugé à l'image : on mesure l'angle des roues d'une image à
## l'autre.
extends GutTest


func test_lien_perdu_les_roues_s_arretent_et_ne_repartent_qu_avec_les_trames() -> void:
	var controller := AppController.new()
	controller.preferences_enabled = false
	add_child_autofree(controller)
	var scene := RaceScene.new()
	add_child_autofree(scene)
	scene.setup(controller, RenderQuality.Level.LOW)
	# La scene lit l'etat chez le moteur : on l'arme, et on alimente SON etat.
	# L'armement reconstruit les coureurs : le rig se prend APRES.
	assert_true(controller.engine.arm(controller.current_config(), 0), "le moteur est arme")
	controller.race_state_changed.emit(RaceEngine.State.COUNTDOWN, RaceEngine.State.RUNNING)
	var rig := scene.rider_rig(0)
	assert_not_null(rig, "la piste 1 est construite")
	var state: RaceState = controller.engine.race_state()
	var physics := Physics.new(state.config.roller_mm)
	var metres := 0.0
	# 12,5 m/s — 45 km/h — pendant une seconde d'images.
	for i: int in range(60):
		metres += 12.5 / 60.0
		state.apply_sample([physics.metres_to_ticks(metres), 0, 0, 0], int(metres * 80.0))
		controller.progress_updated.emit(state)
		await get_tree().process_frame
	var turning: float = await _wheel_turn(rig)
	assert_gt(turning, 0.01, "a 45 km/h les roues tournent d'une image a l'autre")

	controller.link_state_changed.emit(Protocol.State.LINK_LOST)
	assert_true(scene.link_lost())
	for i: int in range(120):
		await get_tree().process_frame
	var frozen: float = await _wheel_turn(rig)
	assert_lt(
		frozen, turning * 0.1, "lien perdu : les roues s'arretent (%.4f vs %.4f)" % [frozen, turning]
	)

	# Le lien revient, puis les trames : les roues repartent.
	controller.link_state_changed.emit(Protocol.State.IDENTIFIED)
	assert_false(scene.link_lost())
	for i: int in range(60):
		metres += 12.5 / 60.0
		state.apply_sample([physics.metres_to_ticks(metres), 0, 0, 0], int(metres * 80.0))
		controller.progress_updated.emit(state)
		await get_tree().process_frame
	var back: float = await _wheel_turn(rig)
	assert_gt(back, turning * 0.5, "les trames reviennent, les roues tournent")


## Rotation de la roue avant entre deux images consecutives, en radians.
func _wheel_turn(rig: RiderRig) -> float:
	var before: float = rig.wheel_angles()[0]
	await get_tree().process_frame
	var after: float = rig.wheel_angles()[0]
	return absf(wrapf(after - before, -PI, PI))
