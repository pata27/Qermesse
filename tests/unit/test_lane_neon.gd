## Le neon d'un couloir s'estompe a l'elimination — docs/02 §3.
extends GutTest


func test_un_coureur_en_course_garde_sa_couleur_pleine() -> void:
	var cyan := Color("#00E5FF")
	assert_eq(RaceScene.lane_neon(cyan, 1.0), cyan)


func test_un_elimine_a_un_couloir_gris_et_desature() -> void:
	var off := RaceScene.lane_neon(Color("#FF2E88"), 0.0)
	assert_lt(off.s, 0.2, "desature : le couloir ne parle plus de son coureur")
	assert_lt(off.v, 0.5, "et sombre")
	assert_eq(RaceScene.lane_neon(Color("#FF2E88"), -3.0), off, "borne basse")


func test_le_fondu_est_continu() -> void:
	var color := Color("#FFB300")
	var mid := RaceScene.lane_neon(color, 0.5)
	assert_between(mid.s, RaceScene.lane_neon(color, 0.0).s, color.s)


func test_le_velo_bascule_des_deux_cotes_en_danseuse() -> void:
	# docs/04 §4 : le coureur s'incline avec le pedalage. Le roulis valait
	# `sin(angle) * 0.5 + 0.5`, c'est-a-dire toujours POSITIF : le velo penchait
	# d'un seul cote puis revenait droit, comme un metronome bloque. Un
	# sprinteur en danseuse bascule des deux cotes, et c'est ce mouvement-la que
	# le public reconnait.
	var rig := RiderRig.new()
	add_child_autofree(rig)
	rig.setup(0, Color("#00E5FF"), 8)

	var low := INF
	var high := -INF
	# Plusieurs tours de pedalier a allure de course.
	for step: int in range(600):
		rig.advance(1.0 / 120.0, 45.0, false, false)
		low = minf(low, rig.lean_rad())
		high = maxf(high, rig.lean_rad())
	assert_lt(low, -0.01, "il penche d'un cote")
	assert_gt(high, 0.01, "et de l'autre")
	assert_almost_eq(low, -high, 0.05, "et symetriquement")
