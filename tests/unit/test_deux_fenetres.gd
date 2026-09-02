## La fenetre spectacle telle que l'application l'ouvre — docs/03 §6.
##
## `Main.open_spectacle()` a change deux fois recemment : le niveau de qualite
## puis le plein ecran y sont passes depuis les reglages. Rien ne l'exercait —
## une regression y casse l'ecran du public le soir du spectacle, et se
## verifie autrement qu'en branchant un videoprojecteur.
extends GutTest

var _main: Node


func before_each() -> void:
	_main = (load("res://scenes/main.gd") as GDScript).new()
	# AVANT l'entree dans l'arbre : `_ready` construit le controleur, qui lit
	# aussitot les reglages. Les poser apres, c'etait lire l'etat REEL de la
	# machine — et faire dependre le test de la derniere soiree de l'operateur,
	# qui a pu laisser la fenetre spectacle ouverte.
	_main.preferences_enabled = false
	_main.recorder_logs_dir = ProjectSettings.globalize_path("user://test_2f/logs")
	_main.recorder_races_dir = ProjectSettings.globalize_path("user://test_2f/races")
	add_child_autofree(_main)


func after_each() -> void:
	if _main != null and _main.spectacle != null:
		_main.spectacle.queue_free()
		_main.spectacle = null


func test_la_fenetre_spectacle_s_ouvre_avec_sa_scene() -> void:
	assert_null(_main.spectacle, "fermee tant qu'on ne la demande pas")
	_main.open_spectacle()
	assert_not_null(_main.spectacle, "la fenetre existe")
	assert_not_null(_main.spectacle.scene, "et porte sa scene 3D")
	assert_false(_main.controller.settings.single_window_mode, "le reglage suit")


func test_le_niveau_de_qualite_regle_est_celui_de_la_scene() -> void:
	_main.controller.settings.render_quality = RenderQuality.Level.LOW
	_main.open_spectacle()
	assert_eq(_main.spectacle.scene.quality.level, RenderQuality.Level.LOW)
	assert_false(_main.spectacle.scene.auto_degrade(), "un niveau impose n'est pas defait")


func test_fermer_l_ecran_public_ne_detruit_pas_la_scene() -> void:
	# « La course, elle, continue : l'affichage public n'est pas la course. »
	# Fermer l'ecran par megarde en pleine soiree ne doit rien couter — et
	# rouvrir ne doit pas reconstruire toute la scene 3D devant le public.
	_main.open_spectacle()
	assert_true(_main.spectacle_visible())
	var scene_before: Node = _main.spectacle.scene

	_main.close_spectacle()
	assert_false(_main.spectacle_visible(), "l'ecran public est retire")
	assert_true(
		_main.controller.settings.single_window_mode,
		"et le prochain lancement s'en souvient"
	)

	_main.open_spectacle()
	assert_true(_main.spectacle_visible())
	assert_same(scene_before, _main.spectacle.scene, "la scene n'est pas reconstruite")
	assert_false(_main.controller.settings.single_window_mode)


func test_le_plein_ecran_suit_le_reglage_et_non_l_ouverture() -> void:
	_main.controller.settings.spectacle_fullscreen = false
	assert_false(_main.spectacle_fullscreen(), "sans fenetre, c'est le reglage qui repond")
	_main.set_spectacle_fullscreen(true)
	assert_true(_main.controller.settings.spectacle_fullscreen, "memorise sans fenetre ouverte")
