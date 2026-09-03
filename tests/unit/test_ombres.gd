## Ombres des coureurs — `docs/04` §4.
##
## Un coureur est fait de vingt-six pièces. Les faire toutes projeter donne une
## ombre qui RESSEMBLE à un cycliste — on y lit le buste, les bras, la roue —
## mais une lumière directionnelle les redessine une fois par cascade. Un volume
## approché s'en charge donc partout, sauf au profil élevé, qui est un choix
## délibéré de l'opérateur sur une machine qui le supporte.
##
## Rien de tout cela ne se lit sur une capture : `cast_shadow` est un réglage,
## et une boîte apparue sur le vélo — c'est arrivé — ne se voit qu'à l'image.
extends GutTest

const RIG := preload("res://scenes/race3d/rider_rig.gd")


func _rig() -> RiderRig:
	var rig := RIG.new()
	add_child_autofree(rig)
	rig.setup(0, Color("#00E5FF"), 8)
	return rig


## Les pièces du coureur qui projettent une ombre, hors volume approché.
func _casting_pieces(rig: RiderRig) -> int:
	var count := 0
	for node: Node in rig.find_children("*", "MeshInstance3D", true, false):
		var piece := node as MeshInstance3D
		if piece.name == "ShadowProxy":
			continue
		if piece.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			count += 1
	return count


func test_le_profil_eleve_est_le_seul_a_montrer_la_vraie_silhouette() -> void:
	assert_false(
		bool(RenderQuality.new(RenderQuality.Level.LOW).option("detailed_shadows")),
		"profil bas : volume approche"
	)
	assert_false(
		bool(RenderQuality.new(RenderQuality.Level.MEDIUM).option("detailed_shadows")),
		"profil moyen aussi — c'est celui detecte par defaut sur un GPU integre"
	)
	assert_true(
		bool(RenderQuality.new(RenderQuality.Level.HIGH).option("detailed_shadows")),
		"profil eleve : la vraie silhouette"
	)


func test_les_deux_ombres_ne_coexistent_jamais() -> void:
	# Laisser les deux projeter donnerait une silhouette ENFERMEE dans une
	# boite, ce qui est pire que l'un ou l'autre.
	var rig := _rig()

	rig.set_detailed_shadows(false)
	assert_eq(_casting_pieces(rig), 0, "au repos, aucune piece ne projette")
	var approx: Dictionary = rig.shadow_proxy_state()
	assert_true(approx["visible"], "c'est le volume approche qui s'en charge")

	rig.set_detailed_shadows(true)
	assert_gt(_casting_pieces(rig), 10, "en detaille, les pieces projettent")
	var detailed: Dictionary = rig.shadow_proxy_state()
	assert_false(detailed["visible"], "et le volume approche s'efface")


func test_le_volume_approche_ne_se_dessine_jamais_dans_l_image() -> void:
	# LE DEFAUT EXACT QUI S'EST PRODUIT. Couper son ombre avec
	# `SHADOW_CASTING_SETTING_OFF` retire l'ombre mais laisse le MAILLAGE se
	# dessiner : une boite de quarante centimetres sur un metre est apparue
	# debout sur le velo, en plein ecran. `SHADOWS_ONLY` est ce qui le tient
	# hors de la passe principale, et c'est la VISIBILITE qui decide s'il
	# projette.
	var rig := _rig()
	for detailed: bool in [false, true, false]:
		rig.set_detailed_shadows(detailed)
		var state: Dictionary = rig.shadow_proxy_state()
		assert_true(
			state["shadows_only"],
			"detaille=%s : le volume reste hors de la passe principale" % detailed
		)


func test_ni_la_trainee_ni_les_confettis_ne_projettent() -> void:
	# La trainee est transparente et les confettis sont des particules : leur
	# donner une ombre, c'est en donner une a des choses qui n'ont pas de corps,
	# et payer le cout pour rien.
	var rig := _rig()
	rig.set_detailed_shadows(true)
	for name: String in ["Trail"]:
		var node := rig.find_child(name, true, false) as GeometryInstance3D
		assert_not_null(node, "« %s » existe" % name)
		assert_eq(
			node.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			"« %s » ne projette pas, meme en detaille" % name
		)
	for node: Node in rig.find_children("*", "GPUParticles3D", true, false):
		assert_eq(
			(node as GPUParticles3D).cast_shadow,
			GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			"les particules ne projettent pas"
		)
