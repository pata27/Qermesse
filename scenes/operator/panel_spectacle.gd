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

## Identifiant de l'entree « automatique », dans les DEUX selecteurs.
##
## Et surtout pas -1, qui est pourtant la valeur du reglage. `add_item(texte,
## -1)` ne stocke pas -1 : Godot y met l'INDEX de l'entree. « automatique »
## recevait donc l'id 0 — c'est-a-dire « ecran 1 » et « qualite basse ». Le
## selecteur d'ecran en souffrait deja : choisir « automatique » ecrivait
## `show_window_screen = 0`, et le mode automatique, que le code recommande
## parce qu'il survit a un rebranchement, etait inatteignable a la souris.
##
## Les entrees portent donc un identifiant propre, traduit en -1 au moment
## d'ecrire le reglage.
const AUTOMATIC_ITEM := 1000

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
	_screens.add_item("automatique (le second si présent)", AUTOMATIC_ITEM)
	for index: int in range(count):
		var size := DisplayServer.screen_get_size(index)
		var main := " — écran de l'opérateur" if index == DisplayServer.window_get_current_screen() \
			else ""
		_screens.add_item("écran %d — %d × %d%s" % [index + 1, size.x, size.y, main], index)
	for item: int in range(_screens.item_count):
		if _screens.get_item_id(item) == _item_of(wanted):
			_screens.select(item)
			break

	var window: Node = _root.get("spectacle")
	_refresh_quality(window)

	var audio: Node = _root.get("audio")
	if audio != null:
		var muted: bool = audio.call("is_muted")
		_mute.text = "SON COUPÉ — cliquer pour activer" if muted \
			else "SON ACTIF — cliquer pour couper"
		_mute.add_theme_color_override(
			"font_color", Color("#FF3B30") if muted else Color("#2BE08A")
		)
		_volume.set_value_no_signal(float(audio.call("volume_db")))
		# LE CURSEUR RESTE MANOEUVRABLE SON COUPE. Il etait grise tant que le
		# son l'etait — et il l'est par defaut : preparer le volume la veille,
		# comme `docs/04` §6 le demande, imposait donc d'activer le son et de
		# faire du bruit dans une salle vide. Le volume est un REGLAGE, pas une
		# sortie : il se pose a froid et s'applique quand on active le son.
		_volume.editable = true

	var open: bool = _root.call("spectacle_visible")
	_toggle.text = "Fermer la fenêtre spectacle" if open else "Ouvrir la fenêtre spectacle"
	_fullscreen.button_pressed = bool(_root.call("spectacle_fullscreen"))
	_fullscreen.disabled = not open

	if SpectacleWindow.compositor_places_windows():
		# Le sélecteur reste visible mais inactif : un réglage qui semble agir
		# et n'agit pas est pire qu'un réglage absent.
		_screens.disabled = true
		_fullscreen.disabled = true
		_status.text = (
			"Session Wayland : c'est le compositeur qui choisit l'écran ET le "
			+ "plein écran, pas ces réglages — une règle sur le titre de la fenêtre "
			+ "fait les deux. Voir docs/DEPANNAGE.md."
		)
	elif count > 1:
		_screens.disabled = false
		_status.text = "%d écrans détectés." % count
	else:
		# Mode dégradé mono-écran : on l'annonce, on ne le subit pas.
		_status.text = (
			"Un seul écran détecté : la fenêtre spectacle s'ouvrira en fenêtré "
			+ "par-dessus. Branchez le projecteur puis rouvrez-la pour l'y envoyer."
		)


## Le sélecteur de qualité — docs/04 §4.
##
## L'AUTOMATIQUE EST UNE ENTRÉE, comme pour l'écran. Sans elle, essayer
## « élevé » un soir coûtait définitivement la dégradation qui protège les
## 60 fps : le réglage se persiste, et plus rien dans l'interface ne pouvait le
## ramener à -1. Elle annonce en plus le niveau détecté, faute de quoi
## « automatique » ne dirait pas ce qui tourne.
##
## Le sélecteur montre le niveau RÉELLEMENT appliqué quand la fenêtre est
## ouverte — il a pu être dégradé en cours de course. Fermée, c'est le réglage
## persisté qui fait foi : on règle la veille, comme le plein écran.
func _refresh_quality(window: Node) -> void:
	var live: Node = null if window == null else window.get("scene")
	var detected := RenderQuality.detect()
	var running := int(live.quality.level) if live != null else detected
	_quality.clear()
	_quality.add_item(
		"automatique (%s)" % str(RenderQuality.PROFILES[running]["name"]), AUTOMATIC_ITEM
	)
	for level: int in [RenderQuality.Level.LOW, RenderQuality.Level.MEDIUM, RenderQuality.Level.HIGH]:
		_quality.add_item(str(RenderQuality.PROFILES[level]["name"]), level)
	var wanted := _controller.settings.render_quality
	if live != null and not bool(live.call("auto_degrade")):
		wanted = int(live.quality.level)
	for item: int in range(_quality.item_count):
		if _quality.get_item_id(item) == _item_of(wanted):
			_quality.select(item)
			break


## Traductions entre le réglage (-1 = automatique) et l'identifiant d'entrée.
static func _item_of(setting: int) -> int:
	return AUTOMATIC_ITEM if setting < 0 else setting


static func _setting_of(item_id: int) -> int:
	return -1 if item_id == AUTOMATIC_ITEM else item_id


## Le curseur de volume — pour les tests.
func volume_slider() -> HSlider:
	return _volume


## Les deux sélecteurs — pour les tests.
func quality_selector() -> OptionButton:
	return _quality


func screen_selector() -> OptionButton:
	return _screens


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
	_root.call("set_spectacle_screen", _setting_of(_screens.get_item_id(index)))


func _on_fullscreen_toggled(pressed: bool) -> void:
	_root.call("set_spectacle_fullscreen", pressed)


func _on_quality_selected(index: int) -> void:
	var level := _setting_of(_quality.get_item_id(index))
	# Retenu pour les soirees suivantes, comme la coupure du son et son volume.
	# Écrit MÊME fenêtre fermée : c'est un réglage, pas l'état d'une fenêtre.
	_controller.settings.render_quality = level
	var window: Node = _root.get("spectacle")
	if window != null and window.scene != null:
		var automatic := level < 0
		# Le choix manuel désarme la dégradation automatique : sinon le niveau
		# choisi serait défait dès la première seconde sous le budget, sans que
		# l'opérateur comprenne pourquoi. Le retour à l'automatique la réarme,
		# et reprend le niveau détecté — sans quoi « automatique » garderait le
		# niveau imposé la veille.
		window.scene.set_auto_degrade(automatic)
		window.scene.quality.level = (
			RenderQuality.detect() if automatic else level as RenderQuality.Level
		)
		window.scene.apply_quality()
	_refresh_quality(window)
