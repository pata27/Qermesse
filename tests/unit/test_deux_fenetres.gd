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


func test_le_selecteur_de_qualite_annonce_l_automatique_et_le_niveau_detecte() -> void:
	# Le reglage par defaut est l'automatique (-1). Le selecteur affichait
	# « bas » — la premiere entree, faute de mieux : il mentait sur le reglage
	# en cours, et sur ce qui tournait.
	_main.controller.settings.render_quality = -1
	var panel: PanelSpectacle = _main.operator.spectacle_panel()
	panel.refresh()
	var selector := panel.quality_selector()
	assert_eq(
		selector.get_selected_id(), PanelSpectacle.AUTOMATIC_ITEM,
		"l'automatique est selectionne"
	)
	assert_string_contains(selector.get_item_text(selector.selected), "automatique")
	assert_string_contains(
		selector.get_item_text(selector.selected),
		str(RenderQuality.PROFILES[RenderQuality.detect()]["name"]),
		"et dit quel niveau il a detecte"
	)


func test_on_peut_revenir_a_l_automatique_apres_un_choix_manuel() -> void:
	# Sans cette entree, essayer « eleve » un soir coutait DEFINITIVEMENT la
	# degradation qui protege les 60 fps : plus aucun chemin de retour hors
	# edition du JSON.
	_main.controller.settings.render_quality = RenderQuality.Level.HIGH
	_main.open_spectacle()
	var panel: PanelSpectacle = _main.operator.spectacle_panel()
	panel.refresh()
	assert_false(_main.spectacle.scene.auto_degrade(), "un choix manuel la desarme")

	var selector := panel.quality_selector()
	var automatic := -1
	for item: int in range(selector.item_count):
		if selector.get_item_id(item) == PanelSpectacle.AUTOMATIC_ITEM:
			automatic = item
			break
	assert_gt(automatic, -1, "l'entree automatique existe")
	selector.select(automatic)
	selector.item_selected.emit(automatic)

	assert_eq(_main.controller.settings.render_quality, -1, "le reglage revient a l'automatique")
	assert_true(_main.spectacle.scene.auto_degrade(), "et la degradation est rearmee")
	assert_eq(
		_main.spectacle.scene.quality.level, RenderQuality.detect(),
		"la scene reprend le niveau detecte"
	)


func test_la_qualite_se_regle_meme_ecran_public_ferme() -> void:
	# C'est un reglage persiste, pris la veille — comme le plein ecran, que
	# `Main.set_spectacle_fullscreen` memorise deja fenetre fermee.
	var panel: PanelSpectacle = _main.operator.spectacle_panel()
	panel.refresh()
	var selector := panel.quality_selector()
	assert_false(selector.disabled, "reglable sans fenetre ouverte")
	for item: int in range(selector.item_count):
		if selector.get_item_id(item) == RenderQuality.Level.MEDIUM:
			selector.select(item)
			selector.item_selected.emit(item)
			break
	assert_eq(_main.controller.settings.render_quality, RenderQuality.Level.MEDIUM)
	_main.open_spectacle()
	assert_eq(
		_main.spectacle.scene.quality.level, RenderQuality.Level.MEDIUM,
		"et la fenetre ouverte ensuite le respecte"
	)


func test_choisir_l_ecran_automatique_ecrit_bien_l_automatique() -> void:
	# `add_item(texte, -1)` ne stocke pas -1 : Godot y met l'index de l'entree.
	# « automatique » portait donc l'id 0, et le choisir ecrivait « ecran 1 ».
	# Le mode que le code recommande — il survit a un rebranchement — etait
	# inatteignable a la souris.
	_main.controller.settings.show_window_screen = 0
	var panel: PanelSpectacle = _main.operator.spectacle_panel()
	panel.refresh()
	var screens: OptionButton = panel.screen_selector()
	assert_eq(screens.get_item_text(0).substr(0, 11), "automatique", "premiere entree")
	screens.select(0)
	screens.item_selected.emit(0)
	assert_eq(
		_main.controller.settings.show_window_screen, -1,
		"automatique, et non l'ecran numero 1"
	)


func test_le_niveau_de_qualite_regle_vraiment_l_anticrenelage() -> void:
	# `RenderQuality.PROFILES` declare un `msaa` par niveau — 0, 1, 2, qui sont
	# exactement les valeurs de `Viewport.MSAA_DISABLED / 2X / 4X`. Personne ne
	# le lisait : le bouton existait dans le tableau, dans le document et dans
	# l'outil de mesure, et ne touchait rien. Le niveau « bas », fait pour les
	# machines faibles, gardait l'anticrenelage.
	_main.controller.settings.render_quality = RenderQuality.Level.LOW
	_main.open_spectacle()
	assert_eq(
		_main.spectacle.msaa_3d, Viewport.MSAA_DISABLED,
		"en qualite basse, l'anticrenelage est coupe"
	)

	_main.spectacle.scene.quality.level = RenderQuality.Level.HIGH
	_main.spectacle.scene.apply_quality()
	assert_eq(
		_main.spectacle.msaa_3d, Viewport.MSAA_4X,
		"en qualite elevee, il est au maximum du profil"
	)


func test_aucun_reglage_de_profil_n_est_lettre_morte() -> void:
	# LE DEFAUT DE CLASSE. Un reglage declare dans `PROFILES` que rien ne lit est
	# une promesse non tenue : le document annonce trois niveaux de qualite, et
	# l'un des leviers ne bougeait rien. Chaque cle doit etre lue quelque part.
	var sources := ""
	for path: String in [
		"res://scenes/race3d/race_scene.gd",
		"res://scenes/race3d/split_screen.gd",
		"res://scenes/race3d/render_quality.gd",
		"res://scenes/race3d/rider_rig.gd",
		"res://scenes/race3d/crowd.gd",
	]:
		var file := FileAccess.open(path, FileAccess.READ)
		if file != null:
			sources += file.get_as_text()

	var unread: Array[String] = []
	for key: Variant in (RenderQuality.PROFILES[RenderQuality.Level.HIGH] as Dictionary).keys():
		var name := str(key)
		# `name` est le libelle affiche, pas un levier de rendu.
		if name == "name":
			continue
		if not sources.contains('option("%s")' % name):
			unread.append(name)
	assert_eq(unread, [] as Array[String], "des reglages de profil que rien ne lit")


func test_le_curseur_de_volume_reste_manoeuvrable_son_coupe() -> void:
	# Le curseur etait grise tant que le son etait coupe. Comme il l'est par
	# defaut, preparer le volume la veille imposait d'activer le son.
	var panel: PanelSpectacle = _main.operator.spectacle_panel()
	panel.refresh()
	assert_true(_main.audio.is_muted(), "coupe par defaut")
	assert_true(
		panel.volume_slider().editable,
		"le volume se regle meme son coupe : c'est un reglage, pas une sortie"
	)
