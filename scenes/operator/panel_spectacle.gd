## Pilotage de la fenêtre spectacle — docs/03 §6 et docs/05 lot 5.
##
## L'opérateur règle tout depuis son écran ; le public n'en voit rien. Ce
## panneau ne fait que commander la seconde fenêtre : sur quel écran, en plein
## écran ou non, et à quel niveau de qualité.
##
## Il RELIT toujours l'état réel de la fenêtre plutôt que de supposer que sa
## dernière commande a abouti : un gestionnaire de fenêtres peut refuser un
## plein écran, et un écran peut avoir été débranché entre-temps.
class_name PanelSpectacle
extends VBoxContainer

var _root: Node
var _controller: AppController
var _toggle: Button
var _screens: OptionButton
var _fullscreen: CheckBox
var _quality: OptionButton
var _mute: Button
var _volume: HSlider
var _status: Label


func setup(root: Node, controller: AppController) -> void:
	_root = root
	_controller = controller
	_build()
	if _root.has_signal("spectacle_changed"):
		_root.connect("spectacle_changed", refresh)
	refresh()


func _build() -> void:
	var title := Label.new()
	title.text = "Fenêtre spectacle"
	title.add_theme_font_size_override("font_size", 20)
	add_child(title)

	_toggle = Button.new()
	_toggle.custom_minimum_size = Vector2(220, 44)
	_toggle.pressed.connect(_on_toggle)
	add_child(_toggle)

	var screen_row := HBoxContainer.new()
	add_child(screen_row)
	var screen_label := Label.new()
	screen_label.text = "Écran"
	screen_label.custom_minimum_size = Vector2(90, 0)
	screen_row.add_child(screen_label)
	_screens = OptionButton.new()
	_screens.custom_minimum_size = Vector2(260, 0)
	_screens.item_selected.connect(_on_screen_selected)
	screen_row.add_child(_screens)

	_fullscreen = CheckBox.new()
	_fullscreen.text = "Plein écran"
	_fullscreen.toggled.connect(_on_fullscreen_toggled)
	add_child(_fullscreen)

	var quality_row := HBoxContainer.new()
	add_child(quality_row)
	var quality_label := Label.new()
	quality_label.text = "Qualité"
	quality_label.custom_minimum_size = Vector2(90, 0)
	quality_row.add_child(quality_label)
	_quality = OptionButton.new()
	_quality.custom_minimum_size = Vector2(260, 0)
	for level: int in [RenderQuality.Level.LOW, RenderQuality.Level.MEDIUM, RenderQuality.Level.HIGH]:
		_quality.add_item(str(RenderQuality.PROFILES[level]["name"]), level)
	_quality.item_selected.connect(_on_quality_selected)
	quality_row.add_child(_quality)

	# --- Son ----------------------------------------------------------------
	var sound_title := Label.new()
	sound_title.text = "Son"
	sound_title.add_theme_font_size_override("font_size", 20)
	add_child(sound_title)

	# UN bouton, gros, qui dit l'état plutôt que l'action à faire — docs/04 §6.
	_mute = Button.new()
	_mute.custom_minimum_size = Vector2(220, 44)
	_mute.pressed.connect(_on_mute_pressed)
	add_child(_mute)

	var volume_row := HBoxContainer.new()
	add_child(volume_row)
	var volume_label := Label.new()
	volume_label.text = "Volume"
	volume_label.custom_minimum_size = Vector2(90, 0)
	volume_row.add_child(volume_label)
	_volume = HSlider.new()
	_volume.min_value = -40.0
	_volume.max_value = 6.0
	_volume.step = 1.0
	_volume.custom_minimum_size = Vector2(260, 0)
	_volume.value_changed.connect(_on_volume_changed)
	volume_row.add_child(_volume)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(360, 0)
	add_child(_status)


## Recharge la liste des écrans ET l'état de la fenêtre. Appelée à chaque
## changement : brancher un vidéoprojecteur ne doit pas obliger à redémarrer.
func refresh() -> void:
	var count := DisplayServer.get_screen_count()
	var wanted: int = _controller.settings.show_window_screen
	_screens.clear()
	# « Automatique » n'est pas un raccourci : c'est le comportement à
	# recommander, parce qu'il survit à un changement de branchement.
	_screens.add_item("automatique (le second si présent)", -1)
	for index: int in range(count):
		var size := DisplayServer.screen_get_size(index)
		var main := " — écran de l'opérateur" if index == DisplayServer.window_get_current_screen() \
			else ""
		_screens.add_item("écran %d — %d × %d%s" % [index + 1, size.x, size.y, main], index)
	for item: int in range(_screens.item_count):
		if _screens.get_item_id(item) == wanted:
			_screens.select(item)
			break

	# Le sélecteur de qualité doit montrer le niveau RÉELLEMENT appliqué, qui
	# est détecté automatiquement au montage et peut avoir été dégradé en cours
	# de course. Laisser la première entrée sélectionnée annonçait « bas » sur
	# une scène qui tournait en « moyen ».
	var window: Node = _root.get("spectacle")
	if window != null and window.scene != null:
		for item: int in range(_quality.item_count):
			if _quality.get_item_id(item) == int(window.scene.quality.level):
				_quality.select(item)
				break
	_quality.disabled = window == null or window.scene == null

	var audio: Node = _root.get("audio")
	if audio != null:
		var muted: bool = audio.call("is_muted")
		_mute.text = "SON COUPÉ — cliquer pour activer" if muted \
			else "SON ACTIF — cliquer pour couper"
		_mute.add_theme_color_override(
			"font_color", Color("#FF3B30") if muted else Color("#2BE08A")
		)
		_volume.set_value_no_signal(float(audio.call("volume_db")))
		_volume.editable = not muted

	var open: bool = _root.call("spectacle_visible")
	_toggle.text = "Fermer la fenêtre spectacle" if open else "Ouvrir la fenêtre spectacle"
	_fullscreen.button_pressed = bool(_root.call("spectacle_fullscreen"))
	_fullscreen.disabled = not open

	if count > 1:
		_status.text = "%d écrans détectés." % count
	else:
		# Mode dégradé mono-écran : on l'annonce, on ne le subit pas.
		_status.text = (
			"Un seul écran détecté : la fenêtre spectacle s'ouvrira en fenêtré "
			+ "par-dessus. Branchez le projecteur puis rouvrez-la pour l'y envoyer."
		)


func _on_mute_pressed() -> void:
	var audio: Node = _root.get("audio")
	if audio != null:
		audio.call("set_muted", not bool(audio.call("is_muted")))
	refresh()


func _on_volume_changed(value: float) -> void:
	var audio: Node = _root.get("audio")
	if audio != null:
		audio.call("set_volume_db", value)


func _on_toggle() -> void:
	if bool(_root.call("spectacle_visible")):
		_root.call("close_spectacle")
	else:
		_root.call("open_spectacle")


func _on_screen_selected(index: int) -> void:
	_root.call("set_spectacle_screen", _screens.get_item_id(index))


func _on_fullscreen_toggled(pressed: bool) -> void:
	_root.call("set_spectacle_fullscreen", pressed)


func _on_quality_selected(index: int) -> void:
	var level := _quality.get_item_id(index)
	var window: Node = _root.get("spectacle")
	if window != null and window.scene != null:
		# Le choix manuel désarme la dégradation automatique : sinon le niveau
		# choisi serait défait dès la première seconde sous le budget, sans que
		# l'opérateur comprenne pourquoi.
		window.scene.set_auto_degrade(false)
		window.scene.quality.level = level as RenderQuality.Level
		window.scene.apply_quality()
