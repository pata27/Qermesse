## Le photo-finish — docs/04 §4 : l'ecart des deux premiers encore en course.
extends GutTest


func test_deux_coureurs_roue_dans_roue_un_troisieme_loin_derriere() -> void:
	# `leader - dernier` valait 30 m ici, et refusait un vrai photo-finish.
	var gap := RaceScene.photo_finish_gap({0: 499.5, 1: 499.0, 2: 470.0}, [0, 1, 2])
	assert_almost_eq(gap, 0.5, 0.001)


func test_un_coureur_seul_n_a_pas_de_photo_finish() -> void:
	assert_eq(RaceScene.photo_finish_gap({0: 499.5}, [0]), INF, "seul de la course")
	# Trois arrives, le dernier approche seul : rien a departager.
	assert_eq(RaceScene.photo_finish_gap({0: 500.0, 1: 500.0, 2: 500.0, 3: 495.0}, [3]), INF)
	assert_eq(RaceScene.photo_finish_gap({}, []), INF, "personne")


func test_l_ordre_des_couloirs_ne_compte_pas() -> void:
	assert_almost_eq(RaceScene.photo_finish_gap({0: 470.0, 1: 499.0, 2: 499.8}, [0, 1, 2]), 0.8, 0.001)
	assert_almost_eq(RaceScene.photo_finish_gap({3: 499.8, 2: 499.0}, [2, 3]), 0.8, 0.001)


func test_la_camera_ne_bascule_que_pres_de_la_ligne_et_sous_un_metre() -> void:
	var rig := CameraRig.new()
	assert_false(rig.consider_photo_finish(INF, 5.0), "personne a departager")
	assert_false(rig.consider_photo_finish(0.5, 40.0), "trop loin de la ligne")
	assert_true(rig.consider_photo_finish(0.5, 8.0))
	assert_true(rig.is_photo_finish())
	rig.free()
