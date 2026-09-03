## Le pédalier — `scenes/race3d/rider_rig.gd`.
##
## Le sens de rotation d'une pièce ne se lit sur aucune capture : une roue à
## rayons tourne trop vite pour qu'on voie de quel côté, et une manivelle qui
## va à l'envers ne se remarque qu'en la comparant à la jambe posée dessus.
## C'est un défaut qui a survécu à une correction — laquelle avait aligné le
## pédalier sur des roues elles-mêmes fausses.
extends GutTest

const RIG := preload("res://scenes/race3d/rider_rig.gd")


func _rig() -> RiderRig:
	var rig := RIG.new()
	add_child_autofree(rig)
	rig.setup(0, Color("#00E5FF"), 8)
	return rig


func test_le_point_bas_recule_quand_le_velo_avance() -> void:
	# ON AVANCE VERS +Z : `RaceScene` place le coureur a `distance - ancrage`,
	# et la porte d'arrivee est DEVANT, donc a z croissant. Une roue qui roule
	# vers l'avant voit son point de contact reculer, et le pied au point bas
	# fait de meme. C'est le SOL qui donne le sens, jamais la piece voisine :
	# c'est le seul referentiel qui ne peut pas etre faux.
	var bottom := RiderRig.pedal_offset(0.0)
	assert_almost_eq(bottom.x, -RiderRig.CRANK_LENGTH_M, 0.0001, "au point bas")
	assert_almost_eq(bottom.y, 0.0, 0.0001, "et dans l'axe")
	var just_after := RiderRig.pedal_offset(0.05)
	assert_lt(just_after.y, 0.0, "le pied au point bas RECULE quand le velo avance")


func test_le_pied_est_sur_la_pedale_a_tous_les_angles() -> void:
	# Le bout de manivelle et le pied sont LE MEME POINT — c'est ce qui definit
	# un pedalier. Ils etaient calcules separement et avaient diverge en Z : les
	# manivelles tournaient a l'envers des jambes, et seuls les points morts
	# haut et bas les remettaient d'accord, ce qui rendait le defaut difficile a
	# nommer sans le voir bouger.
	var rig := _rig()
	for step: int in range(12):
		# Une image a vitesse constante fait avancer le pedalier d'un cran.
		rig.advance(0.08, 34.0, false, false)
		for index: int in range(2):
			var probe := rig.pedal_probe(index)
			var crank: Vector3 = probe["manivelle"]
			var foot: Vector3 = probe["pied"]
			assert_almost_eq(
				foot.y, crank.y, 0.002, "image %d, jambe %d : meme hauteur" % [step, index]
			)
			assert_almost_eq(
				foot.z, crank.z, 0.002, "image %d, jambe %d : meme avancee" % [step, index]
			)


func test_les_deux_manivelles_sont_a_un_demi_tour_l_une_de_l_autre() -> void:
	# Un pedalier dont les deux manivelles seraient en phase ferait pedaler des
	# deux jambes ensemble, ce qui ne se voit qu'en mouvement.
	var rig := _rig()
	rig.advance(0.05, 30.0, false, false)
	var left: Vector3 = rig.pedal_probe(0)["manivelle"]
	var right: Vector3 = rig.pedal_probe(1)["manivelle"]
	assert_almost_eq(left.y, -right.y, 0.002, "hauteurs opposees")
	assert_almost_eq(left.z, -right.z, 0.002, "et avancees opposees")


func test_les_roues_tournent_dans_le_meme_sens_que_le_pedalier() -> void:
	# La correction precedente avait fait l'inverse : elle a aligne le pedalier
	# sur les roues, alors que les roues etaient fausses. L'erreur s'est
	# propagee au lieu de se corriger.
	var rig := _rig()
	rig.advance(0.05, 30.0, false, false)
	var wheels := rig.wheel_angles()
	assert_gt(wheels.size(), 0, "le velo a des roues")
	for angle: float in wheels:
		assert_gt(angle, 0.0, "elles tournent dans le sens de la marche")
	assert_gt(rig.crank_probe_angle(), 0.0, "le pedalier aussi")
