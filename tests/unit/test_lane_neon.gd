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
