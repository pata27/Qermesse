## Panneau materiel — ports, etat du lien, version firmware, test capteurs,
## calibration du rouleau (docs/05 lot 3).
##
## Ce panneau est l'outil de depannage terrain. Il doit dire POURQUOI un port
## n'est pas retenu, et pas seulement lesquels existent : c'est la moitie du
## diagnostic quand le boitier ne repond pas.
class_name PanelHardware
extends VBoxContainer

signal backend_changed()

## Aide a la mesure — docs/05 lot 3.
const CALIBRATION_HELP := (
	"Mesurer la distance de l'aimant au centre du rouleau, puis doubler. "
	+ "Un tick = un tour de rouleau = une circonférence. "
	+ "Aucun rapport de transmission n'intervient."
)

var _controller: AppController
var _backend_toggle: CheckButton
var _state_label: Label
var _firmware_label: Label
var _port_list: ItemList
var _ports: Array = []
var _refresh_button: Button
var _sensor_button: Button
var _sensor_labels: Array[Label] = []
var _roller: SpinBox
var _development: SpinBox
var _ticks_label: Label
var _stats_label: Label


func setup(controller: AppController) -> void:
	_controller = controller
	_build()
	_controller.link_state_changed.connect(func(_s: int) -> void: refresh())
	_controller.sensor_activity.connect(_on_sensor_activity)
	_controller.sensor_test_changed.connect(_on_sensor_test_changed)
	_controller.race_state_changed.connect(func(_p: int, _c: int) -> void: _refresh_sensor_button())
	_controller.demo_mode_changed.connect(func(_a: bool) -> void: _refresh_sensor_button())
	refresh()


func _build() -> void:
	var title := Label.new()
	title.text = "Matériel"
	title.add_theme_font_size_override("font_size", 20)
	add_child(title)

	_backend_toggle = CheckButton.new()
	_backend_toggle.text = "Simulateur"
	_backend_toggle.button_pressed = _controller.settings.use_simulator
	_backend_toggle.toggled.connect(_on_backend_toggled)
	add_child(_backend_toggle)

	_state_label = Label.new()
	add_child(_state_label)
	_firmware_label = Label.new()
	add_child(_firmware_label)

	var port_row := HBoxContainer.new()
	add_child(port_row)
	_refresh_button = Button.new()
	_refresh_button.text = "Rafraîchir les ports"
	_refresh_button.pressed.connect(refresh_ports)
	port_row.add_child(_refresh_button)

	_port_list = ItemList.new()
	_port_list.custom_minimum_size = Vector2(520, 110)
	_port_list.item_selected.connect(_on_port_selected)
	add_child(_port_list)

	var roller_row := HBoxContainer.new()
	add_child(roller_row)
	var roller_label := Label.new()
	roller_label.text = "Diamètre du rouleau (mm)"
	roller_row.add_child(roller_label)
	_roller = SpinBox.new()
	_roller.min_value = 20.0
	_roller.max_value = 500.0
	_roller.step = 0.1
	_roller.value = _controller.settings.roller_mm
	_roller.value_changed.connect(_on_roller_changed)
	roller_row.add_child(_roller)

	# Développement : la donnée que le capteur ne peut PAS fournir.
	#
	# Un tick est un tour de rouleau ; aucun rapport de transmission n'y entre
	# (docs/01 §6). La cadence de pédalage dépend donc du braquet monté, que
	# seul l'opérateur connaît. Elle ne sert qu'à l'affichage : ni les
	# distances, ni les temps, ni le classement n'en dépendent.
	var development_row := HBoxContainer.new()
	add_child(development_row)
	var development_label := Label.new()
	development_label.text = "Développement (m/tour de manivelle)"
	development_row.add_child(development_label)
	_development = SpinBox.new()
	_development.min_value = 1.0
	_development.max_value = 20.0
	_development.step = 0.1
	_development.value = _controller.settings.development_m
	_development.tooltip_text = (
		"Sert UNIQUEMENT à afficher la cadence. Le capteur compte des tours de "
		+ "rouleau : il ne connaît pas le braquet."
	)
	_development.value_changed.connect(_on_development_changed)
	development_row.add_child(_development)

	_ticks_label = Label.new()
	add_child(_ticks_label)

	var help := Label.new()
	help.text = CALIBRATION_HELP
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.custom_minimum_size.x = 520
	add_child(help)

	_sensor_button = Button.new()
	_sensor_button.text = "Test capteurs"
	_sensor_button.toggle_mode = true
	_sensor_button.toggled.connect(_on_sensor_test_toggled)
	add_child(_sensor_button)

	var sensor_row := HBoxContainer.new()
	add_child(sensor_row)
	for lane: int in range(Protocol.MAX_RIDERS):
		var label := Label.new()
		label.text = "P%d : —" % (lane + 1)
		label.custom_minimum_size.x = 110
		sensor_row.add_child(label)
		_sensor_labels.append(label)

	_stats_label = Label.new()
	_stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_stats_label.custom_minimum_size.x = 520
	add_child(_stats_label)


func refresh() -> void:
	var state := _controller.link_state()
	_state_label.text = "Lien : %s" % Protocol.state_name(state)
	if state == Protocol.State.IDENTIFIED:
		_state_label.add_theme_color_override("font_color", Color("#00E676"))
	elif state == Protocol.State.LINK_LOST:
		_state_label.add_theme_color_override("font_color", Color("#FF3B30"))
	else:
		_state_label.add_theme_color_override("font_color", Color("#FFB300"))

	var version := _controller.firmware_version()
	_firmware_label.text = (
		"Firmware : %s" % version
		if not version.is_empty()
		# docs/01 §4 : un port ouvert n'est pas une preuve. On le dit.
		else "Firmware : inconnu — aucun V: reçu, le départ reste interdit"
	)
	_backend_toggle.set_pressed_no_signal(_controller.is_simulated())
	_refresh_ticks_label()
	_refresh_stats()


func refresh_ports() -> void:
	_ports = _controller.list_ports()
	_port_list.clear()
	for entry: Dictionary in _ports:
		var ids := "sans VID/PID"
		if int(entry.get("vid", -1)) >= 0:
			ids = "%04x:%04x" % [int(entry["vid"]), int(entry["pid"])]
		# MEME VOCABULAIRE que `docs/RECETTE.md` §1 et que `ss_monitor` : la
		# recette se coche en lisant l'ecran, pas en traduisant une puce.
		var mark := "CANDIDAT" if bool(entry.get("candidate", false)) else "ignore"
		_port_list.add_item(
			"%-8s %-22s %-13s %s"
			% [mark, entry.get("port", "?"), ids, entry.get("reason", "")]
		)
	if _ports.is_empty():
		_port_list.add_item("aucun port détecté")


func ticks_text() -> String:
	return _ticks_label.text


func port_list() -> ItemList:
	return _port_list


func backend_toggle() -> CheckButton:
	return _backend_toggle


func sensor_text(lane: int) -> String:
	return _sensor_labels[lane].text


func sensor_button() -> Button:
	return _sensor_button


func roller_field() -> SpinBox:
	return _roller


func ticks_hint() -> String:
	return _ticks_label.text


func _refresh_ticks_label() -> void:
	# Retour immediat sur la calibration : l'operateur voit ce que sa mesure
	# donne en ticks avant de lancer quoi que ce soit.
	var physics := Physics.new(_controller.settings.roller_mm)
	var settings := _controller.settings
	# LE SECOND REPERE SUIT LE MODE. Annoncer « 500 m = 1392 ticks » pendant une
	# course en temps, ou la distance ne decide de rien, c'est un chiffre juste
	# au mauvais endroit — et l'operateur le lit comme un objectif.
	var second := ""
	match settings.mode:
		RaceConfig.Mode.DISTANCE:
			if not is_equal_approx(settings.distance_m, 100.0):
				second = ", %.0f m = %d ticks" % [
					settings.distance_m, physics.metres_to_ticks(settings.distance_m)
				]
		RaceConfig.Mode.PURSUIT:
			second = ", écart %.0f m = %d ticks" % [
				settings.gap_m, physics.metres_to_ticks(settings.gap_m)
			]
	_ticks_label.text = (
		"Circonférence %.1f mm — 100 m = %d ticks%s"
		% [physics.circumference_mm, physics.metres_to_ticks(100.0), second]
	)


func _refresh_stats() -> void:
	var stats := _controller.link_stats()
	if stats.is_empty():
		_stats_label.text = ""
		return
	_stats_label.text = (
		"Trames %s, inconnues %s, perdues %s — reconnexions %s, watchdog %s"
		% [
			stats.get("frames_total", 0),
			stats.get("frames_unknown", 0),
			stats.get("frames_dropped", 0),
			stats.get("connects", 0),
			stats.get("watchdog_trips", 0),
		]
	)
	# docs/06 §4 : un shield kiosque emet des `G`/`S` que le logiciel ignore. On
	# ne les commente que s'il y en a — sur un boitier ordinaire, il n'y en a
	# aucune, et une ligne « kiosque : 0 » serait du bruit permanent.
	if _controller.kiosk_frames() > 0:
		_stats_label.text += (
			"\nTrames kiosque : %d — boitier a shield, comportement non active"
			% _controller.kiosk_frames()
		)
	# docs/06 : un capteur qui rebondit se voit ici, avant de fausser une course.
	if _controller.rejected_ticks() > 0:
		_stats_label.text += (
			"\nTicks rejetés : %d (dernier : %s)"
			% [_controller.rejected_ticks(), _controller.last_rejection()]
		)


func stats_text() -> String:
	return _stats_label.text


func _on_backend_toggled(pressed: bool) -> void:
	_controller.apply_backend(pressed)
	refresh()
	backend_changed.emit()


func _on_port_selected(index: int) -> void:
	if index < _ports.size():
		_controller.set_preferred_port(str((_ports[index] as Dictionary).get("port", "")))


func _on_roller_changed(value: float) -> void:
	_controller.settings.roller_mm = value
	_refresh_ticks_label()


func _on_development_changed(value: float) -> void:
	_controller.settings.development_m = value


func _on_sensor_test_toggled(pressed: bool) -> void:
	if pressed:
		_controller.begin_sensor_test()
		# Refuse — en course, lien muet — : le bouton ne reste pas enfonce sur
		# un test qui n'existe pas.
		if not _controller.sensor_test_active():
			_sensor_button.set_pressed_no_signal(false)
	else:
		_controller.end_sensor_test()
		_reset_sensor_labels()


## LE BOUTON DIT L'ETAT DU CONTROLEUR, pas l'inverse. Un START met fin au test,
## un lien qui tombe aussi : le bouton se relache et l'affichage se vide, sans
## que l'operateur ait a cliquer sur un test deja fini.
func _on_sensor_test_changed(active: bool) -> void:
	_sensor_button.set_pressed_no_signal(active)
	if not active:
		_reset_sensor_labels()


## Grise pendant une course, comme la vitrine : le boitier ne fait pas deux
## choses a la fois, et le refus dans le journal n'empechait pas le bouton de
## s'enfoncer.
func _refresh_sensor_button() -> void:
	var running := _controller.race_in_progress()
	var demo := _controller.demo_mode
	_sensor_button.disabled = running or demo
	if running:
		_sensor_button.tooltip_text = (
			"Impossible pendant une course : le test est une course à blanc côté boîtier."
		)
	elif demo:
		_sensor_button.tooltip_text = "Impossible pendant le mode démo : l'arrêter d'abord."
	else:
		_sensor_button.tooltip_text = (
			"Lance une course à blanc pour vérifier que chaque rouleau anime la bonne piste."
		)


func _reset_sensor_labels() -> void:
	for lane: int in range(Protocol.MAX_RIDERS):
		_sensor_labels[lane].text = "P%d : —" % (lane + 1)


func _on_sensor_activity(ticks: PackedInt32Array) -> void:
	# On affiche la piste qui bouge : c'est ainsi qu'on detecte un cablage
	# inverse avant la course, et pas pendant.
	for lane: int in range(Protocol.MAX_RIDERS):
		_sensor_labels[lane].text = "P%d : %d ticks" % [lane + 1, ticks[lane]]
